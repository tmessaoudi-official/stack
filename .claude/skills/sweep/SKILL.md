---
name: sweep
description: Use when running a Phase 6 second sweep on uncommitted changes before committing, or reviewing code written outside the standard agent workflow.
user-invocable: true
disallowed-tools: AskUserQuestion
---

<!-- ═══════════════════════════════════════════════════════════════════════════════════
  /stack CONTAINER ADAPTATION (2026-08-05). Imported from the developer's machine bundle
  `claude-setup-global-20260722` (committed at claude-setup/claude-setup-global.tar.gz) via the
  already-container-adapted phorj and pdfturbo ports. These deltas OVERRIDE the body below wherever
  they conflict:

  1. QUESTIONS ARE PLAIN TEXT. `AskUserQuestion` TIMES OUT in this container. Any "ask" is plain prose
     per `.claude/skills/ask-human/SKILL.md`; every reply ends with a `❓ QUESTION` / `⏹ NO QUESTION`
     marker as its literal last line.
  2. REPORTS GO TO `var/claude/sweeps/` in the repo — gitignored by the blanket `/var` rule, survives
     compaction inside the session, never committed. NOT `~/.claude/projects/…`, which is wiped when
     the container is reclaimed.
  3. THE LINTERS ARE ABSENT IN THIS CONTAINER — `shellcheck`, `hadolint`, `yamllint`, `shfmt`,
     `yamlfmt` are not installed, so `/lint` and `/fmt` silently no-op. This skill's shell and YAML
     dimensions are therefore a MANUAL read, not a tool run. Never report a finding count as though a
     linter produced it. `bash -n` always works.
  4. PROJECT RULES WIN on any conflict: `/stack/CLAUDE.md`.
═══════════════════════════════════════════════════════════════════════════════════ -->

## /stack dimensions — MANDATORY additions to this skill's review set

Run these **in addition to** the generic dimensions below, on every sweep of this repo. Each one is a
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
  legitimate exceptions: `log_obs` writes end in `|| true` by contract (Rule 13), and the PreCompact
  hook always exits 0 by contract — those are designed, not bandaids.
- **What is deliberate — do NOT flag these.** `privileged: true` on all containers (needed for
  Docker-in-Docker and mount ops in local dev), `start_period: 24h` + `retries: 99999` (the two-phase
  install genuinely takes 10+ minutes), `password = username` for local service credentials,
  `core.fileMode=false`, and `set -xeE -o pipefail` without `-u` in startup scripts. Flagging a
  documented trade-off as a defect is noise, and it trains the next reviewer to ignore the report.
- **Destructive-name traps.** `make soft-restart` is **not** a soft restart (it `sudo rm -rf`s
  `tools/`); `make save` exports every image on the machine. If a diff adds a Makefile target whose
  name understates what it does, that is a finding on its own.

## --help

> If ARGUMENTS contains `--help`: output the text below verbatim, then STOP — do not execute any other steps.
>
> ```
> /sweep — Run a Phase 6 second sweep on uncommitted changes before committing, or review code
>          written outside the standard agent workflow. Read-only; never auto-applies anything.
>
> No flags — invoked without arguments.
> ```

---

Run a Phase 6 Second Sweep on current uncommitted changes. **Never auto-applies anything — this skill
only reads and reports.** Use before committing, or to review code written outside the standard
workflow.

## Steps

1. **Assess the diff**:
   - `git diff --stat` — change footprint
   - `git diff` — full unstaged diff
   - `git diff --cached --stat` + `git diff --cached` — staged changes too
   - `git status --porcelain` — and do not forget untracked files; a brand-new unreferenced script is
     invisible to `git diff` entirely

