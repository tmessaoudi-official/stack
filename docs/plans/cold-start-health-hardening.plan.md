# cold-start-health-hardening Plan

Found during the 2026-09-28 `make hard-restart` bring-up (empty volumes, busy host).
Implement AFTER the bring-up settles — nothing changes while the stack is still starting.

## Decisions Log
- [2026-09-28 12:16] AGREED: Postgres health check tests over TCP (`pg_isready -U root -h 127.0.0.1`) so it cannot pass against the init-time temp server (A).
- [2026-09-28 12:16] AGREED: Postgres gets `PGCTLTIMEOUT=300` so the init-time `pg_ctl -w stop` does not abort at the 60s default under build load (B).
- [2026-09-28 12:16] AGREED: SonarQube start script runs the upstream entrypoint as a signal-forwarded child; an unrequested exit writes `tools/errors/sonarqube` and exits 1 so `on-failure:5` retries (C).
- [2026-09-28 12:16] AGREED: the three fixes are done after the bring-up; the rbenv rehash-lock collision and the SDKMAN stall timeout are planned in the same pass, Postgres first.
- [2026-09-28 12:27] ASSUMED (review): fix A ships WITH a patient Postgres healthcheck window (`start_period: 24h`, the stack norm) — because the current `start_period: 30s` + `retries: 5` × `interval: 10s` ≈ 80s would mark Postgres UNHEALTHY once the check stops passing against the init temp server (real TCP readiness took ~4 min today), and compose then aborts every `service_healthy` dependent (keycloak, pgadmin, sonarqube). Alternatives: raise only `retries`; leave the window and accept dependents failing on a fresh volume.
- [2026-09-28 15:20] ASSUMED (review): SonarQube's error token is errors/02sonarqube, not errors/sonarqube as decision C says — because the token invariant (CLAUDE.md) requires the error token to match the success marker, and the elapsed wrapper writes successes/02sonarqube. Alternative: rename the wrapper's service argument to sonarqube (moves the success marker and its elapsed line).
- [2026-09-28 15:50] AGREED: rbenv takes its flock UNCONDITIONALLY like sdkman (not gated on GLOBAL_STACK_USE_LOCKS), covering the ruby install and gem installs, because rbenv refuses concurrent rehashes on the shared tools/rbenv; accepted cost: cold-start ruby compiles run one after another (developer answer 2026-09-28).

## Evidence (2026-09-28 bring-up)
- `01postgres18` logs: temp server ready 08:35:46Z, `touch successes/01postgres18` 08:35:50Z (socket-only `pg_isready`), `received fast shutdown` 08:35:54Z, `pg_ctl: server does not shut down` 08:36:54Z, restart, fsync recovery, real `ready to accept connections` 08:39:45Z.
- Image `docker-entrypoint.sh:297` starts the temp server with `-c listen_addresses=''`; `:311` stops it with `pg_ctl -m fast -w stop`.
- `02sonarqube` started 08:36:51Z (depends_on already satisfied), `FATAL: the database system is not yet accepting connections`, `SonarQube is stopped` 08:39:16Z, exit 0, `restart: on-failure:5` → never retried; no error token written.
- `03ruby3`: ruby-3.4.11 built, then `rbenv: cannot rehash: /stack/tools/rbenv/shims/.rbenv-shim exists` (rbenv v1.3.2 `rbenv-rehash` noclobber lock, no wait) → `rbenv install` exit 1 at 09:04:37Z, 13s after `03ruby4` finished installing into the same `tools/rbenv`; self-healed on restart (`--skip-existing`).
- `03java17-zulu`: SDKMAN curl of spark 4.1.1 (573 MB, archive.apache.org) at ~48 KB/s while holding `tools/locks/sdkman.flock`; `sdkman_curl_connect_timeout=7` but no low-speed/stall limit.

