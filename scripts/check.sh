#!/bin/bash
# The one local check. Nothing runs in CI, so a green summary from this script at a clean head
# is what lets main or a release tag be pushed (see .githooks/pre-push).
#
# Usage, from any worktree:  scripts/check.sh [--core-runs N] [--only step[,step]]
#
#   --core-runs N   Run GrimoireCore's debug `swift test` N times (default 1). Each run counts,
#                   so a test that fails now and then fails the check.
#   --only STEPS    Run just these steps: xcodegen, build-mac, build-ios, test-core,
#                   test-editor, test-intelligence, perf-core, swift-format, swiftlint,
#                   dmg-layout. A partial run never writes the stamp; it exists for working on
#                   a failure.
#
# Every step runs even after a failure, so one run reports everything. Full logs go to
# build/check-logs/<sha>/, with summary.txt beside them. A passing, clean, full run records
# the head SHA in <git common dir>/grimoire-check-passed, which every worktree shares.
set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# SwiftPM writes a report here when a test process crashes, even if `swift test` then exits 0.
# Overridable so the crash path can be exercised without crashing anything.
diag_dir=${GRIMOIRE_CHECK_DIAGNOSTICS_DIR:-$HOME/Library/Logs/DiagnosticReports}

# --- Reading logs -----------------------------------------------------------------------

build_line() { grep -aE '\*\* BUILD (SUCCEEDED|FAILED) \*\*' "$1" | tail -1; }
test_run_lines() { grep -a 'Test run with' "$1"; }
test_run_passed() { test_run_lines "$1" | grep -aq 'passed'; }
failed_test_lines() { grep -aE '^. (Test|Suite) .* failed after' "$1" | grep -av 'Test run with'; }

