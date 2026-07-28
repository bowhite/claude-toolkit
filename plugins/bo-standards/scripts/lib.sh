#!/usr/bin/env bash
# Shared helpers for the bo-standards hook scripts. Sourced, never executed.
#
# Tool resolution is deliberately project-local: this plugin assumes ruff, ty,
# and biome are dev dependencies of the project being edited, not global
# installs. A missing tool is a normal state (the repo hasn't run
# /adopt-standards yet), so every resolver returns empty rather than failing and
# every caller treats empty as "skip silently".

# Hooks run with a stripped environment, so binaries installed by nvm, Homebrew,
# or the Astral installer are not on PATH unless we put them there.
harden_path() {
  PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
  # Node managers keep their binaries outside the system prefix. fnm matters as
  # much as nvm here: bootstrap.sh installs node via fnm on Linux, and a tool
  # shim like node_modules/.bin/biome is `#!/usr/bin/env node` -- so if node is
  # not on PATH, biome fails with a confusing "env: node: No such file or
  # directory" rather than anything that points at the real cause.
  for d in "$HOME"/.nvm/versions/node/*/bin \
           "$HOME"/.local/share/fnm/node-versions/*/installation/bin \
           "$HOME"/.fnm/node-versions/*/installation/bin; do
    [ -d "$d" ] && PATH="$d:$PATH"
  done
  export PATH
}

# project_root [dir] : the git toplevel containing dir, else dir itself.
project_root() {
  local dir="${1:-$PWD}"
  [ -d "$dir" ] || dir=$(dirname "$dir")
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$dir"
}

# find_ruff <root> : path to the project's ruff, or empty.
#
# The venv binary is used directly rather than `uv run ruff`: this runs on every
# single edit, and `uv run` pays lock resolution on each invocation.
find_ruff() {
  local root="$1"
  [ -x "$root/.venv/bin/ruff" ] && printf '%s\n' "$root/.venv/bin/ruff"
}

# find_node_dir <startdir> <root> : nearest ancestor of startdir (stopping at
# root) that contains a package.json, or empty.
#
# The Node project is frequently NOT at the repo root -- two of three Node
# projects here keep it in `frontend/`. Assuming the root silently skipped those
# repos entirely, so walk up from the edited file instead.
find_node_dir() {
  local dir="$1" root="$2"
  [ -d "$dir" ] || dir=$(dirname "$dir")
  while :; do
    [ -f "$dir/package.json" ] && { printf '%s\n' "$dir"; return 0; }
    [ "$dir" = "$root" ] || [ "$dir" = "/" ] && return 1
    dir=$(dirname "$dir")
  done
}

# find_biome <dir> : path to the biome installed for <dir>, or empty.
#
# Deliberately does NOT fall back to `npx @biomejs/biome` or a global binary.
# npx silently downloads an unpinned latest from the network, which is exactly
# the version drift that per-project dev dependencies exist to prevent -- a
# formatter that disagrees with CI is worse than no formatter.
find_biome() {
  local dir="$1"
  [ -x "$dir/node_modules/.bin/biome" ] && printf '%s\n' "$dir/node_modules/.bin/biome"
}

# warn_once <key> <message> : emit message on stderr the first time this key is
# seen for this project, then stay quiet.
#
# Used so "biome is not installed here" surfaces once rather than either
# spamming every edit or -- as it did before -- vanishing entirely and leaving
# files silently unformatted.
warn_once() {
  local key="$1" msg="$2"
  local stamp="${TMPDIR:-/tmp}/bo-standards-warn-$(printf '%s' "$key" | shasum | cut -c1-16)"
  [ -e "$stamp" ] && return 1
  : > "$stamp"
  printf '%s\n' "$msg" >&2
  return 0
}

# hook_input : the raw hook JSON from stdin.
hook_input() { cat; }

# json_field <json> <jq-expr> : extract a field, empty if absent or unparseable.
json_field() {
  printf '%s' "$1" | jq -r "$2 // empty" 2>/dev/null
}
