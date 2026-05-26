---
name: service-info
description: Use when needing comprehensive details about a specific stack service — compose config, Dockerfile, startup script, health status, version vars, and port bindings.
user-invocable: true
---

Show comprehensive information about a specific stack service.

The service name is: $ARGUMENTS

If no service name provided, list all available services from COMPOSE_FILE and ask which one to inspect.

## Steps:
1. **Compose config**: find the service's `docker-compose.yaml` under `docker/images/<service>/` and show key settings (image, ports, volumes, depends_on, healthcheck, environment)
2. **Dockerfile**: read the service's `Dockerfile` under `docker/images/<service>/` — show FROM image, key ENV vars, installed tools
3. **Startup script**: find the service's startup script in `docker/config/dist/bin/` (the pattern is `<runtime>-bin/global-stack-<runtime>-start.sh` where runtime is the tool name, not the tier number)
4. **Health status**: check `tools/successes/` and `tools/errors/` for this service's health token
5. **Version vars**: grep `.env` for variables matching the service name (e.g., `GLOBAL_STACK_NODE*` for node services)
6. **Tier dependencies**: identify which tier this service belongs to and what it depends on (tier 03 needs tier 02, etc.)
7. **Port bindings**: show any `*_PORT_*` variables for this service

## Output:
- Structured summary with all the above information
- Highlight any issues (missing health token, failed health, missing tier dependency)
