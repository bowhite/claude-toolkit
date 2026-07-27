#!/usr/bin/env bash
# Dev environment bootstrap.
#
# Installs ONLY the tooling that cannot come from uv or npm -- the bottom layer
# a project needs before its own dev dependencies can be installed. Everything
# above this line (ruff, ty, pytest, biome) is a per-project dev dependency and
# is deliberately NOT installed here.
#
# The point is that a fresh machine or a Claude Desktop cloud sandbox can clone
# a repo, run this, and be ready to work.
#
# Idempotent: every step is guarded by a `command -v` check, so re-running is a
# no-op that reports what was already present.
#
# Usage:  ./bootstrap.sh [--no-project]
#           --no-project   install tooling only, skip `uv sync` / `npm ci`

set -uo pipefail

# Put the locations these installers write to on PATH up front.
#
# Without this the script is not actually idempotent: the Astral installer puts
# uv in ~/.local/bin and updates the shell profile, but a non-login,
# non-interactive shell never sources that profile -- so a second run does not
# see uv and reinstalls it every time. Same story for fnm's node.
for d in "$HOME/.local/bin" "$HOME/.local/share/fnm" /opt/homebrew/bin /usr/local/bin; do
  [ -d "$d" ] && case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
done
for d in "$HOME"/.nvm/versions/node/*/bin "$HOME"/.local/share/fnm/node-versions/*/installation/bin; do
  [ -d "$d" ] && PATH="$d:$PATH"
done
export PATH

SKIP_PROJECT=0
[ "${1:-}" = "--no-project" ] && SKIP_PROJECT=1

installed=()
present=()
failed=()

log()  { printf '  %s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }

# ---------------------------------------------------------------- platform ---

OS=$(uname -s)
case "$OS" in
  Darwin) PLATFORM=macos ;;
  Linux)  PLATFORM=linux ;;
  *)      printf 'Unsupported platform: %s\n' "$OS" >&2; exit 1 ;;
esac

# On Linux, apt needs root. Use sudo only when we are not already root and sudo
# actually exists -- neither is guaranteed inside a container.
SUDO=""
if [ "$PLATFORM" = linux ] && [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 && SUDO=sudo
fi

APT_UPDATED=0
apt_install() {
  if [ "$APT_UPDATED" -eq 0 ]; then
    $SUDO apt-get update -qq >/dev/null 2>&1
    APT_UPDATED=1
  fi
  $SUDO apt-get install -y -qq "$@" >/dev/null 2>&1
}

# pkg_install <name> : install via the platform package manager.
pkg_install() {
  case "$PLATFORM" in
    macos)
      command -v brew >/dev/null 2>&1 || return 1
      brew install "$1" >/dev/null 2>&1
      ;;
    linux)
      command -v apt-get >/dev/null 2>&1 || return 1
      apt_install "$1"
      ;;
  esac
}

# ensure <binary> <installer-function> : install only if missing.
ensure() {
  local bin="$1" installer="$2"
  if command -v "$bin" >/dev/null 2>&1; then
    present+=("$bin")
    log "$bin already present ($(command -v "$bin"))"
    return 0
  fi
  log "installing $bin ..."
  if "$installer" && command -v "$bin" >/dev/null 2>&1; then
    installed+=("$bin")
    log "$bin installed"
  else
    failed+=("$bin")
    log "FAILED to install $bin"
  fi
}

# ---------------------------------------------------------------- installers -

install_git() { pkg_install git; }
install_jq()  { pkg_install jq; }

install_curl() { pkg_install curl; }

install_uv() {
  # Astral's installer puts uv in ~/.local/bin and needs no root.
  curl -LsSf https://astral.sh/uv/install.sh | sh >/dev/null 2>&1
  export PATH="$HOME/.local/bin:$PATH"
}

