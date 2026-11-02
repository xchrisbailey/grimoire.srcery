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

**The DMG window.** The DMG opens as a fixed-size icon-view window with the mark on Mocha behind the app and the Applications shortcut (artwork in `Brand/dmg-background.tiff`, geometry in `Brand/dmg-layout.json`; `Brand/README.md` says how to regenerate it). The script builds a writable image, mounts it at `/Volumes/Grimoire <label>` (so that name must be free), writes the window layout into its `.DS_Store` with `scripts/dmg-layout.py`, ejects it and compresses it. That script writes the file directly with Python's standard library, never driving Finder, so a headless runner and a Mac with a logged-in user get the same layout; `python3 scripts/test-dmg-layout.py` checks what it writes. The ad-hoc "Read me first" note sits in the bottom corner, off the artwork.

To try the updater on a Mac that has the certificate but no notary profile, `SKIP_NOTARIZE=1 TEAM_ID=<team id> scripts/package-mac.sh <label>` signs everything with the Developer ID identity and stops before notarization. Setting `LOCAL_FEED_URL=http://localhost:8000/appcast.xml` as well points the app at a feed served from this Mac, with an App Transport Security exception for that host. A build made either way is never notarized, and the script refuses `LOCAL_FEED_URL` together with notarization.

## QA builds

`TEAM_ID=<team id> scripts/package-qa.sh <label>` writes `dist/qa/<label>/GrimoireQA.app` for trying a commit on a Mac that has the real Grimoire. It is signed with the Developer ID Application certificate, hardened and sandboxed like a release, and never notarized. Its bundle identifier is `computer.srcery.grimoire.qa` and its name `GrimoireQA`, so the sandbox gives it a container of its own and it can't touch the real app's projects, versions or preferences. Its update feed is removed and automatic checks are off. The production identifier is refused.

It builds `HEAD` from a scratch export (`git archive`), so tracked files in the checkout stay as they were and the app matches a commit. The script verifies the signature, identifier, name, sandbox entitlement and absent feed before reporting. Gatekeeper rejects the app as unnotarized if it is downloaded; one built on the Mac that runs it opens normally.

## Updates