## Formal Plan
1. **Postgres (A+B)** — `docker/images/01postgres18/docker-compose.yaml`: healthcheck `pg_isready -U root -h 127.0.0.1`; `start_period: 24h` (+ patient `retries`) so the longer not-ready window cannot flip it UNHEALTHY; env `PGCTLTIMEOUT=300`. Test first: static guard in `bin/tests/` that the check names a TCP host, the window is patient, and the env carries the timeout. B is [Inferred: pg_ctl docs give a 60s default overridable by `PGCTLTIMEOUT`; entrypoint `:311` uses `-w`; env pass-through across the entrypoint's user switch unverified]. Runtime proof for BOTH A and B = a fresh-volume bring-up under load: healthy only after the real server, no `pg_ctl: server does not shut down`, keycloak/pgadmin/sonarqube start. Note 01mysql9/01mariadb13/01mongo7 share the 80s window (mysql took 4m17s today) — review them in the same pass.
2. **SonarQube (C)** — `docker/config/dist/bin/sonarqube-bin/global-stack-start-sonarqube.sh`: child + `trap` forwarding TERM/INT, `wait`; on unrequested exit write `${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/02sonarqube` (token invariant — see the ASSUMED entry), exit 1; clear a stale token at start; add the token to the compose healthcheck + `GLOBAL_STACK_ERROR_TOKEN`. Behavioural test against a stub entrypoint (exit 0 → token + rc 1; TERM → clean stop, no token).
3. **rbenv** — root cause [Verified, rbenv v1.3.2 source]: `rbenv-rehash` takes a noclobber lock and exits 1 instead of waiting; `rbenv-install` always rehashes; the gem hook rehashes through backticks (silent). Locks were off (`GLOBAL_STACK_USE_LOCKS=false`). Fix (AGREED 15:50): the rbenv flock is unconditional, like sdkman's; release stays before `sleep infinity`; the locked region has no wait-for.
4. **SDKMAN** — stall limit for the broker curl (low-speed abort) so a dead transfer cannot hold the shared lock forever. Design at implementation time.
5. **SDKMAN tolerant install / strict activation** — 2026-09-28 13:31:11 `03java17-zulu`: `curl: (7) Failed to connect to broker.sdkman.io` on gradle 8.14.5; the `--tolerant` install loop moved on, then the strict activation loop's `sdk use gradle 8.14.5` hit `Stop! Candidate version is not installed.` and exited 1 (self-healed on restart). Decide at implementation: retry the download, or make the activation skip a package the install loop recorded as failed.

## Status
<!-- progress-block v1 -->
| # | Step | Size | State | Evidence | Files |
|---|------|------|-------|----------|-------|
| 1 | Postgres TCP healthcheck + PGCTLTIMEOUT | S | done | 481c889 | docker/images/01postgres18/**, bin/tests/postgres-healthcheck.test.sh |
| 2 | SonarQube error token + retry | M | done | c49dbec | docker/config/dist/bin/sonarqube-bin/**, docker/images/02sonarqube/** |
| 3 | rbenv install/rehash serialization | M | done | 585b891 | docker/config/dist/bin/rbenv-bin/**, bin/tests/startup-prologue.test.sh |
| 4 | SDKMAN download stall limit | S | todo | - | docker/config/dist/bin/sdkman-bin/** |
| 5 | SDKMAN tolerant install vs strict activation | S | todo | - | docker/config/dist/bin/sdkman-bin/** |
<!-- /progress-block -->
### Blocked
### Needs input
### Needs research
- [Inferred, read-only] 01mysql9's check is `mysqladmin ping -h localhost` — for the MySQL client `localhost` means the Unix SOCKET, and its init server runs with networking off, so it likely has Postgres's false positive; not probed. 01mariadb13 uses `healthcheck.sh --connect --innodb_initialized`, which requires a network connection — likely immune. Both keep the 80 s window (mysql/mariadb took ~4 min on 2026-09-28).
- Step 4: where the stall limit can be set (sdkman config vs wrapper) without patching the downloaded installer.
### Fragile
### Known issues
- Step 3 live proof (2026-09-28 16:14, warm path): `docker restart` of 03ruby3 + 03ruby4 together — ruby3 held the rbenv lock 15.557→15.692, ruby4 acquired at 15.693 (1 ms after the release), both healthy, no `cannot rehash`, `tools/errors/` empty. The COLD collision (two ~28 min compiles finishing together) is only reproduced by a wipe — the developer's planned hard-restart.
- Step 2 live proof (2026-09-28, rebuilt image — 02sonarqube BAKES its start script, a restart alone kept the old one): `kill -TERM` of java → `errors/02sonarqube` in 2 s, `RestartCount` 0→1, token cleared by the restart, healthy in 92 s; `docker stop` → graceful "SonarQube is stopped" in 2 s, exit 143, no token.
- Step 2: a stop is forwarded to the JVM as SIGTERM, not the image's StopSignal SIGINT — a background child starts with SIGINT ignored (SigIgn 0x6, measured), which the JVM cannot handle. docker stop's 10 s grace vs SonarQube's shutdown: measured 2 s on an idle instance (no analyses in flight); under load, unmeasured.
- Step 1 corrections (2026-09-28): the `service_healthy` dependents of 01postgres18 are 02keycloak-keycloak and 02sonarqube only — 02dpage-pgadmin4 does not depend on it (the ASSUMED entry named pgadmin). B's 300 s is agreed, not measured: the throwaway probe proves the variable reaches the init process, not that 300 s suffices under build load — that needs a fresh-volume bring-up. The fix takes effect on the next Postgres recreate (make-hash prediction: only 01postgres18 differs of 44).
