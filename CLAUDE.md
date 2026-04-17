# CLAUDE.md

> **/stack infrastructure and development tasks** (Docker, Bash scripts, Makefile, services, env-update, env-scan, Dockerfiles, compose configs) **MUST be delegated to the `global-stack-lead-dev` agent** (subagent_type: `global-stack-lead-dev`).
> **Non-/stack tasks** (general development, research, analysis, content creation, tooling outside this project) are handled directly in the main conversation using the global reasoning framework defined in `~/.claude/CLAUDE.md`.

---

This file provides guidance to Claude Code when working with code in this repository.

## What This Project Is

**Global Stack** (`global_stack`) is a single-developer Dockerized local development environment. It runs many containerized services (databases, web servers, language runtimes, tooling) via Docker Compose on Linux. All services share a common Docker bridge network and a bind-mounted `tools/` volume.

- **Version**: `2_0_0_local` — **Platform**: Linux only
- **Remote**: GitLab — single `master` branch
- **Developer**: single developer

## Architecture — Image Tier Hierarchy

Services live in `docker/images/<tier><name>/` and are numbered by build dependency order:

| Tier | Purpose | Examples |
|------|---------|---------|
| `00*` | Base Ubuntu image + core tooling (Go, Zig, Docker-in-Docker, mkcert, hadolint, shellcheck) | `00base` |
| `01*` | Infrastructure: databases, cache, web servers, mail, cloud simulators | MySQL9, Postgres18, Redis, Nginx, Caddy, Mailpit, LocalStack |
| `02*` | Language/version managers — install tools into shared `tools/` volume | NVM, PHPBrew, PyEnv, RbEnv, SDKMAN, Rust, FVM |
| `03*` | Pre-configured language runtimes (depend on tier 02 being healthy) | Node 22/24, PHP 8.2–8.5, Python 3, Ruby 3/4, Java 11/17/25, Flutter 3 |
| `04*` | Specialized application tools | PhpMyAdmin, Android SDK, Serverless Framework |
| `05*` | Combined all-in-one images (`05stable` / `05edge`) | All tier 03 runtimes in one container |
| `local.*` | Machine-specific custom images (git-ignored) | Project-specific variants |

**Build chain**: images build `FROM` the local registry (`local-global-stack-registry.local:5000`). Run `make start-local-registry` before first build. `COMPOSE_BAKE=true` uses BuildX bake; `make generate-buildx` produces the intermediate `docker-bake.local.json`.

**Network**: Single bridge `public` (`172.18.0.0/16`). Root `docker-compose.yaml` defines only this network — each service has its own `docker/images/<name>/docker-compose.yaml`. Services are composed together via the `COMPOSE_FILE` env var (semicolon-separated list in `.env`/`.env.local`).

## Shared Tools Volume & Health Signaling

- `./tools` on host is mounted as `${GLOBAL_STACK_DOCKER_TOOLS_PATH}` (`/stack/tools`) in **all** containers
- **Tier 02 containers install** runtimes/version managers into this volume; **tier 03+ containers use** what's already there
- **File-based health signaling** (not port-based): containers write `tools/successes/<token>` on success, `tools/errors/<token>` on failure; Docker healthchecks poll these files
- `start_period: 24h`, `retries: 99999` — intentionally patient; full stack can take 10+ minutes to come healthy
- `tools/locks/` — optional coordination between containers (controlled by `GLOBAL_STACK_USE_LOCKS`)
- Container startup scripts live in `docker/config/dist/bin/<runtime>-bin/global-stack-<runtime>-start.sh` (runtime name, not image tier — e.g., `nvm-bin/`, not `02nvm-bin/`)
- Entrypoint pattern: `CMD ["global-stack-base-sync-bin-n-exec.sh", "global-stack-<runtime>-start.sh"]`
- `make down` clears `tools/successes/*`, `tools/errors/*`, `tools/locks/*`, `tools/elapsed/*`
- **Two-phase model**: tier 02 runs with `MODE=install` (installs the tool), tier 03 runs with `MODE=setup` (configures specific versions). Both use the **same** startup script (e.g., `nvm-start.sh` serves both `02nvm` and `03node*`). The `*_MODE` env var differentiates behavior.
- **Error tokens**: each service sets `GLOBAL_STACK_ERROR_TOKEN` in compose YAML. On failure, startup creates `tools/errors/<TOKEN>`. Healthcheck: healthy only when error file is absent AND success file is present.
- **Host-container binding** (the signature feature): startup scripts write env exports to `tools/.shellrc/<runtime>.shellrc` (e.g., `nvm.shellrc`). Host shell sources these files, making container-installed tools available on the host via PATH propagation.

