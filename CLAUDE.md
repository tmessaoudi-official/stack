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
| `03*` | Pre-configured language runtimes (depend on tier 02 being healthy) | Node 24/26/edge, PHP 8.4/8.5/edge, Python 3, Ruby 3/4, Java 17/21/26, Flutter 3 |
| `04*` | Specialized application tools | PhpMyAdmin, Android SDK, Serverless Framework |
| `05*` | Combined all-in-one images (`05stable` / `05edge`) | All tier 03 runtimes in one container |
| `local.*` | Machine-specific custom images (git-ignored) | Project-specific variants |

> **Tier-prefix rule**: the number encodes build-dependency order, nothing else. Four services install nothing into `tools/` despite their tier-02 prefix (`02dpage-pgadmin4`, `02keycloak-keycloak`, `02sonarqube`, `02mongoclient`) — placed there for dependency ordering; `04phpmyadmin` is pgadmin's functional twin in a different tier. Don't infer install behavior from the prefix.

**Build chain**: images build `FROM` the local registry (`local-global-stack-registry.local:5000`). Run `make start-local-registry` before first build. `COMPOSE_BAKE=true` uses BuildX bake; `make generate-buildx` produces the intermediate `docker-bake.local.json`.

**Network**: Single bridge `public` (`172.20.0.0/16`). Root `docker-compose.yaml` defines only this network — each service has its own `docker/images/<name>/docker-compose.yaml`. Services are composed together via the `COMPOSE_FILE` env var (semicolon-separated list in `.env`/`.env.local`).

## Shared Tools Volume & Health Signaling

- `./tools` on host is mounted as `${GLOBAL_STACK_DOCKER_TOOLS_PATH}` (`/stack/tools`) in **all** containers
- **Tier 02 containers install** runtimes/version managers into this volume; **tier 03+ containers use** what's already there
- **File-based health signaling** (not port-based): containers write `tools/successes/<token>` on success, `tools/errors/<token>` on failure; Docker healthchecks poll these files
- `start_period: 24h`, `retries: 99999` — intentionally patient; full stack can take 10+ minutes to come healthy
- `tools/locks/` — optional coordination between containers (controlled by `GLOBAL_STACK_USE_LOCKS`)
- Container startup scripts live in `docker/config/dist/bin/<runtime>-bin/global-stack-<runtime>-start.sh` (runtime name, not image tier — e.g., `nvm-bin/`, not `02nvm-bin/`)
- Entrypoint pattern: `CMD ["global-stack-base-sync-bin-n-exec.sh", "global-stack-<runtime>-start.sh"]`
- `make down` clears `tools/successes/*`, `tools/errors/*`, `tools/locks/*`, `tools/elapsed` (single file)
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
- **Host port range**: `42700–42899` (avoids conflicts with system services)
- `GLOBAL_STACK_DOCKER_USER_ID` (`developer`) is the master credential — all DB passwords, pgAdmin, Keycloak default to it
- `GLOBAL_STACK_RELOAD_*=true` forces full reinstall of that tier's tools on next container start (slow!)

### @todo env-update Annotation System

Every version variable in `.env` is annotated for automated checking:

```bash
# @todo env-update [FLAGS] TYPE:IDENTIFIER [MAJOR_HINT] CURRENT_VERSION
GLOBAL_STACK_POSTGRES18_VERSION=18.3-alpine3.23
```

See `templates/tips/env-update.md` for the full fetcher-type and flag reference.

## Key Scripts

### bin/env-update.sh

**v2.0.0 (all fetcher types)** — parses `.env` annotations, fetches latest versions across all 12 fetcher types (dockerhub, github, ghcr, npm, pecl, pypi, quay, rubygems, sdkman, sdkmanager, url, codeberg), streams a `[AUTO|HOLD|SKIP|ERROR]` report, and can apply AUTO decisions back to `.env`.

