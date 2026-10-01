import GrimoireCore
import GrimoireEditor
import SwiftUI

/// One row in a palette: a page to summon, an incantation, a heading.
struct PaletteItem: Identifiable {
    var id: String
    var title: String
    var subtitle: String = ""
    /// The keyboard shortcut, shown at the row's end.
    var shortcut: String = ""
    var icon: String?
    /// Extra text the filter matches, such as a file's path.
    var keywords: String = ""
    /// Heading level, for indenting the outline.
    var indent: Int = 0
    var perform: () -> Void
}

/// The palettes that float over the window: Summon a page (⌘P), Incantations (⌘K) and the
/// heading outline (⇧⌘J).
enum Palette: Equatable {
    case summon
    case incantations
    case headings

    var title: String {
        switch self {
        case .summon: String(localized: "Summon a page")
        case .incantations: String(localized: "Incantations")
        case .headings: String(localized: "Jump to a heading")
        }
    }

    var prompt: String {
        switch self {
        case .summon: String(localized: "Type part of a file name")
        case .incantations: String(localized: "Type a command")
        case .headings: String(localized: "Type part of a heading")
        }
    }

    /// What ↵ does, for the footer.
    var returnHint: String {
        switch self {
        case .summon: String(localized: "↵ summon")
        case .incantations: String(localized: "↵ cast")
        case .headings: String(localized: "↵ jump")
        }
    }

    var emptyMessage: String {
        switch self {
        case .summon: String(localized: "No pages match.")
        case .incantations: String(localized: "No incantations match.")
        case .headings: String(localized: "No headings match.")
        }
    }
}

/// A search field over a ranked list: type to filter, ↑↓ to choose, ↵ to run, esc to close.
struct PaletteView: View {
    let palette: Palette
    let items: [PaletteItem]
    let close: () -> Void

    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var filtered: [PaletteItem] {
        FuzzyMatch.rank(items, by: query) { $0.title + " " + $0.keywords }
    }

    var body: some View {
        let results = Array(filtered.prefix(200))
        VStack(alignment: .leading, spacing: 0) {
            Text(palette.title.uppercased())
                .font(.brand(.metadata))
                .tracking(0.9)
                .foregroundStyle(Color.brand(\.overlay1))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .accessibilityAddTraits(.isHeader)
            TextField(palette.prompt, text: $query)
                .textFieldStyle(.plain)
                .font(.brand(.body))
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .onSubmit { run(results) }
                .onKeyPress(.upArrow) {
                    move(-1, count: results.count)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    move(1, count: results.count)
                    return .handled
                }
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if results.isEmpty {
                            Text(palette.emptyMessage)
                                .brandFont(.chrome)
                                .foregroundStyle(Color.brand(\.overlay1))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        }
                        ForEach(Array(results.enumerated()), id: \.element.id) { position, item in
                            row(item, isSelected: position == selected)
                                .id(item.id)
                                .contentShape(.rect)
                                .onTapGesture {
                                    selected = position
                                    run(results)
                                }
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
                .onChange(of: selected) {
                    if results.indices.contains(selected) { proxy.scrollTo(results[selected].id) }
                }
            }
            HStack(spacing: 14) {
                Text("↑↓ choose")
                Text(palette.returnHint)
                Text("esc close")
            }
            .font(.brand(.metadata))
            .foregroundStyle(Color.brand(\.overlay0))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Color.brand(\.surface0)).frame(height: 1) }
            .accessibilityHidden(true)
        }
        .frame(width: 560)
        .background(Color.brand(\.sidebar), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.brand(\.surface0)))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
        .onAppear { focused = true }
        .onChange(of: query) { selected = 0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(palette.title))
    }

    private func move(_ step: Int, count: Int) {
        guard count > 0 else { return }
        selected = (selected + step + count) % count
    }

    private func run(_ results: [PaletteItem]) {
        guard results.indices.contains(selected) else { return }
        let item = results[selected]
        close()
        item.perform()
    }

    private func row(_ item: PaletteItem, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isSelected ? Color.brand(\.magic) : Color.brand(\.subtext))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .brandFont(.chrome)
                    .foregroundStyle(Color.brand(\.ink))
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.brand(.metadata))
                        .foregroundStyle(Color.brand(\.overlay1))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .padding(.leading, CGFloat(item.indent) * 14)
            Spacer(minLength: 8)
            Text(item.shortcut)
                .font(.brand(.metadata))
                .foregroundStyle(Color.brand(\.overlay0))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 36)
        .background(isSelected ? Color.brand(\.magic).opacity(0.18) : .clear, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
