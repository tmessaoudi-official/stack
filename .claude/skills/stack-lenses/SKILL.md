---
name: stack-lenses
description: >
  MANDATORY companion to every global review skill run in /stack. Load this BEFORE running
  /sweep, /sleuth, /inspect, /gaps, /forge, /cross-check, /converge, /pre-commit or
  /aggregate-findings here — it carries the /stack review dimensions (token invariant, two-phase
  MODE model, env cascade, port rules), sleuth lens K (infrastructure divergence), and the repo
  conventions those global skills do not know about. Extracted 2026-08-18 from the deleted
  repo-local copies of those skills (global-is-reference ruling: a repo may not duplicate a
  global skill; what was repo-specific in them lives here instead).
---

# /stack-lenses — /stack review dimensions & conventions

This skill adds no procedure of its own. It is the **domain payload** for the global review
skills: run the global skill for its machinery, with everything below folded into its scope.

## Repo conventions (apply to every review skill)

- **Reports live in the repo**: `var/claude/<skill>/` (gitignored). Never `~/.claude/projects/…`.
- **Non-blocking closes — no interrupts.** End with the findings and a plainly-stated offer
  (`N findings (P0:a P1:b P2:c) — say which to fix`), never a blocking question.
- **`/converge` runs the ladder** at the tier CLAUDE.md § "Certification ladder" mandates
  (MAXIMAL for any operational-surface diff; STANDARD for docs-only) — the three lenses are the
  repo agents: `stack-infra-reviewer`, `completeness-reviewer`, `reproducibility-reviewer`
  (`.claude/agents/`).
- **Project scope only.** `~/.claude/` is the developer's own persistent install, out of this
  repo's audit scope — audit it from its own sessions, not from here.
- **What a review here cannot verify, it must say so:** "the stack comes up healthy" needs Docker
  and 10+ minutes; a verdict that hides an unverifiable dimension is a false certification.

## Review dimensions — MANDATORY additions to any sweep/review of this repo

Run these **in addition to** the global skill's own dimensions, on every review. Each one is a
real failure mode documented in `CLAUDE.md` § Gotchas, not a hypothetical.

- **Token invariant (P0 — silent permanent unhealth).** Success and error tokens must use the *same*
  identifier. The error token is single-sourced from `GLOBAL_STACK_ERROR_TOKEN` in the service's
  compose file; the success write must be `tools/successes/${GLOBAL_STACK_ERROR_TOKEN}`. A different
  literal on the success side yields a container that is **fully functional yet permanently
  unhealthy**, masked for 24h by `start_period` — which is exactly why it survives review. Any
  health-signalling edit with a hardcoded success name is **P0**.
- **One script, two tiers (P0 — unintended blast radius).** Startup scripts under
  `docker/config/dist/bin/<rt>-bin/` serve BOTH the tier-02 installer (`MODE=install`) and every
  tier-03 consumer (`MODE=setup`). A change guarded by neither `MODE` branch lands on all of them.
  Confirm which services run the edited script (`grep -rl '<script>' docker/images/*/docker-compose.yaml`)
  and state that list in the finding.
- **`COMPOSE_FILE` trailing `;` (P0 — silent breakage).** A trailing semicolon breaks Docker Compose
  with no useful error. Check it on every `.env` / `.env.local` edit that touches `COMPOSE_FILE`.
- **Port var trailing `:` (P0).** The compose template is `${VAR:-}PORT`, so a set port var MUST end
  with `:` (`42708:`). Omitting it silently concatenates the digits into one absurd port
  (`427083306`) instead of failing. Also check the range: 42700–42899 standard, 41700–41899 for
  `GLOBAL_STACK_LOCAL_*`.
- **Tier dependency completeness.** If a tier-03 service is added to `COMPOSE_FILE`, its tier-02
  manager must be there too (`02nvm`→`03node*`, `02phpbrew`→`03php*`, `02sdkman`→`03java*`,
  `02pyenv`→`03python*`, `02rbenv`→`03ruby*`). And `00base` must always be present.