# Prints "File.swift start end" for each region of GrimoireIntelligence's tests that only runs
# when the on-device model is ready: a whole suite, or a single test in an ungated suite. A
# region ends at the closing brace that matches the indent of the attribute that opened it.
model_gated_regions() {
  local file
  for file in $(grep -rl 'modelIsReady' "$root/Packages/GrimoireIntelligence/Tests"); do
    awk -v name="$(basename "$file")" '
      match($0, /^[ ]*/) { indent = substr($0, 1, RLENGTH) }
      open == 0 && /\.enabled\(if: *modelIsReady/ { open = 1; start = NR; close_at = indent "}"; next }
      open == 1 && $0 == close_at { print name, start, NR; open = 0 }
    ' "$file"
  done
}

# True when the log has at least one recorded issue and every one sits inside a model-gated
# region. A failure from a helper outside those regions, or a crash that records no issue,
# counts as a real failure.
failed_only_in_model_gated_tests() {
  local log=$1 regions issues
  regions=$(model_gated_regions)
  issues=$(grep -aoE 'recorded an issue at [^ :]+\.swift:[0-9]+' "$log" | sed -E 's|recorded an issue at (.*/)?||')
  [ -n "$regions" ] && [ -n "$issues" ] || return 1
  printf '%s\n' "$issues" | awk -F: -v regions="$regions" '
    BEGIN { n = split(regions, lines, "\n"); }
    {
      ok = 0
      for (i = 1; i <= n; i++) {
        split(lines[i], r, " ")
        if (r[1] == $1 && $2 >= r[2] && $2 <= r[3]) ok = 1
      }
      if (!ok) bad = 1
    }
    END { exit bad }
  '
}

# When sourced (to test the log readers above), stop here.
[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

core_runs=1
only=""
while [ $# -gt 0 ]; do
  case "$1" in
    --core-runs)
      [ $# -ge 2 ] || { echo "--core-runs needs a number." >&2; exit 2; }
      core_runs=$2
      shift 2
      ;;
    --only)
      [ $# -ge 2 ] || { echo "--only needs step names." >&2; exit 2; }
      only=$2
      shift 2
      ;;
    -h | --help)
      sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done
case "$core_runs" in
  '' | *[!0-9]* | 0) echo "--core-runs must be a whole number of at least 1." >&2; exit 2 ;;
esac

cd "$root" || exit 2

# --- Running steps ----------------------------------------------------------------------

head_sha=$(git rev-parse HEAD)
tree_dirty() { [ -n "$(git status --porcelain)" ]; }

if tree_dirty; then
  start_dirty=1
  # Kept apart so a dirty run never overwrites the logs of a clean run at the same SHA.
  logdir="$root/build/check-logs/$head_sha-dirty"
else
  start_dirty=0
  logdir="$root/build/check-logs/$head_sha"
fi
rm -rf "$logdir"
mkdir -p "$logdir"
results="$logdir/.results"
: > "$results"
failed=0

common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
stamp="$common_dir/grimoire-check-passed"

marker="$logdir/.started"
: > "$marker"
list_reports() {
  [ -d "$diag_dir" ] && find "$diag_dir" -maxdepth 1 -name 'swiftpm-testing-helper-*.ips' | sort
}
reports_before=$(list_reports)

want() {
  [ -z "$only" ] && return 0
  case ",$only," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

record() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$results"
  if [ "$2" = FAIL ]; then failed=1; fi
}
note() { record "$1" NOTE "$2"; }

# run_logged <log> <dir> <command…>: runs in a subshell so `cd` doesn't leak.
run_logged() {
  local log=$1 dir=$2
  shift 2
  ( cd "$dir" && "$@" ) > "$log" 2>&1
}

progress() { printf '%s\n' "$*" >&2; }

# A plain command: PASS when it exits 0.
plain_step() {
  local name=$1 log="$logdir/$1.log" dir=$2
  shift 2
  want "$name" || return 0
  progress "-> $name"
  if run_logged "$log" "$dir" "$@"; then record "$name" PASS ""; else record "$name" FAIL "see $name.log"; fi
}

# An xcodebuild: needs exit 0 and the BUILD SUCCEEDED line, which is also what gets reported.
build_step() {
  local name=$1 log="$logdir/$1.log" line
  shift
  want "$name" || return 0
  progress "-> $name"
  run_logged "$log" "$root" "$@"
  local rc=$?
  line=$(build_line "$log")
  if [ "$rc" -eq 0 ] && [ "$line" = "** BUILD SUCCEEDED **" ]; then
    record "$name" PASS "$line"
  else
    record "$name" FAIL "${line:-no ** BUILD … ** line, exit $rc}"
  fi
}

# One `swift test` run. Needs exit 0 and a passing `Test run with` line: a run that crashed
# before printing one has not passed. Sets run_ok and the lines for the caller to report.
swift_test_run() {
  local log=$1 package=$2
  shift 2
  run_logged "$log" "$root/Packages/$package" "$@"
  local rc=$?
  if [ "$rc" -eq 0 ] && test_run_passed "$log"; then run_ok=1; else run_ok=0; fi
}

# Notes the log's `Test run with` lines under a step, each led by an optional label.
report_test_lines() {
  local name=$1 log=$2 label=${3:+$3: } line
  if [ -z "$(test_run_lines "$log")" ]; then
    note "$name" "${label}no 'Test run with' line in $(basename "$log")"
  else
    test_run_lines "$log" | while IFS= read -r line; do note "$name" "$label$line"; done
  fi
}

package_step() {
  local name=$1 package=$2 log="$logdir/$1.log"
  want "$name" || return 0
  progress "-> $name"
  swift_test_run "$log" "$package" swift test
  if [ "$run_ok" -eq 1 ]; then
    record "$name" PASS ""
    report_test_lines "$name" "$log"
    return 0
  fi
  # Suites gated on the real on-device model vary run to run. A failure confined to them gets
  # one rerun; both result lines and the failing tests are reported either way.
  if [ "$package" = GrimoireIntelligence ] && failed_only_in_model_gated_tests "$log"; then
    local rerun="$logdir/$name-rerun.log"
    progress "   $name failed only in model-gated tests; rerunning once"
    swift_test_run "$rerun" "$package" swift test
    if [ "$run_ok" -eq 1 ]; then record "$name" PASS "passed on rerun"; else record "$name" FAIL "failed again on rerun"; fi
    note "$name" "first run failed only in model-gated tests:"
    failed_test_lines "$log" | while IFS= read -r line; do note "$name" "  $line"; done
    report_test_lines "$name" "$log" "first run"
    report_test_lines "$name" "$rerun" "rerun"
    return 0
  fi
  record "$name" FAIL "see $name.log"
  report_test_lines "$name" "$log"
  failed_test_lines "$log" | while IFS= read -r line; do note "$name" "  $line"; done
}

core_pass=0
core_step() {
  local i=1 name log
  want test-core || return 0
  while [ "$i" -le "$core_runs" ]; do
    name="test-core run $i/$core_runs"
    log="$logdir/test-core-run-$i.log"
    progress "-> $name"
    swift_test_run "$log" GrimoireCore swift test
    if [ "$run_ok" -eq 1 ]; then
      record "$name" PASS ""
      core_pass=$((core_pass + 1))
    else
      record "$name" FAIL "see test-core-run-$i.log"
      failed_test_lines "$log" | while IFS= read -r line; do note "$name" "  $line"; done
    fi
    report_test_lines "$name" "$log"
    i=$((i + 1))
  done
}

started=$(date '+%Y-%m-%d %H:%M:%S')
SECONDS=0

mac_dest='platform=macOS'
ios_dest='generic/platform=iOS Simulator'

plain_step xcodegen "$root" xcodegen generate
build_step build-mac xcodebuild build -project Grimoire.xcodeproj -scheme GrimoireMac \
  -destination "$mac_dest" -derivedDataPath build/DerivedData ARCHS=arm64 CODE_SIGNING_ALLOWED=NO
build_step build-ios xcodebuild build -project Grimoire.xcodeproj -scheme GrimoireiOS \
  -destination "$ios_dest" -derivedDataPath build/DerivedData ARCHS=arm64 CODE_SIGNING_ALLOWED=NO
core_step
package_step test-editor GrimoireEditor
package_step test-intelligence GrimoireIntelligence

# Release-mode parse speed. CI used to run it only on main; it is part of every local check now.
if want perf-core; then
  progress "-> perf-core"
  swift_test_run "$logdir/perf-core.log" GrimoireCore swift test -c release --filter PerformanceTests
  if [ "$run_ok" -eq 1 ]; then record perf-core PASS ""; else record perf-core FAIL "see perf-core.log"; fi
  report_test_lines perf-core "$logdir/perf-core.log"
fi

plain_step swift-format "$root" xcrun swift-format lint --strict --recursive Apps Packages
plain_step swiftlint "$root" swiftlint --strict
plain_step dmg-layout "$root" python3 scripts/test-dmg-layout.py

# --- Verdict ----------------------------------------------------------------------------

reasons=""
add_reason() { reasons="${reasons:+$reasons; }$1"; }

if [ "$failed" -ne 0 ]; then add_reason "a step failed"; fi

# New or rewritten crash reports from the test helper, whatever `swift test` exited with.
crashes=""
reports_after=$(list_reports)
while IFS= read -r report; do
  [ -n "$report" ] || continue
  if ! printf '%s\n' "$reports_before" | grep -qxF "$report" || [ "$report" -nt "$marker" ]; then
    crashes="${crashes:+$crashes
}$report"
  fi
