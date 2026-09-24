import SwiftUI

extension View {
    /// Runs `action` with the view's size once it is laid out and whenever it changes.
    ///
    /// Not a PreferenceKey with `onPreferenceChange`: in an NSHostingView on
    /// macOS 27, once the content holds an AppKit-backed control such as a
    /// Button, that action fires once with a zero size and never again
    /// (reproduced in LidlessTests). `onChange` of the reader's size keeps firing.
    func onSizeChange(perform action: @escaping (CGSize) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.onAppearAndChange(of: proxy.size, perform: action)
            }
        }
    }

    /// Runs `action` with `value` when the view appears and whenever `value` changes.
    func onAppearAndChange<Value: Equatable>(of value: Value, perform action: @escaping (Value) -> Void) -> some View {
        modifier(AppearAndChangeReporter(value: value, action: action))
    }
}

private struct AppearAndChangeReporter<Value: Equatable>: ViewModifier {
    let value: Value
    let action: (Value) -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.onChange(of: value, initial: true) { _, newValue in
                action(newValue)
            }
        } else {
            // onChange(of:initial:) is macOS 14+; this pair is its 12–13 equivalent.
            content
                .onAppear { action(value) }
                .onChange(of: value) { newValue in action(newValue) }
        }
    }
}
