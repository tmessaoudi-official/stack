# Deprecated

This template is historical. It predates the fragment architecture and references
services (e.g. mariadb11) that no longer exist in this stack.

Known issues requiring update before any use:
1. `depends_on: 01mariadb11` — that service no longer exists; use `01mariadb13`
2. `init: ${DOCKER_INIT}` — must be `${GLOBAL_STACK_DOCKER_INIT}` (GLOBAL_STACK_ prefix)
3. Healthcheck uses curl; replace with file-based token check (`tools/successes/`)
4. `GLOBAL_STACK_ERROR_TOKEN` env var is missing (required by stackCatch)
5. Startup script lacks the stackCatch error trap pattern

For scaffolding new services, use the `/new-service` skill instead.
