---
name: validate
spotlight: true
description: Use when verifying Docker Compose configuration, checking environment file sync, or before starting the stack after changes to .env, .env.local, or compose files.
user-invocable: true
---

Validate the Docker Compose configuration and environment consistency.

## Steps:
1. **COMPOSE_FILE integrity** *(pre-flight — run before docker compose to surface clear errors first)*: Read `COMPOSE_FILE` from `.env.local`, verify:
   - No trailing semicolon — run: `grep -qE 'COMPOSE_FILE=.*;[[:space:]]*$' .env.local && echo "[ERROR] COMPOSE_FILE has trailing semicolon — will break Docker Compose silently" || echo "[OK] No trailing semicolon"` (a trailing `;` silently adds an empty path entry; Docker Compose accepts the config but fails at runtime)
   - All referenced compose files exist on disk
   - `00base` compose file is included
   - If any check fails, report the error and stop — do not proceed to step 2
2. **Compose validation**: `docker compose --env-file .env.local config --quiet` — check for syntax errors
3. **Env sync check**: `bin/env-scan.sh --dry-run` — check for missing or divergent variables between .env and .env.local
4. **Tier dependency check**: For each active `03*` service, verify its corresponding `02*` tier manager is also in COMPOSE_FILE
5. **Port-var colon check**: For every non-empty `GLOBAL_STACK_*_PORT_*` variable in `.env.local`, verify the value ends with `:` — run: `grep -E '^GLOBAL_STACK_[A-Z0-9_]+_PORT_[A-Z0-9_]+=.+' .env.local | grep -v ':$' | grep -v '^#'` — any match is a misconfigured port var that will silently concatenate host and container port numbers (e.g. `427083306` instead of `42708:3306`)
6. **Local compose override detection**: Check for git-ignored machine-specific overrides — run: `find . -maxdepth 3 -name 'docker-compose*.local.yaml' 2>/dev/null` — list any found files so the user is aware they may silently override tracked compose configs

## Output:
- Pass/fail for each check
- If any check fails, explain the issue and how to fix it
- If all pass, report "Stack configuration is valid"

$ARGUMENTS