2. **Review each changed file** using the Phase 6 checklist:

   **All files**:
   - **Bug hunt**: logic errors, off-by-one, unset-variable deref, unchecked error returns, unhandled
     edge cases
   - **Security**: credentials/secrets in code, injection risks (shell, SQL, template), missing input
     validation at boundaries
   - **Contracts**: changed function signatures, CLI flags, env var names, `make` target names, health
     token names, output formats — flag every one as a potential breaking change
   - **Tests**: new behaviour without a test? Modified behaviour without updated tests?
   - **Docs**: changed public interface without updated `CLAUDE.md` / `templates/tips/`?

   **Shell scripts** (`.sh`):
   - Missing `set -eEuo pipefail` (new scripts) — note the deliberate variants: `set -xeE -o pipefail`
     for container startup scripts, `set -uo pipefail` for the never-fail PreCompact hook
   - Unquoted expansions (`$VAR` rather than `"$VAR"`), especially in `rm`/`cp`/`mv` paths
   - Missing include guard in a `bin/lib/` file (`_GS_EU2_*_SH_LOADED` / `_GS_ES_*` pattern)
   - A lib file that `source`s another — forbidden: `main.sh` is the single coordinator of all
     `source` calls; lib files declare dependencies via a `# Sources:` comment only
   - Functions >150 lines or nesting >4 levels → decompose
   - Error propagation across subshells done via stdout instead of a temp file (stdout is reserved for
     return values here)

   **Config / infra files** (`.yaml`, `Dockerfile`, `.env`, `Makefile`):
   - Secrets committed directly
   - `ARG` without matching `ENV` where runtime access is needed
   - Trailing `;` in `COMPOSE_FILE`; missing trailing `:` on a set port var
   - A new service missing any of: `COMPOSE_FILE` entry, the five Makefile macro lines, the `.PHONY`
     entry, `GLOBAL_STACK_ERROR_TOKEN`

3. **Classify each finding** by severity:
   - **CRITICAL**: security hole, data loss risk, broken contract, shell injection, token-invariant
     violation, a change that silently lands on every tier-03 consumer
   - **WARNING**: missing test, logic edge case, missing error handling, unquoted variable, incomplete
     env cascade
   - **NOTE**: style, naming, non-blocking improvement

4. **Output a structured findings table**:

```
## Sweep Results

| # | Severity | File:Line | Finding | Fix |
|---|----------|-----------|---------|-----|
| 1 | CRITICAL | docker/images/02nvm/docker-compose.yaml:31 | Success token `nvm-install` != GLOBAL_STACK_ERROR_TOKEN `nvm` | Write to tools/successes/${GLOBAL_STACK_ERROR_TOKEN} |
| 2 | WARNING  | bin/env-scan.sh:412 | Unquoted $DEST in cp | Quote: cp "$DEST" |
| 3 | NOTE     | Makefile:88 | New target absent from .PHONY | Add to the .PHONY block |

**Verdict**: PASS (safe to commit) or BLOCKED (N critical findings must be fixed first)
**Verified with**: <the tools that ACTUALLY ran — e.g. "bash -n only; shellcheck absent in container">
```

5. **Save the report** so it survives compaction:

```bash
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
SWEEP_DIR="$REPO_ROOT/var/claude/sweeps"
mkdir -p "$SWEEP_DIR"
SWEEP_PATH="$SWEEP_DIR/$(date +%Y-%m-%d-%H%M%S).md"
```

Write the full findings table (including verdict and the "Verified with" line) to `$SWEEP_PATH`.
Announce: "Sweep report saved to `$SWEEP_PATH`".

## Notes

- A single CRITICAL finding means the verdict is BLOCKED
- Multiple WARNINGs with no CRITICAL = PASS with notes (your discretion)
- Apply **Kernighan's Law**: if the diff is hard to understand, that itself is a WARNING (complexity)
- Apply **Chesterton's Fence**: before flagging a removal as wrong, understand why the code existed
  (`git blame`, the commit message, the `CLAUDE.md` gotcha that may explain it)
- Apply **Hyrum's Law**: any changed public interface — a `make` target, an env var name, a health
  token, an output format — is a potential contract break; flag it
- **Report what you could not check.** If a dimension needed a tool that is absent, say so rather than
  silently dropping it. A sweep that claims coverage it does not have is worse than a short one
