# /new-service — Scaffold a New Docker Service

Creates the full boilerplate for a new /stack service. Arguments-first; falls back to interactive Q&A for anything missing.

**Usage**: `/new-service <name> [--parent <image>] [--runtime <name>] [--port <number>] [--health file|curl]`

```
/new-service 03node26 --parent 02nvm --runtime nvm --port 42760
/new-service 01myapp  --parent 00base --runtime myapp --health curl
/new-service          # no args → full interactive mode
```

---

## Phase 0: Gather inputs

Parse `$ARGUMENTS`:
- Positional arg → `NAME` (e.g. `03node26`)
- `--parent <image>` → `PARENT_IMAGE` (e.g. `02nvm`, `00base`)
- `--runtime <name>` → `RUNTIME` (startup script prefix, e.g. `nvm`, `nginx`)
- `--port <number>` → `HOST_PORT` (e.g. `42760`; omit for no host binding)
- `--health file|curl` → `HEALTH_TYPE` (default: `file` for tier 02/03, `curl` for tier 01)

For any missing value, ask interactively:
1. "Service name? (e.g. `03node26`)"
2. "Parent image to build FROM? (e.g. `02nvm`, `00base`)"
3. "Runtime name for startup script? Enter an **existing** name to reuse its script, a **new** name to scaffold one (e.g. `nvm`, `phpbrew`, `myapp`)"
4. "Host port? (number only, e.g. `42760` — leave blank for no host binding)"
5. "Healthcheck type? **[file]** file-based markers (tier 02/03) or **[curl]** HTTP endpoint (tier 01)"

If `NAME` is still unknown: exit with `Error: service name is required.`

---

## Phase 1: Derive variables

From the gathered inputs compute:
- `PARENT_SLUG` = `PARENT_IMAGE` with hyphens → underscores (e.g. `02nvm` → `02nvm`)
- `NAME_UPPER` = `NAME` uppercased with hyphens → underscores (e.g. `03node26` → `03NODE26`)
- `RUNTIME_UPPER` = `RUNTIME` uppercased (e.g. `nvm` → `NVM`)
- `TIER` = derived from `NAME` prefix: `00`=base, `01`=infra, `02`=manager, `03`=runtime, `04`=tool, `05`=combined
- `PORT_VAR` = `GLOBAL_STACK_${NAME_UPPER}_PORT_${HOST_PORT}` (only if `HOST_PORT` set)
- `ENV_PREFIX` = `GLOBAL_STACK_${NAME_UPPER}_`

Check for existing script:
```bash
ls docker/config/dist/bin/${RUNTIME}-bin/global-stack-${RUNTIME}-start.sh 2>/dev/null
```
Set `SCRIPT_EXISTS=true` if found.

Check for existing service dir:
```bash
ls docker/images/${NAME}/ 2>/dev/null
```
If directory exists: **abort** — "docker/images/${NAME}/ already exists. Delete it first or choose a different name."

Announce:
```
Scaffolding service: NAME (tier: TIER)
  Parent image : PARENT_IMAGE
  Runtime      : RUNTIME (SCRIPT_EXISTS)
  Host port    : HOST_PORT or "none"
  Healthcheck  : HEALTH_TYPE
```

---

## Phase 2: Create `docker/images/<NAME>/Dockerfile`

Write this file, substituting all `<PLACEHOLDER>` values:

```dockerfile
# shellcheck disable=SC2148
ARG GLOBAL_STACK_VERSION=2_0_0_local

# shellcheck disable=SC2086
ARG GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000=5000
# shellcheck disable=SC2086
ARG GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS=local-global-stack-registry.local
# shellcheck disable=SC2086
FROM ${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}/local_global_stack_<PARENT_SLUG>:${GLOBAL_STACK_VERSION}

LABEL maintainer="${GLOBAL_STACK_DOCKER_USER_ID}" \
      info="local_global_stack"

USER root

SHELL ["/bin/bash", "-xeEu", "-o", "pipefail", "-c"]

# TODO: Add ARG/ENV pairs for version variables:
#   ARG GLOBAL_STACK_<NAME_UPPER>_VERSION
#   ENV GLOBAL_STACK_<NAME_UPPER>_VERSION="${GLOBAL_STACK_<NAME_UPPER>_VERSION}"
#
# TODO: Add RUN layers for package installation (tier 01 / 00 only)
# TODO: Add COPY layers for config files: COPY conf/ /etc/<service>/
# TODO: Add EXPOSE for ports the service listens on (e.g. EXPOSE 8080 8443)

USER "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}"

CMD ["global-stack-base-sync-bin-n-exec.sh", "global-stack-<RUNTIME>-start.sh"]
```

