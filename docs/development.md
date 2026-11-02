# Development

Grimoire is a native markdown editor for macOS with an iOS companion. It requires Xcode 27 with the macOS 27 and iOS 27 SDKs, XcodeGen, and SwiftLint. `README.md` covers the layout, opening the project, and packaging a release.

## Checks

Checks run locally. `.github/workflows/release.yml` is the only workflow, and it only packages a release (see `docs/RELEASING.md`).

Run `scripts/check.sh` from the root of the checkout or worktree, at a clean tree, before a branch is reviewed or merged. It runs every step and reports all of them, in this order:

- `xcodegen generate` (`Grimoire.xcodeproj` is generated and not checked in, so a fresh worktree has none until this runs);
- the Mac and iOS app builds;
- `swift test` in `GrimoireCore`, `GrimoireEditor` and `GrimoireIntelligence`;
- the release-mode parse speed tests in `GrimoireCore`;
- `swift-format` and SwiftLint, both strict;
- the DMG layout writer test.

It takes a long time. Run it in the foreground with a long timeout, so the result arrives with the run. `--core-runs N` repeats `GrimoireCore`'s debug `swift test` N times, and every run counts; `--only` runs chosen steps while you work on a failure, and a partial run never counts as a check.

Read the result in `build/check-logs/<sha>/summary.txt`, which the script also prints. It holds the head SHA, PASS or FAIL for each step, each build's `** BUILD SUCCEEDED **` or `** BUILD FAILED **` line, each package's `Test run with … passed` or `… failed` line, the `GrimoireCore` tally, and an overall result. Full per-step logs sit beside it. A dirty tree reports `dirty` and fails. A new `swiftpm-testing-helper-*.ips` crash report under `~/Library/Logs/DiagnosticReports` during the run fails it too, and the summary names the file.

A pass at a clean head also records that commit in `grimoire-check-passed` in the git common directory, which every worktree shares. The `pre-push` hook (`scripts/install-hooks.sh`, once per clone) lints every push and refuses `main` and `v*` tags for a commit without that record.

The suites in `GrimoireIntelligence` gated on `modelIsReady` run the real on-device model, so they only run on a Mac that has it, and its output varies from run to run. `WritingEvaluations` fails now and then on unchanged code. When a failure sits only in those suites, the script reruns the package once; a pass on the rerun counts, and the summary shows both result lines and the name of the test that failed. Any other failure is real until it has a ticket or a measured cause, and a failure that repeats is real regardless. Never call a non-model failure a flake without one of those.

Derived data (`build/DerivedData`) and each package's `.build` sit inside the checkout, so runs in separate worktrees don't share a build. The first build in a worktree fetches and compiles the tree-sitter grammars, which takes a few minutes and needs a network connection.

The timing tests assume a local Apple silicon Mac. On a slower machine, set `GRIMOIRE_PERF_BUDGET_SCALE` to stretch their budgets.

`WKWebView` never loads inside `swift test`, so PDF export and print can't be covered there. Check them in the built Mac app.

Native QA notes for folder content templates are in [docs/qa/folder-content-templates.md](qa/folder-content-templates.md).

## Workflows

`.github/workflows/release.yml` packages a DMG when a `v*` tag is pushed; see `docs/RELEASING.md`. No other workflow exists.