- **`ARG` → `ENV` flow.** `ARG` is build-time only. A Dockerfile that needs the value at runtime must
  do `ARG GLOBAL_STACK_FOO` **then** `ENV GLOBAL_STACK_FOO=${GLOBAL_STACK_FOO}`. An `ARG` alone with
  runtime consumers is a finding.
- **Env cascade completeness.** A `.env` change is not done until `.env.local` and every matching
  Dockerfile `ARG` line agree — that is `bin/env-scan.sh`'s job. Vars whose value contains `${` are
  deliberately skipped by propagation (expansion-dependent); flag any expectation that they propagate.
- **Anti-bandaid gate.** For every `||` fallback, `2>/dev/null`, `|| true`, error trap, retry loop,
  `timeout` bump, `start_period` increase or default-value assignment introduced: state the exact
  failure mode, the *physical* evidence that confirmed it (log line, marker file, command output), and
  whether the root cause is fixed. No evidence ⇒ **P0**, replace it with a root-cause fix. Note the
  legitimate exception: `log_obs` writes end in `|| true` by contract (Rule 13) — designed, not a
  bandaid.
- **What is deliberate — do NOT flag these.** `privileged: true` on all containers (needed for
  Docker-in-Docker and mount ops in local dev), `start_period: 24h` + `retries: 99999` (the two-phase
  install genuinely takes 10+ minutes), `password = username` for local service credentials,
  `core.fileMode=false`, and `set -xeE -o pipefail` without `-u` in startup scripts. Flagging a
  documented trade-off as a defect is noise, and it trains the next reviewer to ignore the report.
- **Destructive-name traps.** `make soft-restart` is **not** a soft restart (it `sudo rm -rf`s
  `tools/`); `make save` exports every image on the machine. If a diff adds a Makefile target whose
  name understates what it does, that is a finding on its own.

## Sleuth lens K — MANDATORY additional agent for /sleuth

Beyond the global skill's agents A–J, **always run agent K** on this repo, and report its findings
as category **K** alongside A–J. It targets the failure class unique to /stack: a container that is
*functionally fine but structurally wrong*, where nothing crashes and no test fails.

> **K — Infrastructure divergence.** This stack signals health through *files*, installs through *two
> phases sharing one script*, and configures through a *cascade* of env files. Each is a place where two
> halves can silently disagree. Hunt for:
> 1. **Token mismatch** — a service whose success write is not `tools/successes/${GLOBAL_STACK_ERROR_TOKEN}`.
>    Cross-check every `docker/images/*/docker-compose.yaml` `GLOBAL_STACK_ERROR_TOKEN` against the
>    literal the startup script actually writes. A mismatch = permanently unhealthy yet working,
>    masked for 24h by `start_period`. **This is the single highest-value check in this skill.**
> 2. **`MODE` branch asymmetry** — a startup script serving both `MODE=install` (tier 02) and
>    `MODE=setup` (tier 03) where a code path is reachable in one mode but assumes state only the
>    other creates.
> 3. **Version-gate logic** — `gs_version_gate` content-compares a marker under `tools/versions/`
>    against the env value. Hunt for a marker written with a different value than the one compared, a
>    reinstall path that does not refresh its marker, or a sidecar marker (e.g. `php.edge.build`) that
>    can drift from its primary.
> 4. **Env cascade breaks** — a `.env` var whose Dockerfile `ARG` or `.env.local` counterpart cannot
>    receive it (contains `${`, so propagation deliberately skips it), yet is documented as propagating.
> 5. **Tier-dependency assumptions** — a tier-03 service that reads from `tools/` without its tier-02
>    manager being a healthcheck dependency.
> 6. **Concurrency on `tools/`** — the volume is bind-mounted into every container. Two services
>    writing the same path with no lock (`GLOBAL_STACK_USE_LOCKS`) is a real race here.
> 7. **`ARG` without `ENV`** — a build-time-only value that runtime code reads, so it is empty at run
>    time rather than failing at build time.
>
> For each: file + line, which two halves diverge, the smallest observable symptom, and whether any
> existing test or healthcheck would catch it (if not, that absence *is* the finding). Research only,
> no writes.
