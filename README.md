# claude-toolkit

Bo's project conventions, packaged once as a Claude Code plugin and installed
per repo instead of copy-pasted into each one.

**Marketplace:** `bo-toolkit` · **Plugin:** `bo-standards`

## The toolchain

| Language | Format & lint | Types |
|---|---|---|
| Python | `ruff` | `ty` |
| JS / TS / JSX / TSX / CSS / JSON | `biome` | `tsc --noEmit` |
| Markdown | *nothing, deliberately* | — |

Not used, and blocked by the Bash guard: **prettier, eslint, markdownlint,
mypy, pyright**. One tool per job; a second opinion in the editor that CI does
not share is a bug, not a safety net.

Markdown is untooled on purpose. Biome does not format it (verified against
2.5.3 — `.md` passes through byte-for-byte unchanged), and nothing else was
added to fill the gap.

**Biome does no type checking at all**, which is why `tsc --noEmit` is separate.
Without it a TypeScript project is linted and formatted but never type-checked.

---

## What actually happens when you install

Installing is **mechanical and safe — it never edits your files.** This is the
most common point of confusion, so, precisely:

| | Active immediately? |
|---|---|
| Format hook, Bash guard, session-start | ✅ **yes**, from the next session |
| The 8 skills | ⚠️ **available, but only run when invoked** — by you (`/lint`) or when Claude judges one applies |
| Templates | ❌ **inert files.** Nothing reads them unless a skill does |
| `pyproject.toml`, dev dependencies | ❌ **untouched** |

So on a fresh install the hooks run but **do nothing to Python files**, because
`format.sh` looks for `.venv/bin/ruff` and finds nothing.

**Run `adopt-standards` to actually onboard a repo.** That is the step that
installs `ruff`/`ty`/`pytest`, writes the config from
`templates/pyproject-snippet.toml`, and wires `.claude/settings.json`. Install
and adopt are deliberately separate so installing can never surprise you with a
50-finding diff.

## Install

Per project, never globally. From inside the target repo:

```bash
claude plugin marketplace add bowhite/claude-toolkit --scope project && claude plugin install bo-standards@bo-toolkit --scope project
```

That writes `.claude/settings.json`, which **must be committed**. It is what
carries the plugin into a fresh clone or a cloud sandbox. Gitignore only
`.claude/settings.local.json` — never `.claude/` wholesale.

Then set the machine up and onboard the repo:

```bash
~/claude-toolkit/plugins/bo-standards/scripts/bootstrap.sh
```

…and ask Claude to run the **`adopt-standards`** skill. That is the step that
installs `ruff`/`ty` and edits `pyproject.toml` — installing the plugin does not.

(`scaffold-project` copies `bootstrap.sh` into new projects as `scripts/bootstrap.sh`,
so in those it is just `./scripts/bootstrap.sh`.)

## Without GitHub

**GitHub is not required.** Verified: a marketplace in a plain directory with no
git repository at all installs cleanly and its skills register. Useful on a work
machine where publishing would drag a reviewer into something that is just your
own tooling.

```bash
claude plugin marketplace add /path/to/your-toolkit --scope project
claude plugin install your-standards@your-toolkit --scope project
```

The only structure needed is `.claude-plugin/marketplace.json` plus
`plugins/<name>/.claude-plugin/plugin.json`. No remote, no commits, no git.

### Recommended setup for a machine with no GitHub

```bash
git clone https://github.com/bowhite/claude-toolkit ~/claude-toolkit
cd ~/claude-toolkit && git remote set-url --push origin no-push
```

**`set-url --push no-push` beats removing the remote**: `git fetch` still pulls
upstream changes, while any `git push` fails outright. Verified — fetch exits 0,
push is rejected. Commit your local edits on a branch; you keep both your changes
and the ability to pull mine.

Then wire it into every project at once:

```bash
~/claude-toolkit/plugins/bo-standards/scripts/enable-in-projects.sh ~/work/*/
```

The wiring is **identical in every project** — the path points at the toolkit,
not at the project — so copying `.claude/settings.json` between repos genuinely
works. Verified: a project that only had the file copied in, with no install
command ever run, reports the plugin enabled at project scope.

`enable-in-projects.sh` merges into an existing `settings.json` rather than
overwriting it, and refuses to write a path with no `marketplace.json` at it.
Use `--local` for repos shared with colleagues: it writes
`settings.local.json` and gitignores it, so an absolute path that exists only on
your machine is never committed.

**Keep the toolkit at a stable path.** A wrong path does not fail loudly — the
plugin can keep resolving from a stale cache, so it looks installed while the
source is gone. `~/claude-toolkit` and leave it there.