done <<EOF
$reports_after
EOF
if [ -n "$crashes" ]; then
  add_reason "swiftpm-testing-helper crash report"
  failed=1
fi

# The tree must be clean when the run ends too: a test that rewrites a tracked file, or a
# checkout moving under the run, makes the SHA in the summary mean nothing.
tree_state=clean
if [ "$start_dirty" -eq 1 ]; then
  tree_state=dirty
  add_reason "dirty tree at start"
  failed=1
elif tree_dirty; then
  tree_state="dirty (changed during the run)"
  add_reason "tree became dirty during the run"
  failed=1
fi
if [ "$(git rev-parse HEAD)" != "$head_sha" ]; then
  add_reason "HEAD moved during the run"
  failed=1
fi

if [ -n "$only" ]; then scope="partial (--only $only)"; else scope=full; fi

if [ "$failed" -eq 0 ] && [ -n "$only" ]; then
  result="PASS (partial scope: not a full check)"
elif [ "$failed" -eq 0 ]; then
  result=PASS
else
  result="FAIL ($reasons)"
fi

stamp_state="not written"
if [ "$failed" -eq 0 ] && [ -z "$only" ]; then
  printf '%s %s core-runs=%s\n' "$head_sha" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$core_runs" >> "$stamp"
  stamp_state="written to $stamp"
elif [ "$failed" -eq 0 ]; then
  stamp_state="not written (partial scope)"
elif [ "$start_dirty" -eq 1 ] || [ "$tree_state" != clean ]; then
  stamp_state="not written (dirty)"
else
  stamp_state="not written (failed)"
fi

print_summary() {
  local name status detail
  echo "Grimoire check"
  echo "head:       $head_sha ($(git log -1 --format=%s "$head_sha"))"
  echo "branch:     $(git rev-parse --abbrev-ref HEAD)"
  echo "tree:       $tree_state"
  echo "scope:      $scope"
  echo "core runs:  $core_runs"
  echo "started:    $started, took ${SECONDS}s"
  echo
  while IFS="$(printf '\t')" read -r name status detail; do
    if [ "$status" = NOTE ]; then
      printf '    %s\n' "$detail"
    elif [ -n "$detail" ]; then
      printf '%-28s %s  %s\n' "$name" "$status" "$detail"
    else
      printf '%-28s %s\n' "$name" "$status"
    fi
  done < "$results"
  echo
  if want test-core; then echo "GrimoireCore tally: $core_pass/$core_runs runs passed"; fi
  if [ -n "$crashes" ]; then
    echo "Crash reports during the run:"
    printf '%s\n' "$crashes" | sed 's/^/    /'
  else
    echo "Crash reports during the run: none"
  fi
  echo "Logs:       $logdir"
  echo "Stamp:      $stamp_state"
  echo "Result:     $result"
}

print_summary | tee "$logdir/summary.txt"
[ "$failed" -eq 0 ]
