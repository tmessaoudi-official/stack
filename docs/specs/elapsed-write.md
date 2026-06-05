# Spec: All Containers Write to tools/elapsed
**Session**: 2026-06-04/05 | **Status**: ✅ Implemented 2026-06-05

---

## Context

`tools/elapsed` is a shared host-mounted file (`./tools/elapsed`) that records timing and
status for every container as it completes initialization. Format:

```
DD-MM-YYYY HH:MM:SS: <name> - N hours and N minutes and N seconds elapsed.
DD-MM-YYYY HH:MM:SS: Error - ** line: N ** ** command: X ** <script-name>
```

Written via `global-stack-base-print-success.sh` (success) and `stackCatch()` error trap (failure).
The file is append-only except for the very first write from 00base (which uses `>`).

### 00base lifecycle (confirmed by reading global-stack-base-start.sh):
1. Removes `successes/base` + `elapsed` (line 3 of base-start.sh)
2. Does its work (mkcert, go, zig, mise, etc.)
3. Calls `print-success.sh "${DURATION}" "base" "create"` → truncates/creates `elapsed`
4. Writes `> "${SUCCESSES}/base"` → marks itself healthy
5. `service_healthy` fires → dependent containers may now start

Key invariant: base ONLY clears `successes/base` and `elapsed`. It does NOT clear
`successes/<other-service>` files. Stale files from previous runs persist.

---

## Current State

### Group ✓ — Already write to tools/elapsed (31 containers, no action needed)

`00base`, `01caddy`, `01httpd`, `01nginx`, `01selenium-standalone-chrome`,
`01selenium-standalone-firefox`, `02fvm`, `02nvm`, `02phpbrew`, `02pyenv`, `02rbenv`,
`02rust`, `02sdkman`, `03java17-zulu`, `03java21-zulu`, `03java26-zulu`, `03node24`,
`03node26`, `03nodeedge`, `03php8-4`, `03php8-5`, `03phpedge`, `03python3`, `03ruby3`,
`03ruby4`, `04android`, `04phpmyadmin`, `03flutter3`, `04serverless-framework`,
`05edge`, `05stable`, `local.*`

### Group A — Need implementation (14 containers)

| Container | Type | Healthcheck cmd (in-container) | Base image shell |
|---|---|---|---|
| `01mysql9` | DB | `mysqladmin ping -h localhost -u $MYSQL_USER -p$MYSQL_PASSWORD` | bash ✓ |
| `01postgres18` | DB | `pg_isready -U root` | Alpine (**sh only**) |
| `01mariadb12` | DB | `mysqladmin ping -h localhost -u $MYSQL_USER -p$MYSQL_PASSWORD` | bash ✓ |
| `01mongo7` | DB | `mongosh --eval 'db.runCommand("ping")'` | bash ✓ |
| `01redis` | Cache | `redis-cli ping` | Alpine (**sh only**) |
| `01valkey` | Cache | `valkey-cli ping` | Alpine (**sh only**) |
| `01epiclabs-docker-oracle-xe-11g` | DB | sqlplus / custom | bash ✓ |
| `01localstack-localstack` | Infra | `curl -s localhost:4566/_localstack/health` | verify at impl |
| `02dpage-pgadmin4` | UI | HTTP check | Alpine (**sh only**) |
| `02keycloak-keycloak` | Auth | `curl -s localhost:8080/health/ready` | bash ✓ |
| `02mongoclient-mongoclient` | UI | HTTP check | verify at impl |
| `02sonarqube` | QA | `curl -s localhost:9000/api/system/status` | bash ✓ |
| `00corentinth-it-tools` | UI | HTTP check | no Dockerfile (verify at impl) |
| `01axllent-mailpit` | Mail | `curl localhost:8025/api/v1/info` | no Dockerfile (verify at impl) |

---

## Approach: Side-effecting healthcheck (Approach C)

**Why not entrypoint-override (Approach A)**: 7 of 14 are stateful databases. Overriding
entrypoint makes the wrapper PID 1, which must own SIGTERM/SIGINT forwarding. A wrong trap
→ `docker stop` → 10s grace → SIGKILL → unclean DB stop → data corruption.

**Why not sidecar (Approach B)**: No benefit over C for purely diagnostic writes, and adds
14 extra containers (`Exited(0)`) visible in `compose ps`.

**Approach C**: Mount `tools` + `bin` volumes, add env vars, wrap the existing `test:` command.
Zero changes to official container entrypoints, init scripts, PID 1, or lifecycle.

---

## Design Decisions

### Ordering — depends_on: 00base (mandatory for correctness)

All 14 Group A containers MUST have `depends_on: 00base: condition: service_healthy` (add if
not already present). Reason:
- base truncates `elapsed` using `>` (create mode) as part of reaching `service_healthy`
- If a Group A container appends BEFORE base's create write, the line is lost
- The `depends_on` gate guarantees base has already created `elapsed` before any Group A
  container starts

Currently missing `depends_on: 00base` (verified): `01redis`, `01mysql9`, `01postgres18`.
Others (mariadb, mongo, valkey, pgadmin4, keycloak, mongoclient, mailpit, it-tools) need
checking at implementation time — add if absent.