**Rename the marketplace if you diverge.** If your copy stops tracking this one,
change `name` in `.claude-plugin/marketplace.json` and the plugin directory to
something like `work-toolkit` / `work-standards`. Two different marketplaces both
called `bo-toolkit` on one machine will collide, and the failure is confusing —
you get someone else's version of a skill with no indication why.

There is also no `marketplace update` to run in this mode — the directory *is*
the source, so your edits are live. You still need to restart Claude Code for
hooks and skills to be re-read.

## Updating

The marketplace cache is **a git clone of this repo**, so updates are a pull:

```bash
claude plugin marketplace update bo-toolkit
```

Then **restart Claude Code** — hooks and skills are read at session start.

Nothing prompts users automatically. Pushing a commit here does not reach an
installed copy until someone runs that command, and `claude plugin details`
keeps reporting the old inventory until the session restarts. If you change a
hook, say so — a stale copy fails silently rather than loudly.

---

## Hooks

| Hook | Event | Behaviour |
|---|---|---|
| `format.sh` | `PostToolUse` (`Edit\|Write\|NotebookEdit`) | Formats the edited file. Exit 2 feeds unfixable diagnostics back to Claude. |
| `guard-bash.sh` | `PreToolUse` (`Bash`) | Blocks destructive and off-toolchain commands. Exit 2 prevents the call. |
| `session-start.sh` | `SessionStart` | Working tree, recent commits, and a hint when dependencies are missing. |

There is **no `Stop` hook**. Nothing slow runs on a turn boundary; verification
is the deliberate `pr-check` step and CI.

A missing tool is a silent skip for Python, and a **once-per-project warning**
for JS/TS — an unformatted file that looks identical to success was worse than a
little noise.

The Node project is found by walking up from the edited file to the nearest
`package.json`, so a `frontend/` subdirectory works. Biome resolves from
`node_modules/.bin` only — **never `npx`**, which downloads an unpinned latest
from the network and silently disagrees with CI.

### What the guard blocks

`rm -rf` outside the project · force-push to `main`/`master` (but
`--force-with-lease` is allowed) · direct writes to `uv.lock` /
`package-lock.json` · bare `pip install` (`uv pip install` is fine) ·
prettier / eslint / markdownlint · mypy / pyright

**This is not a security boundary.** It is pattern matching over a shell command
string. It catches mistakes and habits, not `eval`, base64'd payloads, variable
indirection, or a `cd` elsewhere first. A seatbelt.

## Skills

| Skill | Use it when |
|---|---|
| `adopt-standards` | Onboarding an existing repo — **the step that edits your config** |
| `scaffold-project` | Starting a new one |
| `lint` | Whole-repo format, lint, and type-check pass |
| `pr-check` | Before opening a PR |
| `ci-workflow` | Generating or repairing `.github/workflows/ci.yml` |
| `update-docs` | README/CLAUDE.md/docstrings have drifted from the code |
| `fix-security` | Dependabot alerts, leaked credentials, CVEs, code scanning |
| `deploy-toolkit` | Rolling out across a machine and several existing repos |

## Scripts

Run directly; none of them need Claude.

| Script | What it does |
|---|---|
| `bootstrap.sh` | Machine tooling + project dependencies |
| `install-plugins.sh` | The official Anthropic plugins, at user scope |
| `migrate-legacy.sh` | Audit and retire a pre-plugin setup |
| `enable-in-projects.sh` | Wire the plugin into many projects at once |
| `format.sh`, `guard-bash.sh`, `session-start.sh` | The hooks — invoked by Claude Code, not by you |
| `lib.sh` | Shared helpers, sourced by the hooks |

## Templates

Single sources of truth. Skills read these rather than restating them, so
scaffold, adopt, and CI cannot drift apart.

| Template | What it is |
|---|---|
| `pyproject-snippet.toml` | **The canonical ruff/ty/pytest config** |
| `biome.json` | Biome config with VCS ignore handling on |
| `ci.yml`, `codeql.yml`, `dependabot.yml` | CI and security workflows |
| `CLAUDE.md` | Project memory, conventions section included |
| `settings.json` | Per-project plugin wiring |
| `CODEOWNERS` | **Comments only — no owner assigned.** See below |
| `PULL_REQUEST_TEMPLATE.md`, `ISSUE_TEMPLATE/` | GitHub templates |

Templates are **inert** — nothing reads them unless a skill does. Editing one
changes what future `adopt-standards` / `scaffold-project` runs emit; it does
not retroactively change any project.

## Delegated to official Anthropic plugins

