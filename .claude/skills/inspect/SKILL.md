---
name: inspect
description: Use when performing a full project health inspection across security, dead code, deprecations, error handling, documentation staleness, test coverage, and configuration hygiene.
user-invocable: true
args: "[--quick] [--focus=<A..K>] [--target=<path>]"
side-effects: Writes a report to var/claude/inspections/<date>.md (gitignored; never committed)
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
  2. NO `advisor()` HERE. Independent certification = fresh-context read-only reviewer subagents
     (`.claude/agents/stack-infra-reviewer.md`); self-grading must be DISCLOSED as self-graded.
  3. REPORTS GO TO `var/claude/inspections/` in the repo — gitignored by the blanket `/var` rule,
     never committed. NOT `~/.claude/projects/…`, which is wiped when the container is reclaimed.
  4. `--scope=global|both` IS REMOVED: `~/.claude/` here is GENERATED from repo files by
     `scripts/claude-bootstrap/install.sh`, so inspecting it inspects a copy.
  5. `--vision` IS REMOVED — it proposes UI/UX improvements and this project has no user interface.
  6. ≤5 concurrent subagents in two sequential batches; every agent writes raw output to
     `var/claude/inspections/raw/<X>.md` BEFORE returning.
  7. THE LINTERS ARE ABSENT IN THIS CONTAINER — shellcheck, hadolint, yamllint, shfmt, yamlfmt are not
     installed, so agents must READ for these patterns rather than run a tool, and must say which
     tool actually ran. Never report a lint-shaped finding count as though a linter produced it.
  8. PROJECT RULES WIN on any conflict: `/stack/CLAUDE.md`.
═══════════════════════════════════════════════════════════════════════════════════ -->

## /stack lens K — MANDATORY additional agent (configuration hygiene)

Beyond agents A–J, **always run agent K** on this repo:

> **K — Configuration hygiene.** This project's health lives in `.env`, the compose files and the
> Makefile, and its most expensive failures are configuration-shaped, not code-shaped. Audit:
> 1. **`COMPOSE_FILE`** — no trailing `;`; `00base` present; every tier-03 service accompanied by its
>    tier-02 manager; every listed path actually exists on disk.
> 2. **Port hygiene** — every set `GLOBAL_STACK_*_PORT_*` ends with `:`; no duplicate host port; every
>    value inside 42700–42899 (or 41700–41899 for `GLOBAL_STACK_LOCAL_*`); report the next free slot.
> 3. **`.env` ↔ `.env.local` ↔ Dockerfile `ARG` agreement** — run `bin/env-scan.sh --dry-run` and
>    `make check-image-versions`, and report what they say. A drifted `ARG` means the built image is
>    stale even though `.env` looks right.
> 4. **`@todo env-update` annotation coverage** — every version variable should carry one; an
>    unannotated version pin is invisible to `bin/env-update.sh` and will silently rot. List the
>    unannotated ones.
> 5. **`RELOAD` flags left on** — any `GLOBAL_STACK_RELOAD_*=true` in `.env`/`.env.local` is a 30+
>    minute reinstall waiting to happen on the next start. Report each as P1.
> 6. **Service completeness** — for each `docker/images/*/`: a compose file, a `GLOBAL_STACK_ERROR_TOKEN`,
>    the five Makefile macro lines, and a `.PHONY` entry. Report each missing piece.
> 7. **Orphans** — a `docker/images/*/` dir absent from `COMPOSE_FILE`; a Makefile target for a service
>    that no longer exists; a startup script no compose file references.
>
> For each: file + line, the concrete consequence (not "bad practice"), severity, and the fix.
> Research only, no writes.

Report its findings as category **K** alongside A–J.

## --help

> If ARGUMENTS contains `--help`: output the text below verbatim, then immediately STOP — do not execute any other steps. (`--help` takes precedence over all other flags.)
>
> ```
> /inspect — Project health inspection: security, dead code, deprecations, error handling, docs,
>            test coverage, configuration hygiene. Read-only; proposes, never fixes.
>
> Usage: /inspect [--quick] [--focus=<A..K>] [--target=<path>]
>
> Flags:
>   --quick          Agents A, D and K only (security, error handling, config hygiene)
>   --focus=<X>      Run a single agent
>   --target=<path>  Inspect a specific directory (default: the repo root)
> ```
>
> Then STOP.

