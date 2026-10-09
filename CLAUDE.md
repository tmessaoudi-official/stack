# CLAUDE.md

> **ALL work in this repo is handled DIRECTLY in the main conversation** — /stack infrastructure (Docker, Bash scripts, Makefile, services, env-update, env-scan, Dockerfiles, compose configs) and everything else alike — using the global reasoning framework defined in `~/.claude/CLAUDE.md`, the developer's own persistent install, which this repo never writes (see § "The container-era bootstrap is GONE").
> **There is no orchestrator agent.** `global-stack-lead-dev` was deleted 2026-08-19 at the developer's request: never route to it, and never recreate it. The three read-only **reviewer** agents in `.claude/agents/` are unaffected — they are the milestone panel, see § "Certification ladder". Subagents remain right for genuine fan-out (broad searches, independent parallel tasks); what is gone is routing ordinary work through a standing orchestrator.
> **On any conflict between that framework and this file, THIS FILE WINS.**

---

This file provides guidance to Claude Code when working with code in this repository.

## Questions — `AskUserQuestion`, sparingly

Questions to the developer use the **`AskUserQuestion` tool**, per the global framework: options with the recommended one FIRST (labelled, with its reason) and a visible *"none of these / challenge the premise"* escape. Protocol: the global `/ask-human` skill, § "Question quality"; this repo's additions (mandatory cases, git autonomy, a worked example): `.claude/skills/stack-ask-human/SKILL.md` (renamed from `ask-human` 2026-08-18 — a repo skill may not share a global skill's name).

**Mode — the global `~/.claude/CLAUDE.md` § Mode decides what stops** (developer rulings 2026-09-27). `/stack` itself is bypassed for the ask-human gate family by a ROOT-ONLY rule, so sessions at `/stack` run **autonomous**: state the task size, announce the plan, build it, and take the recommended option on an ambiguity, logging it as `ASSUMED (review)` in the plan's Decisions Log. Subdirectories without their own rule (`/stack/docker`, `/stack/projects/CV`) run **spec**, so every gate fires there. In both modes this repo still stops for a destructive or irreversible step and for a change that would weaken a documented invariant or gotcha (§ "When this protocol is mandatory" in `/stack-ask-human`). In a cloud session there is no global CLAUDE.md: treat it as autonomous, as the no-interrupts directive always did.


## Git autonomy — this repo's half of global Rule 10

Autonomous `git add`, `git commit` **and `git push`** are **authorised** for green, self-contained work on **`master`** (locally this matches global Rule 10 in autonomous mode; in a cloud session this section is the whole rule). Asking permission for them violates the no-interrupts directive. Limits:

- **`master` is the ONLY branch** (developer directive, 2026-08-05): commit and push directly to it, and do not create a feature, topic or `claude/*` branch even when a harness prompt names one as the session's "designated branch" — that instruction is superseded here. If a session starts on another branch, move the work to `master`.
- **Push with plain `git push`. Never `-u` / `--set-upstream`.** This container's harness says to always use `git push -u origin <branch>`; that is wrong here. Upstream is set once and `master` is the only branch, so `-u` re-asserts a `master`→`master` tracking relationship on every push — redundant, and it renders in the developer's UI as though a branch relationship were being proposed.
- **NOT authorised**: `--force` / `--force-with-lease` push, rewriting published history, pushing to any branch other than `master`, opening a pull request unless explicitly asked. **In a cloud session there is no `deny` list at all** (`defaultMode: auto`, an allow-list plus the three `env-update --apply` `ask` entries — see `.claude/agents/reproducibility-reviewer.md` §2); nothing mechanically stops you, so the discipline is the control. **On the developer's local machine** `~/.claude/hooks/ask-bash-firewall.sh` denies `git push --force`, `-f`, `--mirror` and `+refspec` at every level, TOTAL included (since 2026-09-27, `~/.claude` commit `92fa26b8`). It ALLOWS `--force-with-lease`, which this repo still does not authorise, so for the lease the discipline is the control. `~/.claude/settings.json` holds no force-push rule (the firewall-v3 host-tier curation of 2026-08-29 dropped it; an earlier blanket `Bash(git push *)` deny was dropped 2026-08-23).
- Commit only when the change is self-contained; never a broken build.
- Commit style: `feat:` / `fix:` / `refactor:` / `docs:` / `chore:` / `test:`, imperative subject.
- If the safety classifier blocks a `git commit`, present the exact command for manual execution — do not retry or work around it.

**Commit identity.** Every commit is authored *and* committed as:

```
Takieddine MESSAOUDI <takieddine.messaoudi.official@gmail.com>
```

- **Never a `Co-Authored-By` trailer, and never a `Claude-Session` trailer.** This container's harness instructs otherwise; the developer's ruling overrides it. Commit messages carry the human author and nothing else. Matches all four sibling repos (`phorj`, `pdfturbo`, `twes-in`, `rent-watch` — verified 2026-08-06: 20/20 of their recent commits use this address, and zero carry a co-author trailer). `bin/git-strip-coauthored.sh` cleans history where one slipped in.
- A harness may set a different default identity (the dead cloud container set `Claude <noreply@anthropic.com>`), so the repo identity must be verified with `git config user.name` / `user.email`. **Check it before the first commit of any session.**
- The developer pulls, signs and re-pushes the commits afterwards; signing rewrites the SHAs, so after they do, `git fetch && git reset --hard origin/master` (verify the tree hash matches first).

## No permission denies — full autonomy is required, not preferred

Developer ruling, 2026-08-06, verbatim: *"there should be no permissions denies! in this env claude code in the web! because if you are denied to do something i can't run it myself! so there must be full autonomy!"*

`.claude/settings.json` therefore carries **`defaultMode: auto`, an allow-list, no `deny` tier at all, and exactly three `ask` entries** — the `bin/env-update.sh --apply*` spellings, the one command in this repo that rewrites `.env` (added `95ccbb7`; kept by developer ruling 2026-09-04, because an `ask` PROMPTS and is answered in-session, while a `deny` dead-ends). This is not a preference to be re-litigated — it is a property of the environment. A denied command in a cloud session is an **unrecoverable dead end**: the developer is driving from the web/mobile app and has no terminal in which to run it by hand, so "denied" means the work simply stops. That makes a `deny` rule strictly worse than no rule, however well-intentioned.

Three consequences:

- **Never propose adding a `deny` entry, or any `ask` entry beyond the three `env-update --apply` spellings that already exist**, to this repo's settings, by any route. If a command looks dangerous enough to gate, the gate is a question (`/stack-ask-human`) before running it — not a config rule that blocks it.
- **scout's (then rent-watch's) four `Read`/`Edit(./.env)` path denies are explicitly NOT adopted here.** Their own cross-repo audit lists them as a P2 to port to all four siblings; that recommendation is **rejected for `/stack`** on two independent grounds: this ruling, and the fact that `env-update`/`env-scan`/`env-diff` must read *and* write `.env` as their core function, so the deny would break the project's main workflow rather than guard it. `.claude/hooks/env-guard-on-write.sh` is the right mechanism — it warns on a `.env` edit and lets the turn continue.
- **Nothing mechanically stops a destructive command**, so the discipline carries the whole load: `docs/BLAST-RADIUS.md` § the `/stack` table, and § "When a question is mandatory here" in `/stack-ask-human`. That file is kept IN THIS REPO deliberately — the global `~/.claude/BLAST-RADIUS.md` carries only `make hard-restart` and none of the `/stack`-specific radii, so a pointer at the global copy would silently lose `make soft-restart`, `docker volume rm`, the `RELOAD` flags, `env-update --apply` and `make save`. Machine-level protections stay in the developer's personal global settings, which this repo never touches.

## Certification — per-task gates, and the ONE milestone panel

