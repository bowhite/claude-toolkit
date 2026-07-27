---
name: pr-check
description: Verify a branch is ready to become a pull request — run the full check suite, review docstring accuracy, summarize the diff, and draft the PR description. Use before opening a PR or when asked whether a change is ready to merge.
---

The gate before a PR. There is no `Stop` hook running these checks, so nothing
runs them automatically — this skill is the deliberate verification step.

## Context

Current branch: !`git rev-parse --abbrev-ref HEAD`

Commits not on main: !`git log --oneline main..HEAD 2>/dev/null || echo "(no main to compare against)"`

Files changed: !`git diff --stat main...HEAD 2>/dev/null || git diff --stat HEAD`

Full diff: !`git diff main...HEAD 2>/dev/null || git diff HEAD`

## 1. Run the checks

Use the `lint` skill for the format / lint / type-check passes rather than
repeating its commands here — one definition, so the two can never drift.

Then run the tests:

```bash
uv run pytest
```

Run the Python half only if `pyproject.toml` exists, and the Node half only if
`package.json` exists.

**"No tests" is a skip, not a failure.** Most of these repos do not have a
`tests/` directory yet. Report the absence plainly and move on — do not
manufacture a passing result, and do not treat it as a blocker.

These are exactly the commands `.github/workflows/ci.yml` runs. If a check
passes here and fails in CI, that divergence is itself the bug — fix the drift
rather than the symptom.

## 2. Review docstring accuracy

Ruff's `D` rules prove a docstring **exists**. They cannot tell you it is
**true**.

Use the `pr-review-toolkit:comment-analyzer` agent on the changed files to
catch docstrings that describe behaviour the code no longer has. Scope it to
the diff, not the whole repo.

## 3. Summarize and draft

Write the PR description against `templates/PULL_REQUEST_TEMPLATE.md`:

- **What changed** — the shape of the change, not a restatement of the diff
- **Why** — the problem being solved
- **Verification** — which checks ran and what they said. Name anything that
  was skipped and why (no tests, no Node half). Do not claim a check passed
  that you did not run.
- **Notes for the reviewer** — deliberate omissions, known limits, decisions
  worth a second opinion

## 4. Hand off

Do **not** reimplement committing or PR creation. Use `/commit-push-pr`.

## Report honestly

If something fails, say so and show the output. A `pr-check` that reports
success on a red branch is worse than no check at all — it is the only gate
between a broken change and `main`, since branch protection is deliberately not
configured on these repos.
