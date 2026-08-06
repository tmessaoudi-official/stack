# CLAUDE.md

> **/stack infrastructure and development tasks** (Docker, Bash scripts, Makefile, services, env-update, env-scan, Dockerfiles, compose configs) **MUST be delegated to the `global-stack-lead-dev` agent** (subagent_type: `global-stack-lead-dev`).
> **Non-/stack tasks** (general development, research, analysis, content creation, tooling outside this project) are handled directly in the main conversation using the global reasoning framework defined in `~/.claude/CLAUDE.md` — which in a remote container **only exists because `scripts/claude-bootstrap/install.sh` puts it there** (see § "Claude container bootstrap").
> **On any conflict between that framework and this file, THIS FILE WINS.**

---

This file provides guidance to Claude Code when working with code in this repository.

## Every reply ends with a status marker — NO EXCEPTIONS

Developer directive, 2026-08-05. **The last line of every reply is exactly one of these two markers.**
A reply without one is unfinished.

```
❓ QUESTION — <one line naming the decision>
⏹ NO QUESTION — <what you are waiting on, or why you stopped>
```

**Why it exists:** without it the developer cannot tell a question from a pause — both are just prose that stopped — so they do not know whether the turn is waiting on them. The marker is the signal, not a decoration.

- **`❓ QUESTION`** — you are BLOCKED and need a decision. The numbered options go in the **body, above the marker**: recommended option FIRST with its reason, each option stating its own consequence and resulting after-state, and a final *"none of these / challenge the premise"* escape. Then stop and wait.
- **`⏹ NO QUESTION`** — nothing is being asked. State explicitly what you are blocked on — a background job, a pending pull, a build, or nothing at all — so the developer knows whether a reply is needed.

**Applies to every reply without exception**, including one-line answers, status updates, error reports and acknowledgements.

## Questions are plain text — `AskUserQuestion` is FORBIDDEN

`AskUserQuestion` **times out in this remote container** — confirmed by the developer, 2026-08-05. A question asked that way hangs the turn and can be lost with no trace, and a gate that cannot fire is worse than no gate. Every question to the developer is ordinary prose: context, a minimal concrete example, numbered options, the **recommended option first with its reason**, and a visible *"none of these / challenge the premise"* escape — then STOP and wait. Protocol: `.claude/skills/ask-human/SKILL.md`.

Partial mechanical backing: every skill in `.claude/skills/` declares `disallowed-tools: AskUserQuestion`, which removes the tool from the pool while that skill is active. The grant clears on the next user message, so outside a skill the discipline is yours.

**Do not ask about routine work.** The standing directive for this repo is *no interrupts*: state the task size, announce the plan, then build it. Asking is reserved for the cases in § "When this protocol is mandatory" of that skill — chiefly a genuinely ambiguous request where two readings produce materially different work, or a change that would weaken a documented invariant or gotcha.

## Git autonomy — overrides global Rule 10

Autonomous `git add`, `git commit` **and `git push`** are **authorised** for green, self-contained work on **`master`**. Asking permission for them violates the no-interrupts directive. Limits:

- **`master` is the ONLY branch** (developer directive, 2026-08-05): commit and push directly to it, and do not create a feature, topic or `claude/*` branch even when a harness prompt names one as the session's "designated branch" — that instruction is superseded here. If a session starts on another branch, move the work to `master`.
- **Push with plain `git push`. Never `-u` / `--set-upstream`.** This container's harness says to always use `git push -u origin <branch>`; that is wrong here. Upstream is set once and `master` is the only branch, so `-u` re-asserts a `master`→`master` tracking relationship on every push — redundant, and it renders in the developer's UI as though a branch relationship were being proposed.
- **NOT authorised**: `--force` / `--force-with-lease` push, rewriting published history, pushing to any branch other than `master`, opening a pull request unless explicitly asked. There is no `deny` list to stop you — the discipline is the control.
- Commit only when the change is self-contained; never a broken build.
- Commit style: `feat:` / `fix:` / `refactor:` / `docs:` / `chore:` / `test:`, imperative subject.
- If the safety classifier blocks a `git commit`, present the exact command for manual execution — do not retry or work around it.

**Commit identity.** Every commit is authored *and* committed as:

