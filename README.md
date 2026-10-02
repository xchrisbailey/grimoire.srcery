# grimoire.srcery

A native markdown editor for macOS, with an iOS companion, by srcery. Work is tracked in GitHub Issues, starting at the epic #1.

## Layout

| Path | What lives there |
|---|---|
| `Packages/GrimoireCore` | Pure Swift: document/block model, markdown parse and serialize, workspaces, theme tokens. No AppKit or UIKit. |
| `Packages/GrimoireEditor` | TextKit 2 editor engine with thin `NSTextView` / `UITextView` adapters, plus font helpers. |
| `Packages/GrimoireIntelligence` | Foundation Models wrapper (empty until #18). |
| `Apps/GrimoireMac` | SwiftUI macOS app. |
| `Apps/GrimoireiOS` | Placeholder iOS app so the shared code keeps compiling for iOS. |
| `Apps/Shared` | Asset catalog shared by both apps. |
| `Resources` | String Catalog and bundled fonts, shared by both apps. |
| `Brand` | SVG masters of the mark and wordmark, and the Icon Composer icon. |

## Building

Requires Xcode 27 (macOS 27 / iOS 27 SDKs) and [XcodeGen](https://github.com/yonaskolb/XcodeGen). The Xcode project is generated from `project.yml` and is not checked in. App sources are synced folders, so new files build without regenerating; run `xcodegen generate` again only when `project.yml` changes.

```sh
xcodegen generate
open Grimoire.xcodeproj
```

The first build fetches the tree-sitter grammars that color code blocks (#13), so it needs a network connection and takes a few minutes.

Package tests run on their own:

```sh
(cd Packages/GrimoireCore && swift test)
```

Formatting uses `swift-format` (ships with Xcode) and SwiftLint:

```sh
xcrun swift-format format --in-place --recursive Apps Packages
swiftlint
```

## Packaging a release

`scripts/package-mac.sh <label>` builds an ad-hoc signed Release of the Mac app and writes `dist/Grimoire-<label>.dmg` with its SHA-256. The version shown in the app comes from `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`; the label only names the DMG and volume.

```sh
scripts/package-mac.sh 1.0.0-beta.1
```

The build isn't notarized (no Developer ID yet, see #16), so Gatekeeper blocks the first launch. The DMG carries a "Read me first" note: right-click the app in Applications and choose Open, or run `xattr -dr com.apple.quarantine /Applications/Grimoire.app`.
