Validate the Docker Compose configuration and environment consistency.

## Steps:
1. **Compose validation**: `docker compose --env-file .env.local config --quiet` — check for syntax errors
2. **Env sync check**: `bin/env-scan.sh --dry-run` — check for missing or divergent variables between .env and .env.local
3. **COMPOSE_FILE integrity**: Read `COMPOSE_FILE` from `.env.local`, verify:
   - No trailing semicolon
   - All referenced compose files exist on disk
   - `00base` compose file is included
4. **Tier dependency check**: For each active `03*` service, verify its corresponding `02*` tier manager is also in COMPOSE_FILE

## Output:
- Pass/fail for each check
- If any check fails, explain the issue and how to fix it
- If all pass, report "Stack configuration is valid"

$ARGUMENTS
