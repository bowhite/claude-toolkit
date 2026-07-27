#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash)
#
# Blocks a small set of commands that are either destructive or contradict the
# project toolchain. Exit 2 blocks the call and feeds stderr back to Claude;
# exit 0 allows it. Exit 1 would only warn and enforce nothing, so it is never
# used here.
#
# SCOPE, HONESTLY: this is pattern matching over a shell command string. It
# catches the obvious and the accidental. It does NOT catch `eval`, base64'd
# payloads, variable indirection, command substitution, or a `cd` into another
# tree first. Treat it as a seatbelt against mistakes, NOT as a security
# boundary against a determined or adversarial caller.

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

harden_path

input=$(hook_input)
cmd=$(json_field "$input" '.tool_input.command')
[ -z "$cmd" ] && exit 0

root=$(project_root "$PWD")

# block <reason> <suggestion> : refuse the command and tell Claude why.
block() {
  {
    echo "BLOCKED by bo-standards: $1"
    [ -n "${2:-}" ] && { echo; echo "$2"; }
  } >&2
  exit 2
}

# Strip quotes so `rm -rf "$HOME"` and `rm -rf $HOME` look alike to the matcher.
bare=${cmd//\"/}
bare=${bare//\'/}

# Because quotes are stripped, a tool name inside a string literal is
# indistinguishable from an invocation -- `echo "no pip install here"` would
# otherwise be blocked. Anchoring to command position (start of line, or just
# after a shell separator, allowing a sudo/env prefix) removes that whole class
# of false positive while still catching `foo && pip install bar`.
CMD_POS='(^|[;&|(])[[:space:]]*(sudo[[:space:]]+)?(env[[:space:]]+[A-Za-z_]+=[^[:space:]]*[[:space:]]+)*'

# at_cmd_pos <regex> : true when regex matches at a command position in $bare.
at_cmd_pos() {
  printf '%s' "$bare" | grep -qE "${CMD_POS}$1"
}

# --------------------------------------------------------------- rm -rf ------
# Only inspect commands that actually recursive-force delete.
if printf '%s' "$bare" | grep -qE '\brm\b[^|;&]*-[a-zA-Z]*r[a-zA-Z]*f|\brm\b[^|;&]*-[a-zA-Z]*f[a-zA-Z]*r'; then
  # Pull out the operands that follow `rm`, ignoring its flags and stopping at
  # a shell separator so `rm -rf build && cd /` does not report `/` as a target.
  #
  # This is awk rather than sed on purpose: BSD sed (the macOS default) does not
  # support \b, so a word-boundary pattern here silently matches nothing and the
  # whole check becomes a no-op that still looks like it is running.
  targets=$(printf '%s\n' "$bare" | awk '{
    for (i = 1; i <= NF; i++) {
      if ($i ~ /(^|\/)rm$/)                                   { inrm = 1; continue }
      if (!inrm)                                              { continue }
      if ($i == "&&" || $i == "||" || $i == ";" || $i == "|") { inrm = 0; continue }
      if ($i ~ /^-/)                                          { continue }
      print $i
    }
  }')

  while IFS= read -r t; do
    [ -z "$t" ] && continue
    case "$t" in
      /|/\*|'~'|'~/'*|'$HOME'|'$HOME/'*|'${HOME}'*)
        block "\`rm -rf\` targeting a home or root path ($t)." \
              "If you really mean it, run it yourself outside Claude Code." ;;
      *..*)
        block "\`rm -rf\` with a parent-directory traversal ($t)." \
              "Delete by an explicit path inside the project instead." ;;
      /*)
        # Absolute path: allowed only if it is inside the project.
        case "$t" in
          "$root"|"$root"/*) ;;
          *) block "\`rm -rf\` targeting an absolute path outside the project ($t)." \
                   "Project root is: $root" ;;
        esac ;;
    esac
  done <<< "$targets"
fi

# --------------------------------------------------------------- force push --
# --force-with-lease is deliberately allowed: it refuses to clobber work it has
# not seen, which is the whole reason it exists.
if printf '%s' "$bare" | grep -qE '\bgit\b.*\bpush\b'; then
  if printf '%s' "$bare" | grep -qE '(--force([^-]|$)|[[:space:]]-[a-zA-Z]*f([[:space:]]|$))' \
     && ! printf '%s' "$bare" | grep -q -- '--force-with-lease'; then
    if printf '%s' "$bare" | grep -qE '\b(main|master)\b|HEAD'; then
      block "force-push to main/master." \
             "Use --force-with-lease, or push to a branch and open a PR."
    fi
  fi
fi

# --------------------------------------------------------------- lockfiles ---
# Lockfiles are generated artefacts. Hand-editing them desynchronises them from
# the manifest in ways that only surface later, on someone else's machine.
if printf '%s' "$bare" | grep -qE '(>>?[[:space:]]*[^[:space:]]*(uv\.lock|package-lock\.json)|\bsed\b[^|;&]*-i[^|;&]*(uv\.lock|package-lock\.json)|\b(tee|truncate)\b[^|;&]*(uv\.lock|package-lock\.json))'; then
  block "a direct write to a lockfile." \
         "Change the manifest and let the tool regenerate it: \`uv lock\` or \`npm install\`."
fi

# --------------------------------------------------------------- pip ---------
# `uv pip ...` is fine; bare pip is not.
if at_cmd_pos '(python3?[[:space:]]+-m[[:space:]]+)?pip3?[[:space:]]+install' \
   && ! printf '%s' "$bare" | grep -qE 'uv[[:space:]]+pip[[:space:]]+install'; then
  block "\`pip install\`." \
         "This project uses uv: \`uv add <pkg>\` (or \`uv add --dev <pkg>\`)."
fi

# --------------------------------------------------------------- toolchain ---
# These are the tools this plugin deliberately replaced. Blocking them keeps a
# stray invocation from reintroducing a second formatter or type checker whose
# opinions differ from CI's.
if at_cmd_pos '(npx[[:space:]]+)?(prettier|eslint|markdownlint(-cli2)?)([[:space:]]|$)'; then
  block "prettier/eslint/markdownlint." \
         "This project uses Biome for JS/TS/JSX/TSX/CSS/JSON. Markdown is deliberately not linted or formatted at all."
fi

if at_cmd_pos '(uvx?[[:space:]]+(run[[:space:]]+)?)?(mypy|pyright)([[:space:]]|$)'; then
  block "mypy/pyright." \
         "This project uses ty for type checking: \`uv run ty check\`."
fi

exit 0
