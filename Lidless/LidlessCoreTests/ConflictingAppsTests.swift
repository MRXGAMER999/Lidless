import Testing
@testable import LidlessCore

struct ConflictingAppsTests {
    // MARK: - Table

    @Test(arguments: [
        ("pro.betterdisplay.BetterDisplay", "BetterDisplay"),
        ("fyi.lunar.Lunar", "Lunar"),
        ("dev.solodisplay.SoloDisplay", "SoloDisplay"),
        ("de.brightintosh.app", "BrightIntosh"),
        ("com.goodsnooze.vivid", "Vivid"),
        ("app.monitorcontrol.MonitorControl", "MonitorControl"),
        ("me.guillaumeb.MonitorControl", "MonitorControl"),
        ("com.sids.DisplayBuddy", "DisplayBuddy"),
    ])
    func `known bundle identifiers map to their app`(bundleID: String, name: String) {
        #expect(ConflictingApps.app(forBundleID: bundleID)?.name == name)
    }

    @Test func `matching ignores case and a Setapp suffix`() {
        #expect(ConflictingApps.app(forBundleID: "PRO.BETTERDISPLAY.BETTERDISPLAY")?.name == "BetterDisplay")
        #expect(ConflictingApps.app(forBundleID: "com.goodsnooze.vivid-setapp")?.name == "Vivid")
    }

    @Test(arguments: [
        "org.herf.Flux",
        "com.stengo.DeskPad",
        "com.displaylink.DisplayLinkUserAgent",
        "de.brightintosh.app.Widgets",
        "io.github.mrxgamer999.Lidless",
        "",
    ])
    func `other apps are not conflicts`(bundleID: String) {
        #expect(ConflictingApps.app(forBundleID: bundleID) == nil)
    }

    @Test func `every table entry is well formed`() {
        var seen: Set<String> = []
        for app in ConflictingApps.known {
            #expect(!app.name.isEmpty)
            #expect(!app.bundleIDs.isEmpty)
            #expect(!app.features.isEmpty)
            #expect(app.features == app.features.sorted())
            for id in app.bundleIDs {
                #expect(seen.insert(id.lowercased()).inserted, "\(id) is listed twice")
            }
        }
    }

    @Test func `what each app fights over`() {
        let features = { (id: String) in ConflictingApps.app(forBundleID: id)?.features }
        #expect(features("pro.betterdisplay.BetterDisplay") == [.deskMode, .boost, .externalBrightness])
        #expect(features("fyi.lunar.Lunar") == [.deskMode, .boost, .externalBrightness])
        #expect(features("dev.solodisplay.SoloDisplay") == [.deskMode])
        #expect(features("de.brightintosh.app") == [.boost])
        #expect(features("com.goodsnooze.vivid") == [.boost])
        #expect(features("app.monitorcontrol.MonitorControl") == [.externalBrightness])
        #expect(features("com.sids.DisplayBuddy") == [.externalBrightness])
    }

    @Test func `running lists each app once in table order`() {
        let running = ConflictingApps.running(in: [
            "com.apple.finder",
            "me.guillaumeb.MonitorControl",
            "pro.betterdisplay.BetterDisplay",
            "app.monitorcontrol.MonitorControl",
        ])
        #expect(running.map(\.name) == ["BetterDisplay", "MonitorControl"])
    }

    @Test func `running filters by feature`() {
        let ids = ["pro.betterdisplay.BetterDisplay", "de.brightintosh.app", "com.sids.DisplayBuddy"]
        #expect(ConflictingApps.running(in: ids, conflictingWith: .deskMode).map(\.name) == ["BetterDisplay"])
        #expect(ConflictingApps.running(in: ids, conflictingWith: .boost).map(\.name) == ["BetterDisplay", "BrightIntosh"])
        #expect(ConflictingApps.running(in: ids, conflictingWith: .externalBrightness).map(\.name) == ["BetterDisplay", "DisplayBuddy"])
        #expect(ConflictingApps.running(in: [], conflictingWith: .boost).isEmpty)
    }

    // MARK: - Advisor

    @Test func `a running app is announced once with its first conflict`() {
        var advisor = ConflictAdvisor()
        let first = advisor.appsSeen(["pro.betterdisplay.BetterDisplay", "com.apple.Safari"], activeFeatures: [])
        #expect(first.map(\.app.name) == ["BetterDisplay"])
        #expect(first.map(\.feature) == [.deskMode])
        #expect(advisor.appsSeen(["pro.betterdisplay.BetterDisplay"], activeFeatures: []).isEmpty)
    }

    @Test func `the announcement names a feature that is on`() {
        var advisor = ConflictAdvisor()
        let notices = advisor.appsSeen(["fyi.lunar.Lunar"], activeFeatures: [.externalBrightness, .boost])
        #expect(notices.map(\.feature) == [.boost])
    }

    @Test func `turning a feature on warns about each conflicting app once`() {
        var advisor = ConflictAdvisor()
        let running = ["pro.betterdisplay.BetterDisplay", "de.brightintosh.app", "com.sids.DisplayBuddy"]
        let boost = advisor.featureTurnedOn(.boost, runningBundleIDs: running)
        #expect(boost.map(\.app.name) == ["BetterDisplay", "BrightIntosh"])
        #expect(boost.allSatisfy { $0.feature == .boost })
        #expect(advisor.featureTurnedOn(.boost, runningBundleIDs: running).isEmpty)
        #expect(advisor.featureTurnedOn(.deskMode, runningBundleIDs: running).map(\.app.name) == ["BetterDisplay"])
    }

    @Test func `a feature already announced at launch isn't repeated`() {
        var advisor = ConflictAdvisor()
        let running = ["pro.betterdisplay.BetterDisplay"]
        #expect(advisor.appsSeen(running, activeFeatures: [.deskMode]).map(\.feature) == [.deskMode])
        #expect(advisor.featureTurnedOn(.deskMode, runningBundleIDs: running).isEmpty)
        #expect(advisor.featureTurnedOn(.boost, runningBundleIDs: running).map(\.feature) == [.boost])
    }

    @Test func `an app warned about on turn-on isn't announced again when seen`() {
        var advisor = ConflictAdvisor()
        #expect(advisor.featureTurnedOn(.boost, runningBundleIDs: ["com.goodsnooze.vivid"]).count == 1)
        // It quit and launched again.
        #expect(advisor.appsSeen(["com.goodsnooze.vivid"], activeFeatures: []).isEmpty)
    }

    @Test func `features that don't conflict warn about nothing`() {
        var advisor = ConflictAdvisor()
        #expect(advisor.featureTurnedOn(.deskMode, runningBundleIDs: ["com.goodsnooze.vivid", "com.sids.DisplayBuddy"]).isEmpty)
    }

    @Test func `features sort in declaration order`() {
        #expect([ConflictFeature.externalBrightness, .deskMode, .boost].sorted() == [.deskMode, .boost, .externalBrightness])
    }
}
