# <PROJECT NAME>

<One or two sentences: what this project is and who or what it serves.>

## Setup

```bash
./scripts/bootstrap.sh
```

Installs the out-of-band tooling (uv, node, jq, gh, git) if missing, then
`uv sync` and `npm ci`. Idempotent — safe to re-run.

## Running it

<Entry points and the commands to run them. Replace these examples.>

```bash
uv run <cli-name> --help
```

## Layout

<Only what is not obvious from a directory listing: where the real logic lives,
which directories are generated, anything surprising.>

---

# Conventions

These apply to every project and are enforced by the `bo-standards` plugin
(see `.claude/settings.json`). Do not restate them in other files.

## Python

Never use `pip` or `pip3` directly — always use `uv` for package management.

Never invoke `python` or `python3` directly either. Bare `python` points to
nothing, and `python3` is only the old macOS system Python (3.9), which is never
wanted. Python is installed **only** via uv — inside projects, or via `uvx` as
tooling. Pick the interpreter by context:

- **In a folder with uv config** (`pyproject.toml` / `uv.lock`): run
  `uv run python …`.
- **In a folder without uv config**: run `uvx python …` (ephemeral, uv-managed
  interpreter).

Common uv commands:

- Install packages: `uv add <package>` (dev deps: `uv add --dev <package>`)
- Sync environment: `uv sync`
- Create project / env: `uv init` / `uv venv`

## Linting, formatting, and types

- **Python**: `ruff` for both format and lint, `ty` for type checking. Both are
  per-project dev dependencies — run them as `uv run ruff` / `uv run ty`.
- **JS / TS / JSX / TSX / CSS / JSON**: `biome`, a project devDependency.
- **Markdown**: nothing. Markdown is deliberately not linted or formatted.
- Do **not** use prettier, eslint, markdownlint, mypy, or pyright. The Bash
  guard hook blocks them.

Edits are auto-formatted by the plugin's `PostToolUse` hook. For a whole-repo
pass, use the `lint` skill. Before opening a PR, use the `pr-check` skill.

## Data processing

Prefer **Polars** over pandas and NumPy whenever possible.

## Browser control

For any browser automation or web-page control, use the globally installed
**Playwright CLI** (`playwright open`, `playwright screenshot`,
`playwright codegen`, or a Playwright script) or **Claude's built-in browser**
(the `claude-in-chrome` tools).

Do **not** use or suggest the Playwright MCP server — it is intentionally not
installed. Do not install it.

## Claude API access

Never use the `anthropic` Python package or require `ANTHROPIC_API_KEY`. The
user is authenticated via a Claude Code subscription — call the `claude` CLI
instead.

Directly on the command line:

```bash
claude -p "your prompt here"
```

Or from Python via subprocess (run the script with `uv run python` or
`uvx python`, per the Python rules above):

```python
subprocess.run(["claude", "-p", prompt], capture_output=True, text=True)
```

## Git and GitHub

- Default branch is `main`.
- Work on a branch and open a PR; use the `/commit-push-pr` command.
- Force-pushing to `main` is blocked. Use `--force-with-lease` on your own
  branches.
- Lockfiles (`uv.lock`, `package-lock.json`) are generated — never hand-edit
  them. Change the manifest and re-run `uv lock` / `npm install`.
