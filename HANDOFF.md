# Handoff: build `claude-toolkit`

Seed document for a Claude Code session. Save at
`/Users/bo/Developer/claude-toolkit/HANDOFF.md`, then from that directory run
`claude` and say: **"Read HANDOFF.md and build out Phase 1."**

---

## Context

I have multiple GitHub projects under `/Users/bo/Developer/`. They share
conventions, so I want the conventions packaged once as a Claude Code plugin and
installed into every project — not copy-pasted per repo.

**Stack, common to most projects:**

- Markdown files in every project
- Python in most: `uv` / `uvx` for packages and tools
- Lint/format: `ruff`, with autofixing on
- Types: `mypy`, strict mode required
- Frontend/tools in most: `node`, `npm`, `npx`, React (JS / TS / JSX)
- Every project has tests
- Every project should have at least one GitHub Actions workflow for PR CI

---

## Target structure

```
/Users/bo/Developer/claude-toolkit/
├── .claude-plugin/
│   └── marketplace.json
└── plugins/
    └── bo-standards/
        ├── .claude-plugin/
        │   └── plugin.json
        ├── skills/
        │   ├── pr-check/SKILL.md
        │   ├── scaffold-project/SKILL.md
        │   └── ci-workflow/SKILL.md
        ├── hooks/
        │   └── hooks.json
        ├── scripts/
        │   ├── format.sh
        │   ├── guard-bash.sh
        │   └── verify.sh
        └── README.md
```

---

## Phase 1 — scaffold + format hook

1. `git init` the repo; add a Python-ish + Node `.gitignore`.
2. Create `.claude-plugin/marketplace.json` and
   `plugins/bo-standards/.claude-plugin/plugin.json`. Ask me for the
   marketplace name and my GitHub handle before writing the owner fields.
3. Write `scripts/format.sh`:
   - Reads hook JSON from stdin; extract the edited file path with `jq`.
   - `.py`  → `uv run ruff format <file>` then `uv run ruff check --fix <file>`
   - `.ts` `.tsx` `.js` `.jsx` → `npx prettier --write <file>`, then
     `npx eslint --fix <file>` if an eslint config exists
   - `.md` → `npx prettier --write <file>`
   - Unknown extension → exit 0 silently.
   - Must be fast; it runs on every edit. Skip gracefully if a tool is missing
     rather than erroring.
   - `chmod +x` it.
4. Write `hooks/hooks.json` wiring `PostToolUse` with matcher
   `Edit|Write|MultiEdit` to `scripts/format.sh`.
5. Register and install locally, then verify by editing a `.py` file in a
   scratch dir and confirming the hook fires.

## Phase 2 — guards and the slow gate

6. `scripts/guard-bash.sh` on `PreToolUse` with matcher `Bash`. Block, via
   **exit code 2** with the reason on stderr:
   - `rm -rf` targeting anything outside the project directory
   - `git push --force` / `-f` to `main` or `master`
   - direct edits to lockfiles (`uv.lock`, `package-lock.json`)
   - `pip install` (I use `uv`)
   Exit 0 otherwise. Exit 2 is required — exit 1 only warns and enforces nothing.
7. `scripts/verify.sh` on the `Stop` event: `uv run ruff check .`,
   `uv run mypy --strict .`, then the test suite. Only run the Python half if
   `pyproject.toml` exists and the Node half if `package.json` exists. This is
   the slow gate, deliberately kept off the per-edit path.
8. `SessionStart` hook printing `git status --short` and `git log --oneline -10`.

## Phase 3 — skills

9. `skills/pr-check/SKILL.md` — run ruff, mypy strict, and tests; summarize the
   diff; draft a PR description. Use the `` !`command` `` syntax to inline
   `git diff` output so the skill sees the real diff.
10. `skills/ci-workflow/SKILL.md` — generate/update `.github/workflows/ci.yml`
    for PRs: matrix as appropriate, `astral-sh/setup-uv`, `uv sync`,
    `ruff check`, `mypy --strict`, tests; plus a Node job when `package.json`
    exists. Must mirror what `verify.sh` runs locally — local and CI should
    never disagree.
11. `skills/scaffold-project/SKILL.md` — stand up a new repo my way: `uv init`,
    ruff + mypy-strict config in `pyproject.toml`, optional React frontend,
    tests dir, CI workflow, and a starter `CLAUDE.md`.

## Phase 4 — roll out

12. Write a short `README.md`: install steps and what each hook/skill does.
13. Pick one existing project under `/Users/bo/Developer/`, install the plugin,
    and run a real change through it. Report anything that was slow, noisy, or
    fired when it shouldn't have.
14. Then write a thin per-project `CLAUDE.md` template — repo-specific facts
    only (what this project is, its entry points, how to run it). Conventions
    stay in the plugin; do not duplicate them per repo.

---

## Working agreements

- Ask before assuming a tool is installed; check first.
- Prefer editing the plugin over adding per-project config. If something feels
  project-specific, say so and I'll decide.
- Keep hook scripts POSIX-ish and dependency-light (`jq` is fine).
- After each phase, stop and let me test before moving on.