**Key flags**: `--check` (fetch + report), `--apply` (apply AUTO decisions; implies `--check`), `--apply-resolve` (also apply RESOLVED decisions — floating→concrete rewrites; requires `--apply`), `--dry-run` (no writes), `--filter=<regex>`, `--no-cache`, `--format=text|json`, `--dump`, `--env-file=<path>`, `--cache-ttl=<N>`, `--with-tags`, `--unstable[=full|info]` (prerelease channel mode), `--stable[=full|info]` (stable channel mode; only `--stable=full + --unstable=full` is banned), `--no-notes` (suppress note sub-lines), `--changes-only` (hide up-to-date SKIP records), `--no-drift` (suppress [DRIFT]/[REPLACE-DRIFT] sub-lines), `--no-fail` (always exit 0; only ERROR fetch decisions suppressed — usage/backup errors remain fatal), `--scan` (run `bin/env-scan.sh` after `--apply` to propagate updated values to `.env.local` and Dockerfiles), `--force-auto` (bypass `(manual)`/`(override)`/`HOLD` gates; requires `--confirm="Confirm override"` with `--apply`; emits advisory when used without `--apply`), `--force-hold` (upgrade HOLD decisions to AUTO only — `(manual)`/`(override)` unaffected; requires `--confirm="Confirm override"` with `--apply`), `--confirm=TEXT` (confirmation gate for `--force-auto`/`--force-hold` with `--apply`), `--reference[=SECTION]` (print annotation/fetcher/decision reference and exit)

**Apply gate**: `--apply` is self-guarding — TTY prompts before writing; non-TTY requires `--yes`. Use `--check --dry-run` to preview without writing. Add `--yes` to `--apply` for scripted/CI use.

**Full reference**: `templates/tips/env-update.md`

### bin/env-scan.sh

**v1.0.0 (stable baseline)** — run `--version` to confirm. 8-phase pipeline: parse args → build source index → scan docker sources → detect conflicts → **backup pre-flight** → sync env files → propagate to Dockerfiles (+ Dockerfile backup) → retention prune + cleanup.

Propagation is automatic: any `ARG VAR=value` line in a Dockerfile whose value diverges from the canonical `.env` value is rewritten in-place. Vars with `${` in their `.env` value are skipped (expansion-dependent). Vars matching `_GS_ES_PATTERN_CONFLICT_IGNORE` are protected.

**Key flags**: `--version` (print version and exit), `--sync-values=false` (preserve dest values that differ from source; default is `true` — values are overwritten), `--profile=true` (show timing), `--dry-run` (report only — suppresses both env file sync and Dockerfile propagation), `--no-fail` (always exit 0; only Phase 6 propagation errors suppressed — infrastructure and backup failures remain fatal), `--backup=false` (skip backup this run), `--backup-keep=<N>` (keep N newest backups per file; 0 = unlimited; default 10), `--backup-purge=true` (delete all existing `<file>.bak.*` before run), `--backup-suffix=<str>` (suffix anchor; default `.bak`; full name: `<file><suffix>.<YYYYMMDD-HHMMSS>`)

**TTY behavior**: env-scan prompts on TTY and proceeds silently on non-TTY (no `--yes` required) — opposite of `env-update --apply`, which requires `--yes` in non-TTY.

**Full reference**: `templates/tips/env-scan.md`, `templates/tips/env-update.md`

## Shell Coding Conventions

`bin/env-update.sh` and its library use `set -eEuo pipefail`; `bin/env-scan.sh` also uses `set -eEuo pipefail` (added after the initial release to harden the entry point). Container startup scripts use `set -xeE -o pipefail` (debug tracing, no `-u`). When writing new scripts, use `set -eEuo pipefail`. Follow these patterns:

- **Variable prefixes**: `_GS_EU2_` for env-update, `_GS_ES_` for env-scan
- **Include guards** (every lib file):
  ```bash
  [[ -n "${_GS_EU2_MODULENAME_SH_LOADED:-}" ]] && return 0
  readonly _GS_EU2_MODULENAME_SH_LOADED=1
  ```
- **Error propagation across subshells**: write to temp files, read back in parent — stdout is reserved for return values
- **Parallel arrays** instead of objects (bash limitation): records indexed by count
- **Function naming**: `_gs_eu2_<module>_<action>` for env-update; `es_<action>` or `_gs_es_<action>` for env-scan
- **CLI-first with API fallback**: activates the correct runtime (nvm/pyenv/rbenv), tries CLI in subshell, falls back to API
- **NO_COLOR** support per no-color.org; color only when `stdout` is a terminal
- **Dependencies**: `bash 4.3+`, `curl`, `jq`, `perl`, `sort -V` (GNU coreutils), `sed`, `awk`, `grep`
- **Function size**: functions >150 lines or nesting >4 levels → decompose (precedent: d953279)
- **`# Sources:` convention**: lib files declare their dependencies via `# Sources: <file>` header comments but never `source` them — `main.sh` is the single coordinator of all `source` calls

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
make soft-restart                    # DESTRUCTIVE: sudo-wipes tools/, restores from var/tools — NOT down-n-up!

# Per-service
make login-03node24                  # Shell into a container
make log-follow-03node24             # Tail container logs
make restart-03node24                # Restart one service

