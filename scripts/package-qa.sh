#!/bin/sh
# Builds GrimoireQA.app for testing on a Mac that also has the real Grimoire. It is signed with
# the Developer ID Application certificate, hardened and sandboxed like a release, and never
# notarized. Its bundle identifier differs, so the sandbox gives it a container of its own and
# it can't touch the real app's projects, versions or preferences, and its update feed is off.
#
# The build runs in a scratch export of HEAD (`git archive`), so the checkout's tracked files
# stay as they were and the app matches a commit, not the working tree.
#
# Usage, from the repo root:  TEAM_ID=ABCDE12345 scripts/package-qa.sh <label>
# Writes dist/qa/<label>/GrimoireQA.app. QA_BUNDLE_ID overrides the identifier; the production
# one is refused.
set -eu

label=${1:?usage: TEAM_ID=<team id> scripts/package-qa.sh <label>}
team=${TEAM_ID:?TEAM_ID is required: QA builds are Developer ID signed}
production_id=computer.srcery.grimoire
bundle_id=${QA_BUNDLE_ID:-computer.srcery.grimoire.qa}
name=GrimoireQA
root=$(cd "$(dirname "$0")/.." && pwd)
export_dir="$root/build/qa-export"
derived="$root/build/qa-derived"
out="$root/dist/qa/$label"
app="$out/$name.app"

# The production identifier would share the real app's container and defaults.
[ "$bundle_id" != "$production_id" ] \
  || { echo "Refusing to build with the production bundle identifier $production_id." >&2; exit 1; }
case "$label" in
  */* | .*) echo "The label names a folder; use letters, digits, dots and dashes." >&2; exit 1 ;;
esac

identity=$(security find-identity -v -p codesigning \
  | sed -n "s/.*\"\(Developer ID Application: .*($team)\)\"/\1/p" | head -1)
[ -n "$identity" ] \
  || { echo "No Developer ID Application certificate for team $team in the keychain." >&2; exit 1; }

cd "$root"
tracked_before=$(git status --porcelain --untracked-files=no)
rm -rf "$export_dir" "$out"
mkdir -p "$export_dir" "$out"
trap 'rm -rf "$export_dir"' EXIT
git archive HEAD | tar -x -C "$export_dir"

cd "$export_dir"
# Only the Mac target gets the new name and identifier; the iOS target isn't built here.
sed -i '' \
  -e "/^  GrimoireMac:/,/^  GrimoireiOS:/ s/PRODUCT_BUNDLE_IDENTIFIER: $production_id\$/PRODUCT_BUNDLE_IDENTIFIER: $bundle_id/" \
  -e "/^  GrimoireMac:/,/^  GrimoireiOS:/ s/PRODUCT_NAME: Grimoire\$/PRODUCT_NAME: $name/" \
  -e "s/INFOPLIST_KEY_CFBundleDisplayName: Grimoire\$/INFOPLIST_KEY_CFBundleDisplayName: $name/" \
  project.yml
# No feed and no automatic checks: a QA build must never offer to replace itself with a release.
plist_in=Config/GrimoireMac-Info.plist
/usr/libexec/PlistBuddy -c 'Delete :SUFeedURL' -c 'Set :SUEnableAutomaticChecks false' "$plist_in"

xcodegen generate --quiet
xcodebuild build \
  -project Grimoire.xcodeproj -scheme GrimoireMac -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$derived" \
  CODE_SIGN_IDENTITY="$identity" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$team" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS=--timestamp \
  -quiet
built="$derived/Build/Products/Release/$name.app"
[ -d "$built" ] || { echo "The build produced no $name.app." >&2; exit 1; }
ditto "$built" "$app"

# Sparkle's nested code first, then the app, keeping its entitlements, as package-mac.sh does.
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
set -- "$sparkle/XPCServices/Installer.xpc" "$sparkle/XPCServices/Downloader.xpc" \
  "$sparkle/Autoupdate" "$sparkle/Updater.app" "$app/Contents/Frameworks/Sparkle.framework"
for component in "$@"; do
  [ -e "$component" ] || { echo "Missing Sparkle component: $component" >&2; exit 1; }
  codesign --force --sign "$identity" --options runtime --timestamp \
    --preserve-metadata=entitlements "$component"
done
codesign --force --sign "$identity" --options runtime --timestamp \
  --preserve-metadata=entitlements "$app"

# Verify what makes it a safe QA build before reporting it.
cd "$root"
codesign --verify --deep --strict "$app"
plist="$app/Contents/Info.plist"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" = "$bundle_id" ] \
  || { echo "The app's bundle identifier isn't $bundle_id." >&2; exit 1; }
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$plist")" = "$name" ] \
  || { echo "The app's display name isn't $name." >&2; exit 1; }
! /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist" >/dev/null 2>&1 \
  || { echo "The app still has an update feed." >&2; exit 1; }
[ "$(/usr/libexec/PlistBuddy -c 'Print :SUEnableAutomaticChecks' "$plist")" = false ] \
  || { echo "The app still checks for updates automatically." >&2; exit 1; }
for component in "$@" "$app"; do
  details=$(codesign -dv --verbose=4 "$component" 2>&1)
  for expected in "TeamIdentifier=$team" "flags=0x10000(runtime)" "Timestamp=" "Authority=Developer ID Application"; do
    printf '%s\n' "$details" | grep -q -F "$expected" \
      || { echo "$component: no $expected in its signature." >&2; exit 1; }
  done
done
codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q 'com.apple.security.app-sandbox' \
  || { echo "The app isn't sandboxed." >&2; exit 1; }
[ "$(git status --porcelain --untracked-files=no)" = "$tracked_before" ] \
  || { echo "The build changed tracked files in the checkout." >&2; exit 1; }

echo "Built $app"
codesign -dv --verbose=4 "$app" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier|Timestamp|CodeDirectory|Signature)|flags='
echo "Not notarized: it opens on this Mac because it was built here, not downloaded."
