---
name: env-diff
description: Use when comparing .env (master reference) with .env.local (active config) to find divergences, missing vars, or port mismatches.
user-invocable: true
---

Show differences between `.env` (master reference) and `.env.local` (active config).

## Steps:
1. Run `diff --color=always <(grep -v '^\s*#' .env | grep -v '^\s*$' | sort) <(grep -v '^\s*#' .env.local | grep -v '^\s*$' | sort)` to show value differences
2. Count: variables only in `.env`, only in `.env.local`, and with different values
3. For variables with different values, show both sides clearly
4. Flag any `COMPOSE_FILE` differences especially (high impact)
5. Flag any port variables where one side is empty and the other is set

## Output:
- Summary: X vars only in .env, Y vars only in .env.local, Z vars with different values
- Table of differences with columns: Variable | .env value | .env.local value
- Recommendation: if out of sync, suggest `bin/env-scan.sh --sync-values=true`
- If fully in sync: "Environment files are synchronized"

$ARGUMENTS
