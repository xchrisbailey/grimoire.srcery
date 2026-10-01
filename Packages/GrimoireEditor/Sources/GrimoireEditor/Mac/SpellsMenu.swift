#if os(macOS)
import AppKit
import SwiftUI

/// What the Spells menu shows: spells after `/`, or languages after the Code block spell.
@MainActor @Observable
final class SpellsMenuModel {
    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String?
        let hint: String
    }

    var title = ""
    var items: [Item] = []
    var selected = 0
    var onChoose: ((Int) -> Void)?

    var selectedItem: Item? { items.indices.contains(selected) ? items[selected] : nil }
}

/// The floating Spells menu, anchored under the caret. It's a child panel that never takes
/// focus, so typing keeps going to the text view while it's open.
@MainActor
final class SpellsMenu {
    let model = SpellsMenuModel()
    private var panel: NSPanel?
    static let width: CGFloat = 300

    var isOpen: Bool { panel?.isVisible == true }

    /// Shows the menu beside `caretRect` (screen coordinates), flipping above the caret when
    /// there's no room below.
    func show(at caretRect: CGRect, in window: NSWindow) {
        let panel = panel ?? makePanel()
        self.panel = panel
        let height = contentHeight
        let screen = window.screen?.visibleFrame ?? window.frame
        var origin = CGPoint(x: caretRect.minX - 8, y: caretRect.minY - height - 6)
        if origin.y < max(screen.minY, window.frame.minY) { origin.y = caretRect.maxY + 6 }
        origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - Self.width - 4)
        panel.setFrame(CGRect(origin: origin, size: CGSize(width: Self.width, height: height)), display: true)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func close() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func moveSelection(by step: Int) {
        guard !model.items.isEmpty else { return }
        model.selected = (model.selected + step + model.items.count) % model.items.count
        announceSelection()
    }

    /// Reads the selected item aloud for VoiceOver.
    func announceSelection() {
        guard let item = model.selectedItem else { return }
        NSAccessibility.post(
            element: NSApp.mainWindow as Any, notification: .announcementRequested,
            userInfo: [.announcement: "\(item.title), \(item.subtitle)", .priority: NSAccessibilityPriorityLevel.high])
    }

    private var contentHeight: CGFloat {
        let rows = CGFloat(min(model.items.count, 7))
        return 34 + max(rows, 1) * 44 + 34
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = NSHostingView(rootView: SpellsMenuView(model: model))
        return panel
    }
}

/// The menu's content: header, rows and the key hints footer.
struct SpellsMenuView: View {
    @Bindable var model: SpellsMenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.title.uppercased())
                .font(.brand(.metadata))
                .tracking(0.9)
                .foregroundStyle(Color.brand(\.overlay1))
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if model.items.isEmpty {
                            Text("No spells match.")
                                .brandFont(.chrome)
                                .foregroundStyle(Color.brand(\.overlay1))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { position, item in
                            row(item, selected: position == model.selected)
                                .id(item.id)
                                .contentShape(.rect)
                                .onTapGesture { model.onChoose?(position) }
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .onChange(of: model.selected) {
                    if let item = model.selectedItem { proxy.scrollTo(item.id) }
                }
            }
            HStack(spacing: 14) {
                Text("↑↓ choose")
                Text("↵ cast")
                Text("esc close")
            }
            .font(.brand(.metadata))
            .foregroundStyle(Color.brand(\.overlay0))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Color.brand(\.surface0)).frame(height: 1) }
            .accessibilityHidden(true)
        }
        .frame(width: SpellsMenu.width)
        .background(Color.brand(\.sidebar), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.brand(\.surface0)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(model.title))
    }

    private func row(_ item: SpellsMenuModel.Item, selected: Bool) -> some View {
        HStack(spacing: 10) {
            if let icon = item.icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(selected ? Color.brand(\.magic) : Color.brand(\.subtext))
                    .background(Color.brand(\.page), in: .rect(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(selected ? Color.brand(\.magic) : Color.brand(\.surface0)))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .brandFont(.chrome)
                    .foregroundStyle(Color.brand(\.ink))
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(Font(BrandFont.ctFont(monospaced: false, size: 11.5, weight: 400)))
                        .foregroundStyle(Color.brand(\.overlay1))
                }
            }
            Spacer(minLength: 4)
            Text(item.hint)
                .font(.brand(.metadata))
                .foregroundStyle(Color.brand(\.overlay0))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .background(selected ? Color.brand(\.magic).opacity(0.18) : .clear, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
#endif
