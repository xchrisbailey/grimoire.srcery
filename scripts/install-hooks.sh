#!/bin/sh
# Points this repository's hooks at .githooks. core.hooksPath lives in the shared git config,
# so one run covers every worktree; the relative path resolves in whichever worktree pushes.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
current=$(git config --get core.hooksPath || true)
if [ -n "$current" ] && [ "$current" != .githooks ]; then
  echo "core.hooksPath is already set to $current; replacing it with .githooks." >&2
fi
git config core.hooksPath .githooks
chmod +x .githooks/pre-push
echo "Hooks enabled: .githooks/pre-push runs lint on every push, and needs scripts/check.sh to have passed for main and v* tags."
