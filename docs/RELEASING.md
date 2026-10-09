# Releasing Grimoire

## Packaging a DMG

`scripts/package-mac.sh <label>` builds a Release of the Mac app and writes `dist/Grimoire-<label>.dmg` with its SHA-256. The version shown in the app comes from `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`; the label only names the DMG and volume.

```sh
TEAM_ID=<team id> scripts/package-mac.sh 1.0.0-beta.2
```

With `TEAM_ID` set, the app and DMG are signed with that team's Developer ID Application certificate, and the DMG is notarized and stapled. That needs, once per Mac:

1. The Developer ID Application certificate in the login keychain (Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application).
2. A notarytool profile, saved with an app-specific password from account.apple.com: `xcrun notarytool store-credentials grimoire-notary --apple-id <email> --team-id <team id>`. Set `NOTARY_PROFILE` to use another name.

Sparkle's framework, XPC services and helper apps are signed one component at a time, inside out, with the same identity, hardened runtime and a timestamp; the script checks each one's signature and then runs `codesign --verify --deep --strict` on the app.

Without `TEAM_ID`, the build is ad-hoc signed and not notarized, so Gatekeeper blocks the first launch. That DMG carries a "Read me first" note: right-click the app in Applications and choose Open, or run `xattr -dr com.apple.quarantine /Applications/Grimoire.app`.

To try the updater on a Mac that has the certificate but no notary profile, `SKIP_NOTARIZE=1 TEAM_ID=<team id> scripts/package-mac.sh <label>` signs everything with the Developer ID identity and stops before notarization. Setting `LOCAL_FEED_URL=http://localhost:8000/appcast.xml` as well points the app at a feed served from this Mac, with an App Transport Security exception for that host. A build made either way is never notarized, and the script refuses `LOCAL_FEED_URL` together with notarization.

## Updates

The Mac app updates itself with [Sparkle](https://sparkle-project.org). It checks `https://xchrisbailey.github.io/grimoire.srcery/appcast.xml` in the background, and the app menu has "Check for Updates…". The feed URL and the EdDSA public key (`SUPublicEDKey`) are in `Config/GrimoireMac-Info.plist`. The app stays sandboxed and installs through Sparkle's XPC installer service, which the `-spks` and `-spki` mach-lookup entries in `GrimoireMac.entitlements` allow. `docs/entitlements.md` says what each sandbox entitlement is for.

**Build numbers.** Sparkle compares `CFBundleVersion`, which is `CURRENT_PROJECT_VERSION` in `project.yml`. Raise it for every release (beta 1 was 1, beta 2 was 2), before tagging. The release workflow runs `scripts/check-build-number.sh` before packaging and fails if the number isn't higher than every build in the published feed. A feed that doesn't exist yet (HTTP 404) passes; any other failure to read it fails the run. Re-running a release whose feed was already published fails for the same reason: the feed then holds that build number.

**The feed.** After the DMG is attached to the release, the workflow runs `scripts/make-appcast.sh`, which signs that DMG with the EdDSA key and has Sparkle's `generate_appcast` write `appcast.xml` with one item: version, build number, minimum macOS version, the release DMG's download URL, its length and signature, and a link to the release's page for the notes. The tools come from the Sparkle package the build resolved, so they match the linked framework. A second job then deploys the feed to GitHub Pages. The workflow owns the whole Pages site, and every deploy replaces it, so nothing else may publish there. Pages must use GitHub Actions as its source and the `github-pages` environment must allow `v*` tags.

**The key.** The `SPARKLE_PRIVATE_KEY` repository secret holds the private key in the form `generate_keys -x` exports. It's also kept in the login keychain of the Mac that generated it, under the Sparkle account `grimoire`. Losing it means shipping a build with a new `SUPublicEDKey` that nobody can update to, so keep a backup. Never print or commit it.

**Re-running a release.** If a run fails after the DMG is on the release, "Re-run failed jobs" on the same run recovers it. Re-running the `mac` job passes the build-number check, because nothing was published (the feed is missing, or still holds a lower build), repackages the DMG, replaces the release's copy, and signs the copy the release now serves, so the feed always matches the download. Re-running only the `feed` job redeploys the feed the first attempt built, which matches the DMG that attempt uploaded. Once the feed has been published, a re-run of the `mac` job fails at the build-number check, because the feed already holds that build: that is the safe outcome, and a fix needs a new build number and a new tag.

The feed is only published for a signed, notarized build with `SPARKLE_PRIVATE_KEY` set. Without the key, or on an ad-hoc build, the workflow skips the feed and still attaches the DMG.

To try an update without a release, build an older build number and a newer one with `SKIP_NOTARIZE=1` and `LOCAL_FEED_URL` as above, build the feed with `SPARKLE_ACCOUNT=grimoire DOWNLOAD_URL_PREFIX=http://localhost:8000/ RELEASE_NOTES_URL=http://localhost:8000/notes.html scripts/make-appcast.sh v<label> dist/Grimoire-<label>.dmg <dir>`, serve `<dir>` and the DMG with `python3 -m http.server 8000`, and open the older app.

## Releasing from CI

Pushing a `v*` tag runs `.github/workflows/release.yml`, which packages the DMG, attaches it to that tag's GitHub release (a prerelease if it's new), and publishes the update feed (see Updates). Raise `CURRENT_PROJECT_VERSION` first:

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
| `SPARKLE_PRIVATE_KEY` | The Sparkle EdDSA private key, as `generate_keys -x` exports it (see Updates). Without it the workflow skips the feed. |

To make them:

1. **Certificate.** In Xcode > Settings > Accounts, select the team, choose Manage Certificates, and add a Developer ID Application certificate. In Keychain Access > My Certificates, right-click "Developer ID Application: …", choose Export, and save a .p12 with a password.
2. **API key.** In App Store Connect > Users and Access > Integrations > App Store Connect API, generate a Team key with the Developer role. Download the .p8 (it can only be downloaded once) and note the key ID and issuer ID.

The team ID is read from the certificate, so it isn't a secret of its own.
