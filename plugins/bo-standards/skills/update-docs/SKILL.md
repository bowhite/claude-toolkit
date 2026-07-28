---
name: update-docs
description: Bring README, CLAUDE.md, and docstrings back in line with what the code actually does. Use when documentation has drifted, after a change that alters behaviour or setup steps, or when asked to update, audit, or write project documentation.
---

Documentation rots silently — nothing fails when a README describes a flag that
no longer exists. This is the deliberate pass that catches it.

## Context

Changed since main: !`git diff --stat main...HEAD 2>/dev/null || git diff --stat HEAD`

Docs in the repo: !`git ls-files '*.md' 2>/dev/null | head -30`

## Scope it first

Default to **the diff**, not the whole repo. A full-repo docs pass on a mature
project produces a wall of low-value edits. Widen only when asked.

Ask which of these applies before editing:

- a behaviour change that makes existing docs *wrong*
- a new capability with no documentation at all
- setup or install steps that no longer work
- a general audit

## What to check, in priority order

**1. Things that are actively wrong.** Highest value by a wide margin. A command
that errors, a flag that was renamed, a path that moved, a prerequisite that is
no longer needed. Every code block in a README is a claim — verify the ones the
diff touched by actually running them.

**2. Things that are missing.** New entry points, new env vars, new required
setup. Check `--help` output and any `[project.scripts]` against what the README
lists.

**3. `CLAUDE.md`.** Keep it to repo-specific facts: what the project is, entry
points, how to run it, non-obvious layout. **Conventions belong in the plugin,
not here** — if you find uv/ruff/ty/Biome rules restated in a repo's CLAUDE.md,
delete them rather than updating them. For a deeper audit use the
`claude-md-management` plugin.

**4. Docstrings.** Ruff's `D` rules prove a docstring *exists*; they cannot tell
you it is *true*. For changed functions, use the
`pr-review-toolkit:comment-analyzer` agent to find docstrings that describe
behaviour the code no longer has.

## Rules

- **Markdown is not linted or formatted here.** Biome does not touch `.md` and
  no other Markdown tool is used. Match the file's existing style by hand.
- **Do not pad.** Adding a paragraph that restates the function name is worse
  than silence — it dilutes the parts that carry information.
- **Do not document what the code says plainly.** Document *why*, constraints,
  and anything surprising.
- **Verify before you write.** If you cannot run the command, say the doc is
  unverified rather than asserting it works.

## Report

- what was **wrong** and is now corrected (the part that matters)
- what was **missing** and is now added
- anything left alone deliberately, and why