## Environment Variable System

```
.env            # Master reference (tracked in git)
.env.local      # Machine-specific active config (gitignored)
```

- All project variables use `GLOBAL_STACK_*` prefix; nested `${VAR}` expansion is used extensively
- `bin/env-scan.sh` syncs `.env` → `.env.local`: adds new vars, detects differences, reports conflicts
- **Port binding pattern**: `GLOBAL_STACK_<SERVICE>_PORT_<N>=` — empty = no host binding; when set, value must end with `:` (e.g. `42708:`)
- **Host port range**: `42700–42811` (avoids conflicts with system services)
- `GLOBAL_STACK_DOCKER_USER_ID` (`developer`) is the master credential — all DB passwords, pgAdmin, Keycloak default to it
- `GLOBAL_STACK_RELOAD_*=true` forces full reinstall of that tier's tools on next container start (slow!)

### @todo env-update Annotation System

Every version variable in `.env` is annotated for automated checking:

```bash
# @todo env-update [FLAGS] TYPE:IDENTIFIER [MAJOR_HINT] CURRENT_VERSION
GLOBAL_STACK_POSTGRES18_VERSION=18.3-alpine3.23
```

**Fetcher types**: `dockerhub`, `github`, `codeberg`, `npm`, `pecl`, `pecl-git`, `sdkman`, `sdkmanager`, `pypi`, `quay`, `rubygems`, `url`

**Common flags**: `(propagate)` — update all occurrences; `(override)` — always report, never auto-apply; `(skip:REASON)`; `(channel:rc|beta|nightly)`; `(tag-filter:REGEX)`; `(tag-exclude:REGEX)`; `(tag-strip-prefix:STR)`; `(tag-extract:REGEX)`; `(tag-suffix:STR)` — match tags ending with suffix; `(depends-on:VAR:constraint)`; `(version-prefix:v)`; `(fetch-extract:PERL_REGEX)`; `(fetch-json:JQ_PATH)`; `(stable-only)`

See `templates/tips/env-update.md` for full annotation reference.

## Key Scripts

### bin/env-update.sh

Parses `.env` annotations, fetches latest versions from 12 registries, auto-applies safe updates.

**Decision outcomes**: `[AUTO]` auto-applied; `[MANUAL]` requires human review; `[HOLD]` pre-release vs stable; `[SKIP]` no change/unversioned; `[UBUNTU]` codename alignment needed

**Key flags**:
```bash
--dry-run            # Preview only, no files modified
--offline            # Use cache only, no network
--progress           # Show fetch indicator
--filter=<pattern>   # Only process matching vars (bash regex)
--type=<types>       # Comma-separated fetcher types
--no-auto-apply      # Report all, apply nothing
--show-ok            # Include up-to-date entries
--cache-ttl=<sec>    # Default 3600
```

### bin/env-scan.sh

6-phase pipeline: parse args → build source index → scan docker sources → detect conflicts → sync env files → cleanup.

**Key flags**: `--sync-values=true` (overwrite dest values from source), `--profile=true` (show timing), `--dry-run`

### bin/migrate-annotations.sh

One-shot migration from legacy URL-based annotations to `TYPE:IDENTIFIER` format. Should not need re-running.

**Full reference**: `templates/tips/env-scan.md`, `templates/tips/env-update.md`

## Shell Coding Conventions

`bin/env-update.sh` and its library use `set -eEuo pipefail`; `bin/env-scan.sh` does not (strict mode is commented out). Container startup scripts use `set -xeE -o pipefail` (debug tracing, no `-u`). When writing new scripts, use `set -eEuo pipefail`. Follow these patterns:

- **Variable prefixes**: `_GS_EU_` for env-update, `_GS_ES_` for env-scan
- **Include guards** (every lib file):
  ```bash
  [[ -n "${_GS_EU_MODULENAME_SH_LOADED:-}" ]] && return 0
  readonly _GS_EU_MODULENAME_SH_LOADED=1
  ```
