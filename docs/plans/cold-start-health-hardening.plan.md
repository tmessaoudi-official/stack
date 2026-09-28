# cold-start-health-hardening Plan

Found during the 2026-09-28 `make hard-restart` bring-up (empty volumes, busy host).
Implement AFTER the bring-up settles — nothing changes while the stack is still starting.

## Decisions Log
- [2026-09-28 12:16] AGREED: Postgres health check tests over TCP (`pg_isready -U root -h 127.0.0.1`) so it cannot pass against the init-time temp server (A).
- [2026-09-28 12:16] AGREED: Postgres gets `PGCTLTIMEOUT=300` so the init-time `pg_ctl -w stop` does not abort at the 60s default under build load (B).
- [2026-09-28 12:16] AGREED: SonarQube start script runs the upstream entrypoint as a signal-forwarded child; an unrequested exit writes `tools/errors/sonarqube` and exits 1 so `on-failure:5` retries (C).
- [2026-09-28 12:16] AGREED: the three fixes are done after the bring-up; the rbenv rehash-lock collision and the SDKMAN stall timeout are planned in the same pass, Postgres first.

## Evidence (2026-09-28 bring-up)
- `01postgres18` logs: temp server ready 08:35:46Z, `touch successes/01postgres18` 08:35:50Z (socket-only `pg_isready`), `received fast shutdown` 08:35:54Z, `pg_ctl: server does not shut down` 08:36:54Z, restart, fsync recovery, real `ready to accept connections` 08:39:45Z.
- Image `docker-entrypoint.sh:297` starts the temp server with `-c listen_addresses=''`; `:311` stops it with `pg_ctl -m fast -w stop`.
- `02sonarqube` started 08:36:51Z (depends_on already satisfied), `FATAL: the database system is not yet accepting connections`, `SonarQube is stopped` 08:39:16Z, exit 0, `restart: on-failure:5` → never retried; no error token written.
- `03ruby3`: ruby-3.4.11 built, then `rbenv: cannot rehash: /stack/tools/rbenv/shims/.rbenv-shim exists` (rbenv v1.3.2 `rbenv-rehash` noclobber lock, no wait) → `rbenv install` exit 1 at 09:04:37Z, 13s after `03ruby4` finished installing into the same `tools/rbenv`; self-healed on restart (`--skip-existing`).
- `03java17-zulu`: SDKMAN curl of spark 4.1.1 (573 MB, archive.apache.org) at ~48 KB/s while holding `tools/locks/sdkman.flock`; `sdkman_curl_connect_timeout=7` but no low-speed/stall limit.

## Formal Plan
1. **Postgres (A+B)** — `docker/images/01postgres18/docker-compose.yaml`: healthcheck `pg_isready -U root -h 127.0.0.1`; env `PGCTLTIMEOUT=300`. Test first: static guard in `bin/tests/` that the check names a TCP host and the env carries the timeout; runtime proof = fresh-volume bring-up under load, healthy only after the real server.
2. **SonarQube (C)** — `docker/config/dist/bin/sonarqube-bin/global-stack-start-sonarqube.sh`: child + `trap` forwarding TERM/INT, `wait`; on unrequested exit write `${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/sonarqube`, exit 1; clear a stale token at start; add the token to the compose healthcheck + `GLOBAL_STACK_ERROR_TOKEN`. Behavioural test against a stub entrypoint (exit 0 → token + rc 1; TERM → clean stop, no token).
3. **rbenv** — serialize `rbenv install` / rehash across 03ruby* (flock like sdkman, or retry the rehash). Design at implementation time.
4. **SDKMAN** — stall limit for the broker curl (low-speed abort) so a dead transfer cannot hold the shared lock forever. Design at implementation time.

## Status
<!-- progress-block v1 -->
| # | Step | Size | State | Evidence | Files |
|---|------|------|-------|----------|-------|
| 1 | Postgres TCP healthcheck + PGCTLTIMEOUT | S | todo | - | docker/images/01postgres18/** |
| 2 | SonarQube error token + retry | M | todo | - | docker/config/dist/bin/sonarqube-bin/**, docker/images/02sonarqube/** |
| 3 | rbenv install/rehash serialization | M | todo | - | docker/config/dist/bin/rbenv-bin/** |
| 4 | SDKMAN download stall limit | S | todo | - | docker/config/dist/bin/sdkman-bin/** |
<!-- /progress-block -->
### Blocked
### Needs input
### Needs research
- Step 4: where the stall limit can be set (sdkman config vs wrapper) without patching the downloaded installer.
### Fragile
### Known issues
