import Testing

@testable import GrimoireCore

@Suite struct HTMLRendererTests {
    let renderer = HTMLRenderer()

    @Test func escapesTextAndCode() {
        let html = renderer.render("Fish & chips < 3\n\n`a<b>`\n\n```\nif a < b {}\n```\n")
        #expect(html.contains("<p>Fish &amp; chips &lt; 3</p>"))
        #expect(html.contains("<code>a&lt;b&gt;</code>"))
        #expect(html.contains("<pre><code>if a &lt; b {}</code></pre>"))
    }

    @Test func keepsSingleLineBreaksWhenAsked() {
        #expect(renderer.render("one\ntwo").contains("<p>one\ntwo</p>"))
        var loose = HTMLRenderer()
        loose.keepsLineBreaks = true
        #expect(loose.render("one\ntwo").contains("one<br />\ntwo"))
    }

    @Test func leavesOutFrontmatterAndMDX() {
        let html = renderer.render(
            "---\ntitle: Hidden\n---\n\nimport X from './x'\n\n# Shown\n\n<Figure src=\"a.png\" />\n", flavor: .mdx)
        #expect(!html.contains("Hidden"))
        #expect(!html.contains("import"))
        #expect(!html.contains("Figure"))
        #expect(html.contains("<h1 id=\"shown\">Shown</h1>"))
    }

    @Test func givesHeadingsUniqueIDs() {
        let html = renderer.render("# Notes\n\n## Notes\n\n## What's here?\n")
        #expect(html.contains("id=\"notes\""))
        #expect(html.contains("id=\"notes-1\""))
        #expect(html.contains("id=\"whats-here\""))
    }

    @Test func rendersTasksTablesAndCallouts() {
        let html = renderer.render(
            "- [x] Done\n- [ ] Not yet\n\n| A | B |\n| :-: | --: |\n| 1 | 2 |\n\n> [!WARNING]\n> Volatile.\n")
        #expect(html.contains("<ul class=\"tasks\">"))
        #expect(html.contains("<li class=\"task done\"><input type=\"checkbox\" disabled checked /> Done</li>"))
        #expect(html.contains("<th style=\"text-align: center\">A</th>"))
        #expect(html.contains("<td style=\"text-align: right\">2</td>"))
        #expect(html.contains("callout-warning"))
        #expect(html.contains("<p>Volatile.</p>"))
    }

    @Test func letsTheCallerHighlightCodeAndInlineImages() {
        var renderer = HTMLRenderer()
        renderer.highlightCode = { _, language in "<b>\(language ?? "")</b>" }
        renderer.imageSource = { "data:" + $0 }
        let html = renderer.render("```swift\nlet a = 1\n```\n\n![Ink](ink.png)\n")
        #expect(html.contains("<pre><code class=\"language-swift\"><b>swift</b></code></pre>"))
        #expect(html.contains("<img src=\"data:ink.png\" alt=\"Ink\" />"))
    }
}
