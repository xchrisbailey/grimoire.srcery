import AppKit
import GrimoireCore
import GrimoireEditor
import SwiftUI

/// File › Browse Versions…: earlier versions of the open file, newest first, with the last
/// committed text when the file is in a git repository. Each shows what changed from it to
/// now, and can be restored or copied.
struct VersionBrowser: View {
    let document: OpenDocument
    let editor: EditorProxy
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [Entry] = []
    @State private var selection: Entry.ID?

    struct Entry: Identifiable, Hashable {
        var id: String
        var title: String
        var detail: String
        var text: String
    }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                List(selection: $selection) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).brandFont(.chrome)
                            Text(entry.detail)
                                .font(.brand(.metadata))
                                .foregroundStyle(Color.brand(\.overlay1))
                        }
                        .padding(.vertical, 2)
                        .tag(entry.id)
                    }
                }
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 300)
                .overlay {
                    if entries.isEmpty {
                        Text("No earlier versions yet. They're kept as you write.")
                            .brandFont(.chrome)
                            .foregroundStyle(Color.brand(\.overlay1))
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
                DiffView(diff: selected.map { LineDiff(from: $0.text, to: document.text) })
                    .frame(minWidth: 420)
            }
            Divider()
            HStack {
                Text("Versions are kept for two weeks in Grimoire's own folder, not next to your files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy") { copySelected() }
                    .disabled(selected == nil)
                Button("Restore This Version") { restoreSelected() }
                    .disabled(selected == nil)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 720, minHeight: 460)
        .onAppear(perform: load)
    }

    private var selected: Entry? {
        entries.first { $0.id == selection }
    }

    private func load() {
        var entries: [Entry] = []
        if let committed = GitBaseline.committedText(of: document.url) {
            entries.append(
                Entry(
                    id: "git", title: String(localized: "Last committed"),
                    detail: String(localized: "From git, read-only"), text: committed))
        }
        let store = document.versions ?? .standard
        for version in store.versions(of: document.url) {
            guard let text = store.text(of: version, for: document.url) else { continue }
            entries.append(
                Entry(
                    id: version.id.uuidString,
                    title: version.date.formatted(date: .abbreviated, time: .shortened),
                    detail: Self.describe(version.reason), text: text))
        }
        self.entries = entries
        selection = entries.first?.id
    }

    private static func describe(_ reason: Version.Reason) -> String {
        switch reason {
        case .edit: String(localized: "Before editing")
        case .replaceAll: String(localized: "Before Replace All")
        case .externalChange: String(localized: "Before another app changed it")
        case .conflict: String(localized: "Before a conflict was resolved")
        case .restore: String(localized: "Before restoring a version")
        case .intelligence: String(localized: "Before an AI edit")
        }
    }

    /// Restores the version as one undoable edit, keeping the current text as a version too.
    private func restoreSelected() {
        guard let selected else { return }
        document.keepVersion(.restore)
        if editor.hasEditor {
            editor.replaceText(selected.text, actionName: String(localized: "Restore Version"))
        } else {
            document.text = selected.text
        }
        dismiss()
    }

    private func copySelected() {
        guard let selected else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selected.text, forType: .string)
    }
}

/// What changes between a version and now: removed lines red, added lines green.
private struct DiffView: View {
    let diff: LineDiff?

    var body: some View {
        if let diff {
            VStack(alignment: .leading, spacing: 0) {
                Text(summary(diff))
                    .font(.brand(.metadata))
                    .foregroundStyle(Color.brand(\.overlay1))
                    .padding(10)
                Divider()
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(diff.lines.enumerated()), id: \.offset) { _, line in
                            row(line)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .background(Color.brand(\.page))
        } else {
            Text("Choose a version to see what's changed since.")
                .brandFont(.chrome)
                .foregroundStyle(Color.brand(\.overlay1))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func summary(_ diff: LineDiff) -> String {
        diff.isEmpty
            ? String(localized: "Same as now")
            : String(localized: "Restoring removes \(diff.added) lines and brings back \(diff.removed)")
    }

    @ViewBuilder private func row(_ line: DiffLine) -> some View {
        switch line.kind {
        case .skipped(let count):
            Text("⋯ \(count) unchanged lines")
                .font(.brand(.metadata))
                .foregroundStyle(Color.brand(\.overlay0))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
        case .same, .added, .removed:
            HStack(spacing: 8) {
                Text(line.kind == .added ? "+" : line.kind == .removed ? "−" : " ")
                    .foregroundStyle(tint(line.kind))
                Text(line.text.isEmpty ? " " : line.text)
                    .foregroundStyle(line.kind == .same ? Color.brand(\.subtext) : Color.brand(\.ink))
            }
            .font(.brand(.metadata))
            .padding(.horizontal, 12)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint(line.kind).opacity(line.kind == .same ? 0 : 0.12))
        }
    }

    private func tint(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: Color.brand(\.string)
        case .removed: Color.brand(\.error)
        default: Color.brand(\.overlay0)
        }
    }
}
