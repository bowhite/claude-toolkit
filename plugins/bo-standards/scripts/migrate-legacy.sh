#!/usr/bin/env bash
# Audit and retire pre-bo-standards configuration.
#
# Before this plugin, the same conventions typically lived as: a user-level
# PostToolUse hook, a /lint slash command, and global fallback configs under
# ~/.config for ruff, mypy, markdownlint, and eslint. The plugin now owns all of
# it. Leaving the old copies in place causes three distinct problems:
#
#   1. Two formatters run on every edit, and the old one still touches Markdown.
#   2. `~/.config/ruff/ruff.toml` with a `select = [...]` REPLACES ruff's
#      defaults, so any project without its own config is linted by a different
#      ruleset than an adopted project -- silently, with no signal.
#   3. mypy/pyright configs keep a second type checker's opinions alive after
#      the switch to ty.
#
# NOTHING IS DELETED. Files are renamed to *.retired and settings.json is backed
# up first: ~/.claude and ~/.config are not version controlled, so a delete here
# is unrecoverable.
#
# Usage:
#   ./migrate-legacy.sh                  audit only, change nothing (default)
#   ./migrate-legacy.sh --apply          retire hooks and commands
#   ./migrate-legacy.sh --apply --include-configs
#                                        also retire the ~/.config tool configs

set -uo pipefail

MODE=audit
INCLUDE_CONFIGS=0
for arg in "$@"; do
  case "$arg" in
    --apply)            MODE=apply ;;
    --audit|--dry-run)  MODE=audit ;;
    --include-configs)  INCLUDE_CONFIGS=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
STAMP=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo backup)
FOUND=0

command -v jq >/dev/null 2>&1 || { echo "jq is required (run bootstrap.sh first)." >&2; exit 1; }

hit()  { FOUND=$((FOUND+1)); printf '  %-9s %s\n' "$1" "$2"; }
note() { printf '            %s\n' "$1"; }

retire_file() {
  local f="$1"
  [ -e "$f" ] || return 1
  if [ "$MODE" = apply ]; then
    mv "$f" "$f.retired" && note "-> renamed to $(basename "$f").retired"
  else
    note "-> would rename to $(basename "$f").retired"
  fi
}

# --------------------------------------------------------------- 1. hooks ----
echo
echo "== Claude Code hooks and commands =="

# Only retire hooks this plugin actually replaces. An unrelated user hook is
# reported but left alone -- sweeping up every .sh in here would silently
# destroy work that has nothing to do with linting.
for f in "$CLAUDE_DIR"/hooks/*.sh; do
  [ -e "$f" ] || continue
  base=$(basename "$f")
  case "$base" in
    lint*|format*|*lint-format*|ruff*|prettier*|eslint*|markdownlint*|mypy*|pyright*|biome*)
      hit "hook" "$f"
      note "superseded by the plugin's format.sh"
      retire_file "$f"
      ;;
    *)
      hit "hook?" "$f"
      note "NOT recognised as a lint/format hook -- left alone. Review it yourself:"
      note "   if it duplicates the plugin, rename it to $base.retired by hand."
      ;;
  esac
done

# Any user-level command or skill whose name collides with a plugin skill --
# the plugin's copy would otherwise be shadowed or silently duplicated.
for name in lint pr-check ci-workflow scaffold-project adopt-standards update-docs fix-security; do
  for f in "$CLAUDE_DIR/commands/$name.md" "$CLAUDE_DIR/skills/$name/SKILL.md"; do
    [ -e "$f" ] || continue
    hit "command" "$f"
    note "collides with the plugin skill '$name'"
    retire_file "$f"
  done
done

# --------------------------------------------------------- 2. settings.json --
echo
echo "== settings.json hook wiring =="

migrate_settings() {
  local s="$1" scope="$2" tmp
  [ -f "$s" ] || return 0
  jq -e '.hooks | (.PostToolUse // .PreToolUse // .Stop // empty)' "$s" >/dev/null 2>&1 || return 0

  hit "$scope" "$s"
  note "declares hooks the plugin now provides"
  if [ "$MODE" = apply ]; then
    cp "$s" "$s.$STAMP.bak"
    tmp=$(mktemp)
    # Remove only the hook events the plugin owns. Everything else in the file --
    # model, permissions, enabledPlugins -- is left untouched.
    jq 'del(.hooks.PostToolUse) | del(.hooks.PreToolUse) | del(.hooks.Stop)
        | if (.hooks | type) == "object" and (.hooks | length) == 0 then del(.hooks) else . end' \
       "$s" > "$tmp" && mv "$tmp" "$s"
    if jq -e . "$s" >/dev/null 2>&1; then
      note "-> hooks removed; backup at $(basename "$s").$STAMP.bak"
    else
      cp "$s.$STAMP.bak" "$s"
      note "!! produced invalid JSON, backup restored"
    fi
  else
    note "-> would remove .hooks.{PostToolUse,PreToolUse,Stop}, backing up first"
  fi
}

migrate_settings "$SETTINGS" "user"
migrate_settings "$PWD/.claude/settings.json" "project"
migrate_settings "$PWD/.claude/settings.local.json" "project"

# ------------------------------------------------------- 3. global configs ---
echo
echo "== global tool configs =="

CFG_PATHS="\
$HOME/.config/ruff/ruff.toml|ruff|A global 'select = [...]' REPLACES ruff's defaults, so a project without its own config is linted differently from an adopted one.
$HOME/.config/ruff/pyproject.toml|ruff|Same risk as ruff.toml.
$HOME/.config/mypy/config|mypy|This toolchain uses ty; a lingering mypy config keeps a second type checker alive.
$HOME/.mypy.ini|mypy|As above.
$HOME/pyrightconfig.json|pyright|This toolchain uses ty.
$HOME/.markdownlint.jsonc|markdown|Markdown is deliberately not linted or formatted at all.
$HOME/.markdownlint.json|markdown|As above.
$HOME/.eslintrc|eslint|Biome replaces eslint.
$HOME/.eslintrc.json|eslint|Biome replaces eslint.
$HOME/.eslintrc.js|eslint|Biome replaces eslint.
$HOME/eslint.config.js|eslint|Biome replaces eslint.
$HOME/.prettierrc|prettier|Biome replaces prettier."

cfg_found=0
while IFS='|' read -r path tool why; do
  [ -n "$path" ] || continue
  [ -e "$path" ] || continue
  cfg_found=1
  hit "$tool" "$path"
  note "$why"
  if [ "$INCLUDE_CONFIGS" -eq 1 ]; then
    retire_file "$path"
  else
    note "-> left in place (pass --include-configs to retire it)"
  fi
done <<< "$CFG_PATHS"
[ "$cfg_found" -eq 0 ] && echo "  none found"

# --------------------------------------------------------------- summary -----
echo
if [ "$FOUND" -eq 0 ]; then
  echo "Nothing to migrate. This machine is clean."
  exit 0
fi

if [ "$MODE" = audit ]; then
  echo "Found $FOUND item(s). Nothing was changed."
  echo
  echo "Re-run with --apply to retire hooks and commands; add --include-configs"
  echo "to also retire the global tool configs listed above."
else
  echo "Migrated $FOUND item(s). Nothing was deleted."
  echo
  echo "To undo: rename the *.retired files back and restore any settings.json.*.bak."
  echo "Once satisfied, delete them yourself."
  echo
  echo "Restart Claude Code -- hooks are read at session start, so an old one"
  echo "stays active in any session already running."
fi
