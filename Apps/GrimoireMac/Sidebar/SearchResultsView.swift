import GrimoireCore
import GrimoireEditor
import SwiftUI

/// Find in Project, in the sidebar: the query and its options, then matches grouped by
/// file. Clicking a match opens the file at it.
struct SearchResultsView: View {
    let window: WindowState
    @FocusState private var focused: Bool

    private var search: ProjectSearch { window.search }

    var body: some View {
        @Bindable var search = search
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TextField("Find in project", text: $search.query)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                        .onKeyPress(.escape) {
                            search.end()
                            return .handled
                        }
                    Button {
                        search.end()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .accessibilityLabel(Text("Close search"))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.brand(\.overlay1))
                    .help(Text("Back to files (esc)"))
                }
                HStack(spacing: 6) {
                    option("Aa", isOn: $search.caseSensitive, help: String(localized: "Match case"))
                    option(".*", isOn: $search.regex, help: String(localized: "Regular expression"))
                    option("W", isOn: $search.wholeWord, help: String(localized: "Whole words"))
                    Spacer()
                    Text(summary)
                        .font(.brand(.metadata))
                        .foregroundStyle(search.search.isInvalid ? Color.brand(\.error) : Color.brand(\.overlay1))
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            List {
                ForEach(search.results) { file in
                    Section {
                        ForEach(file.matches, id: \.range) { match in
                            MatchRow(match: match)
                                .contentShape(.rect)
                                .onTapGesture { window.open(file.document.url, revealing: match.range) }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Text(file.document.name)
                                .brandFont(.chrome)
                                .foregroundStyle(Color.brand(\.subtext))
                            Text(String(file.matches.count))
                                .font(.brand(.metadata))
                                .foregroundStyle(Color.brand(\.overlay0))
                            Spacer(minLength: 4)
                            Text(file.document.path)
                                .font(.brand(.metadata))
                                .foregroundStyle(Color.brand(\.overlay0))
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .onChange(of: search.focusRequest, initial: true) { focused = true }
    }

    private var summary: String {
        if search.search.isInvalid { return String(localized: "Invalid pattern") }
        if search.query.isEmpty { return "" }
        if search.isSearching && search.results.isEmpty { return String(localized: "Searching…") }
        if search.results.isEmpty { return String(localized: "No matches") }
        return String(localized: "\(search.matchCount) in \(search.results.count) files")
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

/// One match: its line number and the line, with the match picked out.
private struct MatchRow: View {
    let match: LineMatch

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(match.line))
                .font(.brand(.metadata))
                .foregroundStyle(Color.brand(\.overlay0))
                .frame(minWidth: 24, alignment: .trailing)
            Text(highlighted)
                .brandFont(.chrome)
                .lineLimit(2)
        }
    }

    private var highlighted: AttributedString {
        var text = AttributedString(match.preview)
        text.foregroundColor = Color.brand(\.subtext)
        let preview = match.preview as NSString
        guard NSMaxRange(match.previewRange) <= preview.length,
            let range = Range(match.previewRange, in: match.preview),
            let lower = AttributedString.Index(range.lowerBound, within: text),
            let upper = AttributedString.Index(range.upperBound, within: text)
        else { return text }
        text[lower..<upper].foregroundColor = Color.brand(\.ink)
        text[lower..<upper].backgroundColor = Color.brand(\.magic).opacity(0.22)
        return text
    }
}