Note: `02keycloak` depends on `01postgres18: service_healthy`. Once postgres18 depends on
`00base`, keycloak gets the ordering transitively. No need to add 00base explicitly to keycloak.

### Freshness gate — re-write on each compose up

base only clears `successes/base` and `elapsed` on each run. `successes/redis` etc. from a
previous run PERSIST. A naive `if [ -f success_file ]` fast-path would skip writing on the
second run.

**Fix**: freshness check — a service success file is considered fresh only if it is NEWER
than the current `successes/base`. This is always true within a run (service writes after base
completes) and always false across runs (base creates a new `successes/base` each run, older
than any file from the previous run).

```sh
is_fresh() {
  [ -f "$SUCCESS_FILE" ] && [ -f "$BASE_FILE" ] && [ "$SUCCESS_FILE" -nt "$BASE_FILE" ]
}
```

Docker never runs the same container's healthcheck concurrently, so the
`[ ! fresh ] … touch` guard is race-free within a container.

### Timing — PID 1 start time from /proc/1/stat

Healthcheck runs AFTER the service is already healthy — there is no T=0 hook in healthcheck-only
mode. Container start time is recovered from PID 1's process stats:

```sh
# /proc/1/stat field 22 = starttime (clock ticks since host boot)
# Field 2 (comm) can contain spaces/parens — strip robustly:
HZ=$(getconf CLK_TCK 2>/dev/null || echo 100)
P1_TICKS=$(sed 's/.*) //' /proc/1/stat | awk '{print $20}')
# field 20 after stripping pid + comm = field 22 original
P1_START_BOOT=$(( P1_TICKS / HZ ))
HOST_UPTIME=$(awk '{print int($1)}' /proc/uptime)
DURATION=$(( HOST_UPTIME - P1_START_BOOT ))
```

With `init: ${DOCKER_INIT}`, PID 1 = tini, which starts when the container starts.
`/proc/uptime` is host uptime; both fields are from the same clock, so the subtraction
gives the container's age correctly. This is mechanism, not workaround — no T=0 hook exists.

### Shell compatibility

**POSIX sh** (`#!/bin/sh`) required — Alpine-based containers have no bash. This script
must NOT use bash-only syntax (`[[]]`, `(())`, `$SECONDS`, `shopt`, bash traps).

Note: `global-stack-base-print-success.sh` uses `#!/bin/bash` + `shopt` — it cannot be
reused here. The new script reimplements the elapsed write inline in POSIX sh with
identical output format.

### Output format (must match base's format exactly)

```
DD-MM-YYYY HH:MM:SS: <service-name> - N hours and N minutes and N seconds elapsed.
```

### env var: GLOBAL_STACK_WAIT_FOR_TIMEOUT

Use `${GLOBAL_STACK_WAIT_FOR_TIMEOUT}` — no `:-3600` fallback. The `.env` file owns this
value (`GLOBAL_STACK_WAIT_FOR_TIMEOUT=3600`). Inconsistent fallback values across containers
would be a maintenance hazard.

---

## New file to create

**`docker/config/dist/bin/base-bin/global-stack-base-healthcheck-elapsed.sh`**

```sh
#!/bin/sh
# Wraps a healthcheck command: writes elapsed to tools/elapsed on first success per run.
# Container start time is recovered from PID 1 start time in /proc/1/stat since there
# is no T=0 hook available in healthcheck-only mode.
# Freshness gate: re-writes on each compose up by comparing mtime vs successes/base.
set -e

SERVICE="$1"; shift
SUCCESS_FILE="${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/${SERVICE}"
BASE_FILE="${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"
ELAPSED_FILE="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"

# Fast path: already written this run (success file newer than current base)
if [ -f "$SUCCESS_FILE" ] && [ -f "$BASE_FILE" ] && [ "$SUCCESS_FILE" -nt "$BASE_FILE" ]; then
  exec "$@"
fi

# Run the real healthcheck
if "$@" >/dev/null 2>&1; then
  # Guard: check freshness again inside (handles rapid retry races)
  if ! { [ -f "$SUCCESS_FILE" ] && [ -f "$BASE_FILE" ] && [ "$SUCCESS_FILE" -nt "$BASE_FILE" ]; }; then
    # Recover container start time from PID 1 (tini/docker-init with init: true)
    # Field 22 of /proc/1/stat = starttime; strip pid+comm first (comm can contain spaces)
    HZ=$(getconf CLK_TCK 2>/dev/null || echo 100)
    P1_TICKS=$(sed 's/.*) //' /proc/1/stat | awk '{print $20}')
    P1_START_BOOT=$(( P1_TICKS / HZ ))
    HOST_UPTIME=$(awk '{print int($1)}' /proc/uptime)
    DURATION=$(( HOST_UPTIME - P1_START_BOOT ))
    HOURS=$(( DURATION / 3600 ))
    MINUTES=$(( (DURATION % 3600) / 60 ))
    SECS=$(( DURATION % 60 ))
    printf '%s: %s - %d hours and %d minutes and %d seconds elapsed.\n' \
      "$(date '+%d-%m-%Y %H:%M:%S')" "$SERVICE" "$HOURS" "$MINUTES" "$SECS" \
      >> "$ELAPSED_FILE"
    touch "$SUCCESS_FILE"
  fi
  exit 0
else
  exit 1
fi
```

