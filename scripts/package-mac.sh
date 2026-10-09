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
# Two variables exist only to try the updater on a development Mac, and the
# result is never notarized, so it can't be released:
#   SKIP_NOTARIZE=1   with TEAM_ID, signs with the Developer ID certificate but skips
#                     the notary profile, notarization, stapling and spctl.
#   LOCAL_FEED_URL    points the app at a feed served over plain http from this Mac,
#                     with an App Transport Security exception for that host.
#
# Sparkle's nested code (XPC services, helper apps, the framework) is signed one
# component at a time, inside out, never with --deep, as Sparkle's sandboxing guide
# describes for builds signed outside Xcode's archive export.
#
# Usage, from the repo root:  [TEAM_ID=ABCDE12345] scripts/package-mac.sh 1.0.0-beta.2
set -eu

label=${1:?usage: scripts/package-mac.sh <release label, e.g. 1.0.0-beta.2>}
team=${TEAM_ID:-}
profile=${NOTARY_PROFILE:-grimoire-notary}
skip_notarize=${SKIP_NOTARIZE:-}
local_feed=${LOCAL_FEED_URL:-}
feed_url=https://xchrisbailey.github.io/grimoire.srcery/appcast.xml
root=$(cd "$(dirname "$0")/.." && pwd)
build="$root/build/release"
dist="$root/dist"
app="$build/Build/Products/Release/Grimoire.app"
dmg="$dist/Grimoire-$label.dmg"

# A build that talks to a local http feed must never be notarized or released.
if [ -n "$local_feed" ] && [ -n "$team" ] && [ -z "$skip_notarize" ]; then
  echo "LOCAL_FEED_URL builds can't be notarized: set SKIP_NOTARIZE=1 or unset TEAM_ID." >&2
  exit 1
fi

if [ -n "$team" ]; then
  # Fail before the slow build if the certificate or notary profile is missing.
  identity=$(security find-identity -v -p codesigning \
    | sed -n "s/.*\"\(Developer ID Application: .*($team)\)\"/\1/p" | head -1)
  [ -n "$identity" ] \
    || { echo "No Developer ID Application certificate for team $team in the keychain." >&2; exit 1; }
  if [ -n "$skip_notarize" ]; then
    echo "SKIP_NOTARIZE set: signing with the Developer ID certificate, without notarization." >&2
  else
    xcrun notarytool history --keychain-profile "$profile" >/dev/null \
      || { echo "No notarytool keychain profile named $profile." >&2; exit 1; }
  fi
else
  identity=-
  [ -z "$skip_notarize" ] || { echo "SKIP_NOTARIZE needs TEAM_ID." >&2; exit 1; }
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

plist="$app/Contents/Info.plist"
if [ -n "$local_feed" ]; then
  host=$(printf '%s' "$local_feed" | sed -n 's|^http://\([^:/]*\).*|\1|p')
  [ -n "$host" ] || { echo "LOCAL_FEED_URL must be an http:// URL." >&2; exit 1; }
  /usr/libexec/PlistBuddy \
    -c "Set :SUFeedURL $local_feed" \
    -c "Add :NSAppTransportSecurity:NSExceptionDomains:$host:NSExceptionAllowsInsecureHTTPLoads bool true" \
    "$plist"
fi

# Re-sign inside out: Sparkle's XPC services, helper tools and framework first, then
# the app, keeping its entitlements. A timestamp needs the real identity.
if [ -n "$team" ]; then stamp=--timestamp; else stamp=--timestamp=none; fi
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
set -- "$sparkle/XPCServices/Installer.xpc" "$sparkle/XPCServices/Downloader.xpc" \
  "$sparkle/Autoupdate" "$sparkle/Updater.app" "$app/Contents/Frameworks/Sparkle.framework"
for component in "$@"; do
  [ -e "$component" ] || { echo "Missing Sparkle component: $component" >&2; exit 1; }
  codesign --force --sign "$identity" --options runtime "$stamp" \
    --preserve-metadata=entitlements "$component"
done
codesign --force --sign "$identity" --options runtime "$stamp" \
  --preserve-metadata=entitlements "$app"