install_node() {
  case "$PLATFORM" in
    macos) pkg_install node ;;
    linux)
      # Debian's `nodejs` package is far behind -- bookworm ships Node 18, which
      # is past end of life. Prefer fnm: a single binary, no root needed, and the
      # version can float per project.
      #
      # fnm's installer hard-requires unzip and exits if it is missing. Without
      # installing it first this whole branch fails its dependency check and
      # falls through to the apt fallback, which looks like success (node exists)
      # while silently leaving you on an EOL runtime.
      apt_install unzip

      if curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell >/dev/null 2>&1 \
         && [ -x "$HOME/.local/share/fnm/fnm" ]; then
        export PATH="$HOME/.local/share/fnm:$PATH"
        eval "$(fnm env --shell bash)" 2>/dev/null || true
        if fnm install --lts >/dev/null 2>&1; then
          fnm default lts-latest >/dev/null 2>&1 || fnm use --lts >/dev/null 2>&1
          # Make the freshly installed node visible to the rest of this script
          # and to `ensure`'s command -v check.
          for d in "$HOME"/.local/share/fnm/node-versions/*/installation/bin; do
            [ -d "$d" ] && PATH="$d:$PATH"
          done
          export PATH
        fi
      fi

      # Fall back only if fnm genuinely did not produce a usable node.
      command -v node >/dev/null 2>&1 || apt_install nodejs npm
      ;;
  esac
}

install_gh() {
  case "$PLATFORM" in
    macos) pkg_install gh ;;
    linux)
      # gh is not in Debian stable's default repos; add GitHub's own.
      $SUDO mkdir -p -m 755 /etc/apt/keyrings 2>/dev/null
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | $SUDO tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null 2>&1
      $SUDO chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null 2>&1
      APT_UPDATED=0
      apt_install gh
      ;;
  esac
}

# ---------------------------------------------------------------- run --------

step "Bootstrapping dev environment ($PLATFORM)"

if [ "$PLATFORM" = macos ] && ! command -v brew >/dev/null 2>&1; then
  log "WARNING: Homebrew not found. git/jq/node/gh cannot be auto-installed."
  log "Install it from https://brew.sh, then re-run this script."
fi

ensure curl install_curl
ensure git  install_git
ensure jq   install_jq
ensure uv   install_uv
ensure node install_node
ensure gh   install_gh

# ---------------------------------------------------------------- project ----

if [ "$SKIP_PROJECT" -eq 0 ]; then
  root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

  if [ -f "$root/pyproject.toml" ]; then
    step "Syncing Python dependencies"
    if (cd "$root" && uv sync); then
      log "uv sync complete"
    else
      failed+=("uv sync")
      log "FAILED: uv sync"
    fi
  fi

  if [ -f "$root/package-lock.json" ]; then
    step "Installing Node dependencies"
    if (cd "$root" && npm ci); then
      log "npm ci complete"
    else
      failed+=("npm ci")
      log "FAILED: npm ci"
    fi
  elif [ -f "$root/package.json" ]; then
    step "Installing Node dependencies (no lockfile)"
    if (cd "$root" && npm install); then
      log "npm install complete"
    else
      failed+=("npm install")
      log "FAILED: npm install"
    fi
  fi
fi

# ---------------------------------------------------------------- profile ---
# uv's installer edits the shell profile; fnm's does not when run with
# --skip-shell. Without this block, node is installed but invisible to the next
# shell, and the failure surfaces much later as
# `/usr/bin/env: 'node': No such file or directory` from a tool shim.
#
# Guarded by a marker so re-running never appends a second copy.
write_profile_block() {
  local marker="# >>> bo-standards bootstrap >>>"
  local rc
  for rc in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -e "$rc" ] || continue
    grep -qF "$marker" "$rc" 2>/dev/null && continue
    cat >> "$rc" <<'PROFILE'

# >>> bo-standards bootstrap >>>
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac
for _d in "$HOME"/.local/share/fnm/node-versions/*/installation/bin; do
  [ -d "$_d" ] && PATH="$_d:$PATH"
done
unset _d
export PATH
# <<< bo-standards bootstrap <<<
PROFILE
    log "PATH block added to $rc"
  done
}

# Linux only. On macOS, Homebrew and nvm already put these on PATH through the
# user's existing shell setup, so appending here would be redundant edits to a
# config file this script has no business touching.
[ "$PLATFORM" = linux ] && write_profile_block

# ---------------------------------------------------------------- summary ----

step "Summary"
[ ${#present[@]}   -gt 0 ] && log "already present: ${present[*]}"
[ ${#installed[@]} -gt 0 ] && log "installed:       ${installed[*]}"

if [ ${#failed[@]} -gt 0 ]; then
  log "FAILED:          ${failed[*]}"
  printf '\nBootstrap incomplete. Install the above manually and re-run.\n' >&2
  exit 1
fi

printf '\nReady.\n'
