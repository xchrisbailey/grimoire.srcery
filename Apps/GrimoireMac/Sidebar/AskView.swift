import GrimoireCore
import GrimoireEditor
import GrimoireIntelligence
import SwiftUI

/// Ask your project, in the sidebar: a question, the answer as it's written, and the
/// passages it cites. Each citation opens its page at the passage.
struct AskView: View {
    let window: WindowState
    @FocusState private var focused: Bool

    private var ask: ProjectAsk { window.ask }

    var body: some View {
        @Bindable var ask = ask
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField("Ask about your pages", text: $ask.question)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { window.askProject() }
                    .onKeyPress(.escape) {
                        ask.end()
                        return .handled
                    }
                Button {
                    ask.end()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .accessibilityLabel(Text("Close"))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.brand(\.overlay1))
                .help(Text("Back to files (esc)"))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            Text(status)
                .font(.brand(.metadata))
                .foregroundStyle(Color.brand(\.overlay1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let error = ask.error {
                        Text(error).brandFont(.chrome).foregroundStyle(Color.brand(\.error))
                    } else if let answer = ask.answer {
                        answerView(answer)
                    } else if ask.isAnswering {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Searching your pages…").brandFont(.chrome).foregroundStyle(Color.brand(\.subtext))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .onChange(of: ask.focusRequest, initial: true) { focused = true }
        .environment(\.openURL, OpenURLAction { url in openCitation(url) })
    }

    private var status: String {
        if let message = IntelligenceService.shared.status(for: window.project).message { return message }
        guard let semantic = window.semantic else { return "" }
        if semantic.isIndexing { return String(localized: "Reading pages…") }
        return String(localized: "Answers come from your pages, on this Mac.")
    }

    @ViewBuilder
    private func answerView(_ answer: ProjectAnswer) -> some View {
        Text(ask.asked)
            .brandFont(.chrome)
            .foregroundStyle(Color.brand(\.subtext))
        Text(Self.linked(answer))
            .brandFont(.chrome)
            .foregroundStyle(Color.brand(\.ink))
            .textSelection(.enabled)
        let cited = answer.citedNumbers
        if !cited.isEmpty && !ask.isAnswering {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sources")
                    .font(.brand(.metadata))
                    .foregroundStyle(Color.brand(\.overlay1))
                ForEach(cited, id: \.self) { number in
                    let hit = answer.sources[number - 1]
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: "\(number)")
                            .font(.brand(.metadata))
                            .foregroundStyle(Color.brand(\.magic))
                        PassageRow(hit: hit)
                    }
                    .contentShape(.rect)
                    .onTapGesture { open(hit) }
                }
            }
        }
    }

    /// The answer with each `[n]` a link to its source.
    static func linked(_ answer: ProjectAnswer) -> AttributedString {
        var result = AttributedString()
        var rest = Substring(answer.text)
        while let match = rest.firstMatch(of: /\[(\d+)\]/) {
            result += AttributedString(String(rest[..<match.range.lowerBound]))
            var citation = AttributedString(String(rest[match.range]))
            if let number = Int(match.1), (1...answer.sources.count).contains(number) {
                citation.link = URL(string: "grimoire-source:\(number)")
                citation.foregroundColor = Color.brand(\.magic)
            }
            result += citation
            rest = rest[match.range.upperBound...]
        }
        return result + AttributedString(String(rest))
    }

    private func openCitation(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "grimoire-source", let number = Int(url.absoluteString.dropFirst("grimoire-source:".count)),
            let answer = ask.answer, (1...answer.sources.count).contains(number)
        else { return .systemAction }
        open(answer.sources[number - 1])
        return .handled
    }

    private func open(_ hit: PassageHit) {
        window.open(hit.passage.url, revealing: NSRange(location: hit.passage.location, length: 0))
    }
}
