# claude-toolkit

Bo's project conventions, packaged once as a Claude Code plugin and installed
per repo instead of copy-pasted into each one.

**Marketplace:** `bo-toolkit` · **Plugin:** `bo-standards`

## The toolchain

| Language | Format & lint | Types |
|---|---|---|
| Python | `ruff` | `ty` |
| JS / TS / JSX / TSX / CSS / JSON | `biome` | — |
| Markdown | *nothing, deliberately* | — |

Not used, and blocked by the Bash guard: **prettier, eslint, markdownlint,
mypy, pyright**. One tool per job; a second opinion in the editor that CI does
not share is a bug, not a safety net.

Markdown is untooled on purpose. Biome does not format it (verified against
2.5.3 — `.md` passes through byte-for-byte unchanged), and nothing else was
added to fill the gap.

## Install

Per project, never globally. From inside the target repo:

```bash
claude plugin marketplace add bowhite/claude-toolkit --scope project && claude plugin install bo-standards@bo-toolkit --scope project
```

That writes `.claude/settings.json`, which **must be committed**. It is what
carries the plugin into a fresh clone or a Claude Desktop cloud sandbox.
Gitignore only `.claude/settings.local.json` — never `.claude/` wholesale.

Tooling is a per-project dev dependency too:

```bash
uv add --dev ruff ty pytest && npm i -D @biomejs/biome
```

Run `adopt-standards` to do all of the above at once.

## Hooks

| Hook | Event | Behaviour |
|---|---|---|
| `format.sh` | `PostToolUse` (`Edit\|Write\|NotebookEdit`) | Formats the edited file. Exit 2 feeds unfixable diagnostics back to Claude. |
| `guard-bash.sh` | `PreToolUse` (`Bash`) | Blocks destructive and off-toolchain commands. Exit 2 prevents the call. |
| `session-start.sh` | `SessionStart` | Prints working tree, recent commits, and a hint if dependencies are missing. |

There is **no `Stop` hook**. Nothing slow runs on a turn boundary; verification
is the deliberate `pr-check` step and CI.

A missing tool is always a silent skip, never an error — a repo that has not
adopted yet should not have every edit fail.

### What the guard blocks

`rm -rf` outside the project · force-push to `main`/`master` (but
`--force-with-lease` is allowed) · direct writes to `uv.lock` /
`package-lock.json` · bare `pip install` (`uv pip install` is fine) ·
prettier / eslint / markdownlint · mypy / pyright

**This is not a security boundary.** It is pattern matching over a shell
command string. It catches mistakes and habits. It does not catch `eval`,
base64'd payloads, variable indirection, or a `cd` elsewhere first. Treat it as
a seatbelt.

## Skills

| Skill | Use it when |
|---|---|
| `adopt-standards` | Onboarding an existing repo |
| `scaffold-project` | Starting a new one |
| `lint` | Whole-repo format, lint, and type-check pass |
| `pr-check` | Before opening a PR |
| `ci-workflow` | Generating or repairing `.github/workflows/ci.yml` |

## Delegated to official Anthropic plugins

`bo-standards` owns only what nothing official knows about. Everything else is
someone else's job:

- **Commit, push, open PR** → `commit-commands` (`/commit`, `/commit-push-pr`)
- **PR review** → `pr-review-toolkit`, `code-review`
- **Docstring accuracy** → `pr-review-toolkit:comment-analyzer`
- **CLAUDE.md upkeep** → `claude-md-management`
- **Library docs** → `context7`
- **GitHub API** → the `gh` CLI, not the GitHub MCP server

## bootstrap.sh

Installs only what uv and npm cannot provide — `uv`, `node`, `jq`, `gh`, `git` —
then runs `uv sync` and `npm ci`. This is what makes a repo usable in a cloud
sandbox that starts with nothing.

```bash
./scripts/bootstrap.sh              # tooling + project dependencies
./scripts/bootstrap.sh --no-project # tooling only
```

Idempotent: every step is guarded, and a second run installs nothing.

**Verified on macOS 26 (arm64) and Debian bookworm (arm64)**, the latter in an
Apple `container` VM. On Linux it installs Node via fnm (Debian's apt package is
Node 18, past EOL) and appends a marker-guarded `PATH` block to the shell
profile. It does **not** touch shell profiles on macOS, where brew and nvm
already handle this.

## Canonical Python config

Emitted identically by `scaffold-project`, `adopt-standards`, and
`ci-workflow`:

```toml
[tool.ruff.lint]
extend-select = ["I", "UP", "B", "SIM", "ANN", "PYI", "D"]
preview = true

[tool.ruff.lint.pydocstyle]
convention = "google"

[tool.ty.rules]
missing-type-argument = "error"
possibly-unresolved-reference = "warn"
```

Astral's own recommendation is `["ANN", "PYI"]` plus `preview`, extending ruff's
default `select` of `["E4", "E7", "E9", "F"]`. That default drops import sorting
and three advisory families, so `I`, `UP`, `B`, and `SIM` are kept explicitly —
making this a strict superset of both Astral's recommendation and what these
repos already passed.

## Adopting an existing repo

The `D` (docstring) rules dominate the cost: roughly 50 findings on a mature
repo, ~44 of them simply missing docstrings, only a handful auto-fixable.

`adopt-standards` therefore records what remains as a burn-down rather than
demanding it all up front:

```toml
[tool.ruff.lint.per-file-ignores]
"src/pkg/legacy.py" = ["D103"]
```

The repo is green immediately, new code is held to the full ruleset, and the
debt is countable. **The block only works if it shrinks** — if it is the same
size in three months, drop `D` rather than keep an ignore list pretending to be
a plan.

## GitHub conventions

New repos get: default branch `main` (set explicitly — `init.defaultBranch` is
usually unset and git still creates `master`), `.github/CODEOWNERS` with
`* @bowhite`, delete-branch-on-merge, PR and issue templates.

**No branch protection or rulesets are configured.** Deliberate, and it has
consequences worth knowing:

- `main` accepts direct pushes, and a red PR can still be merged. CI is
  advisory, which makes `pr-check` the only real gate.
- CODEOWNERS still auto-requests review — that needs no protection — but nothing
  enforces it.
- Auto-merge rarely surfaces, since GitHub only offers it on a PR blocked by a
  required check.

Also: **`allow_auto_merge` cannot be enabled on a private repo** on a free plan.
The CLI exits 0 and the API returns success while the value stays `false`.
Always verify rather than trust the exit code:

```bash
gh api repos/<owner>/<name> --jq '{private, allow_auto_merge, delete_branch_on_merge}'
```

## Repo layout

```text
.claude-plugin/marketplace.json
plugins/bo-standards/
├── .claude-plugin/plugin.json
├── hooks/hooks.json
├── scripts/       lib.sh, bootstrap.sh, format.sh, guard-bash.sh, session-start.sh
├── skills/        adopt-standards, ci-workflow, lint, pr-check, scaffold-project
└── templates/     biome.json, ci.yml, CLAUDE.md, settings.json, PR + issue templates
```

## Changing the plugin

Because installs resolve the marketplace from GitHub, a change is not visible to
other repos until it is pushed. For iterating on the plugin itself, install from
the working tree instead:

```bash
claude plugin marketplace add /path/to/claude-toolkit --scope local
```

After editing, run `claude plugin validate .` and restart the session — hooks
are read at session start.