The Mac app updates itself with [Sparkle](https://sparkle-project.org). It checks `https://xchrisbailey.github.io/grimoire.srcery/appcast.xml` in the background, and the app menu has "Check for Updates…". The feed URL and the EdDSA public key (`SUPublicEDKey`) are in `Config/GrimoireMac-Info.plist`. The app stays sandboxed and installs through Sparkle's XPC installer service, which the `-spks` and `-spki` mach-lookup entries in `GrimoireMac.entitlements` allow. `docs/entitlements.md` says what each sandbox entitlement is for.

**Build numbers.** Sparkle compares `CFBundleVersion`, which is `CURRENT_PROJECT_VERSION` in `project.yml`. Raise it for every release (beta 1 was 1, beta 2 was 2), before tagging. The release workflow runs `scripts/check-build-number.sh` before packaging and fails if the number isn't higher than every build in the published feed. A feed that doesn't exist yet (HTTP 404) passes; any other failure to read it fails the run. Re-running a release whose feed was already published fails for the same reason: the feed then holds that build number.

**The feed.** After the DMG is attached to the release, the workflow runs `scripts/make-appcast.sh`, which signs that DMG with the EdDSA key and has Sparkle's `generate_appcast` write `appcast.xml` with one item: version, build number, minimum macOS version, the release DMG's download URL, its length and signature, and a link to the release's page for the notes. The tools come from the Sparkle package the build resolved, so they match the linked framework. The workflow also attaches `appcast.xml` to the release: that asset is the source of truth for the feed. A second job then deploys GitHub Pages, which is the product page from `site/` plus that `appcast.xml`, assembled by `scripts/assemble-pages.sh`. Every Pages deploy replaces the whole site, so both this workflow and `pages.yml` (which redeploys the page when `site/` changes) publish `site/` plus the latest `appcast.xml`. `pages.yml` takes it from the newest non-draft release that has the asset and fails if none does. Nothing may deploy Pages without the feed. Pages must use GitHub Actions as its source and the `github-pages` environment must allow `v*` tags.

**The key.** The `SPARKLE_PRIVATE_KEY` repository secret holds the private key in the form `generate_keys -x` exports. It's also kept in the login keychain of the Mac that generated it, under the Sparkle account `grimoire`. Losing it means shipping a build with a new `SUPublicEDKey` that nobody can update to, so keep a backup. Never print or commit it.

**Re-running a release.** If a run fails after the DMG is on the release, "Re-run failed jobs" on the same run recovers it. Re-running the `mac` job passes the build-number check, because nothing was published (the feed is missing, or still holds a lower build), repackages the DMG, replaces the release's copy, and signs the copy the release now serves, so the feed always matches the download. Re-running only the `feed` job redeploys the feed the first attempt built, which matches the DMG that attempt uploaded. Once the feed has been published, a re-run of the `mac` job fails at the build-number check, because the feed already holds that build: that is the safe outcome, and a fix needs a new build number and a new tag.

The feed is only published for a signed, notarized build with `SPARKLE_PRIVATE_KEY` set. Without the key, or on an ad-hoc build, the workflow skips the feed and still attaches the DMG.

To try an update without a release, build an older build number and a newer one with `SKIP_NOTARIZE=1` and `LOCAL_FEED_URL` as above, build the feed with `SPARKLE_ACCOUNT=grimoire DOWNLOAD_URL_PREFIX=http://localhost:8000/ RELEASE_NOTES_URL=http://localhost:8000/notes.html scripts/make-appcast.sh v<label> dist/Grimoire-<label>.dmg <dir>`, serve `<dir>` and the DMG with `python3 -m http.server 8000`, and open the older app.

## Before tagging

Nothing runs in CI, so these steps are the gate. Do them in order:

1. Raise `CURRENT_PROJECT_VERSION` in `project.yml` (see Build numbers) and commit it. That commit is the one you tag, so the check runs on it. A check that passed on the commit before it doesn't cover it: the bump touches `project.yml`, which counts as code.
2. Run `scripts/check.sh --core-runs 10` at a clean head of the commit, and read `build/check-logs/<sha>/summary.txt`. A pass records the SHA in `grimoire-check-passed` in the git common directory (the stamp), shared by every worktree. The `pre-push` hook (`scripts/install-hooks.sh`) refuses `main` or a `v*` tag for a commit that isn't in the stamp, or doesn't differ from a stamped one only in `*.md` or `docs/**`.
3. Run the filesystem matrix below with a `scripts/package-qa.sh` build of the same commit.
4. If this release changes anything an installed build stores (`projects.json`, the version index, a preference key), say in the release notes what rolling back to the previous release loses. `StoredShapeTests` fails when a stored value or key changes, and says which; a deliberate change updates its snapshot. Once the release ships, repoint the snapshot and fixtures in `Packages/GrimoireCore/Tests/GrimoireCoreTests/Fixtures/StoredShape` at the new tag.
5. Test a Sparkle update (below) when the release changes the updater, the feed, or the app's signing.
6. Push `main`, then the tag (see Releasing from CI).

**Filesystem matrix.** Documents live on whatever volume the user picked, so try the release on each filesystem it can meet. Make disk images outside the repository, and attach each one:

```sh
for fs in APFS HFS+ ExFAT; do
  hdiutil create -size 100m -fs "$fs" -volname "QA-$fs" "$TMPDIR/qa-$fs.dmg"
  hdiutil attach "$TMPDIR/qa-$fs.dmg"
done
```

In `GrimoireQA`, bind a folder on each volume (`/Volumes/QA-APFS`, `/Volumes/QA-HFS+`, `/Volumes/QA-ExFAT`) to a project, then on each: create a document, edit and save it, rename it, move it into a subfolder and back, and reopen the project. Detach afterwards with `hdiutil detach /Volumes/QA-<fs>` and delete the images. SMB shares are unverified unless someone tests one; say so in the release notes when a release depends on one.

**Testing a Sparkle update without touching a real library.** A human does this; it needs a second login. Create a throwaway standard user in System Settings > Users & Groups, switch to it, and install the previous release there from its GitHub release DMG. Open it, bind a scratch folder inside that account, and edit a few files so it has a library and versions.

- Before publishing, build the previous and the new build numbers with `SKIP_NOTARIZE=1` and `LOCAL_FEED_URL` (see Updates), install the older one in the throwaway account, and serve the feed from your own account with `python3 -m http.server 8000`. `localhost` reaches it from the other account.
- After publishing, the installed previous release finds the new one through the real feed.

Choose Check for Updates, install, and relaunch. The projects and versions must be there. The throwaway account's home folder holds the only copy of that library, so delete the account, with its home folder, when you finish.

## Releasing from CI

Pushing a `v*` tag runs `.github/workflows/release.yml`, which packages the DMG, attaches it to that tag's GitHub release (a prerelease if it's new), and publishes the update feed (see Updates). That workflow builds and signs but runs no tests, so the stamp from Before tagging is the only gate: the `pre-push` hook refuses the tag, and `main`, for a commit without it. Tag the commit that passed:

```sh
git push origin main
git tag v1.0.0-beta.2 && git push origin v1.0.0-beta.2
```

`git push --no-verify` skips the hook. Use it only when the release must go out and the check can't run, and say so in the release notes.

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