`bo-standards` owns only what nothing official knows about:

- **Commit, push, open PR** → `commit-commands`
- **PR review** → `pr-review-toolkit`, `code-review`
- **Docstring accuracy** → `pr-review-toolkit:comment-analyzer`
- **CLAUDE.md upkeep** → `claude-md-management`
- **Library docs** → `context7`
- **Security guidance** → `security-guidance`
- **GitHub API** → the `gh` CLI, not the GitHub MCP server

```bash
./plugins/bo-standards/scripts/install-plugins.sh
```

Installs that set at user scope, idempotently. Deliberately excluded:
`pyright-lsp` (this toolchain uses `ty`) and `github` (the `gh` CLI covers it).

There is **no first-party Anthropic plugin for authoring documentation or for
remediating security findings** — `context7` only looks docs up. That gap is why
`update-docs` and `fix-security` are in this plugin.

## Deploying to a machine that already has a setup

Use the **`deploy-toolkit`** skill, which sequences the machine-level work and
then goes project by project. The migration step is:

```bash
./plugins/bo-standards/scripts/migrate-legacy.sh                        # audit only
./plugins/bo-standards/scripts/migrate-legacy.sh --apply                # hooks + commands
./plugins/bo-standards/scripts/migrate-legacy.sh --apply --include-configs
```

**Audit mode is the default and changes nothing.** It finds:

| Category | Default action |
|---|---|
| `~/.claude/hooks/*lint*`, `*format*`, `*eslint*` … | retired with `--apply` |
| user commands/skills colliding with a plugin skill | retired with `--apply` |
| `PostToolUse`/`PreToolUse`/`Stop` in user **or project** `settings.json` | removed with `--apply`, backed up first |
| `~/.config/ruff/ruff.toml`, `mypy/config`, `.markdownlint.*`, `.eslintrc*`, `.prettierrc`, `pyrightconfig.json` | **reported only** unless `--include-configs` |
| any **unrecognised** hook | reported and **left alone** — never swept up |

**`~/.config/ruff/ruff.toml` deserves a decision, not a reflex.** A global
`select = [...]` *replaces* ruff's defaults, so every project without its own
config is linted by a different ruleset than an adopted one — silently. Retiring
it makes those projects fall back to ruff's defaults, which is a real change.

**Nothing is deleted.** Files become `*.retired` and `settings.json` gets a
timestamped `.bak`, because `~/.claude` and `~/.config` are not version
controlled. Only the hook keys are stripped from `settings.json`; `model`,
`permissions`, and `enabledPlugins` are untouched.

## bootstrap.sh

Installs only what uv and npm cannot provide — `uv`, `node`, `jq`, `gh`, `git`,
`gitleaks` — then installs the project's own dependencies.

```bash
# from this repo
./plugins/bo-standards/scripts/bootstrap.sh --no-project

# from a scaffolded project, where scaffold-project copies it to scripts/
./scripts/bootstrap.sh              # tooling + project dependencies
./scripts/bootstrap.sh --no-project # tooling only
```

### What it skips

**Machine tooling** is skipped whenever the binary is **on `PATH`** — that is the
actual test, not "global vs local". Bootstrap deliberately prepends the places
these land, so it finds tools installed by Homebrew, nvm, fnm, the Astral
installer, or its own `~/.local/bin` fallbacks. On this Mac it correctly detects
all six across four different locations and installs nothing.

A tool installed somewhere unusual and *not* on `PATH` will be reinstalled into
`~/.local/bin`. That is the intended behaviour — an unreachable binary is not
usable by the hooks either.

**Project dependencies:**

- `uv sync` is already idempotent — a no-op when the environment matches.
- `npm ci` is **not**: it deletes `node_modules` and reinstalls from scratch
  every run. So bootstrap skips it when `package-lock.json` is no newer than
  npm's own `node_modules/.package-lock.json`, and reinstalls when it is.
- `package.json` is located up to 3 levels deep, so a `frontend/` subdirectory
  is found — checking only the repo root skipped the Node half entirely in most
  of these projects.

**Verified on macOS 26 (arm64) and Debian bookworm (arm64)**, the latter in an
Apple `container` VM.

### Without root or sudo

Everything except `git` installs into `~/.local/bin` with no privileges:

| Tool | No-sudo Debian |
|---|---|
| `uv`, `jq`, `gh`, `gitleaks` | ✅ release binaries into `~/.local/bin` |
| `node` | ✅ official tarball into `~/.local/node` |
| `git` | ❌ needs a package manager — reported, exit 1 |

`jq` matters most: both hooks parse hook JSON with it, so without `jq` they
silently do nothing.

