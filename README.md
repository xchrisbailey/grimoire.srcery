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

`scripts/package-mac.sh <label>` builds a Release of the Mac app and writes `dist/Grimoire-<label>.dmg` with its SHA-256. The version shown in the app comes from `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`; the label only names the DMG and volume.

```sh
TEAM_ID=<team id> scripts/package-mac.sh 1.0.0-beta.2
```

With `TEAM_ID` set, the app and DMG are signed with that team's Developer ID Application certificate, and the DMG is notarized and stapled. That needs, once per Mac:

1. The Developer ID Application certificate in the login keychain (Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application).
2. A notarytool profile, saved with an app-specific password from account.apple.com: `xcrun notarytool store-credentials grimoire-notary --apple-id <email> --team-id <team id>`. Set `NOTARY_PROFILE` to use another name.

Without `TEAM_ID`, the build is ad-hoc signed and not notarized, so Gatekeeper blocks the first launch. That DMG carries a "Read me first" note: right-click the app in Applications and choose Open, or run `xattr -dr com.apple.quarantine /Applications/Grimoire.app`.

### Releasing from CI

Pushing a `v*` tag runs `.github/workflows/release.yml`, which packages the DMG and attaches it to that tag's GitHub release (a prerelease if it's new):

```sh
git tag v1.0.0-beta.2 && git push origin v1.0.0-beta.2
```

It signs and notarizes when these repository secrets are set (Settings > Secrets and variables > Actions), and builds ad-hoc signed when they aren't:

| Secret | What goes in it |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | The Developer ID Application certificate and its private key, exported from Keychain Access as a .p12 and base64 encoded: `base64 -i grimoire.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PASSWORD` | The password you gave the .p12 when exporting it |
| `APP_STORE_CONNECT_API_KEY` | The whole contents of the `AuthKey_<id>.p8` file, including the BEGIN and END lines |
| `APP_STORE_CONNECT_KEY_ID` | That key's ID |
| `APP_STORE_CONNECT_ISSUER_ID` | The issuer ID shown above the key list |

To make them:

1. **Certificate.** In Xcode > Settings > Accounts, select the team, choose Manage Certificates, and add a Developer ID Application certificate. In Keychain Access > My Certificates, right-click "Developer ID Application: …", choose Export, and save a .p12 with a password.
2. **API key.** In App Store Connect > Users and Access > Integrations > App Store Connect API, generate a Team key with the Developer role. Download the .p8 (it can only be downloaded once) and note the key ID and issuer ID.

The team ID is read from the certificate, so it isn't a secret of its own.