- **Error propagation across subshells**: write to temp files (`_GS_EU_FETCH_ERROR_FILE`), read back in parent — stdout is reserved for return values
- **Sentinel return values**: `__hold_newer_major__:...`, `__pecl_promotion__:ext:ver`, `__codename_upgrade_hint__:...` signal complex decisions from fetcher to caller
- **Parallel arrays** instead of objects (bash limitation): `_GS_EU_RECORDS_ENV_VAR[i]`, `_GS_EU_RECORDS_TYPE[i]` indexed by `_GS_EU_RECORD_COUNT`
- **Function naming**: `_gs_eu_<module>_<action>` for env-update; `es_<action>` or `_gs_es_<action>` for env-scan
- **CLI-first with API fallback**: `_gs_eu_cli_with_fallback fn_cli fn_api` — activates the correct runtime (nvm/pyenv/rbenv), tries CLI in subshell, falls back to API
- **NO_COLOR** support per no-color.org; color only when `stdout` is a terminal
- **Dependencies**: `bash 4.3+`, `curl`, `jq`, `perl`, `sort -V` (GNU coreutils), `sed`, `awk`, `grep`

## Makefile Patterns

- **DRY macros** for per-service targets — five families: `login-service-shell`, `login-service-sh`, `log-service`, `log-follow-service`, `restart-service`
  ```makefile
  $(eval $(call login-service-shell,03node24))
  ```
- **`docker-cli` target**: central dispatcher — assembles `${GLOBAL_STACK_DOCKER_CLI} ${FLAGS} ${EXEC} ${EXEC_FLAGS} ${SERVICE} ${CONTAINER_COMMAND}`
- `local.Makefile` extends via `-include local.Makefile`; uses `create-paths::` double-colon for additive extension
- **Adding a new service**: add five `$(eval $(call ...))` lines + add new targets to the `.PHONY` declaration block

## Common Workflows

```bash
# Start / stop
make up                              # Start stack
make down                            # Stop stack
make down-n-up                       # Soft restart (down then up, no rebuild)
make down-n-rebuild-force-recreate   # Full teardown + rebuild + start
make hard-restart                    # DESTRUCTIVE: wipe all images/volumes, rebuild from scratch

# Per-service
make login-03node24                  # Shell into a container
make log-follow-03node24             # Tail container logs
make restart-03node24                # Restart one service

# Version updates (safe preview first)
bin/env-update.sh --dry-run --progress
bin/env-update.sh --type=github --filter=NODE --dry-run
bin/env-update.sh  # Apply auto-updates

# After updating versions in .env
bin/env-scan.sh --sync-values=true   # Propagate to .env.local
make down-n-rebuild-force-recreate

# Env sync / audit
bin/env-scan.sh --profile=true       # Sync + show timing
docker compose --env-file .env.local config  # Validate compose resolution

# Build artifacts
make generate-buildx                 # Regenerate docker-bake.local.json
make create-buildx-builder           # Set up BuildKit builder
make start-local-registry            # Start local TLS registry (port 5000)
```

## Testing & Verification

- **env-scan tests**: `bash bin/tests/env-scan.test.sh` — custom harness with `assert_equals`, `assert_contains`, `assert_not_contains`, `assert_file_exists`
- **env-update**: no automated tests — verify with `--dry-run --filter=<VAR>` and `--offline` for cache-only testing
- **Shell scripts**: `shell-check <file>` (binary is `shell-check`, not `shellcheck`) and `shfmt -d -i 2 -ci -bn <file>` (diff mode)
- **YAML files**: `yamllint -d relaxed <file>` and `yamlfmt -dry <file>` (dry-run mode)
- **Formatting**: `/fmt --check` to preview all formatting changes, `/fmt` to apply them
- **Compose validation**: `docker compose --env-file .env.local config` or `make generate-buildx`
- **Health check status**: `ls tools/successes/` (healthy) and `ls tools/errors/` (failed)
- **env-update cache**: `/tmp/global-stack-env-update-cache/` (TTL 3600s); use `--no-cache` to bypass

## Claude Code Tooling

