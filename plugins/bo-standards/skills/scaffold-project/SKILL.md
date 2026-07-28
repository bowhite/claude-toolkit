---
name: scaffold-project
description: Stand up a complete new project — uv package with src layout, ruff/ty config, tests, CI, CLAUDE.md, GitHub repo, and PR/issue templates. Use when starting a new project or repository from scratch.
---

Create a project that is correct from the first commit: no adoption backlog, no
retrofitting.

Ask for the project name and a one-line description first if not given. Confirm
whether a frontend is wanted before scaffolding one.

## 1. Local scaffold

```bash
git init -b main
uv init --package <name>
uv add --dev ruff ty pytest
```

Use `-b main` **explicitly**. `init.defaultBranch` is unset on this machine, so
git otherwise creates `master` — that is exactly how one existing repo ended up
on the wrong branch name.

Then append the tooling config from **`templates/pyproject-snippet.toml`** to
`pyproject.toml`. That file is the single source of truth — read it and copy the
blocks rather than typing the config from memory, so scaffold, adopt, and CI can
never disagree.

## 2. Files

| Path | Source |
|---|---|
| `.gitignore` | Python + Node + `.claude/settings.local.json` (never `.claude/` wholesale) |
| `CLAUDE.md` | `templates/CLAUDE.md`, with the project-specific slots filled in |
| `.claude/settings.json` | `templates/settings.json` — commit this |
| `scripts/bootstrap.sh` | copy from the plugin so the repo is self-setting-up |
| `.github/workflows/ci.yml` | via the `ci-workflow` skill |
| `.github/PULL_REQUEST_TEMPLATE.md` | `templates/PULL_REQUEST_TEMPLATE.md` |
| `.github/ISSUE_TEMPLATE/` | `templates/ISSUE_TEMPLATE/` |
| `.github/CODEOWNERS` | `templates/CODEOWNERS` — **comments only, no owner assigned**. Do not write `* @bowhite`: GitHub forbids approving your own PR, so on a solo repo that plus a required-review rule makes every PR permanently unmergeable. Assign an owner only when a second person really reviews. |
| `pyproject.toml` tooling blocks | `templates/pyproject-snippet.toml` — the single source of truth; do not retype the config |
| `tests/test_smoke.py` | one real test that imports the package and asserts something true |

Write a docstring on every function you generate. The `D` rules are on from
commit one — scaffolded code must not start the project in debt.

## 3. Optional frontend

Only if asked:

```bash
npm create vite@latest frontend -- --template react-ts
cd frontend && npm i -D @biomejs/biome typescript
```

Copy `templates/biome.json`. The `ci-workflow` skill adds the Node job.

**Include TypeScript and a `tsconfig.json`, and add a `typecheck` script:**

```json
{ "scripts": { "typecheck": "tsc --noEmit", "build": "tsc --noEmit && vite build" } }
```

Biome does **not** type-check — it has no type checking at all. Without `tsc`
a TypeScript frontend is linted and formatted but never actually type-checked,
which is the same gap `ty` closes on the Python side. `lint`, `pr-check`, and
CI all run `tsc --noEmit` whenever a `tsconfig.json` is present.

Putting the frontend in `frontend/` rather than the repo root is fine and
matches the existing projects — everything resolves the Node directory by
finding the nearest `package.json`.

## 4. GitHub

```bash
gh repo create <name> --private --source=. --push
gh repo edit --enable-auto-merge --delete-branch-on-merge
```

Repos are **private by default** — ask before creating a public one.

### Always attempt auto-merge, then verify

Try to enable it on every repo, and treat failure as informational rather than
an error:

```bash
gh repo edit --enable-auto-merge --delete-branch-on-merge 2>/dev/null || true
gh api repos/<owner>/<name> --jq '{private, allow_auto_merge, delete_branch_on_merge}'
```

**`allow_auto_merge` silently fails on private repos.** `gh repo edit` exits 0
and a direct `gh api -X PATCH ... allow_auto_merge=true` returns success, while
the value stays `false` — it is plan-gated, not a bug in the command. Verified:
it flipped to `true` the moment the same repo was made public.

So **always read the value back**, and report what is actually true:

- `true` → auto-merge is on
- `false` on a private repo → "auto-merge unavailable on private repos on this
  plan; enabled everything else"

Never report auto-merge as enabled on the strength of a zero exit code.
`delete_branch_on_merge` does apply on private repos.

### No branch protection by default

`main` accepts direct pushes and a red PR can still be merged. CODEOWNERS
auto-requests review without protection, but nothing enforces it, and auto-merge
rarely surfaces since GitHub only offers it on a PR blocked by a required check.

If the user wants `main` actually protected — particularly on a repo where
Claude is the only other contributor — see "Stopping Claude from pushing to
main" in the plugin README. The short version is a ruleset requiring a passing
CI check, which needs no second reviewer.

## 5. Verify before declaring done

Run, and report actual output:

```bash
uv run ruff format --check . && uv run ruff check . && uv run ty check && uv run pytest
```

Then confirm the repo state:

```bash
gh api repos/<owner>/<name> --jq '{private, default_branch, delete_branch_on_merge, allow_auto_merge}'
```

Check `default_branch` is `main`, not `master`. Finally, open a throwaway PR to
confirm CI actually runs and goes green — a workflow file that was never
triggered is not verified.
