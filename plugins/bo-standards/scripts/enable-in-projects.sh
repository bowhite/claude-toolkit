#!/usr/bin/env bash
# Wire this toolkit into one or more existing projects.
#
# On a machine with no GitHub access (or where publishing would drag in a
# reviewer), the marketplace can just be a local directory. Every project on
# that machine then needs the same `.claude/settings.json` -- the path points at
# the toolkit, not at the project, so the file is identical everywhere and can
# simply be copied.
#
# This writes that wiring, merging into an existing settings.json rather than
# clobbering it, and refuses to write a path that does not exist.
#
# Usage:
#   ./enable-in-projects.sh ~/work/proj-a ~/work/proj-b
#   ./enable-in-projects.sh --local ~/work/*/       # write settings.local.json
#   ./enable-in-projects.sh --dry-run ~/work/*/
#
#   --local     write .claude/settings.local.json (gitignored) instead of
#               settings.json. Use for repos shared with colleagues: an absolute
#               path that only exists on your machine should not be committed.
#   --dry-run   show what would change.

set -uo pipefail

TOOLKIT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
MARKETPLACE=bo-toolkit
PLUGIN=bo-standards

TARGET_FILE=settings.json
DRY=0
projects=()

for arg in "$@"; do
  case "$arg" in
    --local)   TARGET_FILE=settings.local.json ;;
    --dry-run) DRY=1 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *)  projects+=("$arg") ;;
  esac
done

[ ${#projects[@]} -eq 0 ] && { echo "usage: $0 [--local] [--dry-run] <project-dir>..." >&2; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "jq is required (run bootstrap.sh first)." >&2; exit 1; }

# Refuse to write a path that is not actually a marketplace. A wrong path does
# not fail loudly at load time -- the plugin can keep resolving from a stale
# cache -- so the check has to happen here.
if [ ! -f "$TOOLKIT_ROOT/.claude-plugin/marketplace.json" ]; then
  echo "No marketplace.json under $TOOLKIT_ROOT" >&2
  echo "Run this from the toolkit's own scripts/ directory." >&2
  exit 1
fi

echo "Toolkit:  $TOOLKIT_ROOT"
echo "Writing:  .claude/$TARGET_FILE"
echo

WIRING=$(jq -n --arg mkt "$MARKETPLACE" --arg path "$TOOLKIT_ROOT" --arg plug "$PLUGIN@$MARKETPLACE" '
  { extraKnownMarketplaces: { ($mkt): { source: { source: "directory", path: $path } } },
    enabledPlugins: { ($plug): true } }')

ok=0; skipped=0
for proj in "${projects[@]}"; do
  proj="${proj%/}"
  name=$(basename "$proj")

  if [ ! -d "$proj" ]; then
    printf '  %-28s SKIP  not a directory\n' "$name"; skipped=$((skipped+1)); continue
  fi

  dest="$proj/.claude/$TARGET_FILE"

  if [ "$DRY" -eq 1 ]; then
    printf '  %-28s would wire %s\n' "$name" "$([ -f "$dest" ] && echo '(merge into existing)' || echo '(new file)')"
    continue
  fi

  mkdir -p "$proj/.claude"
  if [ -f "$dest" ]; then
    # Merge, so anything else already in the file survives.
    tmp=$(mktemp)
    if jq -s '.[0] * .[1]' "$dest" <(printf '%s' "$WIRING") > "$tmp" 2>/dev/null && jq -e . "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$dest"; printf '  %-28s merged\n' "$name"; ok=$((ok+1))
    else
      rm -f "$tmp"; printf '  %-28s SKIP  existing %s is not valid JSON\n' "$name" "$TARGET_FILE"; skipped=$((skipped+1))
    fi
  else
    printf '%s\n' "$WIRING" > "$dest"; printf '  %-28s created\n' "$name"; ok=$((ok+1))
  fi

  # settings.json is meant to be committed; settings.local.json never is.
  if [ "$TARGET_FILE" = settings.local.json ] && [ -d "$proj/.git" ]; then
    gi="$proj/.gitignore"
    grep -qxF '.claude/settings.local.json' "$gi" 2>/dev/null \
      || echo '.claude/settings.local.json' >> "$gi"
  fi
done

echo
[ "$DRY" -eq 1 ] && { echo "Dry run -- nothing written."; exit 0; }
echo "Wired $ok project(s), skipped $skipped."
echo
echo "Restart Claude Code, then run the adopt-standards skill in each project --"
echo "wiring the plugin does not install ruff/ty or touch pyproject.toml."