Missing tools are always reported by name with a non-zero exit — never a silent
partial success. On Linux a marker-guarded `PATH` block is appended to the shell
profile; **macOS profiles are never touched**, since brew and nvm already handle
it.

---

## Canonical Python config

In `templates/pyproject-snippet.toml`:

```toml
[tool.ruff.lint]
extend-select = ["ANN", "PYI", "D"]
preview = true

[tool.ruff.lint.pydocstyle]
convention = "google"

[tool.ty.rules]
missing-type-argument = "error"
possibly-unresolved-reference = "warn"
```

This is [Astral's documented recommendation](https://docs.astral.sh/ty/coming-from-mypy-or-pyright/)
plus `D` for docstrings.

**Do not add `I`, `UP`, `B`, or `SIM`** — ruff 0.16 enables them by default.
Verified behaviourally: `ruff check --isolated` with no config at all flags
`I001`, `UP045`, `SIM102`, and `BLE001`. (Older ruff defaulted to just
`E4/E7/E9/F`, which is where the belief they are needed comes from.) Measured on
real repos, adding them changes the finding count by 0–1.

`D` is the entire adoption cost: on one repo it took the count from 12 to 56.

## Adopting an existing repo

`adopt-standards` records pre-existing violations as a burn-down rather than
demanding they all be fixed at once:

```toml
[tool.ruff.lint.per-file-ignores]
"src/pkg/legacy.py" = ["D103"]
```

Green on day one, new code held to the full ruleset, debt countable. **It only
works if it shrinks** — if the block is the same size in three months, drop `D`
rather than keep an ignore list pretending to be a plan.

---

## GitHub conventions

New repos get: **private**, default branch `main` (set explicitly — `init.defaultBranch`
is usually unset and git still creates `master`), delete-branch-on-merge, PR and
issue templates, and an empty CODEOWNERS.

Auto-merge is always attempted, then **read back and reported honestly**:

```bash
gh api repos/<owner>/<name> --jq '{private, allow_auto_merge, delete_branch_on_merge}'
```

**`allow_auto_merge` cannot be enabled on a private repo** on a free plan. The
CLI exits 0 and the API returns success while the value stays `false` — verified,
it flipped to `true` the moment the repo was made public. Never trust the exit
code.

### CODEOWNERS is empty on purpose

`* @yourself` is actively harmful on a solo repo: **GitHub will not let a PR
author approve their own PR**, so pairing it with a required-review rule makes
every PR you open permanently unmergeable. `templates/CODEOWNERS` ships as
comments explaining the format. Assign an owner when a second person genuinely
reviews — e.g. `* @your-boss`.

### Stopping Claude from pushing to main

On a repo where you and Claude are the only contributors, required reviews
cannot work — there is no second human. Use a **ruleset with a required status
check** instead, which needs no reviewer:

```bash
gh api -X POST repos/<owner>/<name>/rulesets --input ruleset.json
```

with `ruleset.json` targeting `refs/heads/main` and enforcing:

- `deletion` and `non_fast_forward` — no force-push, no deleting main
- `pull_request` with `required_approving_review_count: 0` — pushes must go
  through a PR, but you can still merge it yourself
- `required_status_checks` on your CI check — **a red PR cannot be merged**

That gives the property you want: **Claude cannot push to `main`, and its PRs
can never merge without CI passing.** Add yourself as a bypass actor only if you
want an escape hatch; leaving it off means the rule applies to you too.

Note rulesets on **private** repos require a paid plan; on public repos they are
free. The plugin does not configure them by default.

---

## Repo layout

```text
.claude-plugin/marketplace.json
plugins/bo-standards/
├── .claude-plugin/plugin.json
├── hooks/hooks.json
├── scripts/    lib.sh, bootstrap.sh, format.sh, guard-bash.sh, session-start.sh,
│               install-plugins.sh, migrate-legacy.sh, enable-in-projects.sh
├── skills/     adopt-standards, ci-workflow, deploy-toolkit, fix-security, lint,
│               pr-check, scaffold-project, update-docs
└── templates/  pyproject-snippet.toml, biome.json, ci.yml, codeql.yml,
                dependabot.yml, CLAUDE.md, settings.json, CODEOWNERS,
                PULL_REQUEST_TEMPLATE.md, ISSUE_TEMPLATE/
```

## Developing the plugin

Installs resolve the marketplace from GitHub, so a change is invisible to other
repos until pushed. To iterate locally, install from the working tree:

```bash
claude plugin marketplace add /path/to/claude-toolkit --scope local
```

After editing, `claude plugin validate .` and restart the session.
