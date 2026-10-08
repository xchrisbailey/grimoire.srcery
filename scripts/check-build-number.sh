#!/bin/sh
# Fails unless the build number in project.yml is higher than every build number
# in the published update feed. Sparkle compares CFBundleVersion, so a release that
# isn't higher would never be offered. A feed that doesn't exist yet (HTTP 404)
# passes; any other failure to read it fails.
#
# Usage, from the repo root:  scripts/check-build-number.sh [feed URL]
set -eu

feed_url=${1:-https://xchrisbailey.github.io/grimoire.srcery/appcast.xml}
root=$(cd "$(dirname "$0")/.." && pwd)

build=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\{0,1\}\([0-9][0-9]*\)"\{0,1\} *$/\1/p' "$root/project.yml" | head -1)
[ -n "$build" ] || { echo "No CURRENT_PROJECT_VERSION in project.yml." >&2; exit 1; }

feed=$(mktemp)
trap 'rm -f "$feed"' EXIT
# The query string and header keep a CDN from answering with a copy of an older feed.
status=$(curl --silent --show-error --location --max-time 30 --retry 3 \
  --header 'Cache-Control: no-cache' --output "$feed" --write-out '%{http_code}' \
  "$feed_url?$(date +%s)") \
  || { echo "Couldn't read the update feed at $feed_url." >&2; exit 1; }

case $status in
  404)
    echo "No update feed at $feed_url yet; build $build is the first."
    exit 0
    ;;
  200) ;;
  *)
    echo "The update feed at $feed_url answered HTTP $status." >&2
    exit 1
    ;;
esac

elements=$(xmllint --xpath "//*[local-name()='version']" "$feed") \
  || { echo "The update feed at $feed_url isn't XML, or has no sparkle:version." >&2; exit 1; }
published=$(printf '%s' "$elements" | sed 's/<[^>]*>/ /g')

highest=0
for number in $published; do
  case $number in
    *[!0-9]*) echo "The update feed has a build number that isn't an integer: $number" >&2; exit 1 ;;
  esac
  [ "$number" -le "$highest" ] || highest=$number
done

if [ "$build" -le "$highest" ]; then
  echo "Build $build (CURRENT_PROJECT_VERSION in project.yml) isn't higher than $highest, the highest in the published feed." >&2
  echo "Raise CURRENT_PROJECT_VERSION before tagging." >&2
  exit 1
fi
echo "Build $build is higher than $highest in the published feed."
