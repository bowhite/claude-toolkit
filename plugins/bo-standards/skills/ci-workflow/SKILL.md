---
name: ci-workflow
description: Generate or update .github/workflows/ci.yml so CI runs exactly the same checks as the local pr-check skill. Use when a repo has no CI, when CI has drifted from local checks, or after changing the check suite.
---

Write `.github/workflows/ci.yml` from `templates/ci.yml`, adjusted to what the
repo actually contains.

## The one rule

**CI must run the same commands, in the same order, as the `lint` and
`pr-check` skills.** That is the entire point of this file. If CI checks
something local does not, a PR goes red for a reason the author could not have
seen coming; if local checks something CI does not, the gate is theatre.

Before writing, read the `lint` and `pr-check` skills and diff their command
list against the template. If they disagree, fix the drift — do not paper over
it with an extra CI step.

## Shape it to the repo

- **`pyproject.toml` absent** → drop the `python` job entirely
- **`package.json` absent** → drop the `node` job entirely
- **No `tests/` and no test files** → drop the `Tests` step and say so in the
  report. A `pytest` step that exits 5 (no tests collected) is a red CI for no
  reason.
- **Python version**: the template relies on `uv sync` reading
  `requires-python` from `pyproject.toml`. Do not hardcode a version — one of
  these projects is on 3.14 and would silently be tested on the wrong runtime.
- **Matrix**: only add one if the project genuinely supports a range. A
  single-version matrix is noise.

## Check the action versions

Pin to current major versions and verify rather than trusting memory —
`astral-sh/setup-uv`, `actions/checkout`, and `actions/setup-node` all move.
If `gh` is authenticated, the fastest check is the repo's releases:

```bash
gh api repos/astral-sh/setup-uv/releases/latest --jq .tag_name
```

## The workflow scope caveat

Pushing a change under `.github/workflows/` over **SSH** works normally. Doing
it through the **GitHub API** (`gh api`, or an HTTPS push with a token) requires
the `workflow` OAuth scope, which Bo's `gh` token does not currently have.

If an API-based write fails with a scope error, that is the cause:

```bash
gh auth refresh -s workflow
```

## After writing

Report which jobs were included, which were dropped and why, and confirm the
command list matches `pr-check`. If a PR is open, watch the first run:

```bash
gh run watch
```
