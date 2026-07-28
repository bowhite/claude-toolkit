---
name: lint
description: Format, lint, and type-check the whole codebase (Python via ruff + ty, JS/TS/CSS/JSON via Biome); auto-fix, then hand-fix what remains. Use when asked to lint, format, type-check, or clean up a repo, or before opening a PR.
argument-hint: "[path]  — defaults to the whole repo"
---

Run the same tooling as the on-edit hook, but across the **entire target**, then
fix what the tools could not auto-fix.

**Target:** `$ARGUMENTS` if provided, otherwise the whole repository.

Only run the passes for languages that actually appear in the target — check
first with `git ls-files` so you never invoke a tool on zero files.

## Tool resolution

Tooling is a **per-project dev dependency**, not a global install.

- Python: `uv run <tool>`
- Node: **`./node_modules/.bin/<tool>`**, never bare `npx`

**Do not use `npx` as a fallback.** Verified: `npx --yes @biomejs/biome` silently
downloads an unpinned latest from the network, formats with it, and leaves
nothing in the project — so local and CI can format the same file differently.
That is precisely the drift per-project dev dependencies exist to prevent.

If a tool is missing, do not fall back to `uvx`, `npx`, or a global binary. Say
the project has not adopted the standards and offer the `adopt-standards` skill.

## Find the Node project first

`package.json` is often **not** at the repo root — two of three Node projects
here keep it in `frontend/`. Locate it before running anything:

```bash
find . -name package.json -not -path '*/node_modules/*' -maxdepth 3
```

Run every Node command from that directory so `biome.json` and `tsconfig.json`
are discovered. A repo can have more than one; handle each.

## 1. Python — format + lint

```bash
uv run ruff format <target>
uv run ruff check --fix <target>
uv run ruff check <target>
```

Ruff respects `.gitignore` and excludes `.venv` / `node_modules` by default, so
no extra scoping is needed even when the target is the whole repo.

## 2. Python — type check

```bash
uv run ty check <target>
```

`ty` is the type checker here. **Not mypy, not pyright** — the Bash guard hook
blocks both, because a second checker with different opinions makes the local
result stop predicting CI.

## 3. JS / TS / JSX / TSX / CSS / JSON — Biome

From the Node project directory:

```bash
./node_modules/.bin/biome check --write .
./node_modules/.bin/biome check .
```

The project's `biome.json` sets `vcs.useIgnoreFile`, so Biome honors
`.gitignore` and will not descend into `.venv` or vendored directories. If the
repo has no `biome.json`, pass the flags explicitly:
`--vcs-enabled=true --vcs-client-kind=git --vcs-use-ignore-file=true`.

## 4. TypeScript — type check

**Only when a `tsconfig.json` exists.** From the Node project directory:

```bash
./node_modules/.bin/tsc --noEmit
```

**Biome does not type-check — it has no type checking whatsoever.** Skipping
this leaves a TypeScript project linted and formatted but never actually
type-checked, which is the gap `ty` closes on the Python side. If the project
defines a `typecheck` script, run that instead so the flags stay in one place.

## 5. Secrets — gitleaks

```bash
gitleaks git . --no-banner
```

Scans **commit history**, not the working tree. Use `gitleaks git`, not
`gitleaks dir`: the directory mode reads gitignored files too and reports local
`.env` credentials that were never committed, which is noise. History is what
actually matters, because deleting a file does not remove its contents from git.

This is also the only secret scanning available on private repos — GitHub's own
is paywalled behind Advanced Security there.

## 6. Markdown — nothing

Markdown is **deliberately not linted or formatted**. Biome does not format it
(verified: `.md` passes through unchanged), and no other Markdown tool is used
here. Do not add one. Do not reach for prettier or markdownlint — the guard hook
blocks them.

## Then: fix what could not be auto-fixed

Read every remaining diagnostic and **edit the code to fix the underlying
issue**. Re-run the relevant checker on the affected files to confirm each is
resolved.

Do not blanket-suppress with `# noqa` / `biome-ignore` / `ty: ignore` unless a
fix is genuinely infeasible — and if you do suppress, say which and why.

One exception: if the repo has a `[tool.ruff.lint.per-file-ignores]` burn-down
block from `adopt-standards`, entries there are a known backlog, not new
failures. Prefer *removing* an entry by fixing its file over adding one.

## Finally: report

- what the tools **auto-fixed**
- what you **hand-fixed** (file + issue)
- anything **left unresolved**, and why