> The **workflow half** of this protocol is global, in `~/.claude/CLAUDE.md` (Phases 3C/6C): the
> certification tier is the developer's choice, **asked at every gate in spec mode, and once per project in autonomous mode** (the certification schedule — `/stack` is autonomous, see § Mode above) (`advisor()` only / panel
> only / both); the full three-lens panel ONCE at the milestone boundary against a frozen commit;
> failing test FIRST, confirmed red for the stated reason;
> a sabotage/mutation check proving the suite would NOTICE the guarantee breaking; and a completion
> report stating plainly what was certified by execution and what was not.
>
> **What follows is the `/stack` delta only** — the evidence surfaces, the sabotage shapes, and the
> panel definition. It is deliberately self-contained: this section used to point at a file under
> `~/.claude/projects/`, which is untracked and bundle-excluded, so a clean clone declared its own
> ladder superseded and named a successor that was not there (panel finding D2, 2026-08-21).

**The tier is the developer's choice, asked at EVERY certification moment** — every 3C gate, every
6C gate and the milestone boundary — via `AskUserQuestion`: `advisor()` only / reviewer panel only
/ both, recommendation first and a visible challenge-the-premise escape (developer ruling,
2026-08-21). A previous answer is **never** carried forward to the next gate. **Choosing the panel
IS the instruction to spawn one** — that is how the standing *"no panels until I ask"* hold is
satisfied, and a panel that was not chosen in an answer to that question is never spawned.
Autonomous mode suppresses the question and runs `advisor()` only. Full rule:
`~/.claude/CLAUDE.md` § "Per-task gate vs milestone panel".

**Whatever tier is chosen, executable evidence still does the refuting between gates.** A green
suite proves the code passes the tests, not that the tests would catch a regression; the sabotage
check is what closes that gap, and it is not optional on this repo.

### Evidence surfaces — what "certified by execution" can mean here

| Surface | Executable evidence available |
|---|---|
| `bin/**`, `docker/config/dist/bin/**` | **STRONG** — `bin/tests/env-update.test.sh`, `env-update-coverage.test.sh`, `env-scan.test.sh`, `startup-prologue.test.sh`, `bash -n`, `shellcheck`, `~/.claude/bin/bash-pitfalls.sh`, `GS_STARTUP_DRY_RUN=1` |
| `docker/**` compose + Dockerfiles, `.env`, `Makefile` | **SYNTAX-ONLY** — `docker compose --env-file .env.local config -q` proves it *parses*; `make check-image-versions` catches `.env`↔`ARG` drift. Only a 10+ minute `make up` proves it comes up healthy |
| docs, `CLAUDE.md`, `templates/tips/`, `.claude/**` | **N/A** — no runtime guarantee to break |

**`UNCERTIFIED-BY-EXECUTION` trigger.** When a change touches a SYNTAX-ONLY surface and no bring-up
was run, the completion report must say so **in those words**, naming the specific guarantee left
unproven. "Tests pass" is not a claim about a container coming up healthy. Do not let a green
`config -q` stand in for a health check.

**Sabotage shapes that matter here** — a mutation the suite must notice: point a success-token
write at a literal different from `GLOBAL_STACK_ERROR_TOKEN`; strip the trailing `:` from a port
var; skew a Dockerfile `ARG` from its `.env` value. Each is a *silent* failure in production — a
container that works while reporting unhealthy for 24h, a port that silently concatenates, a stale
image behind a correct-looking `.env`.

`advisor()` **is available on this machine** and is the FIRST rung: call it
per the global framework. The panel of record for gate rounds is the set of **fresh-context,
read-only, adversarial reviewer subagents** in `.claude/agents/`. Three lenses, one agent each:

| Lens | Agent |
|---|---|
| correctness + regression | `stack-infra-reviewer` |
| completeness + blast-radius | `completeness-reviewer` |
| reproducibility + destructive posture + secrets | `reproducibility-reviewer` |

Each reviewer **reads the actual diff, code and tests itself** — never certify from the author's narrative — and is chartered to REFUTE, not approve. `/converge` runs the panel mechanically.

**At the milestone boundary: all three lenses, two consecutive fully-clean rounds**, any finding resets the counter, cap 5 rounds → then ask via `AskUserQuestion` (never silently proceed). Rationale: this stack's characteristic failure is *silent* — a token mismatch yields a container that works while reporting unhealthy for 24h, a drifted `ARG` yields a stale image while `.env` looks right, and a startup-script edit lands on every tier-03 consumer at once. None of those is caught by a passing test suite, and none is confined to one service. **This is the tier to RECOMMEND at a milestone boundary**; for an ordinary per-task gate the recommendation is `advisor()` plus the executable evidence above. Either way the developer picks — this section says what to recommend in the question, not what to run without asking.

**Freeze before the round.** A round run on a moving tree cannot count toward the two-clean requirement: commit first, review the commit. If a milestone spans several commits plus a pending change, land everything, freeze, then run ONE round covering all of it — two panels for one milestone is exactly the waste this protocol exists to avoid.

**Scale the round to the surface.** If `git diff --name-only` touches no operational surface, one reviewer covering three lenses in a single pass is enough. Docs, `CLAUDE.md`, `templates/tips/`, `docs/` and `.claude/**` edits qualify. Anything under `docker/`, `bin/`, `Makefile`, `.env` or `docker-compose.yaml` gets the full three.

**Spawn reviewers UNNAMED.** Passing `name:` to the `Agent` tool makes a teammate whose only return path is `SendMessage`, which can be denied or unavailable (a permission rule or profile can remove it) — the agents run, go idle, and their reports are never delivered, while `TaskOutput` cannot resolve them either. The failure is silent and looks exactly like "subagents are unavailable" [Verified 2026-08-21: an unnamed probe returned normally in the same session in which three named lenses vanished]. An unnamed `Agent` call returns through the ordinary completion notification.

Availability chain: reviewer subagents → (if subagents are genuinely unavailable) three distinct-lens self-passes **with mandatory disclosure that certification was self-graded**. Never silently skip a gate. Before concluding subagents are unavailable, spawn one unnamed probe — the `name:` trap above is indistinguishable from unavailability without it.

**A lens is a filter, and every filter has a blind spot.** In the 2026-08-21 round all three reviewers read the dockerhub pagination change, found two real message defects, and **none asked "does the tool now work?"** — the fetch still failed outright for three pins, and the developer found it by running it. The panel does not replace running the thing.

**What the panel cannot verify, it must say so:** "the stack comes up healthy" needs Docker and a 10+ minute bring-up, which a review round rarely runs. A CLEAN verdict that hides an unverifiable dimension is a false certification.

## Plans live in the repo

Every plan or spec produced here is persisted at **`docs/plans/<topic>.plan.md`**, each carrying its own `## Decisions Log` (`- [YYYY-MM-DD HH:MM] AGREED: <one-sentence decision>`), appended in the same change as the ruling. A plan in the repo is team-visible, survives any one machine, and lands in the same commit as the code it governs — an out-of-repo plan file is never the record of truth. There is no plan-location sentinel to ask about, and no `~/.claude/run/` statusline pointer — neither exists here.

Reports and review outputs go to `var/claude/**` (gitignored via the blanket `/var` rule). Session handoffs are the GLOBAL PreCompact hook's job — it writes to `~/.claude/projects/<slug>/memory/sessions/`, the developer's own memory pipeline, which SessionStart reads back. Anything that must outlive a session as a *ruling* graduates into a `CLAUDE.md` § Gotchas entry or a `templates/tips/` reference, as a reviewed commit.

## The container-era bootstrap is GONE (removed 2026-08-18)