---

## Phase 3: Create `docker/images/<NAME>/docker-compose.yaml`

### If `HEALTH_TYPE=file` (tier 02/03 default):

```yaml
services:
  <NAME>:
    init: true
    build:
      context: ../../../
      dockerfile: docker/images/<NAME>/Dockerfile
      args:
        BUILDKIT_INLINE_CACHE: 1
        GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS: ${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}
        GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000: ${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}
        GLOBAL_STACK_VERSION: ${GLOBAL_STACK_VERSION}
        # TODO: Mirror any ARG lines from Dockerfile here
        # GLOBAL_STACK_<NAME_UPPER>_VERSION: ${GLOBAL_STACK_<NAME_UPPER>_VERSION}
    cap_add:
      - NET_ADMIN
    depends_on:
      00base:
        condition: service_healthy
        required: true
      # TODO: Add parent tier-02 dependency if this is a tier-03 service:
      # <PARENT_IMAGE>:
      #   condition: service_healthy
      #   required: true
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      GLOBAL_STACK_DOCKER_TOOLS_PATH: ${GLOBAL_STACK_DOCKER_TOOLS_PATH}
      GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES: ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}
      GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS: ${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}
      GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS: ${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}
      GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS: ${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}
      GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC: ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}
      GLOBAL_STACK_DOCKER_USER_ID: ${GLOBAL_STACK_DOCKER_USER_ID}
      GLOBAL_STACK_DOCKER_GROUP_ID: ${GLOBAL_STACK_DOCKER_GROUP_ID}
      GLOBAL_STACK_USE_LOCKS: ${GLOBAL_STACK_USE_LOCKS}
      GLOBAL_STACK_ERROR_TOKEN: <NAME>_error
      # TODO: Add service-specific env vars (GLOBAL_STACK_<NAME_UPPER>_*)
      # TODO: Add MODE var if two-phase (install/setup):
      # <RUNTIME_UPPER>_MODE: ${GLOBAL_STACK_<NAME_UPPER>_MODE:-setup}
    healthcheck:
      test: >
        bash -c '
          [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/<NAME>_error" ]] &&
          [[ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/<NAME>_success" ]]
        '
      interval: 30s
      timeout: 10s
      start_period: 24h
      retries: 99999
    hostname: <NAME>
    labels:
      stack.service: "<NAME>"
      stack.tier: "TODO"  # replace: base | infra | manager | runtime | tool | combined
      stack.version: "${GLOBAL_STACK_VERSION}"
    networks:
      - public
    # TODO: Add port binding if needed:
    # ports:
    #   - "${<PORT_VAR>:-}<HOST_PORT>"
    restart: on-failure:5
    volumes:
      - ${GLOBAL_STACK_DOCKER_CA_PATH}:/usr/local/share/ca-certificates/mkcert:ro
      - ${GLOBAL_STACK_PROJECTS_PATH}:${GLOBAL_STACK_PROJECTS_PATH}
      - ${GLOBAL_STACK_DOCKER_TOOLS_PATH}:${GLOBAL_STACK_DOCKER_TOOLS_PATH}
      - ${GLOBAL_STACK_DOCKER_HISTORY_PATH}:/home/${GLOBAL_STACK_DOCKER_USER_ID}/.bash_history
      - ./docker/config/root:/root:ro
      - ./docker/config/dist/bin:/usr/local/bin:ro
      - ./docker/config/dist/conf:/etc/global-stack:ro
    working_dir: ${GLOBAL_STACK_PROJECTS_PATH}

networks:
  public:
    external: true
    name: ${COMPOSE_PROJECT_NAME}_${GLOBAL_STACK_VERSION}_public
```

If `HOST_PORT` was provided: uncomment the `ports:` block and fill `<PORT_VAR>` and `<HOST_PORT>`.

### If `HEALTH_TYPE=curl` (tier 01):

