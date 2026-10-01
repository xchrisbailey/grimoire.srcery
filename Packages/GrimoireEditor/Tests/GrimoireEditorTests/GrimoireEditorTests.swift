import Testing

@testable import GrimoireEditor

@MainActor
@Test func platformTextViewUsesTextKit2() {
    let view = PlatformTextView()
    #expect(view.textLayoutManager != nil)
}
