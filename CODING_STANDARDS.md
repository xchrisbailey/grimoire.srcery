# Coding standards

Rules a reviewer applies to a diff. Each one is a judgement call that no build step checks. The coder instructions in `.claude/agents/coder.md` cover how to work; this file covers what the result should look like.

## Domain language

Names, comments, test names, and on-screen text use the terms in `GLOSSARY.md` once it exists. A word on a term's _Avoid_ list is a finding when it stands for that term, and fine when it means something else.

## Package boundaries

- `GrimoireCore` imports no AppKit, UIKit, or SwiftUI. Anything that needs a view or a platform type belongs in `GrimoireEditor` or an app.
- Platform code in `GrimoireEditor` sits behind `#if os(macOS)` or `#if os(iOS)`, so both apps keep compiling. Code under `Mac/` is macOS only.
- Logic that can be tested without a window goes in a package, where `swift test` reaches it. The apps hold views and wiring.

## Text and offsets

- An offset or range that crosses between the document model and a text view is in UTF-16 code units, as `BlockIndex` documents. Convert at the edge when a `String.Index` or byte offset is needed, and name the unit when it isn't UTF-16.
- A document that hasn't been edited serializes to exactly the text it was parsed from. A change to the parser, a block type, or serialization comes with a case in `RoundTripTests`.
- Text the user didn't touch keeps its bytes through an edit: line endings, trailing whitespace, and frontmatter included.

## Localized strings

- On-screen text goes through the String Catalog in `Resources/Localizable.xcstrings`.
- A `String(localized:)` key used inside a package is entered in the catalog by hand with `"extractionState" : "manual"`. Xcode extracts strings from the app targets only and deletes package keys that aren't marked.

## Timing budgets

- A timing test takes its budget through the `GRIMOIRE_PERF_BUDGET_SCALE` helper, so it holds on slower machines.
- Raising a budget to make a test pass is a finding unless the diff says why the work got slower and why that is acceptable.
