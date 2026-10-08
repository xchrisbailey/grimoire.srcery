#!/bin/sh
# Builds the update feed for one release: signs the DMG with Sparkle's EdDSA key
# and writes appcast.xml into <output dir>, with one item for this release.
#
# The release workflow runs this after the DMG is attached to the release, and
# publishes the output directory as the GitHub Pages site. The Sparkle tools come
# from the package scripts/package-mac.sh resolved, so they match the linked framework.
#
# The private key is read from SPARKLE_PRIVATE_KEY, in the form `generate_keys -x`
# exports, or from the login keychain account SPARKLE_ACCOUNT when that isn't set.
# DOWNLOAD_URL_PREFIX and RELEASE_NOTES_URL default to the tag's GitHub release.
#
# Usage, from the repo root:  scripts/make-appcast.sh <tag> <dmg> <output dir>
set -eu

tag=${1:?usage: scripts/make-appcast.sh <tag, e.g. v1.0.0-beta.3> <dmg> <output dir>}
dmg=${2:?usage: scripts/make-appcast.sh <tag> <dmg> <output dir>}
out=${3:?usage: scripts/make-appcast.sh <tag> <dmg> <output dir>}
root=$(cd "$(dirname "$0")/.." && pwd)
bin=${SPARKLE_BIN:-$root/build/release/SourcePackages/artifacts/sparkle/Sparkle/bin}
repo=https://github.com/xchrisbailey/grimoire.srcery
download_prefix=${DOWNLOAD_URL_PREFIX:-$repo/releases/download/$tag/}
notes_url=${RELEASE_NOTES_URL:-$repo/releases/tag/$tag}

[ -f "$dmg" ] || { echo "No DMG at $dmg." >&2; exit 1; }
[ -x "$bin/generate_appcast" ] || { echo "No generate_appcast in $bin; run scripts/package-mac.sh first." >&2; exit 1; }

# generate_appcast works on a directory of archives and writes beside them.
archives=$(mktemp -d)
trap 'rm -rf "$archives"' EXIT
cp "$dmg" "$archives/"
mkdir -p "$out"

if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$bin/generate_appcast" --ed-key-file - \
    --download-url-prefix "$download_prefix" -o "$out/appcast.xml" "$archives"
else
  "$bin/generate_appcast" --account "${SPARKLE_ACCOUNT:-ed25519}" \
    --download-url-prefix "$download_prefix" -o "$out/appcast.xml" "$archives"
fi