codesign --verify --deep --strict "$app"
if [ -n "$team" ]; then
  # Every component is signed by the team, with hardened runtime and a secure timestamp.
  for component in "$@" "$app"; do
    details=$(codesign -dv --verbose=4 "$component" 2>&1)
    for expected in "TeamIdentifier=$team" "flags=0x10000(runtime)" "Timestamp="; do
      printf '%s\n' "$details" | grep -q -F "$expected" \
        || { echo "$component: no $expected in its signature." >&2; exit 1; }
    done
  done
fi
if [ -z "$local_feed" ]; then
  # Every build that isn't for a local update run, ad-hoc ones included since the
  # workflow attaches those to the release too, reads only the published feed, over https.
  [ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist")" = "$feed_url" ] \
    || { echo "The app's SUFeedURL isn't $feed_url." >&2; exit 1; }
  ! /usr/libexec/PlistBuddy -c 'Print :NSAppTransportSecurity' "$plist" >/dev/null 2>&1 \
    || { echo "The app has an App Transport Security exception." >&2; exit 1; }
fi
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' -c 'Print :CFBundleVersion' \
  "$app/Contents/Info.plist"

stage=$(mktemp -d)
volume="Grimoire $label"
mount="/Volumes/$volume"
attached=
scratch=
cleanup() {
  [ -z "$attached" ] || hdiutil detach "$mount" -force -quiet >/dev/null 2>&1 || true
  rm -rf "$stage"
  [ -z "$scratch" ] || rm -f "$scratch"
}
trap cleanup EXIT
ditto "$app" "$stage/Grimoire.app"
ln -s /Applications "$stage/Applications"
# The Finder window's artwork is a hidden file on the volume. Brand/scripts/dmg-background.swift
# renders it; Brand/dmg-layout.json says where everything sits. Ad-hoc builds carry a note,
# and their artwork has a label plate for it.
mkdir "$stage/.background"
if [ -z "$team" ]; then
  cp "$root/Brand/dmg-background-with-note.tiff" "$stage/.background/background.tiff"
else
  cp "$root/Brand/dmg-background.tiff" "$stage/.background/background.tiff"
fi
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

# Lay out the window: build a writable image, write its .DS_Store with scripts/dmg-layout.py
# (no Finder or window server, so it works the same on a headless runner), then compress.
# The layout refers to the artwork on the mounted volume, so it is mounted at its own name.
[ ! -e "$mount" ] || { echo "$mount is already mounted or exists; eject it first." >&2; exit 1; }
mkdir -p "$dist"
scratch="$dist/.layout-$$.dmg"
hdiutil create -quiet -volname "$volume" -srcfolder "$stage" -fs HFS+ -format UDRW "$scratch"
attached=1
hdiutil attach -quiet -nobrowse -noautoopen -noverify "$scratch" >/dev/null 2>&1 \
  || { echo "Could not attach the layout image at $mount." >&2; exit 1; }
[ -d "$mount/.background" ] \
  || { echo "The layout image didn't mount at $mount." >&2; exit 1; }
python3 "$root/scripts/dmg-layout.py" "$mount" "$root/Brand/dmg-layout.json"
# Spotlight and FSEvents drop bookkeeping folders on a freshly attached volume.
rm -rf "$mount/.fseventsd" "$mount/.Spotlight-V100" "$mount/.Trashes"
sync
# Detaching can fail while the volume is briefly busy.
n=0
until hdiutil detach "$mount" -quiet >/dev/null 2>&1; do
  n=$((n + 1))
  [ "$n" -lt 10 ] || { echo "Could not eject $mount." >&2; exit 1; }
  sleep 1
done
attached=
hdiutil convert -quiet "$scratch" -format UDZO -o "$dmg"
rm -f "$scratch"
scratch=

if [ -n "$team" ]; then
  codesign --sign "$identity" --timestamp "$dmg"
fi
if [ -n "$team" ] && [ -z "$skip_notarize" ]; then
  # Prints the submission ID; if it comes back Invalid, `xcrun notarytool log <id>
  # --keychain-profile <profile>` says why, and the staple below fails.
  xcrun notarytool submit "$dmg" --keychain-profile "$profile" --wait
  xcrun stapler staple "$dmg"
  spctl --assess --type open --context context:primary-signature --verbose "$dmg"
fi

(cd "$dist" && shasum -a 256 "${dmg##*/}" | tee "${dmg##*/}.sha256")
