Run the automated version checker in preview mode to find outdated dependencies.

**Phase 2 scope**: `env-update-v2.sh` covers `dockerhub` entries. All other types
(`github`, `npm`, `pecl`, `pypi`, `quay`, `rubygems`, `sdkman`, `url`) still require
the legacy `env-update.sh` until v2 Phase 3+ lands.

## Step 1 — v2 check (dockerhub)

Execute: `bin/env-update-v2.sh --check $ARGUMENTS`

Summarize the v2 output:
- `[AUTO]` entries ready to apply
- `[HOLD]` entries (pre-release vs stable)
- `[SKIP]` entries (up-to-date or non-dockerhub — v2 skips non-dockerhub types by design)
- `[ERROR]` entries — explain what went wrong

## Step 2 — legacy check (github, npm, pecl, pypi, quay, rubygems, sdkman, url)

Execute: `bin/env-update.sh --dry-run --progress --type=github,npm,pecl,pypi,quay,rubygems,sdkman,url $ARGUMENTS`

> Note: `env-update.sh` is deprecated for new workflows but remains the authoritative
> checker for non-dockerhub fetcher types until v2 Phase 3+ is complete.

Summarize the v1 output:
1. Group by decision type: [AUTO], [MANUAL], [HOLD], [SKIP], [UBUNTU]
2. For [MANUAL] entries: explain why human review is needed
3. For [HOLD] entries: explain the pre-release vs stable situation
4. Recommend which [AUTO] updates are safe to apply together
5. Flag any entries where a major version bump is involved

## Combined summary

After both steps, give a single consolidated recommendation:
- How many entries are auto-updatable (v2 + v1 combined)
- Which entries need manual review
- Suggested apply command when ready: `bin/env-update-v2.sh --apply` (dockerhub) then `bin/env-update.sh` (rest)

If `--filter` or `--type` arguments are provided, pass them to both commands.
Common filters:
- `--filter=NODE` — only Node-related versions
- `--type=github` — only GitHub-sourced (goes to v1 only)
- `--type=dockerhub` — only Docker Hub images (goes to v2 only)
