#!/bin/sh
# Assembles the GitHub Pages site: the product page from site/ plus the update feed.
#
# Every Pages deploy replaces the whole site, and the installed app reads its
# updates from appcast.xml there, so both workflows (release.yml and pages.yml)
# publish this directory and never site/ alone. This fails if the appcast is
# missing or isn't well-formed XML, so a site without a working feed can't ship.
# site/README.md is repo documentation, so it stays out of the published site.
#
# The page's download links are filled in here, at deploy time, from the feed's
# enclosure: the DMG URL becomes the href of every element marked data-latest-dmg,
# and the version (read from the Grimoire-<version>.dmg filename) goes into the
# elements marked data-dmg-label and data-dmg-note in the published index.html.
# site/index.html keeps a generic GitHub Releases link, so it still works when
# opened directly. This fails if the enclosure isn't a Grimoire DMG release URL or
# if the page lost a marker, so a stale link can't ship. Nothing is written to the
# output directory until the whole page has been rewritten and checked.
#
# Usage, from the repo root:  scripts/assemble-pages.sh <appcast.xml> <output dir>
set -eu

usage='usage: scripts/assemble-pages.sh <appcast.xml> <output dir>'
appcast=${1:?$usage}
out=${2:?$usage}
root=$(cd "$(dirname "$0")/.." && pwd)

[ -f "$appcast" ] || { echo "No appcast at $appcast; refusing to assemble a site without the update feed." >&2; exit 1; }
command -v xmllint >/dev/null || { echo "xmllint is not installed; it is needed to check the feed." >&2; exit 1; }
xmllint --noout "$appcast" || { echo "$appcast is not valid XML." >&2; exit 1; }

# The feed's one enclosure is the DMG; derive everything shown on the page from it.
url=$(xmllint --xpath 'string(//enclosure/@url)' "$appcast")
[ -n "$url" ] || { echo "$appcast has no enclosure URL; cannot link the latest DMG." >&2; exit 1; }
# The pattern limits the URL to characters that are safe in HTML and in the sed below, so nothing needs escaping.
# The newline check comes first because grep matches line by line.
case $url in
*'
'*) echo "The enclosure URL in $appcast spans several lines." >&2; exit 1 ;;
esac
printf '%s\n' "$url" | grep -Eq '^https://github\.com/xchrisbailey/grimoire\.srcery/releases/download/[A-Za-z0-9._-]+/Grimoire-[0-9A-Za-z.-]+\.dmg$' || {
	echo "The enclosure URL in $appcast is not a Grimoire DMG release URL: $url" >&2
	exit 1
}
version=${url##*/Grimoire-}
version=${version%.dmg}
if printf '%s\n' "$version" | grep -Eq '^[0-9]+(\.[0-9]+)*-beta\.[0-9]+$'; then
	name="beta ${version##*-beta.}"
else
	name=$version
fi
label="Download $name"
note="Grimoire $name for macOS 27 or later."

# Rewrite the marked elements of a copy of the page, then check each one took.
page=$(mktemp)
trap 'rm -f "$page"' EXIT
count() { grep -cF -- "$1" "$2" || true; }
source_page="$root/site/index.html"
links=$(count 'data-latest-dmg' "$source_page")
labels=$(count '<span data-dmg-label>' "$source_page")
notes=$(count '<p data-dmg-note>' "$source_page")
[ "$links" -ge 1 ] && [ "$labels" -ge 1 ] && [ "$notes" -ge 1 ] || {
	echo "site/index.html is missing a download marker (data-latest-dmg: $links, data-dmg-label: $labels, data-dmg-note: $notes)." >&2
	exit 1
}
sed -e "/data-latest-dmg/s|href=\"[^\"]*\"|href=\"$url\"|g" \
	-e "s|<span data-dmg-label>[^<]*</span>|<span data-dmg-label>$label</span>|g" \
	-e "s|<p data-dmg-note>.*</p>|<p data-dmg-note>$note <span aria-hidden=\"true\">↓</span></p>|" \
	"$source_page" > "$page"
[ "$(count "href=\"$url\" data-latest-dmg" "$page")" -eq "$links" ] &&
	[ "$(count "<span data-dmg-label>$label</span>" "$page")" -eq "$labels" ] &&
	[ "$(count "<p data-dmg-note>$note <span aria-hidden=\"true\">↓</span></p>" "$page")" -eq "$notes" ] || {
	echo "Could not fill the download links in site/index.html from $url." >&2
	exit 1
}

mkdir -p "$out"
cp -R "$root/site/." "$out/"
rm -f "$out/README.md"
cp "$page" "$out/index.html"
cp "$appcast" "$out/appcast.xml"
