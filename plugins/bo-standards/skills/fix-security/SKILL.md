---
name: fix-security
description: Triage and fix security findings on a GitHub repo — Dependabot alerts, leaked credentials in git history, dependency CVEs, and code scanning alerts. Use when security alerts arrive, a scan fails CI, or when auditing a repo's security posture.
---

Triage and remediate security findings. Fix what is real; explain what is not.

## Context

Repo: !`gh repo view --json nameWithOwner,isPrivate --jq '"\(.nameWithOwner) private=\(.isPrivate)"' 2>/dev/null || echo "(no gh remote)"`

Open Dependabot alerts: !`gh api repos/{owner}/{repo}/dependabot/alerts --jq '[.[] | select(.state=="open")] | length' 2>/dev/null || echo "unavailable"`

## What is even available depends on visibility

Verified by API, not assumed:

| Source | Public repo | Private repo (free) |
|---|---|---|
| Dependabot alerts | ✅ | ✅ |
| Secret scanning | ✅ | ❌ `422 not available` |
| CodeQL code scanning | ✅ | ❌ needs Advanced Security |
| Dependency review action | ✅ | ❌ needs Advanced Security |
| **gitleaks / osv-scanner** | ✅ | ✅ **works anywhere** |

On a private repo most GitHub-native scanning is paywalled, so `gitleaks` and
`osv-scanner` are not a nice-to-have — they are the only coverage there is.

## 1. Dependency alerts

```bash
gh api repos/{owner}/{repo}/dependabot/alerts --jq \
  '.[] | select(.state=="open") | "\(.security_advisory.severity)\t\(.dependency.package.name)\t\(.security_advisory.summary)"'
```

Fix by bumping the manifest and regenerating the lockfile — `uv add pkg@>=X` or
`npm i pkg@latest`. **Never hand-edit `uv.lock` or `package-lock.json`**; the
Bash guard blocks it.

Then confirm the advisory is actually resolved rather than assuming the bump
covered it:

```bash
osv-scanner --lockfile=uv.lock --lockfile=package-lock.json .
```

**Triage honestly.** A CVE in a dev-only dependency, or in a code path the
project never calls, is worth recording as accepted rather than churning the
lockfile. Say which you did and why.

## 2. Leaked credentials

```bash
gitleaks git . --no-banner --report-format json --report-path /tmp/leaks.json
jq -r '.[] | "\(.RuleID)\t\(.File)\t\(.Commit[0:8])"' /tmp/leaks.json
```

Use `gitleaks git` (history), not `gitleaks dir` (working tree) — the latter
reads gitignored `.env` files and reports local credentials that were never
committed.

**Never print secret values.** Report rule, file, and commit only.

Expect false positives: documentation placeholders like `your-anon-key` or
`YOUR_PROJECT_ID` match the same patterns. Check length and shape before
treating anything as real.

When a real credential is found, in this order:

1. **Rotate it.** This is the only step that actually fixes anything, and it is
   the user's to do — never touch credentials yourself.
2. **Stop the bleeding**: confirm the file is gitignored now.
3. **Purge history**, only if asked. `git filter-repo --replace-text`, then
   force-push every branch. Take a `git clone --mirror` backup first.

**Say this plainly when history is rewritten:** GitHub keeps unreferenced
objects reachable by SHA until it garbage-collects, so the old commit — and the
secret in it — is still fetchable from a rewritten repo. Only rotation closes
that. Purging history reduces exposure; it does not end it.

## 3. Code scanning

```bash
gh api repos/{owner}/{repo}/code-scanning/alerts --jq \
  '.[] | select(.state=="open") | "\(.rule.security_severity_level)\t\(.rule.id)\t\(.most_recent_instance.location.path)"' 2>/dev/null
```

Public repos only unless the org has Advanced Security. If this 404s on a
private repo, that is why — say so instead of reporting zero alerts, which reads
as "clean".

For each: fix the code, or dismiss with an explicit reason. Do not leave alerts
open and unexplained.

## 4. Enable what is free

```bash
gh api -X PUT repos/{owner}/{repo}/vulnerability-alerts
gh api -X PATCH repos/{owner}/{repo} \
  -f 'security_and_analysis[secret_scanning][status]=enabled' \
  -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'
```

The second fails with 422 on a private repo. That is expected — report it and
move on; `gitleaks` in CI covers it.

## Report

- **fixed**: what changed, and how it was verified
- **needs the user**: credentials to rotate — always theirs to do
- **accepted**: findings judged not worth acting on, with the reason
- **unavailable**: scanning that could not run because of repo visibility, so a
  clean result is never mistaken for full coverage