---

# /inspect — Project Health Inspector

Differentiation: `/inspect` finds **what is wrong with existing things**. `/gaps` finds **what is
missing or unfinished**. `/sleuth` finds **hidden behavioural bugs**. `/sweep` reviews **uncommitted
changes only**.

## Step 0: Setup

```bash
TARGET="${target_arg:-${CLAUDE_PROJECT_DIR:-$PWD}}"
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
INSPECT_DIR="$REPO_ROOT/var/claude/inspections"
mkdir -p "$INSPECT_DIR/raw"
TODAY=$(date +%Y-%m-%d-%H%M)
REPORT_PATH="$INSPECT_DIR/$TODAY.md"
PRIOR=$(ls "$INSPECT_DIR"/*.md 2>/dev/null | sort -r | head -1 || true)
```

Announce: "Inspecting: `$TARGET` → saving to `$REPORT_PATH`". If a prior inspection exists, read it —
Step 3 reports drift against it, and a finding present in 2+ inspections is **[CHRONIC]**, which is a
stronger signal than a fresh P1.

## Step 1: Detect project context

```bash
ls "$TARGET"/{Makefile,docker-compose.yaml,.env,.hadolint.yaml,README.md,TODO.md} 2>/dev/null
ls "$TARGET"/docker/images/ | wc -l
ls "$TARGET"/bin/*.sh "$TARGET"/bin/lib/ "$TARGET"/bin/tests/ 2>/dev/null
find "$TARGET/docker/config/dist/bin" -name '*.sh' 2>/dev/null | wc -l
command -v shellcheck hadolint yamllint shfmt yamlfmt 2>/dev/null
```

Summarise as `PROJECT_CONTEXT`, and **explicitly record which linters are available** — that fact
changes what every agent can legitimately claim.

## Step 2: Spawn analysis agents

Respect flags:
- `--quick`: spawn only A, D, **K**
- `--focus=<X>`: spawn only that agent
- Default: two sequential batches, **never more than 5 concurrent** — Batch 1 = A–E; Batch 2 = F–J + K.

Each agent gets `<TARGET>`, `PROJECT_CONTEXT`, `CURRENT_DATE` and its own `$OUTPUT_FILE` =
`$INSPECT_DIR/raw/<X>.md`, and ends with: *"Write your full findings to `$OUTPUT_FILE` using the Write
tool. Return only: 'Complete — [N] findings.'"* Severity: **P0** = exploit/data-loss risk, **P1** =
breaks a documented behaviour or costs real time, **P2** = bad practice, **P3** = polish.

**Agent A: Security** — real secrets in tracked files (distinguish from the deliberate
`password = username` local-dev convention, which is NOT a finding); `eval` or unquoted expansion
reachable from external input; `curl | bash` patterns; a credential echoed into a log or a marker file;
world-readable sensitive files; `http://` where TLS is available. **Do not flag `privileged: true`** —
`CLAUDE.md` documents it as a deliberate local-dev trade-off.

**Agent B: Dead code & unused artifacts** — shell functions never called; `bin/lib/` files nothing
sources; `GLOBAL_STACK_*` vars in `.env` that no compose file, Dockerfile or script reads; startup
scripts no compose file references; Makefile targets calling missing scripts; commented-out blocks.
Flag dynamically-dispatched candidates as "possibly dead", never "dead".

**Agent C: Deprecations & staleness** — backticks instead of `$()`; `[ ]` where `[[ ]]` is meant;
`#!/bin/sh` with bash features; image pins on `:latest` or an EOL distro; a documented tool or path
that no longer exists on disk; a pattern superseded by an existing helper (e.g. hand-rolled version
comparison where `gs_version_gate` exists).

