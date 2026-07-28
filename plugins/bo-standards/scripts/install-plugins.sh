#!/usr/bin/env bash
# Install the official Anthropic plugins this toolkit delegates to.
#
# bo-standards deliberately owns only what nothing official covers -- the
# uv/ruff/ty/biome toolchain and project shape. Everything else (committing,
# PR review, docstring analysis, CLAUDE.md upkeep, library docs) is someone
# else's job. This script installs that set so a new machine or a cloud sandbox
# is one command away from the full setup.
#
# These are installed at USER scope on purpose. They are editor capabilities,
# not project conventions -- unlike bo-standards itself, which is per-project so
# it travels with a clone.
#
# Idempotent: already-installed plugins are reported and skipped.

set -uo pipefail

MARKETPLACE="claude-plugins-official"

# name:why -- the "why" is printed, so the reason each one is here stays
# attached to the decision to install it.
PLUGINS=(
  "commit-commands:commit, push, and open PRs"
  "pr-review-toolkit:PR review, plus the comment-analyzer used by pr-check"
  "code-review:reviewing a diff before merge"
  "code-simplifier:post-implementation cleanup"
  "claude-md-management:auditing and maintaining CLAUDE.md"
  "context7:current library docs -- matters on bleeding-edge versions"
  "security-guidance:security review of changes"
  "skill-creator:authoring and evaluating skills"
  "frontend-design:visual design work on UI"
)

# Deliberately NOT installed:
#   pyright-lsp -- this toolchain uses ty. Two type checkers with different
#                  opinions means the editor contradicts CI.
#   github      -- the gh CLI covers this without an OAuth flow or MCP server.

command -v claude >/dev/null 2>&1 || {
  echo "claude CLI not found on PATH." >&2
  exit 1
}

echo "==> Ensuring marketplace: $MARKETPLACE"
claude plugin marketplace add "$MARKETPLACE" >/dev/null 2>&1 \
  || claude plugin marketplace add anthropics/claude-plugins-official >/dev/null 2>&1 \
  || true

installed=$(claude plugin list 2>/dev/null)
added=() present=() failed=()

for entry in "${PLUGINS[@]}"; do
  name="${entry%%:*}"
  why="${entry#*:}"

  if printf '%s' "$installed" | grep -q "${name}@"; then
    present+=("$name")
    printf '  %-24s already installed\n' "$name"
    continue
  fi

  printf '  %-24s installing (%s)\n' "$name" "$why"
  if claude plugin install "${name}@${MARKETPLACE}" >/dev/null 2>&1; then
    added+=("$name")
  else
    failed+=("$name")
  fi
done

echo
echo "==> Summary"
[ ${#present[@]} -gt 0 ] && echo "  already present: ${present[*]}"
[ ${#added[@]}   -gt 0 ] && echo "  installed:       ${added[*]}"

if [ ${#failed[@]} -gt 0 ]; then
  echo "  FAILED:          ${failed[*]}" >&2
  echo >&2
  echo "Install the above manually with: claude plugin install <name>@$MARKETPLACE" >&2
  exit 1
fi

echo
echo "Restart Claude Code to pick up newly installed plugins."
