---
name: sleuth
description: Use when hunting for hidden behavioral bugs — silent failures, logic traps, contract violations, cross-component inconsistencies, and edge-case mishandling that tests and linters do not catch.
user-invocable: true
args: "[--quick] [--focus=<A..K>] [--target=<path>]"
side-effects: Writes a report to var/claude/sleuth/<date>.md (gitignored; never committed)
disallowed-tools: AskUserQuestion
---

<!-- ═══════════════════════════════════════════════════════════════════════════════════
  /stack CONTAINER ADAPTATION (2026-08-05). Imported from the developer's machine bundle
  `claude-setup-global-20260722` (committed at claude-setup/claude-setup-global.tar.gz) via the
  already-container-adapted phorj port. These deltas OVERRIDE the body below wherever they conflict:

  1. QUESTIONS ARE PLAIN TEXT. `AskUserQuestion` TIMES OUT in this container, so a gate that "asks"
     cannot fire. Every "ask" below means: print the question, a minimal concrete example, numbered
     options and the recommendation as ordinary prose, then STOP and wait. Protocol:
     `.claude/skills/ask-human/SKILL.md`. Every reply ends with a `❓ QUESTION` / `⏹ NO QUESTION`
     marker as its literal last line.
  2. NO `advisor()` HERE. Independent certification = fresh-context read-only reviewer subagents
     (`.claude/agents/stack-infra-reviewer.md`); self-grading must be DISCLOSED as self-graded.
  3. REPORTS GO TO `var/claude/sleuth/` in the repo — gitignored by the blanket `/var` rule, survives
     compaction inside the session, never committed. NOT `~/.claude/projects/…`, which is wiped when
     the container is reclaimed.
  4. `--scope=global|both` IS REMOVED: `~/.claude/` here is GENERATED from repo files by
     `scripts/claude-bootstrap/install.sh`, so investigating it investigates a copy.
  5. ≤5 concurrent subagents, in two sequential batches. Every agent writes its raw findings to
     `var/claude/sleuth/raw/<X>.md` BEFORE returning — autocompact fires here and in-conversation
     results do not survive it.
  6. PROJECT RULES WIN on any conflict: `/stack/CLAUDE.md`.
═══════════════════════════════════════════════════════════════════════════════════ -->

## /stack lens K — MANDATORY additional agent (infrastructure divergence)

Beyond agents A–J, **always run agent K** on this repo. It targets the failure class unique to /stack:
a container that is *functionally fine but structurally wrong*, where nothing crashes and no test fails.

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

Report its findings as category **K** alongside A–J.

## --help

> If ARGUMENTS contains `--help`: output the text below verbatim, then immediately STOP — do not execute any other steps. (`--help` takes precedence over all other flags.)
>
> ```
> /sleuth — Behavioral bug hunter: silent failures, logic traps, contract violations,
>           cross-component inconsistencies, edge cases. Read-only; proposes, never fixes.
>
> Usage: /sleuth [--quick] [--focus=<A..K>] [--target=<path>]
>
> Flags:
>   --quick          Agents A, B, F and K only (~3 min)
>   --focus=<X>      Run a single agent
>   --target=<path>  Investigate a specific directory (default: the repo root)
> ```
>
> Then STOP.

---

# /sleuth — Behavioral Bug Hunter

## Step 0: Setup

```bash
# --target picks the directory to investigate; there is no --scope here (see adaptation note 4).
TARGET="${target_arg:-${CLAUDE_PROJECT_DIR:-$PWD}}"
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
SLEUTH_DIR="$REPO_ROOT/var/claude/sleuth"
mkdir -p "$SLEUTH_DIR/raw"
TODAY=$(date +%Y-%m-%d-%H%M)
REPORT_PATH="$SLEUTH_DIR/$TODAY.md"
PRIOR=$(ls "$SLEUTH_DIR"/*.md 2>/dev/null | sort -r | head -1 || true)
```

Announce: "Investigating: `$TARGET` → saving to `$REPORT_PATH`". If a prior run exists, note its date;
agents flag findings still present since then as **[CHRONIC]**.

## Step 1: Detect project context

```bash
ls "$TARGET"/{Makefile,docker-compose.yaml,.env,README.md,CLAUDE.md} 2>/dev/null
ls "$TARGET"/docker/images/ 2>/dev/null | head -30
ls "$TARGET"/bin/ "$TARGET"/bin/tests/ 2>/dev/null
grep -c '' "$TARGET/.env" 2>/dev/null
git -C "$TARGET" log --oneline -10 2>/dev/null || true
```

Summarise as `PROJECT_CONTEXT`: service count by tier, which services are in `COMPOSE_FILE`, the shell
script inventory, whether the stack is currently up (`ls tools/successes/ tools/errors/`). Pass it to
every agent — an agent without it re-derives the tier model badly.

## Step 2: Spawn investigation agents

Respect flags:
- `--quick`: spawn only A, B, F, **K**
- `--focus=<X>`: spawn only that agent
- Default: two sequential batches, **never more than 5 concurrent** — Batch 1 = A–E, wait for all;
  Batch 2 = F–J + K, wait for all.

Each agent prompt gets `<TARGET>`, `PROJECT_CONTEXT`, `CURRENT_DATE`, `PRIOR_NOTE`, and its own
`$OUTPUT_FILE` = `$SLEUTH_DIR/raw/<X>.md`. Each ends with: *"Write your full findings to `$OUTPUT_FILE`
using the Write tool. Return only: 'Complete — [N] findings.'"*

