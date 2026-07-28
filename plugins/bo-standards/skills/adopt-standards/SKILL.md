---
name: adopt-standards
description: Bring an existing repository up to the bo-standards conventions — install ruff/ty/pytest and Biome, write the canonical config, wire the plugin, and record a burn-down for pre-existing violations. Use when onboarding a repo that does not yet follow the standards.
---

Onboard an existing repository. **Idempotent** — safe to re-run as the backlog
shrinks.

Most repos are not ready for the config alone: some are not git repos, some have
no `pyproject.toml`, most have no tests. Handle those first rather than assuming
them.

## 1. Survey before changing anything

Report what you find, then work through only the gaps:

- git repo? (`git rev-parse --is-inside-work-tree`)
- `pyproject.toml`? `package.json`? `tests/`?
- existing ruff / mypy / ty config?
- `.claude/settings.json`?

## 2. Foundations

Offer each of these only when missing, and say what you are about to do:

- **Not a git repo** → `git init -b main`, then `gh repo create --private
  --source=. --push`. Use `-b main` explicitly; `init.defaultBranch` is often
  unset and git still defaults to `master`.
- **Python files but no `pyproject.toml`** → `uv init`
- **No `tests/`** → create it with one real smoke test that imports the package
  and asserts something true. Not a `pass` stub.

## 3. Dependencies

```bash
uv add --dev ruff ty pytest
```

For a Node project (`package.json` present):

```bash
npm i -D @biomejs/biome
```

and copy `templates/biome.json` to the repo root if absent.

## 4. Canonical config

**Read `templates/pyproject-snippet.toml` and splice its blocks into
`pyproject.toml`.** That file is the single source of truth — do not retype the
config from memory, or scaffold, adopt, and CI will drift apart.

**Merge, do not overwrite.** Preserve any `ignore` list, per-file-ignores, or
`[tool.pytest.ini_options]` the project already has. If it already sets
`extend-select`, union the values rather than replacing them, and say what you
merged.

**Remove any `[tool.mypy]` block and drop `mypy` from dev dependencies.** `ty`
replaces it. Two type checkers with different opinions is the problem, not a
safety net.

## 5. Wire the plugin

Copy `templates/settings.json` to `.claude/settings.json` — the GitHub
marketplace source, which is what lets a fresh clone or a cloud sandbox pick up
the plugin.

Add `.claude/settings.local.json` to `.gitignore`. **Never ignore `.claude/`
wholesale** — `settings.json` must be committed or the wiring does not travel.

Before staging anything under `.claude/`, check `mcp.json` for `env` blocks
containing tokens or keys. Do not commit secrets.

Copy `templates/CLAUDE.md` if the repo has none. If it already has one, do not
overwrite it — the conventions section belongs in the plugin, so strip
duplicated convention text from the repo's copy and keep only repo-specific
facts.

## 6. First pass, then the burn-down

```bash
uv run ruff format .
uv run ruff check --fix .
npx biome check --write .    # Node projects
```

Then run `uv run ruff check .` and `uv run ty check` to see what is left.

**This is where adoption usually stalls.** The `D` rules alone produce ~50
findings on a mature repo, most of them missing docstrings. Do not try to write
them all now, and do not weaken the ruleset to make the number go down.

Instead record what remains as a burn-down:

```toml
[tool.ruff.lint.per-file-ignores]
# Burn-down from initial adoption on <date>. Delete entries as the underlying
# issues are fixed; this block should shrink to nothing. New files never get
# added here -- they are held to the full ruleset.
"src/pkg/legacy.py" = ["D103"]
```

The repo is green immediately, new code is held to the full standard, and the
debt is visible and countable rather than silently disabled.

Scope each entry as narrowly as the violations actually require — per file, per
rule. A blanket ignore defeats the purpose.

## 7. Report

- foundations created (git, pyproject, tests)
- dependencies and config added
- what the first pass auto-fixed
- **what went into the burn-down, as a count per rule** — this is the number
  that has to shrink
- anything needing a decision
