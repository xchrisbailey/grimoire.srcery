#!/bin/sh
# Builds a Release of the Mac app and packages it as a DMG in dist/.
#
# With TEAM_ID set, the app and DMG are signed with that team's Developer ID
# Application certificate (from the login keychain), then the DMG is notarized
# and stapled. Notarization reads credentials from a notarytool keychain profile,
# NOTARY_PROFILE (default "grimoire-notary"), saved once with:
#   xcrun notarytool store-credentials grimoire-notary --apple-id <email> --team-id <TEAM_ID>
#
# Without TEAM_ID the build is ad-hoc signed and not notarized, and the DMG
# carries a note on getting past Gatekeeper.
#
# Usage, from the repo root:  [TEAM_ID=ABCDE12345] scripts/package-mac.sh 1.0.0-beta.2
set -eu

label=${1:?usage: scripts/package-mac.sh <release label, e.g. 1.0.0-beta.2>}
team=${TEAM_ID:-}
profile=${NOTARY_PROFILE:-grimoire-notary}
root=$(cd "$(dirname "$0")/.." && pwd)
build="$root/build/release"
dist="$root/dist"
app="$build/Build/Products/Release/Grimoire.app"
dmg="$dist/Grimoire-$label.dmg"

if [ -n "$team" ]; then
  # Fail before the slow build if the certificate or notary profile is missing.
  identity=$(security find-identity -v -p codesigning \
    | sed -n "s/.*\"\(Developer ID Application: .*($team)\)\"/\1/p" | head -1)
  [ -n "$identity" ] \
    || { echo "No Developer ID Application certificate for team $team in the keychain." >&2; exit 1; }
  xcrun notarytool history --keychain-profile "$profile" >/dev/null \
    || { echo "No notarytool keychain profile named $profile." >&2; exit 1; }
else
  identity=-
  echo "TEAM_ID not set: building ad-hoc signed, without notarization." >&2
fi

cd "$root"
xcodegen generate --quiet
rm -rf "$build" "$dist"
xcodebuild build \
  -project Grimoire.xcodeproj -scheme GrimoireMac -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$build" \
  CODE_SIGN_IDENTITY="$identity" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$team" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS=--timestamp \
  -quiet

codesign --verify --deep --strict "$app"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' -c 'Print :CFBundleVersion' \
  "$app/Contents/Info.plist"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Grimoire.app"
ln -s /Applications "$stage/Applications"
if [ -z "$team" ]; then
  cat > "$stage/Read me first.txt" <<'TXT'
Grimoire is not notarized by Apple yet, so macOS blocks the first launch.

1. Drag Grimoire into Applications.
2. In Applications, right-click (or Control-click) Grimoire and choose Open,
   then choose Open again in the dialog. On recent macOS versions you may
   instead need System Settings > Privacy & Security > "Open Anyway".

Or, in Terminal:  xattr -dr com.apple.quarantine /Applications/Grimoire.app

After that, Grimoire opens normally.
TXT
fi

mkdir -p "$dist"
hdiutil create -quiet -volname "Grimoire $label" -srcfolder "$stage" -fs HFS+ -format UDZO "$dmg"

if [ -n "$team" ]; then
  codesign --sign "$identity" --timestamp "$dmg"
  # Prints the submission ID; if it comes back Invalid, `xcrun notarytool log <id>
  # --keychain-profile <profile>` says why, and the staple below fails.
  xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
  xcrun stapler staple "$dmg"
  spctl --assess --type open --context context:primary-signature --verbose "$dmg"
fi

(cd "$dist" && shasum -a 256 "${dmg##*/}" | tee "${dmg##*/}.sha256")
