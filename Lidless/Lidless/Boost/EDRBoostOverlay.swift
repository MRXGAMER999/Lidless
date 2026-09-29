import AppKit
import Foundation
import Metal
import QuartzCore
import os

/// Brightness Boost's engine: a click-through window over the built-in screen
/// whose `CAMetalLayer` holds one constant EDR colour `k` and is composited with
/// the `"multiply"` filter, so everything behind it is drawn `k` times brighter
/// in the screen's EDR headroom.
///
/// - The filter is the Core Animation name, not a Core Image filter: a CIFilter
///   forces in-process rendering, which can't see other windows' pixels.
/// - One 1×1 frame per factor value, no render loop. The layer's white
///   background multiplies by 1 until the first frame lands, so showing the
///   window can't flash.
/// - Nothing persists: the window and its EDR request die with the process.
/// - Only ever on the built-in screen and never while it is mirrored; a window
///   that leaves it is removed at once (see `OverlayPanel`).
final class EDRBoostOverlay: BoostOverlay {
    var onHeadroom: (@MainActor (Double) -> Void)?
    var onLost: (@MainActor () -> Void)?

    /// True while the window is up, including while it fades out after `hide`.
    var isShown: Bool { panel != nil }

    /// A belt-and-braces cap on any rendered factor; `BoostMachine` already caps
    /// it far lower (≈ 1.67).
    static let hardCeiling = 2.0
    /// Both on by default; the keys turn them off (`defaults write … -bool NO`).
    /// On the M5 Pro (macOS 27) a single static frame got its headroom taken
    /// back after about 5 s, and the screen dimmed to normal under a Boost
    /// that was still on. Together these keep it:
    /// - `contentsHeadroom` (macOS 26+): tell macOS the headroom the layer needs
    ///   (always on: with `preferredDynamicRange` the tag is what turns EDR on).
    /// - `keepAlive`: re-present the frame 5 times a second (`keepAliveInterval`).
    static let keepAliveKey = "boost.experiment.keepAlive"
    /// Other EDR overlays redraw at about 5 fps; a 1×1 frame costs next to nothing.
    static let keepAliveInterval: CFTimeInterval = 0.2

    private let log = Logger(subsystem: "io.github.mrxgamer999.Lidless", category: "Boost")
    private let defaults: UserDefaults

    private var gpu: (device: any MTLDevice, queue: any MTLCommandQueue)?
    private var panel: OverlayPanel?
    private var metalLayer: CAMetalLayer?
    // deinit reads these; they're otherwise touched on the main actor only.
    nonisolated(unsafe) private var observations: [any NSObjectProtocol] = []
    private var keepAlive = true
    /// The factor Boost is heading for (`setHeadroomRequest`): the layer asks
    /// for this headroom at once, so macOS doesn't grant it a step at a time.
    private var headroomRequest = 1.0

    /// The factor on screen now (1 before the first frame: the white background).
    private var current = 1.0
    /// Where the running (or last) ramp ends.
    private var target = 1.0
    private var ramp: (from: Double, start: CFTimeInterval, duration: Double)?
    nonisolated(unsafe) private var rampTimer: Timer?
    /// `hide` ramps to 1 and then removes the window.
    private var removeAfterRamp = false

    nonisolated(unsafe) private var pollTimer: Timer?
    private var pollIsFast = false
    /// Poll every 0.1 s until then (EDR ramps in about 2 s after a request).
    private var fastPollUntil: CFTimeInterval = 0

    /// No drawable is asked for before this time: set after `nextDrawable()`
    /// came back empty, so a stalled compositor can't block every ramp tick.
    private var drawableRetryAt: CFTimeInterval = 0
    /// Empty `nextDrawable()` results in a row (for the log).
    private var missedDrawables = 0
    /// The last headroom logged, so the log shows each change once.
    private var loggedHeadroom = 0.0
    /// When the last frame was presented (for `keepAlive`).
    private var lastFrameAt: CFTimeInterval = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The overlay's owner lives as long as the app, so this is a backstop:
    /// every callback holds `self` weakly, so a dropped overlay would otherwise
    /// leave its timers ticking and its window up.
    deinit {
        let ramp = rampTimer
        let poll = pollTimer
        for token in observations {
            NotificationCenter.default.removeObserver(token)
        }
        if Thread.isMainThread {
            ramp?.invalidate()
            poll?.invalidate()
            MainActor.assumeIsolated {
                if let panel {
                    panel.onLost = nil
                    panel.remove()
                }
            }
        } else {
            // Timers must be invalidated on the run loop they were added to.
            // The window can't be touched from here; with nothing retaining
            // it, it goes away when it is released.
            DispatchQueue.main.async {
                ramp?.invalidate()
                poll?.invalidate()
            }
        }
    }

