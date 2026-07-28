#!/usr/bin/env bash
# Retire a pre-existing user-level lint hook and /lint command.
#
# Before bo-standards, these conventions lived in ~/.claude as a global
# PostToolUse hook and a /lint slash command. The plugin now owns both. Leaving
# the old ones in place means two formatters run on every edit -- and the old
# one still reformats Markdown, which this toolchain deliberately does not.
#
# Nothing is deleted. Files are renamed to *.retired and settings.json is backed
# up first: ~/.claude is not under version control, so a delete here is
# unrecoverable.
#
# Usage:  ./migrate-user-hooks.sh [--dry-run]

set -uo pipefail

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
STAMP=$(git log -1 --format=%cd --date=format:%Y%m%d-%H%M%S 2>/dev/null || echo backup)

act() {
  if [ "$DRY" -eq 1 ]; then echo "  [dry-run] $*"; else eval "$@"; fi
}

echo "==> Checking $CLAUDE_DIR"

if [ ! -d "$CLAUDE_DIR" ]; then
  echo "  no ~/.claude directory -- nothing to migrate."
  exit 0
fi

command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }

# --- 1. the hook script -------------------------------------------------------
found_any=0
for f in "$CLAUDE_DIR"/hooks/lint-format.sh "$CLAUDE_DIR"/hooks/lint.sh; do
  [ -f "$f" ] || continue
  found_any=1
  echo "  found hook script: $f"
  act "mv '$f' '$f.retired'"
  echo "    -> renamed to $(basename "$f").retired"
done

# --- 2. the slash command -----------------------------------------------------
for f in "$CLAUDE_DIR"/commands/lint.md; do
  [ -f "$f" ] || continue
  found_any=1
  echo "  found slash command: $f"
  act "mv '$f' '$f.retired'"
  echo "    -> renamed to $(basename "$f").retired"
done

# --- 3. the PostToolUse wiring in settings.json -------------------------------
if [ -f "$SETTINGS" ]; then
  if jq -e '.hooks.PostToolUse' "$SETTINGS" >/dev/null 2>&1; then
    found_any=1
    echo "  found PostToolUse hooks in settings.json"
    act "cp '$SETTINGS' '$SETTINGS.$STAMP.bak'"
    echo "    -> backed up to settings.json.$STAMP.bak"

    if [ "$DRY" -eq 0 ]; then
      tmp=$(mktemp)
      # Drop PostToolUse, and drop `hooks` entirely if nothing else is left, so
      # no empty object is orphaned behind.
      jq 'del(.hooks.PostToolUse)
          | if (.hooks | length) == 0 then del(.hooks) else . end' \
         "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
      jq -e . "$SETTINGS" >/dev/null 2>&1 \
        && echo "    -> PostToolUse removed, settings.json still valid JSON" \
        || { echo "    !! settings.json is now invalid -- restoring backup" >&2
             cp "$SETTINGS.$STAMP.bak" "$SETTINGS"; exit 1; }
    else
      echo "  [dry-run] would remove .hooks.PostToolUse from settings.json"
    fi
  fi
fi

echo
if [ "$found_any" -eq 0 ]; then
  echo "Nothing to migrate -- no user-level lint hook or command found."
  exit 0
fi

cat <<'EOF'
==> Done.

Nothing was deleted. To undo, rename the *.retired files back and restore the
settings.json.*.bak backup. Once you are satisfied, delete them yourself.

Restart Claude Code: hooks are read at session start, so the old one stays
active in any session that is already running.
EOF