---

## Changes per container

For each of the 14 Group A containers, changes are needed in ONE place:

### `docker/images/<name>/docker-compose.yaml`

**1. Add depends_on: 00base** (if not already present):
```yaml
depends_on:
  00base:
    condition: service_healthy
    required: true
```

**2. Add volume mounts** (append to existing volumes section):
```yaml
volumes:
  - ./tools:${GLOBAL_STACK_DOCKER_TOOLS_PATH}:rw
  - ./docker/config/dist/bin:${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/bin:rw
```

**3. Add environment variables** (append to existing environment section):
```yaml
environment:
  - GLOBAL_STACK_DOCKER_TOOLS_PATH=${GLOBAL_STACK_DOCKER_TOOLS_PATH}
  - GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES=${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}
  - GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS=${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}
  - GLOBAL_STACK_DOCKER_ROOT_DIST_PATH=${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}
  - GLOBAL_STACK_WAIT_FOR_TIMEOUT=${GLOBAL_STACK_WAIT_FOR_TIMEOUT}
```

**4. Wrap the healthcheck test** — replace existing `test:` with:
```yaml
healthcheck:
  test: ["CMD-SHELL", "${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/bin/base-bin/global-stack-base-healthcheck-elapsed.sh <service-name> <original-check-cmd>"]
  # Keep interval/timeout/retries/start_period unchanged
```

The `${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}` is expanded by docker-compose at parse time
(from `.env`), so the healthcheck runs the absolute path without relying on PATH.

### Containers without a Dockerfile (`00corentinth-it-tools`, `01axllent-mailpit`)
These use official images directly. The compose changes above are sufficient — no Dockerfile
needed. Verify the container's default shell (`sh`) is available for the healthcheck.

### Original healthcheck → wrapped form (column to fill at implementation)

| Container | Original test | Wrapped test |
|---|---|---|
| `01mysql9` | `mysqladmin ping -h localhost -u $MYSQL_USER -p$MYSQL_PASSWORD` | `global-stack-base-healthcheck-elapsed.sh 01mysql9 mysqladmin ping -h localhost -u $MYSQL_USER -p$MYSQL_PASSWORD` |
| `01postgres18` | `pg_isready -U root` | `global-stack-base-healthcheck-elapsed.sh 01postgres18 pg_isready -U root` |
| `01mariadb12` | `mysqladmin ping -h localhost -u $MYSQL_USER -p$MYSQL_PASSWORD` | `global-stack-base-healthcheck-elapsed.sh 01mariadb12 mysqladmin ping -h localhost -u $MYSQL_USER -p$MYSQL_PASSWORD` |
| `01mongo7` | `mongosh --eval 'db.runCommand("ping")'` | `global-stack-base-healthcheck-elapsed.sh 01mongo7 mongosh --eval 'db.runCommand("ping")'` |
| `01redis` | `redis-cli ping` | `global-stack-base-healthcheck-elapsed.sh 01redis redis-cli ping` |
| `01valkey` | `valkey-cli ping` | `global-stack-base-healthcheck-elapsed.sh 01valkey valkey-cli ping` |
| `01epiclabs-docker-oracle-xe-11g` | verify at impl | `global-stack-base-healthcheck-elapsed.sh 01epiclabs ...` |
| `01localstack-localstack` | `curl -s localhost:4566/_localstack/health` | `global-stack-base-healthcheck-elapsed.sh 01localstack curl -s localhost:4566/_localstack/health` |
| `02dpage-pgadmin4` | HTTP check | `global-stack-base-healthcheck-elapsed.sh 02pgadmin4 ...` |
| `02keycloak-keycloak` | `curl -s localhost:8080/health/ready` | `global-stack-base-healthcheck-elapsed.sh 02keycloak curl -s localhost:8080/health/ready` |
| `02mongoclient-mongoclient` | HTTP check | `global-stack-base-healthcheck-elapsed.sh 02mongoclient ...` |
| `02sonarqube` | `curl -s localhost:9000/api/system/status` | `global-stack-base-healthcheck-elapsed.sh 02sonarqube curl -s localhost:9000/api/system/status` |
| `00corentinth-it-tools` | HTTP check | `global-stack-base-healthcheck-elapsed.sh 00it-tools ...` |
| `01axllent-mailpit` | `curl localhost:8025/api/v1/info` | `global-stack-base-healthcheck-elapsed.sh 01mailpit curl localhost:8025/api/v1/info` |

**Service name tokens**: use the label value already defined in the compose labels (`stack.service`
field), which matches the format used by Group ✓ containers (e.g. `01redis`, not `redis`).

**Quoting note for mysql/mariadb**: `-p${MYSQL_PASSWORD}` has no space before the password —
pass it as a single argument. Verify quoting survives the `CMD-SHELL` → `sh -c` → `"$@"` chain.

---

## Notes / Things to add

<!-- Add your notes here -->