    // MARK: - BoostOverlay

    func show(on displayID: CGDirectDisplayID, factor: Double, rampSeconds: Double) -> Bool {
        if let panel, panel.displayID != displayID {
            tearDown()
        }
        if panel == nil {
            guard open(on: displayID) else { return false }
        }
        guard panel != nil, let screen = OverlayPanel.screen(for: displayID) else {
            tearDown()
            return false
        }
        let k = Self.clamp(factor, potential: Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue))
        removeAfterRamp = false
        if k > max(current, target) + 0.001 {
            pollFast()
        }
        rampTo(k, over: rampSeconds)
        return true
    }

    func setHeadroomRequest(_ factor: Double) {
        headroomRequest = factor.isFinite ? min(max(factor, 1), Self.hardCeiling) : 1
    }

    func hide(rampSeconds: Double) {
        guard panel != nil else { return }
        guard rampSeconds > 0, current > 1.0005 else {
            tearDown()
            return
        }
        removeAfterRamp = true
        rampTo(1, over: rampSeconds)
    }

    // MARK: - Window

    /// Creates the window and layer on the built-in screen. The factor starts at 1.
    private func open(on displayID: CGDirectDisplayID) -> Bool {
        guard CGDisplayIsBuiltin(displayID) != 0 else {
            log.error("Boost refused: display \(displayID) is not the built-in screen")
            return false
        }
        guard CGDisplayIsInMirrorSet(displayID) == 0 else {
            log.notice("Boost refused: the built-in screen is mirrored")
            return false
        }
        guard let screen = OverlayPanel.screen(for: displayID) else {
            log.error("Boost refused: no screen for display \(displayID)")
            return false
        }
        guard let gpu = gpu ?? Self.makeGPU() else {
            log.error("Boost refused: no Metal device")
            return false
        }
        self.gpu = gpu

        let layer = Self.makeLayer(device: gpu.device, scale: screen.backingScaleFactor)
        let panel = OverlayPanel(displayID: displayID, level: NSWindow.Level(rawValue: Int(CGShieldingWindowLevel())))
        panel.contentView = LayerHostView(layer: layer)
        panel.onLost = { [weak self] in self?.panelLost() }
        self.panel = panel
        metalLayer = layer
        current = 1
        target = 1
        keepAlive = defaults.object(forKey: Self.keepAliveKey) as? Bool ?? true

        guard panel.present() else {
            log.error("Boost: the overlay could not be placed on display \(displayID)")
            tearDown()
            return false
        }
        // Present one EDR frame at identity right away: the machine asks for
        // factor 1 until headroom is reported, and macOS may only grant
        // headroom once an EDR drawable is on screen (to confirm on a device).
        _ = render(1)
        startObserving(panel)
        pollFast()
        reportHeadroom()
        log.notice("Boost overlay up on display \(displayID)")
        return true
    }

    /// Stops everything and removes the window. Never calls `onLost`.
    private func tearDown() {
        stopRamp()
        stopPolling()
        stopObserving()
        removeAfterRamp = false
        if let panel {
            panel.onLost = nil
            panel.remove()
            log.notice("Boost overlay removed")
        }
        panel = nil
        metalLayer = nil
        current = 1
        target = 1
        drawableRetryAt = 0
        missedDrawables = 0
    }

    /// The panel removed itself (screen gone or the window moved), or the
    /// built-in screen joined a mirror set. A window already fading out after
    /// `hide` was on its way down, so that isn't reported as a loss.
    private func panelLost() {
        guard panel != nil else { return }
        let wasHiding = removeAfterRamp
        tearDown()
        if wasHiding {
            log.notice("Boost overlay lost while fading out; not reported")
            return
        }
        onLost?()
    }

    private static func makeGPU() -> (device: any MTLDevice, queue: any MTLCommandQueue)? {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        return (device, queue)
    }

    private static func makeLayer(device: any MTLDevice, scale: CGFloat) -> CAMetalLayer {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .rgba16Float
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        // macOS 26 replaced the EDR flag with a dynamic range. Left to the
        // system, it "modulates brightness to co-exist with other content":
        // the boosted screen dipped for a moment a few seconds in (M5 Pro,
        // macOS 27). High keeps the full range; no tone mapping keeps `k` exact.
        if #available(macOS 26.0, *) {
            layer.preferredDynamicRange = .high
        } else {
            layer.wantsExtendedDynamicRangeContent = true
        }
        if #available(macOS 15.0, *) {
            layer.toneMapMode = .never
        }
        layer.framebufferOnly = true
        layer.isOpaque = false
        // `nextDrawable()` runs on the main thread and blocks while every
        // drawable is still held by the compositor. A 1×1 frame drawn at most
        // once per 60 Hz ramp tick is released within a frame or two, so that
        // only happens when the compositor stops taking frames (a GPU stall,
        // or the window off screen: display sleep, lock). Three drawables (the
        // default, set so it can't drift) keep one free while one is on screen
        // and one is queued; two would make a tick that outruns the display
        // wait for the next vsync. The timeout caps a stall at 1 s and returns
        // nil; `render` then stops asking for a while (see `drawableRetryAt`).
        layer.maximumDrawableCount = 3
        layer.allowsNextDrawableTimeout = true
        // One texel stretched over the screen: a constant colour at any size.
        layer.drawableSize = CGSize(width: 1, height: 1)
        layer.contentsGravity = .resize
        layer.contentsScale = scale
        // White is the identity under multiply, so the layer is harmless until frame 1.
        layer.backgroundColor = CGColor(gray: 1, alpha: 1)
        layer.compositingFilter = "multiply"
        return layer
    }

    /// Screen factor: finite, at least 1, never above the hard ceiling or the
    /// panel's potential headroom (a screen without EDR would only wash out).
    private static func clamp(_ factor: Double, potential: Double) -> Double {
        guard factor.isFinite else { return 1 }
        let ceiling = min(hardCeiling, max(potential, 1))
        return min(max(factor, 1), ceiling)
    }

    // MARK: - Drawing

    /// How long `render` stops asking for a drawable after one timed out.
    private static let drawableRetryDelay: CFTimeInterval = 0.25
    /// How long past its end a fade-out may keep failing to draw before the
    /// window is removed without it.
    private static let hideGiveUpSeconds: CFTimeInterval = 1

    /// Draws one frame at `k`. False when no frame was drawn (no drawable
    /// free, or still waiting after one timed out); the ramp retries on a
    /// later tick and only ends once its final value has been drawn.
    @discardableResult
    private func render(_ k: Double) -> Bool {
        guard let metalLayer, let queue = gpu?.queue else { return false }
        let now = CACurrentMediaTime()
        guard now >= drawableRetryAt else { return false }
        guard let drawable = metalLayer.nextDrawable() else {
            missedDrawables += 1
            drawableRetryAt = CACurrentMediaTime() + Self.drawableRetryDelay
            if missedDrawables == 1 || missedDrawables.isMultiple(of: 10) {
                log.error("Boost: no drawable free (\(self.missedDrawables) in a row); retrying")
            }
            return false
        }
        missedDrawables = 0
        guard let buffer = queue.makeCommandBuffer() else { return false }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: k, green: k, blue: k, alpha: 1)
        buffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        buffer.present(drawable)
        buffer.commit()
        current = k
        lastFrameAt = now
        // With `preferredDynamicRange` the headroom tag is what turns EDR on,
        // so it is always set on macOS 26+.
        if #available(macOS 26.0, *) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            metalLayer.contentsHeadroom = CGFloat(max(k, headroomRequest) + 0.1)
            CATransaction.commit()
        }
        return true
    }

    // MARK: - Ramp

    /// Eases from the factor on screen to `k`. A new target restarts from where
    /// the screen is now, so a reversal never jumps; the same target leaves a
    /// running ramp alone.
    private func rampTo(_ k: Double, over seconds: Double) {
        if ramp != nil, abs(k - target) < 0.0005 { return }
        target = k
        guard abs(k - current) >= 0.0005 else {
            stopRamp()
            finishRamp()
            return
        }
        ramp = (from: current, start: CACurrentMediaTime(), duration: max(seconds, 0))
        if seconds <= 0 {
            // At once; the timer below only runs if no drawable was free.
            rampStep()
            if ramp == nil { return }
        }
        guard rampTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rampStep() }
        }
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        rampTimer = timer
    }

    private func rampStep() {
        guard let ramp else {
            stopRamp()
            return
        }
        let now = CACurrentMediaTime()
        let t = ramp.duration > 0 ? min(1, max(0, (now - ramp.start) / ramp.duration)) : 1
        let eased = t * t * (3 - 2 * t)
        // Log space: equal steps look equally large at any brightness.
        let k = t >= 1 ? target : Foundation.exp(Foundation.log(ramp.from) + (Foundation.log(target) - Foundation.log(ramp.from)) * eased)
        if abs(k - current) >= 0.0005 || (t >= 1 && k != current) {
            guard render(k) else {
                // No frame this tick: a later tick draws where the ramp is by
                // then, and the timer runs on until the exact final value is
                // drawn. A fade-out that still can't draw well after its end
                // removes the window anyway: the fade is only cosmetic.
                if removeAfterRamp, t >= 1, now - ramp.start - ramp.duration > Self.hideGiveUpSeconds {
                    log.error("Boost: fade-out couldn't draw; removing the overlay at once")
                    stopRamp()
                    finishRamp()
                }
                return
            }
        }
        if t >= 1 {
            stopRamp()
            finishRamp()
        }
    }

    private func stopRamp() {
        rampTimer?.invalidate()
        rampTimer = nil
        ramp = nil
    }

    private func finishRamp() {
        if removeAfterRamp {
            tearDown()
        }
    }

    // MARK: - Headroom

    /// Polls at 0.1 s for the next 3 s (after showing or raising the factor), then at `keepAliveInterval`.
    private func pollFast() {
        fastPollUntil = CACurrentMediaTime() + 3
        if !pollIsFast || pollTimer == nil {
            schedulePoll(fast: true)
        }
    }

    private func schedulePoll(fast: Bool) {
        pollTimer?.invalidate()
        pollIsFast = fast
        // The slow poll also paces `keepAlive`.
        let timer = Timer(timeInterval: fast ? 0.1 : Self.keepAliveInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        pollIsFast = false
    }

    private func poll() {
        guard panel != nil else {
            stopPolling()
            return
        }
        if pollIsFast, CACurrentMediaTime() >= fastPollUntil {
            schedulePoll(fast: false)
        }
        if keepAlive, ramp == nil, current > 1, CACurrentMediaTime() - lastFrameAt >= Self.keepAliveInterval - 0.02 {
            render(current)
        }
        reportHeadroom()
    }

    /// The screen's current headroom: the maximum over every app's EDR content,
    /// so it can exceed our own factor (HDR video, Photos).
    private func reportHeadroom() {
        guard let panel, let screen = OverlayPanel.screen(for: panel.displayID) else { return }
        let headroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
        if abs(headroom - loggedHeadroom) >= 0.02 {
            loggedHeadroom = headroom
            log.debug("Boost headroom \(headroom, format: .fixed(precision: 2))")
        }
        onHeadroom?(headroom)
    }

    // MARK: - Observing

    private func startObserving(_ panel: OverlayPanel) {
        let center = NotificationCenter.default
        observations = [
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screenParametersChanged() }
            },
            center.addObserver(forName: NSWindow.didChangeBackingPropertiesNotification, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateScale() }
            },
        ]
    }

    private func stopObserving() {
        for token in observations {
            NotificationCenter.default.removeObserver(token)
        }
        observations = []
    }

    private func screenParametersChanged() {
        guard let panel else { return }
        // A mirror set would carry the multiply onto the other display too.
        if CGDisplayIsInMirrorSet(panel.displayID) != 0 {
            log.notice("Boost overlay removed: the built-in screen is mirrored")
            panelLost()
            return
        }
        reportHeadroom()
    }

    private func updateScale() {
        guard let panel, let metalLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.contentsScale = panel.backingScaleFactor
        CATransaction.commit()
    }
}

/// A layer-hosting view: the layer is set before `wantsLayer`, so AppKit never
/// draws into it or replaces it. The layer follows the view's size.
private final class LayerHostView: NSView {
    init(layer: CALayer) {
        super.init(frame: .zero)
        self.layer = layer
        wantsLayer = true
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.frame = bounds
        CATransaction.commit()
    }
}
