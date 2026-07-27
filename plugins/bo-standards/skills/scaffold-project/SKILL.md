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

Then add to `pyproject.toml`:

```toml
[tool.ruff.lint]
extend-select = ["I", "UP", "B", "SIM", "ANN", "PYI", "D"]
preview = true

[tool.ruff.lint.pydocstyle]
convention = "google"

[tool.ty.rules]
missing-type-argument = "error"
possibly-unresolved-reference = "warn"

[tool.pytest.ini_options]
testpaths = ["tests"]
```

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
| `.github/CODEOWNERS` | `* @bowhite` |
| `tests/test_smoke.py` | one real test that imports the package and asserts something true |

Write a docstring on every function you generate. The `D` rules are on from
commit one — scaffolded code must not start the project in debt.

## 3. Optional frontend

Only if asked:

```bash
npm create vite@latest . -- --template react-ts
npm i -D @biomejs/biome
```

Copy `templates/biome.json`. The `ci-workflow` skill adds the Node job.

## 4. GitHub

```bash
gh repo create <name> --private --source=. --push
gh repo edit --enable-auto-merge --delete-branch-on-merge
```

Repos are **private by default** — ask before creating a public one.

### Two things that will not work as expected

- **`--enable-auto-merge` silently fails on private repos.** The command exits
  0, a direct `gh api -X PATCH ... allow_auto_merge=true` returns success, and
  the value stays `false`. It is plan-gated. Verify rather than assume:

  ```bash
  gh api repos/<owner>/<name> --jq '{private, allow_auto_merge, delete_branch_on_merge}'
  ```

  If it did not take, say so — do not report auto-merge as enabled.

- **No branch protection or rulesets are configured.** This is deliberate. So
  `main` accepts direct pushes and a red PR can still be merged. CODEOWNERS
  still auto-requests review (that needs no protection) but nothing enforces it.
  Auto-merge also rarely surfaces, since GitHub only offers it on a PR blocked
  by a required check.

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
