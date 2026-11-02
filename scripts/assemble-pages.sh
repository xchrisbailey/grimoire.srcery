#!/bin/sh
# Assembles the GitHub Pages site: the product page from site/ plus the update feed.
#
# Every Pages deploy replaces the whole site, and the installed app reads its
# updates from appcast.xml there, so both workflows (release.yml and pages.yml)
# publish this directory and never site/ alone. This fails if the appcast is
# missing or isn't well-formed XML, so a site without a working feed can't ship.
# site/README.md is repo documentation, so it stays out of the published site.
#
# Usage, from the repo root:  scripts/assemble-pages.sh <appcast.xml> <output dir>
set -eu

usage='usage: scripts/assemble-pages.sh <appcast.xml> <output dir>'
appcast=${1:?$usage}
out=${2:?$usage}
root=$(cd "$(dirname "$0")/.." && pwd)

[ -f "$appcast" ] || { echo "No appcast at $appcast; refusing to assemble a site without the update feed." >&2; exit 1; }
xmllint --noout "$appcast" || { echo "$appcast is not valid XML." >&2; exit 1; }

mkdir -p "$out"
cp -R "$root/site/." "$out/"
rm -f "$out/README.md"
cp "$appcast" "$out/appcast.xml"