**Slash commands** (type `/command` in any session):
- `/lint` — shell-check all scripts + hadolint all Dockerfiles
- `/fmt` — format shell scripts (`shfmt`) and YAML files (`yamlfmt`); supports `--check`, `--sh`, `--yaml`
- `/check-versions` — `bin/env-update.sh --dry-run` with summary
- `/validate` — compose config + env consistency + COMPOSE_FILE + tier deps
- `/stack-health` — health markers, container status, version markers
- `/env-diff` — show divergences between `.env` and `.env.local`
- `/service-info <name>` — deep-dive on one service (compose, Dockerfile, startup, health, ports, versions)
- `/recent` — quick context: recent commits, uncommitted changes, stack health

**Automatic hooks** (PostToolUse on Edit/Write):
- `shell-check` — lints `.sh` files on every write
- `hadolint` — lints `Dockerfile*` files on every write
- `yamllint` — validates `.yaml`/`.yml` files on every write
- `shfmt` — checks shell formatting on `.sh` writes (reports diff, doesn't auto-fix)

**Permission rules** (`.claude/settings.json`): safe read-only operations pre-approved (including `docker compose ps/logs`, `shfmt`, `yamlfmt`, `yamllint`, `yq`, `diff`); destructive operations (`rm -rf`, `sudo`, `git push --force`, `docker push`, `make hard-restart`, `docker system prune`, `docker volume rm`, `docker rmi`, `git clean`, `chmod 777`) blocked.

## Gotchas & Pitfalls

- **Trailing `;` in `COMPOSE_FILE`** breaks Docker Compose silently — always check this after editing
- **Port vars must end with `:`** when set (e.g. `42700:`) — omitting the colon causes Docker Compose to treat it as the container port only
- **`00base` must always be in `COMPOSE_FILE`** — nearly everything depends on it being healthy
- **Tier 02 required for tier 03**: if `03node22` is active, `02nvm` must be in `COMPOSE_FILE`; same for `02phpbrew`/`03php*`, `02sdkman`/`03java*`, etc.
- **`${VAR}` expansion in `.env`**: variables must be defined before being referenced; Docker Compose and Make both expand them, but simple dotenv parsers do not
- **`GLOBAL_STACK_RELOAD_*=true`** forces full reinstall (can take 30+ minutes) — reset to `false` after use
- **`tools/` is shared state**: `make down` clears success/error markers; if a container fails mid-install, manually check `tools/errors/` before restarting
- **`local.*` image dirs are git-ignored** — back them up separately or store in a private repo
- **Container startup is intentionally slow** (`start_period: 24h`) — do not tune healthchecks lower without understanding the two-phase install model
- **`docker-compose*.local.yaml` overrides** — git-ignored, machine-specific; can silently override tracked compose files. Check for their existence when debugging unexpected service behavior
- **ARG → ENV flow in Dockerfiles**: `ARG` values are build-time only; to expose at runtime: `ARG GLOBAL_STACK_FOO` then `ENV GLOBAL_STACK_FOO=${GLOBAL_STACK_FOO}`
- **`password = username` convention**: All default service passwords equal `GLOBAL_STACK_DOCKER_USER_ID` (`developer`) — MySQL, Postgres, pgAdmin, Keycloak all share this pattern
- **`privileged: true` on all containers** — intentional for local dev (needed for Docker-in-Docker, mount operations). Do not flag this as a security issue; it's a known trade-off
- **`tools/versions/` markers** control reinstall — deleting a marker forces full reinstall of that runtime even without `GLOBAL_STACK_RELOAD_*=true`
- **`docker-bake.local.json` is generated, not tracked** — if it's stale after env changes, run `make generate-buildx` to regenerate. Stale bake file = wrong build config
- **BuildKit cache can go stale** — if builds fail with mysterious layer errors, `docker buildx prune` is the escape hatch

## Credentials & Stateful Data

- SSH keys go in `docker/config/root/.ssh/` — mounted into all containers
- Persistent data: `docker/data/<service>/`, `docker/storage/<service>/`
- **Credential reset**: stop stack, delete `docker/data/<service>/`, restart (fixes auth corruption for MySQL, Postgres, Mongo)

## Debugging a Failed Container

When a service fails to start or becomes unhealthy:

```bash
# 1. Check what failed
ls tools/errors/                          # Which error tokens exist?
cat tools/errors/<TOKEN>                  # Error details (if written)

# 2. Check logs
make log-follow-<service>                 # Tail the container logs
# or: docker compose --env-file .env.local logs <service>

# 3. Shell into the container (if still running)
make login-<service>                      # Interactive shell

# 4. Check the startup script
# Find it: docker/config/dist/bin/<runtime>-bin/global-stack-<runtime>-start.sh
# The runtime name is the tool (nvm, phpbrew, sdkman), NOT the tier number

# 5. Check tier dependencies
# Is the tier 02 manager healthy? (e.g., 02nvm must be healthy before 03node*)
ls tools/successes/ | grep <tier02-name>

# 6. Nuclear option: force reinstall
# Set GLOBAL_STACK_RELOAD_<RUNTIME>=true in .env.local, restart
# Remember to set it back to false after!
```

## Claude Code Configuration

Claude Code's configuration for this project lives in:

```
~/.claude/CLAUDE.md                      # Global reasoning framework (all projects)
~/.claude/settings.json                  # Global settings (model, plugins)
/stack/.claude/agents/global-stack-lead-dev.md  # /stack infrastructure agent definition (project-scoped)
.claude/settings.json                    # Project permissions, hooks
.claude/settings.local.json              # Local UI preferences (gitignored)
.claude/hooks/                           # PostToolUse hook scripts
  shellcheck-on-write.sh                 # Lint .sh files on write
  hadolint-on-write.sh                   # Lint Dockerfiles on write
  yamllint-on-write.sh                   # Validate YAML on write
  shfmt-on-write.sh                      # Check shell formatting on write
.claude/commands/                        # Slash command definitions
  lint.md  fmt.md  check-versions.md  validate.md
  stack-health.md  env-diff.md  service-info.md  recent.md
```

## Software Craftsmanship & Thinking Frameworks

The `global-stack-lead-dev` agent applies 30+ mental models across 5 categories (thinking razors, engineering laws, debugging models, decision frameworks, creative thinking) plus structured protocols for debugging (triage→investigate→root-cause→hypothesis), confidence-gated code review (P0-P3 severity routing), and adversarial brainstorm filtering. It names frameworks being applied and explains the connection. See the agent definition for the full reference.

## File Layout Quick Reference

```
.env                                 # Master config (tracked)
.env.local                           # Active machine config (gitignored)
Makefile                             # Primary build automation
local.Makefile                       # Machine-specific Makefile extensions
bin/env-update.sh                    # Automated version checker entry point
bin/env-scan.sh                      # Env sync tool entry point
bin/migrate-annotations.sh           # One-shot annotation migration
bin/lib/env-update/                  # Modular env-update library
  config/   codename_map, prerelease_markers, type_map
  core/     cache, channel, diff, dockerfile, parse, report, runtime, tag_flags, ubuntu
  fetchers/ codeberg, dockerhub, github, npm, pecl, pecl_git, pypi, quay, rubygems, sdkman, sdkmanager, url
bin/lib/env-scan/                    # Modular env-scan library
bin/tests/env-scan.test.sh           # Test suite (custom harness)
docker/images/<tier><name>/          # Per-image Dockerfile + docker-compose.yaml
docker/config/dist/bin/              # Container startup scripts
docker/config/dist/conf/             # Per-service runtime configs
docker/config/root/                  # Root home (SSH keys, etc.) — bind-mounted
docker/registry/                     # Local TLS Docker registry config
docker/buildkit/                     # Custom BuildKit image with local CA
tools/                               # Shared volume (gitignored — lives on host)
  successes/ errors/ locks/ elapsed/ # Health/coordination markers
  versions/                          # Installed version markers (skip reinstall)
  .shellrc/                          # Runtime env exports (host sources these)
  bin/                               # Shared executables (mkcert, etc.)
var/                                 # Backups, CA certs, hosts (gitignored)
projects/                            # Project source code (gitignored)
templates/ghost-blog/                # Template for adding a new service
templates/tips/                      # markdown cheat sheets
templates/shell/                     # Host system shell config templates
```

---

> **Remember**: Delegate /stack infrastructure tasks to `global-stack-lead-dev`; handle non-/stack tasks directly with the global reasoning framework. Use `/lint` before committing shell changes. Check for trailing `;` in `COMPOSE_FILE`. Verify with `--dry-run` before applying changes. Tier 02 = install, tier 03 = setup — same startup script, different `MODE`.