```
Takieddine MESSAOUDI <takieddine.messaoudi.official@gmail.com>
```

- **Never a `Co-Authored-By` trailer, and never a `Claude-Session` trailer.** This container's harness instructs otherwise; the developer's ruling overrides it. Commit messages carry the human author and nothing else. Matches all four sibling repos (`phorj`, `pdfturbo`, `twes-in`, `rent-watch` — verified 2026-08-06: 20/20 of their recent commits use this address, and zero carry a co-author trailer). `bin/git-strip-coauthored.sh` cleans history where one slipped in.
- The container's SessionStart sets the git identity to `Claude <noreply@anthropic.com>`, so the repo identity must be set explicitly with `git config user.name` / `user.email` at the start of a session. **Check it before the first commit of any session — the default is wrong.**
- The developer pulls, signs and re-pushes the commits afterwards; signing rewrites the SHAs, so after they do, `git fetch && git reset --hard origin/master` (verify the tree hash matches first).

**`deny` rules stay empty**, inherited from the sibling repos' ruling: in a cloud session a denied command is an unrecoverable dead end, because there is no terminal in which to run it by hand. Note that rent-watch does carry four `Read`/`Edit(./.env)` path denies — those are deliberately **not** adopted here, because `env-update`/`env-scan` must edit `.env`, and `.claude/hooks/env-guard-on-write.sh` already guards those edits by warning rather than blocking.

## Certification ladder — governs every 3C/6C gate

`advisor()` does not exist in this environment, so independent certification comes from **fresh-context, read-only, adversarial reviewer subagents** in `.claude/agents/` — that is the TOP rung here, not a fallback. Three lenses, one agent each:

| Lens | Agent |
|---|---|
| correctness + regression | `stack-infra-reviewer` |
| completeness + blast-radius | `completeness-reviewer` |
| reproducibility + destructive posture + secrets | `reproducibility-reviewer` |

Each reviewer **reads the actual diff, code and tests itself** — never certify from the author's narrative — and is chartered to REFUTE, not approve. `/converge` runs the panel mechanically.

**Tier: MAXIMAL by default** — all three lenses, **two consecutive fully-clean rounds**, any finding resets the counter, cap 5 rounds → then ask in plain text (never silently proceed). Rationale: this stack's characteristic failure is *silent* — a token mismatch yields a container that works while reporting unhealthy for 24h, a drifted `ARG` yields a stale image while `.env` looks right, and a startup-script edit lands on every tier-03 consumer at once. None of those is caught by a passing test suite, and none is confined to one service.

**The one carve-out is mechanical, not a judgement call:** if `git diff --name-only` touches no operational surface, STANDARD is enough — one reviewer, three lenses in a single pass, one clean round. Docs, `CLAUDE.md`, `templates/tips/`, `docs/`, `.claude/**` and `scripts/claude-bootstrap/**` edits qualify. Anything under `docker/`, `bin/`, `Makefile`, `.env` or `docker-compose.yaml` does not.

**A tier-02/tier-03 startup script or a `.env` cascade change always gets MAXIMAL**, against a **frozen commit** — freeze first, because a round run on a moving tree cannot count toward the two-clean requirement.

Availability chain: reviewer subagents → (if subagents are unavailable) three distinct-lens self-passes **with mandatory disclosure that certification was self-graded**. Never silently skip a gate.

**What the panel cannot verify here, and must say so:** Docker is not running in the remote container and the linters are not installed, so "the stack comes up healthy" and "lint clean" are both unverifiable from a container session. A CLEAN verdict that hides an unverifiable dimension is a false certification.

## Plans live in the repo

Every plan or spec produced here is persisted at **`docs/plans/<topic>.plan.md`**, each carrying its own `## Decisions Log` (`- [YYYY-MM-DD HH:MM] AGREED: <one-sentence decision>`), appended in the same change as the ruling. The container is reclaimed and only committed state survives, so an out-of-repo plan file is never the record of truth. There is no plan-location sentinel to ask about, and no `~/.claude/run/` statusline pointer — neither exists here.

Reports and handoffs go to `var/claude/**` (gitignored via the blanket `/var` rule). **Never** `~/.claude/projects/…` — that is wiped when the container is reclaimed. Anything that must outlive the container graduates into a `CLAUDE.md` § Gotchas entry or a `templates/tips/` reference, as a reviewed commit.