Use the same template above but replace the `healthcheck` block with:
```yaml
    healthcheck:
      test: ["CMD-SHELL", "curl -fs http://localhost:TODO_PORT/TODO_PATH || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
```
And remove the `GLOBAL_STACK_ERROR_TOKEN` env var (file-based tokens are tier 02/03 only).

---

## Phase 4: Scaffold startup script (only if `SCRIPT_EXISTS=false`)

Create `docker/config/dist/bin/<RUNTIME>-bin/global-stack-<RUNTIME>-start.sh`:

```bash
#!/usr/bin/env bash
# global-stack-<RUNTIME>-start.sh — startup for <NAME>
# Tier: <TIER> | Parent: <PARENT_IMAGE>
#
# Two-phase model (remove MODE block if single-phase):
#   <RUNTIME_UPPER>_MODE=install → install tool into shared tools/ volume (tier 02)
#   <RUNTIME_UPPER>_MODE=setup  → configure specific version for this container (tier 03)

set -eEuo pipefail

SUCCESS_MARKER="${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/<NAME>_success"
ERROR_MARKER="${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/<NAME>_error"
VERSION_MARKER="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/<RUNTIME>"

MODE="${<RUNTIME_UPPER>_MODE:-setup}"

trap 'echo "ERROR in <RUNTIME> startup (line $LINENO)" >&2; touch "$ERROR_MARKER"; exit 1' ERR

# Uncomment to wait for a dependency's success marker:
# source global-stack-base-wait-for.sh
# wait_for_success "<PARENT_IMAGE>_success"

rm -f "$ERROR_MARKER"

if [[ "$MODE" == "install" ]]; then
  # TODO: Check version marker to skip reinstall on re-run:
  # if [[ -f "$VERSION_MARKER" ]] && [[ "${GLOBAL_STACK_RELOAD_<RUNTIME_UPPER>:-false}" != "true" ]]; then
  #   echo "<RUNTIME> already installed, skipping"
  # else
  #   ... install steps ...
  #   echo "$VERSION" > "$VERSION_MARKER"
  # fi
  echo "TODO: implement install mode" >&2; exit 1

elif [[ "$MODE" == "setup" ]]; then
  # TODO: Configure the specific version/settings.
  # Write shellrc for host PATH propagation:
  # cat > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/<RUNTIME>.shellrc" << 'EOF'
  # export PATH="...":$PATH
  # EOF
  echo "TODO: implement setup mode" >&2; exit 1

else
  echo "Unknown <RUNTIME_UPPER>_MODE: $MODE" >&2; exit 1
fi

touch "$SUCCESS_MARKER"
echo "<NAME> startup complete (mode=$MODE)"
sleep infinity
```

---

## Phase 5: Print manual steps

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Files created:
  ✅ docker/images/<NAME>/Dockerfile
  ✅ docker/images/<NAME>/docker-compose.yaml
  [if new] ✅ docker/config/dist/bin/<RUNTIME>-bin/global-stack-<RUNTIME>-start.sh
           ⚠️  chmod +x docker/config/dist/bin/<RUNTIME>-bin/global-stack-<RUNTIME>-start.sh

Manual steps:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Add to .env (after other service blocks):

   # --- <NAME> ---
   # @todo env-update dockerhub:library/<NAME> latest
   GLOBAL_STACK_<NAME_UPPER>_VERSION=TODO
   [if HOST_PORT] <PORT_VAR>=          # empty = no host binding; set to "<HOST_PORT>:" to bind

2. Append to COMPOSE_FILE in .env:
   docker/images/<NAME>/docker-compose.yaml

3. Add to Makefile (before .PHONY):
   $(eval $(call login-service-shell,<NAME>))
   $(eval $(call log-service,<NAME>))
   $(eval $(call log-follow-service,<NAME>))
   $(eval $(call restart-service,<NAME>))

4. Add to .PHONY in Makefile:
   login-<NAME> log-<NAME> log-follow-<NAME> restart-<NAME>

5. Run to verify:
   bin/env-scan.sh --dry-run
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Phase 6: List open TODOs

```bash
grep -rn 'TODO' docker/images/<NAME>/ \
  docker/config/dist/bin/<RUNTIME>-bin/global-stack-<RUNTIME>-start.sh 2>/dev/null
```

List every TODO so the user knows exactly what needs filling before the service can build.