**Agent A: Logic & condition traps** — tautological conditions; dead branches unreachable given prior
guards; negation at the wrong level (`! a && b` vs `! (a && b)`); `[ ]` vs `[[ ]]` operator-precedence
surprises; assignment where comparison was meant; loop bounds that never terminate or always skip;
short-circuit `&&`/`||` used as control flow in a way that silently skips a step. Report file:line,
what the condition actually evaluates to, what was intended, confidence, and the triggering input.

**Agent B: Silent failure patterns** — ignored return values from `mkdir`, `cp`, `mv`, `curl`, `git`,
`docker`, `jq`; `2>/dev/null` in a path where the error mattered; `|| true` that converts a real
failure into apparent success; a `trap`/`stackCatch` handler that logs but leaves partially-created
state; a function returning 0 unconditionally. **Note the legitimate exceptions here**: `log_obs`
writes end in `|| true` by contract (framework Rule 13), and the PreCompact hook's unconditional
`exit 0` is its contract — do not report either as a bug.

**Agent C: Contract & interface violations** — a documented `--flag` parsed differently than described;
`templates/tips/*.md` or `CLAUDE.md` describing a behaviour the script does not implement; a function
whose comment claims idempotence but which mutates state; a `make` target whose name promises less
(or more) than it does — `make soft-restart` being the archetype; a healthcheck whose condition does
not match the marker the script writes.

**Agent D: Cross-component inconsistencies** — the same constant with different values in two files;
the same error condition handled incompatibly in sibling startup scripts; a var written by one
container and read by another under a different name; two config-loading paths yielding different
results for the same file; a port number appearing twice; a token string spelled differently in the
compose file and the script.

**Agent E: Edge case & boundary traps** — unquoted paths that break on spaces; empty-string vs unset
distinctions (`${VAR:-}` vs `${VAR-}`); `sort -V` assumptions on non-semver input; arithmetic on a
value that can be empty; a `grep` whose no-match exit 1 aborts under `set -e`; regex anchors missing
so a partial match wins; version comparisons where `1.10` sorts below `1.9` lexically.

**Agent F: Shell-specific bugs** — missing `set -eEuo pipefail` on a new script (respecting the
deliberate variants: `set -xeE -o pipefail` in container startup scripts, `set -uo pipefail` in the
never-fail hook); word splitting on unquoted expansions; `cd` without `|| exit`; a subshell whose
variable assignment is lost to the parent (the project convention is to pass state through temp files
because stdout is reserved for return values); a missing include guard in `bin/lib/`; a lib file that
`source`s another instead of declaring `# Sources:`.

**Agent G: State & idempotency** — a script that is not safe to re-run: an append that duplicates on
second run, a `mkdir` without `-p`, a marker written before the work it certifies completes (so a
crash mid-install leaves a success marker), cleanup that runs on success but not on failure.

**Agent H: Concurrency & ordering** — two containers writing the same `tools/` path; a healthcheck
that can pass before the work finishes; a dependency expressed as `depends_on` without
`condition: service_healthy` where health is what actually matters.

**Agent I: Data & credential handling** — a real secret in a tracked file; a credential logged; a
`docker/data` vs named-volume confusion that would silently discard DB state; a backup path that can
be clobbered.

**Agent J: Observability gaps** — a failure with no error token written; an error path that exits
non-zero without a message; a log line that cannot be attributed to a service; a diagnostic that
prints to stdout where stdout is reserved for a return value.

**Agent K: Infrastructure divergence** — the mandatory lens defined at the top of this file.

## Step 3: Synthesise the investigation report

```markdown
# /sleuth Report — <DATE>
Investigated: <TARGET> | Context: <PROJECT_CONTEXT summary>
Agents run: <letters> | Certification: <reviewer subagents | SELF-GRADED — reason>

## Executive summary
[3-5 sentences: the dominant bug class, the single most dangerous finding, overall confidence]

## Findings — HIGH confidence first
| # | Cat | Confidence | File:Line | What breaks | Reproduction | Fix |

## Findings — MEDIUM / LOW confidence
| # | Cat | Confidence | File:Line | What breaks | Why uncertain |

## [CHRONIC] — present in the prior run too
## Quick wins (High confidence, fix ≤30 min)
## Not reported (documented deliberate trade-offs collapsed, with reasons)
## Coverage gaps (what no agent could check, and why)
```

**Confidence is mandatory per finding** and must be earned: HIGH means you traced the actual code path,
not that the pattern looks wrong. A plausible-sounding finding with no traced path is MEDIUM at best —
in an infra repo, a confidently-wrong finding costs more than a missed one because it triggers a
rebuild cycle to disprove.

## Step 4: Save the report

Write to `$REPORT_PATH`. Announce the path.

## Step 5: Present findings — hard stop

Show the executive summary, the full HIGH-confidence table, and the quick wins. Then, in **plain text**
per `/ask-human`, and STOP:

```
N findings (High: X | Medium: Y | Low: Z). Nothing has been changed — every finding above is a
proposal.

1. Fix specific findings (recommended) — name the IDs, e.g. `S1, S4`.
2. Show the Medium/Low tables in full.
3. Show one category in full — name it, e.g. `category K`.
4. Nothing — close the report.

❓ QUESTION — which findings should I act on?
```

*Never fixes anything on its own. The developer decides.*
