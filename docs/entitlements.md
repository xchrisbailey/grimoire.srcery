# Sandbox entitlements

The Mac app is sandboxed and runs with the hardened runtime. This is what each entry in `Apps/GrimoireMac/GrimoireMac.entitlements` is for, checked against the code on 2026-10-08 for #16. Recheck it when an entitlement is added, or when the code that needs one goes away.

| Entitlement | What needs it | Without it |
| --- | --- | --- |
| `com.apple.security.app-sandbox` | Everything below depends on it, and Sparkle's installer service is set up for a sandboxed app. | |
| `com.apple.security.files.user-selected.read-write` | Folders bound to a project through the open panel, files opened from Finder, export through the save panel, and picking images and themes. | No file outside the app's container can be read or written. |
| `com.apple.security.files.bookmarks.app-scope` | The bookmarks `FolderBookmark` makes for project folders and loose files, so they open again after a relaunch. | Every folder and loose file has to be chosen again at each launch. |
| `com.apple.security.network.client` | `WKWebView` in `PagePrinter`, which lays out PDF export and print, and Sparkle, which fetches the update feed and the DMG. | `loadHTMLString` never finishes in the sandbox, even for local HTML, so PDF export and print hang; the app can't update. |
| `com.apple.security.print` | Print, which sends the PDF through `PDFDocument`'s print operation. | The print panel can't reach a printer. |
| `com.apple.security.temporary-exception.mach-lookup.global-name` (`<bundle id>-spks`, `<bundle id>-spki`) | Sparkle's XPC installer and its status service, which install an update on behalf of the sandboxed app. | An update downloads and then fails to install. |

## What goes over the network

The #16 brief was "no network unless it's needed". These are the only requests the app makes:

- **Update checks.** Sparkle reads `appcast.xml` from GitHub Pages in the background, and downloads the DMG from the GitHub release when the user accepts an update. It sends no system profile.
- **Remote images when exporting a PDF or printing.** The exported HTML keeps an image's `https` address, so `WKWebView` fetches it while laying out the page. The editor itself doesn't: `ImageCache` loads file URLs only.

Nothing else opens a connection. Writing commands, image reading and project answers run on the on-device model, and diagnostics from MetricKit are saved to disk and never sent.

## Not requested

No camera, microphone, location, contacts, calendar, photo library, Apple Events, or incoming network entitlement, and no hardened-runtime exception (JIT, unsigned memory, library validation). The app starts no other process itself.

## Open points

- The mach-lookup entry is a temporary exception, which the Mac App Store doesn't accept. A Mac App Store build would leave Sparkle and this entry out.
- Fetching remote images during PDF export and print tells the image's host that the page was exported. If that should be the user's choice, `PagePrinter` is where to block it.
