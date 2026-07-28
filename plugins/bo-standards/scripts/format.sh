#!/usr/bin/env bash
# PostToolUse hook (matcher: Edit|Write|NotebookEdit)
#
# Auto-formats and auto-fixes the just-edited file, then surfaces any remaining
# warnings/errors to Claude via exit code 2 (stderr is fed back to the model).
#
# Dispatch by extension:
#   .py                                    -> ruff format + ruff check --fix
#   .js/.jsx/.ts/.tsx/.mjs/.cjs/.json/...  -> biome check --write
#   everything else, INCLUDING .md         -> exit 0
#
# Markdown is deliberately untouched: Biome does not format it (verified against
# 2.5.3 -- .md passes through unchanged), and no other Markdown tool is used.
#
# Type checking is deliberately absent. `ty` is slow enough to be felt on every
# edit and needs whole-project context to be meaningful, so it lives in the
# pr-check skill and in CI instead.

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

harden_path

input=$(hook_input)
file=$(json_field "$input" '.tool_input.file_path')
[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

# Skip files git ignores (vendored deps, build output, local-only files):
# project lint rules shouldn't apply to them. `git -C <dir>` targets the file's
# own repo; a path outside any repo yields exit 128 (not ignored) and falls
# through to linting.
if git -C "$(dirname "$file")" check-ignore -q -- "$file" 2>/dev/null; then
  exit 0
fi

root=$(project_root "$(dirname "$file")")
remaining=""
had_issues=0

case "$file" in
  *.py)
    ruff=$(find_ruff "$root")
    [ -z "$ruff" ] && exit 0
    "$ruff" format -- "$file" >/dev/null 2>&1
    "$ruff" check --fix -- "$file" >/dev/null 2>&1
    if ! out=$("$ruff" check -- "$file" 2>&1); then
      remaining="$out"; had_issues=1
    fi
    ;;

  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.json|*.jsonc|*.css)
    # The Node project may live in a subdirectory (frontend/), not at the repo
    # root -- resolve it from the file upwards.
    node_dir=$(find_node_dir "$(dirname "$file")" "$root") || node_dir=""
    biome=""
    [ -n "$node_dir" ] && biome=$(find_biome "$node_dir")

    if [ -z "$biome" ]; then
      # Say so once. Silently leaving the file unformatted looked identical to
      # success and let unformatted code accumulate unnoticed.
      if [ -z "$node_dir" ]; then
        warn_once "$root:nonode" \
          "bo-standards: $(basename "$file") was not formatted -- no package.json found under $root. Run the adopt-standards skill to set up Biome."
      else
        warn_once "$node_dir:nobiome" \
          "bo-standards: $(basename "$file") was not formatted -- Biome is not installed in $node_dir. Run: (cd $node_dir && npm i -D @biomejs/biome)"
      fi
      exit 0
    fi

    # Run from the Node project directory so biome.json is discovered.
    (cd "$node_dir" && "$biome" check --write --no-errors-on-unmatched "$file") >/dev/null 2>&1
    if ! out=$(cd "$node_dir" && "$biome" check --no-errors-on-unmatched "$file" 2>&1); then
      remaining="$out"; had_issues=1
    fi
    ;;

  *)
    exit 0
    ;;
esac

if [ "$had_issues" -eq 1 ]; then
  {
    echo "Auto-format/auto-fix ran on: $file"
    echo "Some issues could not be fixed automatically. Please fix them, then re-check the file:"
    echo
    printf '%s\n' "$remaining"
  } >&2
  exit 2
fi
exit 0
