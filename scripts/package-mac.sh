#!/bin/sh
# Builds an ad-hoc signed Release of the Mac app and packages it as a DMG in dist/.
# There is no Developer ID yet, so the app is not notarized and Gatekeeper asks
# before the first launch (see dist/README after a run, or the release notes).
#
# Usage, from the repo root:  scripts/package-mac.sh 1.0.0-beta.1
set -eu

label=${1:?usage: scripts/package-mac.sh <release label, e.g. 1.0.0-beta.1>}
root=$(cd "$(dirname "$0")/.." && pwd)
build="$root/build/release"
dist="$root/dist"
app="$build/Build/Products/Release/Grimoire.app"
dmg="$dist/Grimoire-$label.dmg"

cd "$root"
xcodegen generate --quiet
rm -rf "$build" "$dist"
xcodebuild build \
  -project Grimoire.xcodeproj -scheme GrimoireMac -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$build" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  -quiet

codesign --verify --deep --strict "$app"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' -c 'Print :CFBundleVersion' \
  "$app/Contents/Info.plist"

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Grimoire.app"
ln -s /Applications "$stage/Applications"
cat > "$stage/Read me first.txt" <<'TXT'
Grimoire is not notarized by Apple yet, so macOS blocks the first launch.

1. Drag Grimoire into Applications.
2. In Applications, right-click (or Control-click) Grimoire and choose Open,
   then choose Open again in the dialog. On recent macOS versions you may
   instead need System Settings > Privacy & Security > "Open Anyway".

Or, in Terminal:  xattr -dr com.apple.quarantine /Applications/Grimoire.app

After that, Grimoire opens normally.
TXT

mkdir -p "$dist"
hdiutil create -quiet -volname "Grimoire $label" -srcfolder "$stage" -fs HFS+ -format UDZO "$dmg"
(cd "$dist" && shasum -a 256 "${dmg##*/}" | tee "${dmg##*/}.sha256")
