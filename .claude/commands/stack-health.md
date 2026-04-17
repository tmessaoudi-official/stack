Check the health status of the running stack by inspecting health markers and container state.

## Steps:
1. **Success markers**: `ls tools/successes/ 2>/dev/null` — list healthy services
2. **Error markers**: `ls tools/errors/ 2>/dev/null` — list failed services
3. **Lock files**: `ls tools/locks/ 2>/dev/null` — list services with active locks
4. **Elapsed times**: `ls tools/elapsed/ 2>/dev/null` — list services with timing data
5. **Container status**: `docker compose --env-file .env.local ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}"` — show running containers
6. **Version markers**: `ls tools/versions/ 2>/dev/null` — list installed version markers

## Output:
- Summary table: service → status (healthy/failed/pending/not started)
- For failed services: show error token content if available
- For healthy services: show elapsed time if available
- Highlight any tier dependency issues (e.g., tier 03 healthy but its tier 02 failed)

$ARGUMENTS
