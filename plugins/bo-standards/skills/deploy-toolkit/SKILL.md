---
name: deploy-toolkit
description: Roll bo-standards out across a machine — audit and retire legacy hooks and configs, then install and adopt across multiple existing projects one at a time. Use when setting up a new machine or onboarding several repos at once.
---

Deploy across a whole machine. **Machine-level work once, then one project at a
time** — never a bulk loop that edits many repos before anyone has looked at the
first result.

## 1. Machine-level, once

```bash
./plugins/bo-standards/scripts/bootstrap.sh --no-project
./plugins/bo-standards/scripts/install-plugins.sh
./plugins/bo-standards/scripts/migrate-legacy.sh
```

The migration runs in **audit mode by default and changes nothing.** Read its
report to the user before applying, because the choices are theirs:

- **hooks and commands** → `--apply`. Safe: superseded by the plugin.
- **global tool configs** → `--include-configs`. Think first.
  `~/.config/ruff/ruff.toml` with a `select = [...]` **replaces** ruff's
  defaults, so any not-yet-adopted project is linted by a *different* ruleset
  than an adopted one, silently. Retiring it makes un-adopted projects fall back
  to ruff's defaults — which is a change, so name the projects it affects.
- **unrecognised hooks** are reported and left alone. Ask before touching them.

On a machine **without sudo**, `bootstrap.sh` installs everything but `git` into
`~/.local/bin`. If `git` is missing, stop — nothing else will work.

## 2. Survey the projects

```bash
for d in ~/Developer/*/; do
  printf '%-24s git=%s py=%s node=%s tests=%s claude=%s\n' "$(basename "$d")" \
    "$([ -d "$d.git" ] && echo y || echo n)" \
    "$([ -f "$d/pyproject.toml" ] && echo y || echo n)" \
    "$(find "$d" -maxdepth 3 -name package.json -not -path '*/node_modules/*' -q 2>/dev/null | head -1 | grep -q . && echo y || echo n)" \
    "$([ -d "$d/tests" ] && echo y || echo n)" \
    "$([ -f "$d/.claude/settings.json" ] && echo y || echo n)"
done
```

Present the table and **let the user choose the order.** Expect most repos to
need foundations first — some are not git repos, some have no `pyproject.toml`,
most have no tests.

Start with the repo that is **clean and has a remote.** A dirty working tree is
a blocker, not a detail: `adopt-standards` runs `ruff --fix` across the tree and
will tangle its changes into uncommitted work. Say so and skip it.

## 3. Per project, in order

For each, on a branch — never straight onto `main`:

```bash
cd <project> && git switch -c adopt-bo-standards
claude plugin marketplace add bowhite/claude-toolkit --scope project
claude plugin install bo-standards@bo-toolkit --scope project
```

Then run **`adopt-standards`**, which is the step that installs `ruff`/`ty` and
writes the config. Then `ci-workflow`, then `pr-check`, then open a PR.

**Stop after the first project and show the result.** The finding count varies
enormously — one repo took 25, another measures 56 — and the burn-down policy
should be agreed on real numbers before it is applied eight more times.

## 4. Migrating a project off the old toolchain

`adopt-standards` handles the config, but name these explicitly in the report,
because they change behaviour:

| Was | Becomes | Watch for |
|---|---|---|
| ruff with a custom `select` | `extend-select = ["ANN","PYI","D"]` | A replacing `select` **loses** ruff 0.16's defaults. Union, don't overwrite — and say what changed. |
| pyright / mypy | `ty` | Delete `[tool.mypy]` and `pyrightconfig.json`. Expect different diagnostics — ty is 0.0.x and not a drop-in. |
| eslint + prettier | `biome` | Remove both from `devDependencies`. Biome does **not** type-check; add `tsc --noEmit` where a `tsconfig.json` exists. |
| markdownlint | *nothing* | Markdown is deliberately untooled. Delete the config; do not replace it. |

## Report

Per project: adopted / skipped-and-why / findings deferred to the burn-down.
Machine-level: what was retired, what was left alone, and anything still needing
a decision. Be explicit about repos you did **not** touch — a silent omission
reads as "done".
