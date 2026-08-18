---
name: debug-service
spotlight: true
description: Use when a stack service fails to start or becomes unhealthy — executes the 6-step "Debugging a Failed Container" runbook read-only and reports a root-cause hypothesis with suggested next actions.
user-invocable: true
---

Run the 6-step "Debugging a Failed Container" runbook from CLAUDE.md for one service — **strictly read-only**.

The service name is: $ARGUMENTS

If no service name provided, list failed services from `ls tools/errors/ 2>/dev/null` and ask which one to debug.

**This skill never restarts, never deletes, never writes.** It only reads files and inspects container state, then *suggests* fixes for the user to run manually.

## Steps:
1. **Error token**: read `docker/images/<service>/docker-compose.yaml` and extract its `GLOBAL_STACK_ERROR_TOKEN` value (the token is the runtime name, e.g. `nvm`, not the tier-prefixed service name). Then check `ls tools/errors/ 2>/dev/null` for that token and `cat tools/errors/<TOKEN>` if it exists
2. **Container status + logs**: `docker compose --env-file .env.local ps <service>` then `docker compose --env-file .env.local logs --tail=50 <service>` — show the last 50 log lines
3. **Startup script**: locate the service's startup script under `docker/config/dist/bin/<runtime>-bin/global-stack-<runtime>-start.sh` (the directory uses the runtime name, not the tier number — e.g. `nvm-bin/`, not `02nvm-bin/`) and name it
4. **Tier-02 dependency health**: if the service is tier 03+, identify its tier-02 manager (e.g. `02nvm` for `03node*`, `02phpbrew` for `03php*`, `02sdkman` for `03java*`) and check `ls tools/successes/ 2>/dev/null` for the manager's success token
5. **Version markers**: `ls tools/versions/ 2>/dev/null` — check whether the runtime's install marker exists (a missing marker means the next start triggers a full reinstall)
6. **Root-cause hypothesis**: correlate the findings (error token content, log tail, dependency health, marker state) into a single hypothesis and suggest next actions **without executing any of them**:
   - `make login-<service>` — shell in for interactive inspection
   - `GLOBAL_STACK_RELOAD_<RUNTIME>=true` in `.env.local` + restart — force full reinstall (slow; reset to `false` after)
   - delete `tools/versions/<marker>` — force reinstall of that runtime only
   - `make restart-<service>` — simple restart if the failure looks transient

## Output:
- Per-step findings (token present/absent + content, container state, log highlights, startup script path, tier-02 health, marker state)
- One root-cause hypothesis with the evidence that supports it
- Suggested next actions, clearly marked as **not executed** — the user runs them manually
