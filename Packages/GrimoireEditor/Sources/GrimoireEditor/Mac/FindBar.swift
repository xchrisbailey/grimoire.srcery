#if os(macOS)
import GrimoireCore
import SwiftUI

/// The find and replace bar above the editor: ⌘F to find, ⌥⌘F to replace, ↩ for the
/// next match, ⇧↩ for the previous, esc to close.
public struct FindBar: View {
    @Bindable var proxy: EditorProxy
    @FocusState private var findFocused: Bool

    public init(proxy: EditorProxy) {
        self.proxy = proxy
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                TextField("Find", text: $proxy.findQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($findFocused)
                    .onSubmit {
                        if NSEvent.modifierFlags.contains(.shift) { proxy.findPrevious() } else { proxy.findNext() }
                    }
                    .frame(minWidth: 180)
                option("Aa", isOn: $proxy.caseSensitive, help: String(localized: "Match case"))
                option(".*", isOn: $proxy.regex, help: String(localized: "Regular expression"))
                option("W", isOn: $proxy.wholeWord, help: String(localized: "Whole words"))
                Text(status)
                    .font(.brand(.metadata))
                    .foregroundStyle(proxy.search.isInvalid ? Color.brand(\.error) : Color.brand(\.overlay1))
                    .frame(minWidth: 70, alignment: .trailing)
                Button {
                    proxy.findPrevious()
                } label: {
                    Image(systemName: "chevron.up").accessibilityLabel(Text("Previous"))
                }
                .help(Text("Previous match (⇧⌘G)"))
                Button {
                    proxy.findNext()
                } label: {
                    Image(systemName: "chevron.down").accessibilityLabel(Text("Next"))
                }
                .help(Text("Next match (⌘G)"))
                Button("Done") { proxy.hideFind() }
            }
            if proxy.showsReplace {
                HStack(spacing: 8) {
                    TextField("Replace", text: $proxy.replacement)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { proxy.replaceCurrent() }
                        .frame(minWidth: 180)
                    Button("Replace") { proxy.replaceCurrent() }
                        .disabled(proxy.matchCount == 0)
                    Button("Replace All") { proxy.replaceAll() }
                        .disabled(proxy.matchCount == 0)
                    Spacer()
                }
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.brand(\.sidebar))
        .overlay(alignment: .bottom) { Divider() }
        .onKeyPress(.escape) {
            proxy.hideFind()
            return .handled
        }
        .onChange(of: proxy.findFocusRequest, initial: true) { findFocused = true }
    }

    private var status: String {
        if proxy.search.isInvalid { return String(localized: "Invalid pattern") }
        guard !proxy.findQuery.isEmpty else { return "" }
        guard proxy.matchCount > 0 else { return String(localized: "No matches") }
        if let current = proxy.currentMatch { return String(localized: "\(current + 1) of \(proxy.matchCount)") }
        return String(localized: "\(proxy.matchCount) matches")
    }

    private func option(_ label: String, isOn: Binding<Bool>, help: String) -> some View {
        Toggle(isOn: isOn) {
            Text(label).font(.brand(.metadata))
        }
        .toggleStyle(.button)
        .help(help)
        .accessibilityLabel(Text(help))
    }
}
#endif