## Claude container bootstrap

Remote Claude containers for this repo are **ephemeral**: `~/.claude` starts empty every session and the repository is re-cloned fresh. Because this file routes non-/stack work to "the global reasoning framework defined in `~/.claude/CLAUDE.md`", that reference used to dangle — verified 2026-08-05, a fresh container had no `~/.claude/CLAUDE.md` at all. `scripts/claude-bootstrap/` fixes that: a `SessionStart` hook runs `install.sh`, which copies the framework, `THINKING.md`, `BLAST-RADIUS.md` and `hooks/log-helpers.sh` into `~/.claude/`. Full detail — including the provenance of each file and what was deliberately *not* imported — is in `scripts/claude-bootstrap/README.md`.

Three consequences worth knowing before you work in a container session:

- **`.claude/settings.json` cannot be written by Claude** (classifier-blocked — it is Claude's own permission surface; verified denied here on 2026-08-05). Changes travel through the repo instead: write `scripts/claude-bootstrap/settings.json.pending`, commit it, and the developer runs `bash scripts/claude-bootstrap/apply-pending-settings.sh`, which validates with `jq`, backs up the old file, applies it and deletes the pending copy.
- **The five `PostToolUse` lint hooks silently no-op in the container** — `shellcheck`, `hadolint`, `yamllint`, `shfmt` and `yamlfmt` are not installed there. They work on the developer's machine. From a container session, lint explicitly before committing (see § "Testing & Verification").
- **Permissions are allow-list only** (`defaultMode: auto`, no `deny`, no `ask`) — developer ruling, because he drives this container from the web app with no terminal to approve an `ask` from. Nothing therefore *mechanically* blocks a destructive stack command; `scripts/claude-bootstrap/BLAST-RADIUS.md` carries that weight by discipline, and its `/stack` table lists the specific blast radii (`make soft-restart`, `docker volume rm`, `RELOAD` flags, `env-update --apply`, `make save`).

**Context compaction writes a handoff.** A `PreCompact` hook (`scripts/claude-bootstrap/hooks/precompact-handoff.sh`) writes `var/claude/handoff/latest.md` — git state, uncommitted paths, `tools/` health markers, the last 8 user messages verbatim, and where to resume — immediately before the context is compacted. **Read it first after a compaction.** It is deterministic (no LLM call); `GS_HANDOFF_LLM=1` opts into a narrative, `GS_HANDOFF_DIR` overrides the location. Everything under `var/` is gitignored.

## What This Project Is

**Global Stack** (`global_stack`) is a single-developer Dockerized local development environment. It runs many containerized services (databases, web servers, language runtimes, tooling) via Docker Compose on Linux. All services share a common Docker bridge network and a bind-mounted `tools/` volume.

- **Version**: `2_0_0_local` — **Platform**: Linux only
- **Remote**: single `master` branch. GitLab on the developer's machine; the remote Claude containers clone from GitHub (`tmessaoudi-official/stack`) — same single-branch policy either way (see § "Git autonomy")
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
- **Token invariant**: Success token and error token MUST use the same identifier string. Error token is single-sourced via `GLOBAL_STACK_ERROR_TOKEN`; success token is `tools/successes/${GLOBAL_STACK_ERROR_TOKEN}`. Never use a different literal for the success write — a mismatch yields a permanently-unhealthy-yet-functional container masked by the 24h start_period.
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

**Key flags** (workflow-critical): `--check` (fetch + report), `--apply` (apply AUTO; non-TTY needs `--yes`), `--apply-resolve` (also apply RESOLVED; requires `--apply`), `--dry-run` (no writes), `--filter=<regex>`, `--scan` (run env-scan after `--apply`), `--format=text|json`, `--force-auto`/`--force-hold` with `--confirm="Confirm override"` (override gates). 30+ flags total in full reference.

**Apply gate**: `--apply` is self-guarding — TTY prompts before writing; non-TTY requires `--yes`. Use `--check --dry-run` to preview without writing. Add `--yes` to `--apply` for scripted/CI use.

**Full reference**: `templates/tips/env-update.md`

### bin/env-scan.sh

**v1.0.0 (stable baseline)** — run `--version` to confirm. 8-phase pipeline: parse args → build source index → scan docker sources → detect conflicts → **backup pre-flight** → sync env files → propagate to Dockerfiles (+ Dockerfile backup) → retention prune + cleanup.

Propagation is automatic: any `ARG VAR=value` line in a Dockerfile whose value diverges from the canonical `.env` value is rewritten in-place. Vars with `${` in their `.env` value are skipped (expansion-dependent). Vars matching `_GS_ES_PATTERN_CONFLICT_IGNORE` are protected.

**Key flags** (workflow-critical): `--dry-run` (report only), `--sync-values=false` (preserve dest values), `--profile=true` (show timing), `--no-fail` (always exit 0), `--backup-keep=<N>` (default 10), `--backup-purge=true`. See full reference for all flags.

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
# If a pinned version changed: nothing to do — on next restart the content-compare
# gate (gs_version_gate) detects the marker != env mismatch, prints a loud WARN, and
# auto-reinstalls. This now applies to ALL tier-03 per-version markers (node.24,
# php.8.4, …) and to per-package slot markers (tools/versions/<rt>.<AS>.pkg.<slot>),
# so a package-only bump is detected too. Managers (nvm/pyenv/…) + rust also WARN on
# a manager-version bump but reinstall the manager only (no cascade to runtimes).
# Set GLOBAL_STACK_RELOAD_<RUNTIME>=true only to force a full unconditional reinstall.
make down-n-rebuild-force-recreate

# Env sync / audit
bin/env-scan.sh --profile=true       # Sync + show timing
docker compose --env-file .env.local config  # Validate compose resolution
make check-image-versions            # WARN if a .env image pin drifted from a Dockerfile ARG
                                     # (built image stale; auto-run as a non-fatal preflight of `up`)

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
- **env-update tests**: `bash bin/tests/env-update.test.sh` — 749+ tests across 112 sections (fetchers, cache, semver, apply, args, RESOLVED, --reference…); use `--dry-run --filter=<VAR>` for quick preview; `--offline` is not implemented (use `_GS_EU2_HTTP_FIXTURE_DIR` seam for deterministic offline testing)
- **Shell scripts**: `shellcheck <file>` and `shfmt -d -i 2 -ci -bn <file>` (diff mode)
- **YAML files**: `yamllint -d relaxed <file>` and `yamlfmt -dry <file>` (dry-run mode)
- **Formatting**: `/fmt --check` to preview all formatting changes, `/fmt` to apply them
- **Compose validation**: `docker compose --env-file .env.local config` or `make generate-buildx`
- **Health check status**: `ls tools/successes/` (healthy) and `ls tools/errors/` (failed)
- **env-update cache**: `/tmp/global-stack-env-update-cache/` (TTL 3600s); use `--no-cache` to bypass
- **Startup script dry-run**: `GS_STARTUP_DRY_RUN=1 bash docker/config/dist/bin/nvm-bin/global-stack-nvm-start.sh` — exits before any install; tests the prologue loads and script parses. In containers: PATH includes `/usr/local/bin`; on host: prepend `PATH="/stack/docker/config/dist/bin/base-bin:$PATH"`.
- **Shared prologue**: `docker/config/dist/bin/base-bin/global-stack-base-prologue.sh` — defines `stackCatch` + `trap` for all startup scripts (49 scripts source it). Excluded: caddy/httpd/nginx server scripts, android-setup, localstack, selenium-chrome/firefox, serverless, and utility helper scripts (deliberate 141/1-exempt variant).
- **Startup prologue tests**: `bash bin/tests/startup-prologue.test.sh` — covers prologue syntax/shellcheck, `bash -n` on all 49 sourcing scripts, `GS_STARTUP_DRY_RUN=1` exit-early, `stackCatch` error token writing and clean-exit no-op.
- **PreCompact handoff tests**: `bash bin/tests/precompact-handoff.test.sh` — 37 assertions over `scripts/claude-bootstrap/hooks/precompact-handoff.sh`: the always-exit-0 contract on every failure path, git + `tools/` health blocks, verbatim user-intent extraction, harness-turn noise filtering, `jq -Rrs` encoding, and the `GS_HANDOFF_DIR` override.

> **In a remote container, lint manually — the hooks are dead.** `shellcheck`, `hadolint`, `yamllint`, `shfmt` and `yamlfmt` are **not installed** in the remote Claude container, so the five `PostToolUse` hooks and both `/lint` and `/fmt` silently no-op there. They work on the developer's machine. To gate a container session properly, fetch static binaries once into a scratch dir and run them explicitly at the project's own threshold — `shellcheck -x -S warning -f gcc <file>` (matching `.claude/hooks/shellcheck-on-write.sh`, so info-level SC2015/SC2016 are correctly below the bar) and `shfmt -l -i 2 -ci -bn <file>`. `bash -n` is always available and catches syntax errors with no install at all.

## Claude Code Tooling

**Slash commands** (type `/command` in any session):
- `/lint` — shellcheck all scripts + hadolint all Dockerfiles
- `/fmt` — format shell scripts (`shfmt`) and YAML files (`yamlfmt`); supports `--check`, `--sh`, `--yaml`
- `/check-versions` — v2 `--check` across all fetcher types (dockerhub, github, ghcr, npm, pecl, pypi, quay, rubygems, sdkman, sdkmanager, url, codeberg); no v1 fallback
- `/validate` — compose config + env consistency + COMPOSE_FILE + tier deps
- `/stack-health` — health markers, container status, version markers
- `/env-diff` — show divergences between `.env` and `.env.local`
- `/service-info <name>` — deep-dive on one service (compose, Dockerfile, startup, health, ports, versions)
- `/debug-service <name>` — read-only 6-step runbook on a failing service, ending in a root-cause hypothesis
- `/new-service <name>` — scaffold a new service (Dockerfile, compose, startup script, printed `.env` + Makefile lines)
- `/bump-versions` — guided `env-update` check → approval gate → apply → `env-scan` propagation → rebuild reminder

**Workflow + review skills** (ported from the developer's bundle, adapted to `/stack` — all repo-native under `.claude/skills/`, no install):
- `/ask-human` — the plain-text question protocol (see § "Questions are plain text"). **Not optional reading**: it is the only sanctioned way to ask anything
- `/handoff` — save session state so the next session resumes cleanly
- `/pre-commit` — analyse staged changes for blast radius + produce the evidence table before committing
- `/sweep` — Phase 6 second sweep over uncommitted changes
- `/expanding-context` — widen context at the start of Phase 1 before committing to an approach
- `/converge` — run § "Certification ladder" mechanically: 3 reviewer lenses, two consecutive clean rounds, cap 5. Autonomous by default; honours the STANDARD carve-out for docs-only diffs
- `/retrospective` — deliberate end-of-session learning capture into `var/claude/memory/`
- `/forge` — adversarial design critique with the Chesterton's Fence gate (a fence whose WHY is in § Gotchas is never challenged)
- `/sleuth` — hunt hidden behavioural bugs: silent failures, logic traps, contract violations
- `/inspect` — full project health inspection (security, dead code, deprecations, error handling)
- `/gaps` — find incomplete implementations, stubs, TODO markers, unfulfilled promises
- `/cross-check` — validate a spec or doc for contradictions, undefined terms, unstated assumptions
- `/aggregate-findings` — deduplicate and synthesise findings across the review skills above

> **There is no `~/.claude/refs/SKILLS.md` and no `~/.claude/skills/` in a remote container** — the bundle's 48 global skills are not installed there, so the global commands this file used to list (`/bundle`, `/install`, `/adapt-project`, `/repair`, `/mega-analysis`, `/skill-audit`, `/memory-promote`, `/recent`) are **unavailable in container sessions**. They still work on the developer's machine, where the bundle is installed. `/recent` in particular is redundant here: the PreCompact handoff already emits git state, uncommitted paths and recent commits automatically.
- `/new-service <name> [--parent <image>] [--runtime <name>] [--port <n>]` — scaffold a new service (Dockerfile, compose, startup script, printed `.env` + Makefile lines); args-first with interactive fallback

**Automatic hooks** (PostToolUse on Edit/Write):
- `shellcheck` — lints `.sh` files on every write
- `hadolint` — lints `Dockerfile*` files on every write
- `yamllint` — validates `.yaml`/`.yml` files on every write
- `shfmt` — checks shell formatting on `.sh` writes (reports diff, doesn't auto-fix)

**Automatic hooks** (SubagentStop):
- `subagent-stop-reminder` — fires when a subagent completes; reminds parent to verify Phase 7/8

**Permission rules** (two layers): the project `.claude/settings.json` denies destructive operations (`make hard-restart*`/`soft-restart*`, `sudo`, `rm -rf`, `docker system prune`/`volume rm`/`volume prune`/`container prune`/`image prune`/`network prune`/`rmi`/`compose down -v`, `git clean`, `git push --force`, `chmod 777`, Bash access to `docker/data`/`docker/storage`, Read access to `docker/data`/`docker/storage`/`var`), asks for stack lifecycle (`make up/down/restart`, `env-update --apply`, `docker buildx prune`) and allows read-only previews (`env-update --check/--dry-run/--dump`, `env-scan --dry-run`, `make log-*`). Additional read-only allows (`docker compose ps/logs`, `shfmt`, `yamlfmt`, `yamllint`, `yq`, `diff`) live in the global `~/.claude/settings.json` layer — a bundle of this project carries only the project layer.

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
- **`tools/versions/` markers** control reinstall — all are **content-compared** by the `gs_version_gate` helper (in `base-bin/global-stack-base-prologue.sh`): when a marker's content differs from the current env version, reinstall triggers automatically **with a loud WARN** (no manual marker deletion needed). This covers managers, tier-03 per-version markers (`node.24`, `php.8.4`, …), and per-package slot markers (`<rt>.<AS>.pkg.<slot>`). Deleting a marker still forces reinstall, and `GLOBAL_STACK_RELOAD_*=true` forces a full unconditional one. Note: `make down` clears `successes/`+`errors/`+`locks/` but NOT `versions/`, so these markers persist across restarts as designed. `php.edge` (branch `next`) is now SHA-tracked: its `@todo env-update` annotation uses `(use-sha) (version-prefix:github.com/php/php-src@) github:php/php-src`, so `env-update` resolves php-src HEAD → `GLOBAL_STACK_PHPEDGE_VERSION=github.com/php/php-src@<sha>` (phpbrew builds that commit `as php-master`). Because the main `php.edge` marker is the invariant install dirname (`php-master`), drift is detected via a SIDECAR marker `tools/versions/php.edge.build` (holds the resolved build ref); on a SHA change the edge gate WARNs, cleans the `php-master` dirs + markers, and rebuilds. Manual `RELOAD` is no longer required for edge upstream drift
- **`docker-bake.local.json` is generated, not tracked** — if it's stale after env changes, run `make generate-buildx` to regenerate. Stale bake file = wrong build config
- **BuildKit cache can go stale** — if builds fail with mysterious layer errors, `docker buildx prune` is the escape hatch
- **Bash-written files bypass all PostToolUse hooks** — linting (shellcheck, hadolint, yamllint), formatting (shfmt), and backup only fire on `Edit`/`Write` tool calls. Files written via `cat >`, heredocs, `sed -i`, or other Bash redirects are invisible to hooks. Always use the `Write` or `Edit` tool when hook coverage matters.
- **`core.fileMode=false` in `/stack/`** — git ignores all file permission changes; `chmod` edits take effect on disk but are never staged or committed. For permission fixes, note the change explicitly in the commit message of whatever else touches the file; do not expect `git diff` or `git status` to show the mode delta.
- **Auto-commit in /stack sessions** — see § "Git autonomy" above, which is authoritative: `git add`/`commit`/`push` to `master` are autonomous, pushes use plain `git push` (never `-u`), and the commit identity is fixed. Kept as a pointer rather than a restatement so the two cannot drift.
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

Use `/debug-service <name>` — executes the 6-step runbook read-only and reports a root-cause hypothesis with suggested next actions. Quick manual checks:

```bash
ls tools/errors/                          # Which error tokens exist?
make log-follow-<service>                 # Tail container logs
make login-<service>                      # Shell into container (if running)
ls tools/successes/ | grep <tier02-name>  # Check tier 02 manager health
# Nuclear: set GLOBAL_STACK_RELOAD_<RUNTIME>=true in .env.local, restart, then reset to false
```

## Claude Code Configuration

Claude Code's configuration for this project lives in:

```
~/.claude/CLAUDE.md                      # Global reasoning framework — INSTALLED BY THE BOOTSTRAP
~/.claude/THINKING.md                    #   in a container (empty otherwise); on the dev's machine
~/.claude/BLAST-RADIUS.md                #   these come from his own bundle install
~/.claude/hooks/log-helpers.sh           # log_obs() — sourced by the .claude/hooks/* scripts below
~/.claude/settings.json                  # Global settings (model, plugins) — never touched by this repo

claude-setup/claude-setup-global.tar.gz  # The dev's machine bundle: PROVENANCE for the three docs above
scripts/claude-bootstrap/                # Restores the framework into the ephemeral container
  README.md                              #   provenance table + what was deliberately NOT imported
  install.sh                             #   SessionStart hook; idempotent `cp -u`, one-directional
  CLAUDE-global.md                       #   bundle framework + the /stack adaptation header
  THINKING.md                            #   bundle, byte-identical
  BLAST-RADIUS.md                        #   bundle + the /stack blast-radius table
  apply-pending-settings.sh              #   dev-side applier for settings.json.pending
  settings.json.pending                  #   only present when a settings change is awaiting the dev
  hooks/precompact-handoff.sh            #   PreCompact hook -> var/claude/handoff/latest.md
  hooks/log-helpers.sh                   #   log_obs(), never fatal (framework Rule 13)
bin/tests/precompact-handoff.test.sh     # 37 assertions over the PreCompact hook

.claude/settings.json                    # Project permissions + hooks — CLAUDE CANNOT WRITE THIS
.claude/settings.local.json              # Local UI preferences (gitignored)
.claude/agents/                          # Agent definitions (project-scoped)
  global-stack-lead-dev.md               #   /stack infrastructure orchestrator
  stack-infra-reviewer.md                #   ladder lens 1: correctness + regression
  completeness-reviewer.md               #   ladder lens 2: completeness + blast radius
  reproducibility-reviewer.md            #   ladder lens 3: clean-clone + destructive posture
.claude/hooks/                           # PostToolUse + SubagentStop hook scripts
  shellcheck-on-write.sh                 # Lint .sh files on write        }
  hadolint-on-write.sh                   # Lint Dockerfiles on write      } all five silently
  yamllint-on-write.sh                   # Validate YAML on write         } no-op in the remote
  shfmt-on-write.sh                      # Check shell formatting         } container — the tools
  env-guard-on-write.sh                  # Guard .env edits               } are not installed there
  subagent-stop-reminder.sh              # SubagentStop: remind parent to verify Phase 7/8
.claude/skills/                          # Slash skill definitions (read in place, no install)
  lint/  fmt/  check-versions/  bump-versions/  validate/  stack-health/
  env-diff/  service-info/  new-service/  debug-service/            # domain skills
  ask-human/  handoff/  pre-commit/  sweep/  expanding-context/     # workflow skills
  converge/  retrospective/                                         #   (converge runs the ladder)
  sleuth/  inspect/  gaps/  forge/  cross-check/                    # review skills
  aggregate-findings/                                               #   (synthesises the above)

var/claude/handoff/                      # PreCompact handoffs (gitignored via the blanket /var rule)
```

## File Layout Quick Reference

See `templates/tips/file-layout.md`.

---

> **Core Operating Rules 6 & 7** (Completion Gate and TDD) are defined in the global `~/.claude/CLAUDE.md` and apply here without exception.

> **Remember**: Delegate /stack infrastructure tasks to `global-stack-lead-dev`; handle non-/stack tasks directly with the global reasoning framework. Use `/lint` before committing shell changes — and in a container, lint manually, because the hooks are dead there. Check for trailing `;` in `COMPOSE_FILE`. Verify with `--dry-run` before applying changes. Tier 02 = install, tier 03 = setup — same startup script, different `MODE`.

> **And on every single reply, without exception**: ask in **plain text** (never `AskUserQuestion` — it times out here), work on **`master`** only, and end with a **`❓ QUESTION` / `⏹ NO QUESTION`** marker as the literal last line.