**Agent D: Error handling** — scripts missing `set -eEuo pipefail` where abort-on-failure is intended
(respect the two deliberate variants); unchecked exit codes on `cd`, `mkdir`, `cp`, `curl`, `docker`,
`git`; `2>/dev/null` discarding an error that mattered; generic messages with no file/line/cause;
missing `trap` cleanup; a failure path that does not write its error token — in this project a failing
service that writes no `tools/errors/<token>` is invisible to the healthcheck, which is a P1 at least.

**Agent E: Documentation & comment staleness** — `# Usage:`/`# Args:` comments that no longer match;
`CLAUDE.md`, `README.md` or `templates/tips/*` referencing files, targets or flags that do not exist;
**counts that have drifted** (script totals, test totals, service lists — the fastest-rotting claims
here); example commands that would fail as written; TODO/FIXME with no date or owner.

**Agent F: Test coverage gaps** — map `bin/*.sh` and `docker/config/dist/bin/**` against
`bin/tests/*.test.sh`; find business-critical paths with no test (version gating, token writing, env
propagation, port parsing); tests referencing removed functions; tests with no real assertion; broken
harness or missing fixtures. **Run the suites you find and report the actual PASS/FAIL counts** — an
inspection that reports coverage without running anything is the exact failure this agent exists to catch.

**Agent G: Structure & convention drift** — functions >150 lines or nesting >4 levels (the project's
decomposition threshold); missing include guards; a lib file that `source`s another rather than
declaring `# Sources:`; wrong variable prefix (`_GS_EU2_` for env-update, `_GS_ES_` for env-scan);
inconsistent function naming against `_gs_eu2_<module>_<action>` / `es_<action>`.

**Agent H: Docker & compose hygiene** — Dockerfile layer bloat and missing `--no-install-recommends`;
hadolint rules the `.hadolint.yaml` silences and whether each is still justified; healthchecks whose
`test` does not match the marker actually written; `depends_on` without `condition: service_healthy`
where health is the real prerequisite; a build `FROM` not pointing at the local registry.

**Agent I: Makefile hygiene** — targets missing from `.PHONY`; a service missing any of its five macro
lines; targets that would silently succeed on failure (missing `set -e` semantics in a recipe);
undocumented destructive targets — and note whether each destructive one is still reachable given the
allow-list-only permissions.

**Agent J: Repo hygiene** — tracked files that should be ignored (backups, `.local` variants, logs);
ignored patterns that no longer match anything; large tracked binaries; a `.gitignore` rule
contradicted by a tracked file; leftover `*.bak.*`.

**Agent K: Configuration hygiene** — the mandatory lens defined at the top of this file.

## Step 3: Synthesise findings

```markdown
# /inspect Report — <DATE>
Inspected: <TARGET> | Agents: <letters> | Linters available: <list, or "none — manual read only">
Certification: <reviewer subagents | SELF-GRADED — reason>

## Summary
[3-5 sentences: overall health, the dominant category, the single most urgent item]
| Category | P0 | P1 | P2 | P3 |

## Findings (P0 and P1 — reply "details" for P2/P3)
### [P0|P1] — <Title> — Category <X>
- **Where**: file:line
- **Consequence**: what actually goes wrong, concretely
- **Fix**: the specific change
- **Evidence**: the command/read that established it

## Drift vs prior inspection (<PRIOR_DATE>)
### ✓ Resolved since   ### ⚠ New since   ### [CHRONIC] present in 2+ inspections

## Quick wins (P2/P3, effort low)
## Top 5 actions
## Not reported (documented deliberate trade-offs collapsed, with reasons)
## Coverage gaps (what could not be checked, and why — e.g. linters absent)
```

## Step 4: Save the report

Write to `$REPORT_PATH`. Announce the path.

## Step 5: Present findings — hard stop

Show the summary table, all P0/P1 findings, the drift section and the top 5 actions. Then, in **plain
text** per `/ask-human`, and STOP:

```
N findings (P0: A | P1: B | P2: C | P3: D). Nothing has been changed — every finding is a proposal.

1. Fix the P0/P1 findings (recommended) — or name specific IDs.
2. Show the P2/P3 details.
3. Show one category in full — name it, e.g. `category K`.
4. Nothing — close the report.

❓ QUESTION — which findings should I act on?
```

*Never fixes anything on its own. The developer decides.*