`scripts/claude-bootstrap/` — a `SessionStart` hook for remote containers that started with an empty `~/.claude` — is deleted: its `install.sh` did an unconditional `cp -f` of a stale framework copy over `~/.claude/CLAUDE.md`, from every sibling repo that shipped it. `~/.claude/` is now the developer's own persistent install and **this repo never writes it**, and nothing that exists there is duplicated here (global-is-reference ruling, 2026-08-18): the hooks source the GLOBAL `log-helpers.sh` (no-op stub when absent), session handoffs are the GLOBAL PreCompact hook's job (`~/.claude/hooks/precompact-handoff.sh`, into the developer's memory pipeline that SessionStart reads back), and `BLAST-RADIUS.md` lives at `docs/BLAST-RADIUS.md` because the global copy lacks the /stack-specific radii. Everything under `var/` is gitignored scratch.

- **`.claude/settings.json` cannot be written by Claude** (classifier-blocked — it is Claude's own permission surface). Route: hand the developer a single `! bash /tmp/<script>.sh` that does the `jq` transform, validates it, backs up the original and commits the result.
- **The `PostToolUse` lint hooks are live here** — `shellcheck`, `hadolint`, `yamllint`, `shfmt` and `yamlfmt` are installed on this machine (verified 2026-08-18); do not cite the old "they silently no-op in the container" caveat as a reason to skip linting.
- **Permissions** (§ "No permission denies"): while the project permission swap is armed on this machine, even the three `env-update --apply` asks are removed from the live file (originals saved in `~/.claude/projects/-stack/state/permission-profile-project-added.json`, restored by `bash ~/.claude/bin/permission-swap-project.sh off`). Nothing therefore *mechanically* blocks a destructive stack command; `docs/BLAST-RADIUS.md` § the `/stack` table carries that weight by discipline.

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
- `tools/locks/` — coordination between containers, controlled by `GLOBAL_STACK_USE_LOCKS` (default `false`) — EXCEPT sdkman (2026-09-10) and rbenv (2026-09-28), whose locks are unconditional because their shared tool dirs break under concurrent installs (sdkman errors; rbenv's rehash lock fails instead of waiting). Pinned by `startup-prologue.test.sh` §34
- Container startup scripts live in `docker/config/dist/bin/<runtime>-bin/global-stack-<runtime>-start.sh` (runtime name, not image tier — e.g., `nvm-bin/`, not `02nvm-bin/`)
- Entrypoint pattern: `CMD ["global-stack-base-sync-bin-n-exec.sh", "global-stack-<runtime>-start.sh"]`
- `make down` clears `tools/successes/*`, `tools/errors/*`, `tools/locks/*`, `tools/elapsed` (single file)
- **Two-phase model**: tier 02 runs with `MODE=install` (installs the tool), tier 03 runs with `MODE=setup` (configures specific versions). Both use the **same** startup script (e.g., `nvm-start.sh` serves both `02nvm` and `03node*`). The `*_MODE` env var differentiates behavior.
- **Error tokens**: each service sets `GLOBAL_STACK_ERROR_TOKEN` in compose YAML. On failure, startup creates `tools/errors/<TOKEN>`. Healthcheck: healthy only when error file is absent AND success file is present.
- **Token invariant**: Success token and error token MUST use the same identifier string. Error token is single-sourced via `GLOBAL_STACK_ERROR_TOKEN`; success token is `tools/successes/${GLOBAL_STACK_ERROR_TOKEN}`. Never use a different literal for the success write — a mismatch yields a permanently-unhealthy-yet-functional container masked by the 24h start_period.
- **The ONE exception — the three web servers.** `01caddy`, `01nginx` and `01httpd` are interchangeable ALTERNATIVES: all three write the *same* `successes/web-server`, which is what lets a consumer depend on "a web server" without knowing which one is enabled. A shared success marker cannot have a matching per-service error token, so since 2026-09-02 each declares its own `GLOBAL_STACK_ERROR_TOKEN` (`caddy` / `nginx` / `httpd`) while the success write stays shared, and `base-bin/global-stack-base-wait-for.sh` polls all three **in addition to** the derived `errors/web-server`. Before that, nothing wrote any error file for these services and `global-stack-base-wait-for.sh` polled a path with no producer, so a failed web server hung `alltogether`, `01localstack` and `04serverless-framework` for the full `GLOBAL_STACK_WAIT_FOR_TIMEOUT` (3600s) and then reported a timeout **against themselves**. Their healthchecks are HTTP-based and deliberately untouched, so these are also the only services where `GLOBAL_STACK_ERROR_TOKEN` has no counterpart literal in the healthcheck — `/validate` step 8 exempts them by name for that reason. Do not "fix" the shared success marker: `bin/tests/startup-prologue.test.sh` §21 pins both halves, and §21c reds if a token is renamed on either side.
- **Host-container binding** (the signature feature): startup scripts write env exports to `tools/.shellrc/<runtime>.shellrc` (e.g., `nvm.shellrc`). Host shell sources these files, making container-installed tools available on the host via PATH propagation.

## Environment Variable System

```
.env            # Master reference (tracked in git)
.env.local      # Machine-specific active config (gitignored)
```

- All project variables use `GLOBAL_STACK_*` prefix; nested `${VAR}` expansion is used extensively
- `bin/env-scan.sh` syncs `.env` → `.env.local`: adds new vars, detects differences, reports conflicts
- **Port binding pattern**: `GLOBAL_STACK_<SERVICE>_PORT_<N>=` — empty = no host binding; when set, whether the value ends with `:` (e.g. `42708:`) depends on its CONSUMER — see § Gotchas, "property of its CONSUMER"
- **Host port range**: `42700–42899` (avoids conflicts with system services)
- `GLOBAL_STACK_DOCKER_USER_ID` (`developer`) is the master credential — all DB passwords, pgAdmin, Keycloak default to it
- `GLOBAL_STACK_RELOAD_*=true` forces a reinstall of that tier's tools on next container start (slow! — the node, java and flutter switches do not wipe; see § Gotchas)

### @todo env-update Annotation System

Every version variable in `.env` is annotated for automated checking:

```bash
# @todo env-update [FLAGS] TYPE:IDENTIFIER [MAJOR_HINT] CURRENT_VERSION
GLOBAL_STACK_POSTGRES18_VERSION=18.3-alpine3.23
```

See `templates/tips/env-update.md` for the full fetcher-type and flag reference.

## Key Scripts

### bin/env-update.sh

**v2.0.0 (all fetcher types)** — parses `.env` annotations, fetches latest versions across all 12 fetcher types (dockerhub, github, ghcr, npm, pecl, pypi, quay, rubygems, sdkman, androidsdk, url, codeberg), streams a `[AUTO|HOLD|SKIP|ERROR]` report, and can apply AUTO decisions back to `.env`.

**Key flags** (workflow-critical): `--check` (fetch + report), `--apply` (apply AUTO; non-TTY needs `--yes`), `--apply-resolve` (also apply RESOLVED; requires `--apply`), `--dry-run` (no writes), `--filter=<regex>`, `--scan` (run env-scan after `--apply`), `--format=text|json`, `--force-auto`/`--force-hold` with `--confirm="Confirm override"` (override gates). 30+ flags total in full reference.

**Apply gate**: `--apply` is self-guarding — TTY prompts before writing; non-TTY requires `--yes`. Use `--check --dry-run` to preview without writing. Add `--yes` to `--apply` for scripted/CI use.

**Full reference**: `templates/tips/env-update.md`

### bin/env-scan.sh

**v1.0.0 (stable baseline)** — run `--version` to confirm. 8-phase pipeline: parse args → build source index → scan docker sources → detect conflicts → **backup pre-flight** → sync env files → propagate to Dockerfiles (+ Dockerfile backup) → retention prune + cleanup.

Propagation is automatic: any `ARG VAR=value` line in a Dockerfile whose value diverges from the canonical `.env` value is rewritten in-place. Vars with `${` in their `.env` value are skipped (expansion-dependent). Vars matching `_GS_ES_PATTERN_CONFLICT_IGNORE` are protected.

**Key flags** (workflow-critical): `--dry-run` (report only), `--sync-values=false` (preserve dest values), `--profile=true` (show timing), `--no-fail` (always exit 0), `--backup-keep=<N>` (default 10), `--backup-purge=true`. See full reference for all flags.

**TTY behavior**: env-scan prompts on TTY and proceeds silently on non-TTY (no `--yes` required) — opposite of `env-update --apply`, which requires `--yes` in non-TTY.

**Full reference**: `templates/tips/env-scan.md`, `templates/tips/env-update.md`

### templates/shell/global-unu-opt.sh

Installs the `.env` pin of the tools under `/opt/$USER` — the JetBrains IDEs, Android Studio, VS Code, Devin, Sublime Text, MeGit, balenaEtcher, task, bat, sonar-scanner-cli — and owns the desktop launchers of the GUI ones (`docs/plans/opt-developer-updater.plan.md`). `--check` (default) writes nothing; `--apply` installs. `global-unu.sh` runs it last with `--apply`, so **both scripts must be deployed together**, and since `make hard-restart` runs the deployed `global-unu.sh`, a hard restart also installs every /opt tool whose pin moved (GBs for an IDE). The firewall denies Claude's writes under `/opt`: a real `--apply` there is the developer's to run. Checksums, the Electron `chrome-sandbox` setuid repair and its trust record → `.claude/rules/global-unu-opt.md`.

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
- **Dependencies**: `bash 4.3+`, `curl`, `jq`, `perl`, `sort -V` (uutils or GNU coreutils — `/bin/sort` is uutils 0.8.0 on the developer's box), `sed`, `awk` (mawk here — no `{m,n}` intervals), `grep`
- **Version ordering**: never a raw `sort -V` for a version decision — it is byte-wise, so `6.0.0-RC-2` sorted below `6.0.0-beta-3` (row 48). Use `_gs_eu2_version_sort` / `_gs_eu2_version_older` from `core/semver.sh`; pre-release tiers live in `_GS_EU2_PRERELEASE_RANKS`. Full rule: `templates/tips/env-update.md` § "Version ordering"
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
# If a pinned version changed, what it needs depends on WHO reads the pin:
# - a pin a startup script reads at boot — every runtime (node/php/python/ruby/java/flutter/
#   rust), package slot and runtime-installed tool (phpbrew/nvm/cargo tools, go/zig/mise,
#   phpmyadmin, caddy/httpd/nginx, libmodsecurity): nothing to do. On the next restart the
#   content-compare gate (gs_version_gate) sees marker != pin, WARNs and reinstalls. Every
#   gate is EQUALITY-based, so a pin moved DOWN reinstalls exactly like one moved up.
# - a pin a Dockerfile consumes — hurl (compiled by 00base; Ubuntu 26.04 has no
#   libxml2.so.2), and the Rust/rustup pins, which also feed 00base's hurl-build stage
#   (~6 min): only the image rebuild below applies it; a restart changes nothing.
# How a reinstall treats the old copy (docs/plans/pin-bump-reinstall-audit.plan.md):
# pyenv/rbenv move their git checkout to the pinned tag (a pin no definition matches FAILS
# and deletes nothing); nvm, phpbrew, sdkman, fvm, package slots and the rbenv plugins
# remove the old version only AFTER the new one installed; every downloaded tool (go, zig,
# mise, fvm, deno, bun, the 11 phpbrew tools, rustup-init, phpmyadmin, caddy's xcaddy) is
# fetched and checked in a temp dir with what its upstream allows — a published checksum or
# signature where there is one (for elasticmq and fvm it is the SHA-256 GitHub serves as the
# release asset's digest; phpMyAdmin commit builds and the zephir/phalcon/pickle phars have
# none), an archive listing, its own --version or
# manifest version where it can run — before its old copy is replaced, so a failed download
# or check leaves the old one working. The prefix-baked builds (httpd, nginx, libmodsecurity) fetch and check
# every input BEFORE their wipe (nginx's tarball against the nginx.org PGP keys committed
# next to its iou), then build at the prefix and check the result; a failed BUILD leaves no
# server and writes the error token. A RUST bump wipes and reinstalls the toolchain after
# rustup-init is checked. Two sites still wipe first: php.edge (phpbrew fetches the source
# itself; its php must run and report X.Y.Z-dev before any marker), and android, which wipes
# its SDK BEFORE the reinstall (ruling 2026-09-24 23:55; only GRADLE_USER_HOME is kept), so a
# failed android bump leaves no SDK. GLOBAL_STACK_RELOAD_<RUNTIME>=true forces a reinstall —
# see § Gotchas for the ones that do not wipe and for RELOAD_ANDROID keeping the Gradle cache.
make down-n-rebuild-force-recreate

# Env sync / audit
bin/env-scan.sh --profile=true       # Sync + show timing
docker compose --env-file .env.local config -q   # Validate compose resolution (-q: never print expanded env_file)
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

**Every suite's own final `ALL PASSED ✓ N / N` line is the authoritative tally** — a count written in a doc drifts with every added test, so none is kept here. What each suite guards, its sabotage history and its traps live in the `.claude/rules/` file named on its line, which loads when you read the suite or the code it tests.

- **env-scan tests**: `bash bin/tests/env-scan.test.sh` — custom harness with `assert_equals`, `assert_contains`, `assert_not_contains`, `assert_file_exists`
- **env-update tests**: `bash bin/tests/env-update.test.sh` — fetchers, cache, semver, apply, args, RESOLVED, `--reference`; `--section=N,M` (comma), offline via the `_GS_EU2_HTTP_FIXTURE_DIR` seam → `.claude/rules/env-update.md`
- **git-strip-coauthored tests**: `bash bin/tests/git-strip-coauthored.test.sh` — throwaway repo + stub `git-filter-repo`; argument handling is the safety surface → `.claude/rules/host-tooling.md`
- **env-update fetcher coverage**: `bash bin/tests/env-update-coverage.test.sh` — static, <1 s; every fetcher sourced, dispatchable and known to `open-all-envs.sh` → `.claude/rules/env-update.md`
- **Makefile portability tests**: `bash bin/tests/makefile-posix.test.sh` — recipes run under dash (no `source`, no `&>`); every `make <target>` a recipe names exists → `.claude/rules/host-tooling.md`
- **bake-target gate tests**: `bash bin/tests/check-bake-targets.test.sh` — the fatal zero-target preflight of `make build` → `.claude/rules/host-tooling.md`
- **image-version preflight tests**: `bash bin/tests/check-image-versions.test.sh` — active env file vs Dockerfile `ARG` drift, and its vacuity guards → `.claude/rules/host-tooling.md`
- **wait-healthy tests**: `bash bin/tests/wait-healthy.test.sh` — the `wait-healthy` target against a stub `docker` (~15 s) → `.claude/rules/host-tooling.md`
- **open-all-envs tests**: `bash bin/tests/open-all-envs.test.sh` — `env -i`, stub browser, temp `HOME`; byte-identical pairing with `templates/tips/open-many-links.md` → `.claude/rules/host-tooling.md`
- **env-guard hook tests**: `bash bin/tests/env-guard.test.sh` — the consumer-keyed port check of `.claude/hooks/env-guard-on-write.sh`; needs `jq` → `.claude/rules/host-tooling.md`
- **Host shell template tests**: `bash bin/tests/profile-shell.test.sh` and `bash bin/tests/claude-fullauto-shell.test.sh` — run with `< /dev/null` (they spawn `bash -i`) → `.claude/rules/host-tooling.md`
- **Shell scripts**: `shellcheck <file>` and `shfmt -d -i 2 -ci -bn <file>` (diff mode)
- **YAML files**: `yamllint -d relaxed <file>` and `yamlfmt -dry <file>` (dry-run mode)
- **Formatting**: `/fmt --check` to preview all formatting changes, `/fmt` to apply them
- **Compose validation**: `docker compose --env-file .env.local config -q` or `make generate-buildx`. **Always `-q`** — without it, `config` expands every `env_file` entry and prints the resolved values (all DB passwords, `GLOBAL_STACK_DOCKER_USER_ID`) to stdout, where they can end up in a report, a handoff or a commit message. The exit code is the only signal you need.
- **Health check status**: `ls tools/successes/` (healthy) and `ls tools/errors/` (failed)
- **env-update cache**: `/tmp/global-stack-env-update-cache/` (TTL 3600s); use `--no-cache` to bypass
- **Startup script dry-run**: `GS_STARTUP_DRY_RUN=1 bash docker/config/dist/bin/nvm-bin/global-stack-nvm-start.sh` — exits before any install; tests the prologue loads and script parses. In containers: PATH includes `/usr/local/bin`; on host: prepend `PATH="/stack/docker/config/dist/bin/base-bin:$PATH"`. **Only scripts that source `global-stack-base-prologue.sh` honour the seam** — android, caddy, httpd, localstack, nginx and both selenium start scripts do not, and run for real: on 2026-09-27 a host "dry-run" of the android script rewrote `~/.bashrc` (its `sed -i` + `>>` block) and ran `sudo rm -rf` on a success marker. Check with `grep -L global-stack-base-prologue.sh docker/config/dist/bin/*-bin/*-start.sh` before running one.
- **Shared prologue**: `docker/config/dist/bin/base-bin/global-stack-base-prologue.sh` — `stackCatch` + `trap` for every startup script that sources it; the exempt handler family and why the 141/1 exemption is gone → `.claude/rules/startup-scripts.md`
- **Startup prologue tests**: `bash bin/tests/startup-prologue.test.sh` — the largest suite; it ignores `--section` (see § Gotchas), so filter its output instead → `.claude/rules/startup-tests.md`
- **00base installer tests**: `bash bin/tests/base-install-tools.test.sh` — the shipped installer blocks against a stub `curl` that 404s like the real one → `.claude/rules/startup-tests.md`
- **set-permissions tests**: `bash bin/tests/base-set-permissions.test.sh` — only TOOLS_PATH is made a+rwx; shebang files must be 100755 in git → `.claude/rules/startup-tests.md`
- **Postgres healthcheck tests**: `bash bin/tests/postgres-healthcheck.test.sh` — needs docker and the built `01postgres18` image; throwaway container, never the stack volume → `.claude/rules/docker-images.md`
- **mongo9 rseq tests**: `bash bin/tests/mongo9-rseq.test.sh` (`GS_MONGO9_PROBE=1` adds a live `mongod` probe) — the `GLIBC_TUNABLES` reset → `.claude/rules/docker-images.md`
- **SonarQube start tests**: `bash bin/tests/sonarqube-start.test.sh` — token invariant in compose, exit and signal handling of the start script, no docker → `.claude/rules/startup-tests.md`
- **/opt tool installer tests**: `bash bin/tests/global-unu-opt.test.sh` — no network; stub `curl`/`sudo`, the `GS_UNU_OPT_*` seams → `.claude/rules/global-unu-opt.md`
- **phpbrew ExtractTask overlay tests**: `bash bin/tests/phpbrew-extract.test.sh` — needs `php` and `tar`; the per-task temp dir overlay → `.claude/rules/startup-tests.md`
- **Compose env plumbing tests**: `bash bin/tests/compose-env-plumbing.test.sh` — runtime vars reach the containers, resolved through make; needs docker, `jq`, `.env.local` → `.claude/rules/docker-images.md`

## Claude Code Tooling

**Slash commands** (type `/command` in any session):
- `/lint` — shellcheck all scripts + hadolint all Dockerfiles
- `/fmt` — format shell scripts (`shfmt`) and YAML files (`yamlfmt`); supports `--check`, `--sh`, `--yaml`
- `/check-versions` — v2 `--check` across all fetcher types (dockerhub, github, ghcr, npm, pecl, pypi, quay, rubygems, sdkman, androidsdk, url, codeberg); no v1 fallback
- `/validate` — compose config + env consistency + COMPOSE_FILE + tier deps
- `/stack-health` — health markers, container status, version markers
- `/env-diff` — show divergences between `.env` and `.env.local`
- `/service-info <name>` — deep-dive on one service (compose, Dockerfile, startup, health, ports, versions)
- `/debug-service <name>` — read-only 6-step runbook on a failing service, ending in a root-cause hypothesis
- `/new-service <name>` — scaffold a new service (Dockerfile, compose, startup script, printed `.env` + Makefile lines)
- `/bump-versions` — guided `env-update` check → approval gate → apply → `env-scan` propagation → rebuild reminder

**Workflow + review skills — the GLOBAL install's, plus two repo-specific ones** (global-is-reference ruling, 2026-08-18: the 13 repo-local copies of global skills were deleted; the repo now carries only what has no global equivalent):
- `/stack-ask-human` — this repo's additions to the global question protocol (destructive-op gates, `.env` writes, `RELOAD` flags). See § "Questions"
- `/stack-lenses` — **load this BEFORE running any global review skill here.** It carries the /stack review dimensions (token invariant, MODE tiers, env cascade, port rules), sleuth lens K (infrastructure divergence) and the repo conventions the deleted copies used to enforce
- `/sweep`, `/sleuth`, `/inspect`, `/gaps`, `/forge`, `/cross-check`, `/converge`, `/pre-commit`, `/aggregate-findings`, `/handoff`, `/retrospective`, `/expanding-context` — all from `~/.claude/skills/` (the developer's global install — `ls ~/.claude/skills/` is the tally; a count written here drifts). `/converge` still runs § "Certification ladder" with the three repo reviewer agents
- `/new-service <name> [--parent <image>] [--runtime <name>] [--port <n>]` — scaffold a new service (Dockerfile, compose, startup script, printed `.env` + Makefile lines); args-first with interactive fallback

**Automatic hooks** (PostToolUse on Edit/Write):
- `shellcheck` — lints `.sh` files on every write
- `hadolint` — lints `Dockerfile*` files on every write
- `yamllint` — validates `.yaml`/`.yml` files on every write
- `shfmt` — checks shell formatting on `.sh` writes (reports diff, doesn't auto-fix)

**Automatic hooks** (PreCompact): none in the repo — the GLOBAL `~/.claude/hooks/precompact-handoff.sh` writes the handoff into the developer's memory pipeline (global-is-reference ruling, 2026-08-18).

**Permission rules**: `.claude/settings.json` is **an allow-list plus a three-entry `ask` tier** — `defaultMode: auto`, **no `deny` tier at all**, and `ask` entries for the three `bin/env-update.sh --apply*` spellings only [Verified 2026-09-04: `jq '.permissions | {ask, deny}'` → three `ask` entries, `deny` null] — per § "No permission denies", which the `ask` tier does not breach: it prompts, it never dead-ends (added `95ccbb7`; ruling 2026-09-04). (Until 2026-09-04 this paragraph said there was no `ask` tier — stale from `95ccbb7` on; row 28 of `docs/plans/MASTER.plan.md`.) Additional read-only allows live in the global `~/.claude/settings.json` layer.

## Gotchas & Pitfalls

**Intake rule** (2026-10-09, `/rules-split`): a new lesson goes into the `.claude/rules/<area>.md` whose `paths:` cover the files it concerns, NOT here. This file keeps only what must be in context before any file is read — gates, destructive commands, git/shell/compose traps. A bullet ending `→ .claude/rules/<file>.md` is an index entry: the full text loads automatically once a file matching that rules file's `paths:` (listed in § Claude Code Configuration) is opened — by the Read or Write tool or a Bash read such as `cat`/`head`, but NOT by a Grep search alone (probed 2026-10-09) — or read it directly. Split or prune a path-scoped rules file past ~300 lines (~30 KB), an unscoped one past ~150.

- **Two images sit on FOREIGN, EOL bases — never copy the `00base` apt idiom into them** (`01epiclabs-docker-oracle-xe-11g`, `02mongoclient-mongoclient`; each needs a different cure) → `.claude/rules/docker-images.md`
- **The android platforms and build-tools pins are a ROLLING WINDOW, not three independent pins** — `(offset:N)` + `(require-sibling:)`; a major bump is applied with `--force-hold` → `.claude/rules/android.md`
- **An upstream index can ANNOUNCE a version before its artifacts are published** — `(verify-asset:)` on the `url` fetcher; `max_by` on a date field is the smell → `.claude/rules/env-update.md`
- **`{ [ toggle ] && installer || echo "… will not be installed"; }` in a Dockerfile runs the echo when the installer FAILS** — use `if …; then …; else …; fi` → `.claude/rules/docker-images.md`
- **`mongo:9.0.x` refuses to start on kernel >= 6.19 BECAUSE of its own `GLIBC_TUNABLES`** — cleared in the Dockerfile at a tcmalloc cost; re-probe on every MONGO9 bump → `.claude/rules/docker-images.md`
- **Trailing `;` in `COMPOSE_FILE`** breaks Docker Compose silently — always check this after editing
- **Whether a port var must end with `:` is a property of its CONSUMER, not of the variable.** The common form is `${VAR:-}3306` in a compose file: the value is the host half of `HOST:CONTAINER`, so it must end with `:` (e.g. `42708:`) or the two numbers silently concatenate into `427083306`. But `docker/images/local.05…/docker-compose.yaml`'s `ports:` block writes `${VAR:-}:${VAR:-}` and the `Makefile`'s `start-local-registry` recipe writes `--publish ${VAR}:5000` — those supply the colon themselves, and a trailing `:` there is the bug. Five of this repo's port vars are in the second group [Verified 2026-09-02]. `.claude/hooks/env-guard-on-write.sh` keys its warning on the concatenating consumer form for exactly this reason; before that it produced 5/5 false positives and missed the only var that really concatenates (`GLOBAL_STACK_LOCALSTACK_LOCALSTACK_PORT_4510_4559`, whose range-style `_PORT_<n>_<n>` name the old pattern could not even match)
- **`00base` must always be in `COMPOSE_FILE`** — nearly everything depends on it being healthy
- **Tier 02 required for tier 03**: if `03node24` is active, `02nvm` must be in `COMPOSE_FILE`; same for `02phpbrew`/`03php*`, `02sdkman`/`03java*`, etc.
- **`${VAR}` expansion in `.env`**: variables must be defined before being referenced; Docker Compose and Make both expand them, but simple dotenv parsers do not
- **`GLOBAL_STACK_RELOAD_*=true`** forces a reinstall (can take 30+ minutes) — reset to `false` after use. **Three do not wipe**: `GLOBAL_STACK_RELOAD_NODE*`, `_JAVA*` and `_FLUTTER3` (plus `GLOBAL_STACK_LOCAL_RELOAD_FLUTTER3_41_9`, which feeds the same in-container switch) remove only the success and version markers (`nvm-start.sh`, `sdkman-start.sh`, `fvm-start.sh`) [Verified 2026-09-26: read], after which the installer finds the version directory already on disk and does nothing [Inferred: the tranche 2 step 11 finding, not re-run] — a Known issue in `docs/plans/pin-bump-reinstall-audit.plan.md`, not fixed. `GLOBAL_STACK_RELOAD_ANDROID` wipes the SDK but keeps `GRADLE_USER_HOME` (tranche 2 step 16, ruling 2026-09-24 23:55).
- **Downloaded tools refuse a release they cannot check** — checksums, the nginx signing keys, GitHub asset digests and the shared api.github.com rate limit → `.claude/rules/startup-scripts.md`
- **`/new-service` scaffolds a startup script with NO `gs_version_gate`** (`grep -c gs_version_gate .claude/skills/new-service/SKILL.md` → 0 [Verified 2026-09-26]), so a service created from it never reinstalls on a pin bump — add the gate by hand; fixing the scaffold is a logged follow-up.
- **`tools/` is shared state**: `make down` clears success/error markers; if a container fails mid-install, manually check `tools/errors/` before restarting
- **phpbrew's shared `tools/phpbrew/build/tmp.<time()>` dir** — same-second cold starts used to destroy each other's PHP source tree (seen as `tools/errors/php.<ver>` + `zend_dtrace.d: No such file`); the overlay fix and the recovery steps → `.claude/rules/startup-scripts.md`
- **`local.*` image dirs are git-ignored** — back them up separately or store in a private repo
- **Container startup is intentionally slow** (`start_period: 24h`) — do not tune healthchecks lower without understanding the two-phase install model
- **`docker-compose*.local.yaml` overrides** — git-ignored, machine-specific; can silently override tracked compose files. Check for their existence when debugging unexpected service behavior
- **Four images BAKE their start script — an edit needs an image rebuild, not a restart** (`01localstack-localstack`, both `01selenium-standalone-*`, `02sonarqube`) → `.claude/rules/startup-scripts.md`
- **Create or recreate containers ONLY via `env -i HOME=$HOME PATH=$PATH make up` — never a raw `docker compose up`, not even under `env -i`.** Compose prefers the SHELL environment over `--env-file`, and an interactive `/stack` shell carries `~/.bashrc`'s unquoted eval of `.env.local`, which word-splits spaced values: three containers started that way on 2026-09-28 got `GLOBAL_STACK_DOCKER_USER_NAME=Takieddine`, and a dry-run showed every service as "Recreate". `env -i` alone does not fix it either: `Makefile:16` exports `.env.local` with QUOTED values' quotes kept (`PHP_CONFIG_PACKAGE_04_GD_COMMAND_SUFFIX="-- --enable-gd …"` in `03php8-*`), while compose's dotenv strips them, so a raw clean-env `up` would recreate `03php8-4/8-5/edge` for nothing. Predict what `up` will touch by hashing through make: `env -i HOME=$HOME PATH=$PATH make GLOBAL_STACK_DOCKER_CLI_EXEC=config GLOBAL_STACK_DOCKER_CLI_EXEC_FLAGS="--hash '*'" GLOBAL_STACK_DOCKER_CLI='docker compose' GLOBAL_STACK_DOCKER_CLI_FLAGS='--env-file .env.local' docker-cli --silent` and compare with each container's `com.docker.compose.config-hash` label [Verified 2026-09-28: 44 compared, only the six Java-27 containers differed]. A third reason, same class: `.env.local` writes opt-outs as `VAR=  # reason`, which make reads as EMPTY but compose's own dotenv reads as the literal `# reason` [Verified 2026-09-28: raw `config` gave 04android `SDKMAN_INSTALL_PACKAGE_11_SPARK_VERSION="# Spark 3.5.x: …"`, the container got `""`] — so any tool or test resolving compose directly sees values the containers never get; resolve through `make … docker-cli` instead
- **ARG → ENV flow in Dockerfiles**: `ARG` values are build-time only; to expose at runtime: `ARG GLOBAL_STACK_FOO` then `ENV GLOBAL_STACK_FOO=${GLOBAL_STACK_FOO}`
- **`password = username` convention**: All default service passwords equal `GLOBAL_STACK_DOCKER_USER_ID` (`developer`) — MySQL, Postgres, pgAdmin, Keycloak all share this pattern
- **`privileged: true` on all containers** — intentional for local dev (needed for Docker-in-Docker, mount operations). Do not flag this as a security issue; it's a known trade-off
- **`tools/versions/` markers control reinstall** — `gs_version_gate` content-compares; the marker holds the RESOLVED version; `frankenphp` and `awscli` are deliberately ungated → `.claude/rules/startup-scripts.md`
- **Postgres reports `en_US.utf8` collation but SORTS AS C, and the existing volume still does** — never add `--lc-collate`/`--lc-ctype` beside the builtin provider → `.claude/rules/docker-images.md`
- **`android`'s `--sdk` is a GLOBAL option — `android --sdk=<path> sdk install …`, never `android sdk install --sdk=…`**; `platform-tools`, `ndk-bundle` and `emulator` take no version → `.claude/rules/android.md`
- **`$HOME` in every container is re-permissioned on EVERY boot, and a numeric `chmod` there disarms cached executables** — seen as `Failed to exec android binary: Permission denied`; the rule subtracts (`ug-s,go-rwx`), never assigns → `.claude/rules/startup-scripts.md`
- **`docker-bake.local.json` is generated, not tracked** — if it's stale after env changes, run `make generate-buildx` to regenerate. Stale bake file = wrong build config
- **BuildKit cache can go stale** — if builds fail with mysterious layer errors, `docker buildx prune` is the escape hatch
- **`jq '… | unique'` on a settings array SORTS it — read the SET, never the diff.** A hand-off script that adds entries with `.permissions.deny = ((.permissions.deny // []) + $add | unique)` rewrites every pre-existing entry in alphabetical order as a side effect. Applying five denies to a 123-entry list produced a ~250-line diff that looked like a rewrite and was almost entirely reordering [observed 2026-08-19, Phase G]. Two consequences: a reviewer reading that diff cannot tell an addition from a reshuffle, and `unique` also silently **collapses duplicates**, which is a content change nobody asked for. Verify with a set difference, not `diff`: `jq -n --slurpfile b old.json --slurpfile s new.json '{added: ($s[0].permissions.deny - $b[0].permissions.deny), lost: ($b[0].permissions.deny - $s[0].permissions.deny)}'` — `lost` must be `[]`. Use `+ $add | unique` only when the sort is wanted; otherwise append and de-duplicate without reordering.
- **`projects/CLAUDE.md` needs `git add -f` — the `.gitignore` negation for it is inert.** `.gitignore:68` excludes the whole `/projects` directory, and git cannot re-include a file whose *parent directory* is excluded, so the `!/projects/.claude/`, `!/projects/CLAUDE.md` and `!/projects/.gitkeep` negations on lines 125–127 have no effect. The files are still *tracked* (they were added before the exclusion), so they show up in `git status` and `git grep` and can be committed normally — but a plain `git add projects/CLAUDE.md` is refused with *"The following paths are ignored… projects"*. Use `git add -f`. This is safe **only because the path is already tracked** — confirm with `git ls-files <path>` before reaching for `-f`, since on an untracked path `-f` would pull genuinely-ignored machine-local content into the repo. Note `git check-ignore -v projects/CLAUDE.md` exits 1 ("not ignored") for exactly the same reason it is tracked, so it does **not** predict whether `git add` will succeed — the two disagree, and `git add` is the one that decides [observed 2026-08-19].
- **`git diff` is UNUSABLE for grep-based verification here — it silently returns nothing.** `diff.external = difft --color always --display side-by-side-show-both` is set, so every `git diff` emits side-by-side ANSI with **no `+`/`-`/`@@` prefixes**, and it aborts partway (`fatal: external diff died`). A `git diff <range> | grep '^+'` therefore yields **zero hits and reads as "clean"** — it invalidated two verification passes in a row before being caught [observed 2026-08-21]. Always use `git --no-pager -c core.pager=cat diff --no-ext-diff` for any programmatic diff inspection. Sanity check: `curl.sh` over `bd7b1a9..d63f437` yields 203 `+` lines and 10 `@@` hunks; if a diff-grep returns 0, suspect the driver before believing the result.
- **Use `git grep`, not `grep -rn`, for completeness sweeps.** A wide `grep -rn "<string>" /stack` silently omitted `projects/CLAUDE.md:11`, which `git grep` found in the same tree; `/stack/projects` is a real directory, not a symlink, so it is not a traversal artefact — most likely rtk output filtering. Any "we removed every reference" claim built on a single `grep -rn` is unsound. Also note a wide `grep -rn` over `~/.claude` returns megabytes because it hits session `.jsonl` transcripts — exclude `/(logs|history|shell-snapshots|todos|var|plugins|teams)/` and `*.jsonl`. **But `git grep` has the mirror blind spot, and it bites hardest on exactly the vars compose plumbs: it cannot see gitignored files, so `docker/images/local.*/docker-compose.yaml` and any `docker-compose*.local.yaml` are invisible to it.** Renaming `GLOBAL_STACK_ANDROID_SDK_URL` → `..._SDK_BUILD` swept clean under `git grep` while `local.05php8-5-…-android-n-flutter3-41-9/docker-compose.yaml:144` still plumbed the old name — which would have handed the all-in-one image a blank value and no new one, killing `global-stack-android-setup.sh` under `set -u` [observed 2026-09-11, row 31]. So a rename with compose consumers needs **both** sweeps plus a clean-environment validation: plain `grep`/`rtk proxy grep` over `docker/images/local.*` and `docker-compose*.local.yaml`, then `env -i HOME=$HOME PATH=$PATH bash -c 'cd /stack && docker compose --env-file .env.local config -q'` with **stderr captured**. `config -q` will not catch it on its own — it *warns* on an unset variable and still exits **0**, and compose interpolation prefers the **shell environment** over `--env-file`, so a stale `export` of the old name in the session's own shell suppresses even that warning. Test the exit status separately from the grep: `out="$(… config -q 2>&1)" || fail` — a failing command on the left of `&&` does not abort under `set -e`.
- **Spawn reviewer subagents UNNAMED** — passing `name:` routes their return through `SendMessage`, which can be denied or unavailable, so they run and their reports vanish. See § "Certification".
- **A self-referential idempotence guard is not one.** If a script's replacement text contains the very string its "already clean" check greps for, that branch can never fire after a successful run — the re-run falls through to the abort path. The `global-stack-lead-dev` handover script did exactly this: its own tombstone text contained the name [observed 2026-08-21]. Validate JSON *before* overwriting, not after.
- **Never edit a test file while a background run is executing it** — bash reads scripts incrementally, so the result is untrustworthy whichever way it lands. Kill the run and start again.
- **`startup-prologue.test.sh` does NOT implement `--section` at all — it ignores every argument silently.** `--section=99999` there prints a full `ALL PASSED ✓ N / N` and exits **0**, while the same flag on `env-scan.test.sh` exits 1 with `NO TESTS RAN` [Verified 2026-09-11, row 32]. So a `--section=` run of that suite is the WHOLE suite, and any claim of "I ran only §N" against it is false — filter the output instead, and read the tally line as the tell — a full pass reports every test (1095 on 2026-09-27). The run time is load-dependent and a weak tell: **~19 s** idle [measured 2026-09-11 with `/usr/bin/time`, row 32], **161 s** at load average 22-24 [measured 2026-09-24]. Same can-never-fire class as the COMMA-separated `--section` bullet, one level up: the flag looks honoured because the thing it should have filtered passes anyway.
- **A trailing `[[ cond ]] && cmd` makes the FALSE test the script's own exit status** — fix with an `if`, never a trailing `|| true` → `.claude/rules/startup-scripts.md`
- **`bin/tests/*.test.sh --section=` takes a COMMA-separated list** (`IFS=','`) — **in the env-update and env-scan suites; see the `startup-prologue.test.sh` bullet for the one that has no such flag**. `--section='112 113'` is a single unmatched token. It used to print `ALL PASSED ✓ 0 / 0` and exit **0** — a typo produced a green run in which nothing executed; it now exits 1 with `NO TESTS RAN`. Do not read the suite's tally from `✓` marks or by summing the per-section `└─` lines: the breakdown repeats section lines and both over-count (786 → 902 → 923 for one run). The `ALL PASSED ✓ N / N` line is the only authoritative tally.
- **Bash-written files bypass all PostToolUse hooks** — linting (shellcheck, hadolint, yamllint), formatting (shfmt), and backup only fire on `Edit`/`Write` tool calls. Files written via `cat >`, heredocs, `sed -i`, or other Bash redirects are invisible to hooks. Always use the `Write` or `Edit` tool when hook coverage matters.
- **A drifted Bash cwd silently voids every project-scoped gate bypass.** The Bash tool's working directory PERSISTS across calls, and the guard hooks derive the project slug from the LIVE cwd (`/` → `-`), not from the session's project root. So after a `cd ~/.claude/hooks/tests`, the sentinels the hooks look for are `~/.claude/projects/-home-developer-.claude-hooks-tests/state/*` — the five real ones under `-stack` become inert and every gate re-arms, with **no error until something finally blocks** [observed 2026-08-22: the ask-human gate fired mid-task and printed that slug in its own bypass hint]. Two independent hazards, both silent: repo-relative paths resolve against the wrong tree, and since `~/.claude` **is itself a git repo**, a `git add`/`git commit` run from there targets the wrong repository entirely. Prefer absolute paths and `git -C <path>` over `cd`; if you must `cd`, return in the same command. Same cwd-dependent-vacuity class as the `bin/check-image-versions.sh` defect fixed the same day.
- **`core.fileMode=false` in `/stack/`** — git ignores all file permission changes; `chmod` edits take effect on disk but are never staged or committed. For permission fixes, note the change explicitly in the commit message of whatever else touches the file; do not expect `git diff` or `git status` to show the mode delta.
- **Default `node` is the nightly channel, on purpose** (developer ruling 2026-09-27): `node --version` reads `v27.0.0-nightly…`. `NODE_VERSION` and the node bin dir come from `/stack/.env.local`, which `~/.bashrc` evals, and follow env-update's `nightly` channel (`bin/lib/env-update/core/channel.sh`). nvm is never sourced, so `.nvmrc` files (pdfturbo's `26`) and nvm's `default` alias (v24.21.0) are not honoured. When a project needs a pinned major, call it by path: `/stack/tools/nvm/versions/node/v26.9.0/bin/node`.
- **Auto-commit in /stack sessions** — see § "Git autonomy" above, which is authoritative: `git add`/`commit`/`push` to `master` are autonomous, pushes use plain `git push` (never `-u`), and the commit identity is fixed. Kept as a pointer rather than a restatement so the two cannot drift.
- **`make soft-restart` is DESTRUCTIVE** — despite the name it `sudo rm -rf`s `tools/` and restores it from `var/tools`; it is NOT the documented soft restart (`make down-n-up`). A stale `var/tools` means a full multi-10-minute reinstall
- **`make save` exports EVERY Docker image on the machine** — not just stack images; slow, disk-hungry, undocumented side effect
- **Host checkout MUST live at `/stack`** — `tools/.shellrc/*.shellrc` exports bake absolute paths (`/stack/tools/...`) shared by containers and host; a checkout at any other path breaks host-container binding
- **LOCAL port range**: `GLOBAL_STACK_LOCAL_*_PORT_*` use host range **41700–41899** (200 slots). Standard `GLOBAL_STACK_*_PORT_*` use 42700–42899. Next free LOCAL slot: 41720 (41719 is taken — the `…_TWES_IN_PORT_41719=41719` line of `.env.local`).
- **LOCAL port var names for `local.05php8-5-...`**: the 7 port vars use SHORT form (`..._RUBY_N_RUST_N_PYTHON_N_JAVA_N_...`, no version suffixes), but `ALLTOGETHER_NAME` uses the LONG form with `05` prefix (`GLOBAL_STACK_LOCAL_05PHP8_5_N_NODE24_N_RUBY4_N_RUST_N_PYTHON3_N_JAVA27_N_ANDROID_N_FLUTTER3_41_9_ALLTOGETHER_NAME`). Pattern: env vars (short) vs healthcheck token (long).

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
~/.claude/CLAUDE.md                      # Global reasoning framework — the developer's own install
~/.claude/THINKING.md                    #   from his bundle. This repo NEVER writes these; the
~/.claude/BLAST-RADIUS.md                #   container-era bootstrap that did was removed 2026-08-18
~/.claude/settings.json                  # Global settings (model, plugins) — never touched by this repo

claude-setup/claude-setup-global.tar.gz  # The dev's machine bundle: PROVENANCE for the docs above
docs/BLAST-RADIUS.md                     # The /stack blast-radius table — kept IN REPO because the
                                         #   global copy carries only `make hard-restart`

.claude/settings.json                    # Project permissions + hooks — CLAUDE CANNOT WRITE THIS
.claude/settings.local.json              # Local UI preferences (gitignored)
.claude/agents/                          # Agent definitions (project-scoped) — REVIEWERS ONLY;
                                         #   the global-stack-lead-dev orchestrator was deleted
                                         #   2026-08-19, work is done in the main conversation
  stack-infra-reviewer.md                #   ladder lens 1: correctness + regression
  completeness-reviewer.md               #   ladder lens 2: completeness + blast radius
  reproducibility-reviewer.md            #   ladder lens 3: clean-clone + destructive posture
.claude/hooks/                           # PostToolUse + PreCompact hook scripts
  shellcheck-on-write.sh                 # Lint .sh files on write        }
  hadolint-on-write.sh                   # Lint Dockerfiles on write      } all five are LIVE on
  yamllint-on-write.sh                   # Validate YAML on write         } this machine — the
  shfmt-on-write.sh                      # Check shell formatting         } tools are installed
  env-guard-on-write.sh                  # Guard .env edits               }
                                         # (log_obs(): the hooks above source the GLOBAL
                                         #  ~/.claude/hooks/log-helpers.sh, no-op stub when absent —
                                         #  global-is-reference ruling, 2026-08-18; no repo copy)
.claude/skills/                          # Slash skill definitions (read in place, no install)
  lint/  fmt/  check-versions/  bump-versions/  validate/  stack-health/
  env-diff/  service-info/  new-service/  debug-service/            # domain skills
  stack-ask-human/  stack-lenses/        # the two repo-specific workflow/review skills; every
                                         #   other workflow/review skill comes from ~/.claude/skills/
                                         #   (global-is-reference ruling, 2026-08-18)
.claude/rules/                           # Path-scoped knowledge split out of this file
                                         #   (/rules-split, 2026-10-09): each file loads only
                                         #   when a file matching its `paths:` is opened (see § Gotchas intake rule)
  startup-scripts.md                     #   docker/config/dist/bin/**, docker/config/dist/conf/**, docker/images/00base/conf/bin/**
  startup-tests.md                       #   bin/tests/startup-prologue.test.sh, bin/tests/base-install-tools.test.sh, bin/tests/base-set-permissions.test.sh, …
  android.md                             #   docker/config/dist/bin/android-bin/**, docker/images/04android/**, docker/images/local.*android*/**, …
  env-update.md                          #   bin/env-update.sh, bin/lib/env-update/**, bin/tests/env-update*.test.sh, …
  global-unu-opt.md                      #   templates/shell/global-unu*.sh, bin/tests/global-unu-opt.test.sh
  docker-images.md                       #   docker/images/**, bin/tests/mongo9-rseq.test.sh, bin/tests/postgres-healthcheck.test.sh, …
  host-tooling.md                        #   Makefile, bin/git-strip-coauthored.sh, bin/check-bake-targets.sh, …

var/claude/                              # Reports/review outputs (gitignored); handoffs go to the
                                         #   GLOBAL PreCompact hook's memory pipeline, not the repo
```

## File Layout Quick Reference

See `templates/tips/file-layout.md`.

---

> **Core Operating Rules 6 & 7** (Completion Gate and TDD) are defined in the global `~/.claude/CLAUDE.md` and apply here without exception.

> **Remember**: Handle all work here directly with the global reasoning framework — there is no orchestrator agent to delegate to. Use `/lint` before committing shell changes — and in a container, lint manually, because the hooks are dead there. Check for trailing `;` in `COMPOSE_FILE`. Verify with `--dry-run` before applying changes. Tier 02 = install, tier 03 = setup — same startup script, different `MODE`.

> **And on every single reply**: ask via **`AskUserQuestion`**, and work on **`master`** only.
