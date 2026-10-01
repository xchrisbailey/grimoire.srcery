import GrimoireCore
import GrimoireEditor
import GrimoireIntelligence
import SwiftUI

/// Above a page with no frontmatter: an offer to conjure a title, tags and summary. It
/// never writes anything until "Add" is chosen, and "Not now" hides it for that page.
struct FrontmatterSuggestionBar: View {
    let document: OpenDocument
    let window: WindowState

    @State private var suggestion: FrontmatterSuggestion?
    @State private var isWorking = false
    @AppStorage("grimoire.dismissedFrontmatter") private var dismissed = ""

    private var dismissedPaths: Set<String> { Set(dismissed.split(separator: "\n").map(String.init)) }
    private var path: String { document.url.standardizedFileURL.path(percentEncoded: false) }

    private var isOffered: Bool {
        // Cheap checks: this runs as the page is typed in.
        window.intelligenceReady && !dismissedPaths.contains(path) && !document.text.hasPrefix("---")
            && document.text.utf8.count >= 400
    }

    var body: some View {
        if isOffered {
            HStack(spacing: 10) {
                Image(systemName: "sparkle").foregroundStyle(Color.brand(\.magic))
                if let suggestion {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title).brandFont(.chrome).foregroundStyle(Color.brand(\.ink))
                        Text(suggestion.tags.joined(separator: " · ") + " — " + suggestion.summary)
                            .font(.brand(.metadata))
                            .foregroundStyle(Color.brand(\.subtext))
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Add") { add(suggestion) }
                    Button("Dismiss") { dismiss() }
                } else {
                    Text("This page has no frontmatter. Conjure a title and tags?")
                        .brandFont(.chrome)
                        .foregroundStyle(Color.brand(\.subtext))
                    Spacer()
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Suggest") { suggest() }
                    }
                    Button("Not now") { dismiss() }
                }
            }
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.brand(\.magic).opacity(0.08))
            .overlay(alignment: .bottom) { Divider() }
            .onChange(of: document.url) { suggestion = nil }
        }
    }

    private func suggest() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                suggestion = try await IntelligenceService.shared.suggestFrontmatter(for: document.text)
            } catch {
                window.actions.error = error
            }
        }
    }

    private func add(_ suggestion: FrontmatterSuggestion) {
        document.keepVersion(.intelligence)
        window.editor.replaceText(suggestion.yaml + document.text, actionName: String(localized: "Add Frontmatter"))
        self.suggestion = nil
    }

    private func dismiss() {
        dismissed = (dismissedPaths.union([path])).sorted().joined(separator: "\n")
        suggestion = nil
    }
}
