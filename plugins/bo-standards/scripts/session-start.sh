#!/usr/bin/env bash
# SessionStart hook.
#
# Prints where the repo stands so a session opens with the working tree and
# recent history already in context, plus a nudge when the project's tooling
# hasn't been installed yet -- the normal first-run state in a fresh clone or a
# cloud sandbox.
#
# Always exits 0. This is informational; nothing here should ever stop a session
# from starting.

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

harden_path

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository. \`git init -b main\` to start one, or run the adopt-standards skill."
  exit 0
fi

root=$(project_root "$PWD")

status=$(git status --short 2>/dev/null)
if [ -n "$status" ]; then
  echo "Working tree:"
  printf '%s\n' "$status"
else
  echo "Working tree: clean"
fi

echo
echo "Recent commits:"
git log --oneline -10 2>/dev/null || echo "  (no commits yet)"

# Flag missing tooling. Absence is normal and not an error -- the repo may
# simply not have adopted the standards yet -- so this is a hint, not a warning.
missing=()
[ -f "$root/pyproject.toml" ] && [ ! -x "$root/.venv/bin/ruff" ] && missing+=("Python (.venv)")
[ -f "$root/package.json" ]   && [ ! -d "$root/node_modules" ]   && missing+=("Node (node_modules)")

if [ ${#missing[@]} -gt 0 ]; then
  echo
  echo "Dependencies not installed: ${missing[*]}"
  echo "Run bootstrap.sh to set up the dev environment."
fi

exit 0