# Version updates (safe preview first)
bin/env-update.sh --check                         # preview all types
bin/env-update.sh --filter=NODE --check           # only Node-related
bin/env-update.sh --apply                         # apply AUTO decisions (run --dry-run first!)

# After updating versions in .env
bin/env-scan.sh   # Propagate to .env.local + rewrite ARG lines in Dockerfiles (--sync-values=true by default)
# If a pinned runtime version changed: delete its tools/versions/ marker (or set
# GLOBAL_STACK_RELOAD_<RUNTIME>=true) — the marker gate is existence-only; skipping
# this leaves the old version installed and the container unhealthy after a long wait
make down-n-rebuild-force-recreate

# Env sync / audit
bin/env-scan.sh --profile=true       # Sync + show timing
docker compose --env-file .env.local config  # Validate compose resolution

# Rollback a bad env update (env-update --apply / env-scan cascade)
git checkout -- .env                                  # master is git-tracked
cp "$(ls -t .env.local.bak.* | head -1)" .env.local   # newest env-scan backup
bin/env-scan.sh                                       # re-propagate restored values to Dockerfiles

# Build artifacts
make generate-buildx                 # Regenerate docker-bake.local.json
make create-buildx-builder           # Set up BuildKit builder
make start-local-registry            # Start local TLS registry (port 5000)
```

## Testing & Verification

- **env-scan tests**: `bash bin/tests/env-scan.test.sh` — custom harness with `assert_equals`, `assert_contains`, `assert_not_contains`, `assert_file_exists`
- **env-update tests**: `bash bin/tests/env-update.test.sh` — 700+ tests across 112 sections (fetchers, cache, semver, apply, args, RESOLVED, --reference…); use `--dry-run --filter=<VAR>` for quick preview; `--offline` is not implemented (use `_GS_EU2_HTTP_FIXTURE_DIR` seam for deterministic offline testing)
- **Shell scripts**: `shellcheck <file>` and `shfmt -d -i 2 -ci -bn <file>` (diff mode)
- **YAML files**: `yamllint -d relaxed <file>` and `yamlfmt -dry <file>` (dry-run mode)
- **Formatting**: `/fmt --check` to preview all formatting changes, `/fmt` to apply them
- **Compose validation**: `docker compose --env-file .env.local config` or `make generate-buildx`
- **Health check status**: `ls tools/successes/` (healthy) and `ls tools/errors/` (failed)
- **env-update cache**: `/tmp/global-stack-env-update-cache/` (TTL 3600s); use `--no-cache` to bypass

## Claude Code Tooling

**Slash commands** (type `/command` in any session):
- `/lint` — shellcheck all scripts + hadolint all Dockerfiles
- `/fmt` — format shell scripts (`shfmt`) and YAML files (`yamlfmt`); supports `--check`, `--sh`, `--yaml`
- `/check-versions` — v2 `--check` across all fetcher types (dockerhub, github, ghcr, npm, pecl, pypi, quay, rubygems, sdkman, sdkmanager, url, codeberg); no v1 fallback
- `/validate` — compose config + env consistency + COMPOSE_FILE + tier deps
- `/stack-health` — health markers, container status, version markers
- `/env-diff` — show divergences between `.env` and `.env.local`
- `/service-info <name>` — deep-dive on one service (compose, Dockerfile, startup, health, ports, versions)
- `/recent` — quick context: recent commits, uncommitted changes, changed file stats (global command)
- `/bundle` — *(global command — works in any project)* bundle config into a portable `.tar.gz`; `--scope project` (default) LLM-generalizes this project's CLAUDE.md + .claude/ into a rich template with ADAPT markers; `--scope global` exports `~/.claude/` as-is; `--scope all` produces both archives
- `/install` — *(global command — works in any project)* install a bundle: Phase 0 detects existing `.claude/` (asks replace/manual-merge); bash installer runs; Phase 5 probes target project and fills ADAPT markers in-place
- `/adapt-project` — *(global command)* explore the project deeply and fill all ADAPT markers in CLAUDE.md + .claude/ (from an imported bundle); safe to re-run (idempotent if no markers remain)
- `/repair` — detect and repair config drift: scans CLAUDE.md + .claude/ vs project reality (files, tools, commands, structure), presents a plan, waits for confirmation; supports `--check` (report only) and `--apply` (auto-fix without prompting)
- `/sleuth` — *(global command)* behavioral bug hunter: 10 parallel agents hunt silent failures, logic traps, contract violations, cross-component inconsistencies; confidence-scored report, never auto-fixes
- `/gaps` — *(global command)* incompleteness detector: finds TODO markers, stubs, partial features, promised-but-missing code, template placeholders; prioritized roadmap, never auto-applies
- `/mega-analysis` — *(global command)* full pipeline in one command: repair → audit → skill-audit → inspect × 2 → sleuth × 2 → gaps × 2 → inspect --vision × 2 → retrospective → memory-promote → handoff; versioned delta report at `~/.claude/projects/meta-reports/YYYY-MM-DD/full-analysis[-runN].md`; `--quick` ~30 min, default ~2 hr
- `/skill-audit` — *(global command)* per-skill 15-dimension deep report: 4 parallel agents analyze every skill file (frontmatter completeness, trigger specificity, ask-human gate compliance, convergence gate compliance, cold-start readiness…); never auto-applies
- `/memory-promote` — *(global command)* analyze project memory files and propose promotions to CLAUDE.md (global) or agent def (project-specific); never auto-applies
- `/new-service <name> [--parent <image>] [--runtime <name>] [--port <n>]` — scaffold a new service (Dockerfile, compose, startup script, printed `.env` + Makefile lines); args-first with interactive fallback

**Automatic hooks** (PostToolUse on Edit/Write):
- `shellcheck` — lints `.sh` files on every write
- `hadolint` — lints `Dockerfile*` files on every write
- `yamllint` — validates `.yaml`/`.yml` files on every write
- `shfmt` — checks shell formatting on `.sh` writes (reports diff, doesn't auto-fix)

**Automatic hooks** (SubagentStop):
- `subagent-stop-reminder` — fires when a subagent completes; reminds parent to verify Phase 7/8

**Permission rules** (two layers): the project `.claude/settings.json` denies destructive operations (`make hard-restart*`/`soft-restart*`, `sudo`, `rm -rf`, `docker system prune`/`volume rm`/`rmi`, `git clean`, `git push --force`, `chmod 777`, Bash access to `docker/data`/`docker/storage`), asks for stack lifecycle (`make up/down/restart`, `env-update --apply`, `docker buildx prune`) and allows read-only previews (`env-update --check/--dry-run/--dump`, `env-scan --dry-run`, `make log-*`). Additional read-only allows (`docker compose ps/logs`, `shfmt`, `yamlfmt`, `yamllint`, `yq`, `diff`) live in the global `~/.claude/settings.json` layer — a bundle of this project carries only the project layer.

## Gotchas & Pitfalls

- **Trailing `;` in `COMPOSE_FILE`** breaks Docker Compose silently — always check this after editing
- **Port vars must end with `:`** when set (e.g. `42708:`) — compose uses `${VAR:-}PORT` so the value becomes the host half of `HOST:CONTAINER`; omitting the colon silently concatenates the port numbers (e.g. `427083306`)
- **`00base` must always be in `COMPOSE_FILE`** — nearly everything depends on it being healthy
- **Tier 02 required for tier 03**: if `03node24` is active, `02nvm` must be in `COMPOSE_FILE`; same for `02phpbrew`/`03php*`, `02sdkman`/`03java*`, etc.
- **`${VAR}` expansion in `.env`**: variables must be defined before being referenced; Docker Compose and Make both expand them, but simple dotenv parsers do not
- **`GLOBAL_STACK_RELOAD_*=true`** forces full reinstall (can take 30+ minutes) — reset to `false` after use
- **`tools/` is shared state**: `make down` clears success/error markers; if a container fails mid-install, manually check `tools/errors/` before restarting
- **`local.*` image dirs are git-ignored** — back them up separately or store in a private repo
- **Container startup is intentionally slow** (`start_period: 24h`) — do not tune healthchecks lower without understanding the two-phase install model
- **`docker-compose*.local.yaml` overrides** — git-ignored, machine-specific; can silently override tracked compose files. Check for their existence when debugging unexpected service behavior
- **ARG → ENV flow in Dockerfiles**: `ARG` values are build-time only; to expose at runtime: `ARG GLOBAL_STACK_FOO` then `ENV GLOBAL_STACK_FOO=${GLOBAL_STACK_FOO}`
- **`password = username` convention**: All default service passwords equal `GLOBAL_STACK_DOCKER_USER_ID` (`developer`) — MySQL, Postgres, pgAdmin, Keycloak all share this pattern
- **`privileged: true` on all containers** — intentional for local dev (needed for Docker-in-Docker, mount operations). Do not flag this as a security issue; it's a known trade-off
- **`tools/versions/` markers** control reinstall — deleting a marker forces full reinstall of that runtime even without `GLOBAL_STACK_RELOAD_*=true`; when the marker content differs from the current env version, reinstall triggers automatically without needing to delete the marker
- **`docker-bake.local.json` is generated, not tracked** — if it's stale after env changes, run `make generate-buildx` to regenerate. Stale bake file = wrong build config
- **BuildKit cache can go stale** — if builds fail with mysterious layer errors, `docker buildx prune` is the escape hatch
- **Bash-written files bypass all PostToolUse hooks** — linting (shellcheck, hadolint, yamllint), formatting (shfmt), and backup only fire on `Edit`/`Write` tool calls. Files written via `cat >`, heredocs, `sed -i`, or other Bash redirects are invisible to hooks. Always use the `Write` or `Edit` tool when hook coverage matters.
- **`core.fileMode=false` in `/stack/`** — git ignores all file permission changes; `chmod` edits take effect on disk but are never staged or committed. For permission fixes, note the change explicitly in the commit message of whatever else touches the file; do not expect `git diff` or `git status` to show the mode delta.
- **Auto-commit in /stack sessions** — commits may be made autonomously when staged changes are ready and tests pass; explicit confirmation not required (user preference for this project; overrides global Rule 10). Use descriptive commit messages following the existing style (`feat:`, `fix:`, `docs:` prefix). If `git commit` is blocked by a hook despite user authorization, present the exact command for manual execution rather than retrying.
- **`make soft-restart` is DESTRUCTIVE** — despite the name it `sudo rm -rf`s `tools/` and restores it from `var/tools`; it is NOT the documented soft restart (`make down-n-up`). A stale `var/tools` means a full multi-10-minute reinstall
- **`make save` exports EVERY Docker image on the machine** — not just stack images; slow, disk-hungry, undocumented side effect
- **Host checkout MUST live at `/stack`** — `tools/.shellrc/*.shellrc` exports bake absolute paths (`/stack/tools/...`) shared by containers and host; a checkout at any other path breaks host-container binding
- **LOCAL port range**: `GLOBAL_STACK_LOCAL_*_PORT_*` use host range **41700–41899** (200 slots). Standard `GLOBAL_STACK_*_PORT_*` use 42700–42899. Next free LOCAL slot: 41719.
- **LOCAL port var names for `local.05php8-4-...`**: the 7 port vars use SHORT form (`..._RUBY_N_RUST_N_PYTHON_N_JAVA_N_...`, no version suffixes), but `ALLTOGETHER_NAME` uses the LONG form with `05` prefix (`GLOBAL_STACK_LOCAL_05PHP8_4_N_NODE24_N_RUBY4_N_RUST_N_PYTHON3_N_JAVA26_N_ANDROID_N_FLUTTER3_41_9_ALLTOGETHER_NAME`). Pattern: env vars (short) vs healthcheck token (long).

## Credentials & Stateful Data

- SSH keys go in `docker/config/root/.ssh/` — mounted into all containers
- Persistent data: `docker/data/<service>/`, `docker/storage/<service>/`
- **Credential reset**: DB state lives in **named Docker volumes**, NOT `docker/data/` (those are seed-dump mounts). Procedure: `make down`, then `docker volume ls | grep <service>` and `docker volume rm` the matching volume(s) (e.g. `global_stack_2_0_0_local_01mysql9_data`; Postgres uses `_var_lib_postgresql`), then `make up`. Layout rule: `docker/data/` = seed dumps, `docker/storage/` = app state, named volumes = DB state

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
.claude/hooks/                           # PostToolUse + SubagentStop hook scripts
  shellcheck-on-write.sh                 # Lint .sh files on write
  hadolint-on-write.sh                   # Lint Dockerfiles on write
  yamllint-on-write.sh                   # Validate YAML on write
  shfmt-on-write.sh                      # Check shell formatting on write
  subagent-stop-reminder.sh              # SubagentStop: remind parent to verify Phase 7/8
.claude/skills/                          # Slash skill definitions
  lint/SKILL.md  fmt/SKILL.md  check-versions/SKILL.md  validate/SKILL.md
  stack-health/SKILL.md  env-diff/SKILL.md  service-info/SKILL.md  new-service/SKILL.md
```

## File Layout Quick Reference

See `templates/tips/file-layout.md`.

---

> **Core Operating Rules 6 & 7** (Completion Gate and TDD) are defined in the global `~/.claude/CLAUDE.md` and apply here without exception.

> **Remember**: Delegate /stack infrastructure tasks to `global-stack-lead-dev`; handle non-/stack tasks directly with the global reasoning framework. Use `/lint` before committing shell changes. Check for trailing `;` in `COMPOSE_FILE`. Verify with `--dry-run` before applying changes. Tier 02 = install, tier 03 = setup — same startup script, different `MODE`.
