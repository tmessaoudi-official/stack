---
name: check-versions
description: Use when checking for outdated dependencies, Docker images, or language runtime versions tracked in .env with @todo env-update annotations.
user-invocable: true
---

Run the automated version checker in preview mode to find outdated dependencies.

`env-update.sh` covers all fetcher types (dockerhub, github, ghcr, npm, pecl,
pypi, quay, rubygems, sdkman, sdkmanager, url, codeberg). No legacy fallback needed.

## Step 1 — v2 check (all types)

Execute: `bin/env-update.sh --check $ARGUMENTS`

Summarize the v2 output:
- `[AUTO]` entries ready to apply
- `[HOLD]` entries (pre-release vs stable, or major-version gate)
- `[SKIP]` entries (up-to-date)
- `[ERROR]` entries — explain what went wrong

Group results by decision type. For `[HOLD]` entries explain the pre-release vs stable
situation. Flag any entries where a major version bump is involved.

## Summary

Give a single consolidated recommendation:
- How many entries are auto-updatable
- Which entries need manual review
- Suggested apply command when ready: `bin/env-update.sh --apply`

If `--filter` arguments are provided, pass them through.
Common filters:
- `--filter=NODE` — only Node-related versions
- `--filter=type:github` — only GitHub-sourced versions
- `--filter=type:dockerhub` — only Docker Hub images
