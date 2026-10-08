# Development

Grimoire is a native markdown editor for macOS with an iOS companion. It requires Xcode 27 with the macOS 27 and iOS 27 SDKs, XcodeGen, and SwiftLint. `README.md` covers the layout, opening the project, and packaging a release.

## Checks

Run these from the root of the checkout or worktree before a branch is reviewed or merged. `Grimoire.xcodeproj` is generated and not checked in, so a fresh worktree has none until the first command runs.

```sh
xcodegen generate
xcodebuild build -project Grimoire.xcodeproj -scheme GrimoireMac -destination 'platform=macOS' -derivedDataPath build/DerivedData ARCHS=arm64 CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Grimoire.xcodeproj -scheme GrimoireiOS -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData ARCHS=arm64 CODE_SIGNING_ALLOWED=NO
(cd Packages/GrimoireCore && swift test)
(cd Packages/GrimoireEditor && swift test)
(cd Packages/GrimoireIntelligence && swift test)
xcrun swift-format lint --strict --recursive Apps Packages
swiftlint --strict
```

Each build ends in `** BUILD SUCCEEDED **` or `** BUILD FAILED **`, and each package in a `Test run with … passed` or `… failed` line. When clean, `swift-format` prints nothing and SwiftLint ends in `Found 0 violations`.

The suites in `GrimoireIntelligence` gated on `modelIsReady` run the real on-device model, so they only run on a Mac that has it, and its output varies from run to run. `WritingEvaluations` fails now and then on unchanged code. When one of those suites fails, rerun the package: a pass on the rerun counts, reported with both result lines and the name of the test that failed. A failure anywhere else, or one that repeats, is a real failure.

Derived data (`build/DerivedData`) and each package's `.build` sit inside the checkout, so runs in separate worktrees don't share a build. The first build in a worktree fetches and compiles the tree-sitter grammars, which takes a few minutes and needs a network connection.

The timing tests assume a local Apple silicon Mac. On a slower machine, set `GRIMOIRE_PERF_BUDGET_SCALE` to stretch their budgets, as CI does.

`WKWebView` never loads inside `swift test`, so PDF export and print can't be covered there. Check them in the built Mac app.

## CI

`.github/workflows/ci.yml` runs on every pull request and every push to `main`, on the `xcode-27` GitHub-hosted runner (or the runner named by the `MACOS_RUNNER` repository variable). It runs the same checks: `swift test` in each package, both app builds, and both linters. Pushes to `main` also run the release-mode parse speed tests in `GrimoireCore`. A newer push to the same ref cancels the run in progress.

`.github/workflows/release.yml` packages a DMG when a `v*` tag is pushed; see the README.
