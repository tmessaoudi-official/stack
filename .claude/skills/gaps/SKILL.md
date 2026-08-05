---
name: gaps
description: Use when hunting for incomplete implementations, missing features, unfulfilled promises, stubs, TODO markers, partial feature flags, or undocumented capabilities across the project.
user-invocable: true
args: "[--quick] [--focus=<A..K>] [--target=<path>] [--priority=high]"
side-effects: Writes a report to var/claude/gaps/<date>.md (gitignored; never committed)
disallowed-tools: AskUserQuestion
---

<!-- ═══════════════════════════════════════════════════════════════════════════════════
  /stack CONTAINER ADAPTATION (2026-08-05). Imported from the developer's machine bundle
  `claude-setup-global-20260722` (committed at claude-setup/claude-setup-global.tar.gz) via the
  already-container-adapted phorj port. These deltas OVERRIDE the body below wherever they conflict:

  1. QUESTIONS ARE PLAIN TEXT. `AskUserQuestion` TIMES OUT in this container. Any "ask" is plain prose
     per `.claude/skills/ask-human/SKILL.md`; every reply ends with a `❓ QUESTION` / `⏹ NO QUESTION`
     marker as its literal last line.
  2. REPORTS GO TO `var/claude/gaps/` in the repo — gitignored by the blanket `/var` rule, survives
     compaction inside the session, never committed. NOT `~/.claude/projects/<slug>/gaps/`, which is
     wiped when the container is reclaimed — the upstream path, and the reason this was re-pointed.
  3. `--scope=global|both` IS REMOVED: `~/.claude/` here is GENERATED from repo files by
     `scripts/claude-bootstrap/install.sh`, so scanning it scans a copy.
  4. ≤5 concurrent subagents in two sequential batches; every agent writes raw output to
     `var/claude/gaps/raw/<X>.md` BEFORE returning.
  5. THE SELF-REFLECTION STEP IS REMOVED — it had an agent rewrite this skill's own definition, which
     is a self-modifying config change and belongs in a reviewed commit, not a side effect of a scan.
  6. PROJECT RULES WIN on any conflict: `/stack/CLAUDE.md`.
═══════════════════════════════════════════════════════════════════════════════════ -->

## --help

> If ARGUMENTS contains `--help`: output the text below verbatim, then immediately STOP — do not execute any other steps. (`--help` takes precedence over all other flags.)
>
> ```
> /gaps — Find what is missing or unfinished: stubs, TODO markers, partial implementations,
>         promised-but-absent features, undocumented capabilities. Read-only; never fills a gap.
>
> Usage: /gaps [--quick] [--focus=<A..K>] [--target=<path>] [--priority=high]
>
> Flags:
>   --quick           Agents A, F, H and K only (~3 min)
>   --focus=<X>       Run a single agent
>   --target=<path>   Scan a specific directory (default: the repo root)
>   --priority=high   NOW items only — skip Soon/Later
> ```
>
> Then STOP.

---

Differentiation from `/inspect`: `/inspect` finds *what is wrong with existing things*. `/gaps` finds
*what is missing or unfinished* — features described but not implemented, work started but not
completed, documentation promising things the code does not deliver.

## Step 0: Setup

```bash
TARGET="${target_arg:-${CLAUDE_PROJECT_DIR:-$PWD}}"
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
GAPS_DIR="$REPO_ROOT/var/claude/gaps"
mkdir -p "$GAPS_DIR/raw"
TODAY=$(date +%Y-%m-%d-%H%M)
REPORT_PATH="$GAPS_DIR/$TODAY.md"
PRIOR_GAPS=$(ls "$GAPS_DIR"/*.md 2>/dev/null | sort -r | head -1 || true)
```

Announce: "Scanning gaps: `$TARGET` → saving to `$REPORT_PATH`".

If a prior `/gaps` run exists, note its date. Agents flag items pending since then as **[STALE]**,
which prioritises chronic incompleteness over fresh debt.

## Step 1: Detect project context

```bash
ls "$TARGET"/{Makefile,docker-compose.yaml,.env,README.md,CLAUDE.md,TODO.md} 2>/dev/null
head -60 "$TARGET/CLAUDE.md" 2>/dev/null
cat "$TARGET/TODO.md" 2>/dev/null | head -40
ls "$TARGET"/docker/images/ 2>/dev/null
ls "$TARGET"/templates/tips/ 2>/dev/null
git -C "$TARGET" log --oneline -10 2>/dev/null || true
```

Summarise as `PROJECT_CONTEXT`: service inventory, script inventory, doc inventory, project age from
git log. **`TODO.md` is a first-class input here** — it is the developer's own gap list, so a gap it
already records is not a discovery; cross-reference rather than re-report.

## Step 2: Spawn gap-detection agents

Respect flags:
- `--quick`: spawn only A, F, H, **K**
- `--priority=high`: instruct agents to report NOW-priority items only
- `--focus=<X>`: spawn only that agent
- Default: two sequential batches, **never more than 5 concurrent** — Batch 1 = A–E; Batch 2 = F–J + K.

Each agent gets `<TARGET>`, `PROJECT_CONTEXT`, `CURRENT_DATE`, the prior-run note, and its own
`$OUTPUT_FILE` = `$GAPS_DIR/raw/<X>.md`, ending with: *"Write your full findings to `$OUTPUT_FILE`
using the Write tool. Return only: 'Complete — [N] findings.'"*

**Agent A: Explicit debt markers** — `TODO`, `FIXME`, `HACK`, `XXX`, `WORKAROUND`, `BUG`, `KLUDGE` in
scripts, Dockerfiles, compose files and docs. Classify by age (`git blame`) and actionability. Note
that `@todo env-update` is **not** debt — it is the version-annotation system and must not be reported.

**Agent B: Stubs & placeholders** — functions with empty or `:` bodies; scripts that only `echo` a
"not implemented" message; a startup script whose install branch is a no-op; placeholder values left
in `.env` (`changeme`, `xxx`, `TODO`); `local.*` templates never activated.

**Agent C: Partial implementations** — a `case` statement missing a branch the docs promise; a parsed
CLI flag never used (grep the flag name: parsed once, referenced never); an `env-update` fetcher type
declared but unimplemented; a service with a Dockerfile but no compose file (or the reverse); a
`MODE` value handled in one script but not its sibling.

**Agent D: Undocumented capabilities (code exists, docs absent)** — `make` targets absent from
`CLAUDE.md`/`README.md`; `GLOBAL_STACK_*` vars read by a script but missing from `.env`; script flags
absent from `templates/tips/*.md`; a `.claude/hooks/` script no doc mentions; a service directory
absent from the architecture table.

**Agent E: Promised-but-absent (docs mention, code missing)** — a command or flag documented in
`CLAUDE.md`/`templates/tips/` with no implementation; an env var documented but never read; a workflow
referencing a script that does not exist; a slash command listed but with no `SKILL.md`; a test file
named in the docs but absent from `bin/tests/`. **This is the highest-value agent in this repo** — the
docs here are unusually detailed, which makes an unfulfilled promise unusually easy to trust.

**Agent F: Missing tests for named features** — `bin/*.sh` and startup scripts with no counterpart in
`bin/tests/`; documented behaviours with no assertion (version gating, token writing, port parsing, env
propagation); error paths with no test; a documented flag with no test exercising it.

**Agent G: Config & environment gaps** — a var used by a script but absent from `.env`; a version pin
with no `@todo env-update` annotation (invisible to the updater, so it silently rots); a service with
no `GLOBAL_STACK_ERROR_TOKEN`; a port var with no allocated slot; required config with no startup
validation.

**Agent H: Missing error-handling paths** — a happy path with no failure branch; an install step that
can fail without writing its error token; `stackCatch`/`trap` absent from a script that creates state;
cleanup that runs on success but not on failure; no rollback for a partially-completed install.

**Agent I: Template & placeholder markers** — `<!-- ADAPT: -->` markers, `{{VAR}}` placeholders,
skeleton banners, `.template` files never instantiated, a scaffolded service still carrying
`/new-service` boilerplate comments.

**Agent J: Integration & dependency stubs** — a Makefile target invoking a missing script; a compose
`depends_on` naming a service absent from `COMPOSE_FILE`; a `# Sources:` header naming a file that does
not exist; a hook registered in `settings.json` with no script on disk; an unused fixture directory.

**Agent K: /stack completeness matrix (MANDATORY)** — for **every** directory under `docker/images/`,
build a table with a column per required artifact and a row per service: compose file present ·
Dockerfile present · `GLOBAL_STACK_ERROR_TOKEN` set · listed in `COMPOSE_FILE` · five Makefile macro
lines (`login-service-shell`, `login-service-sh`, `log-service`, `log-follow-service`,
`restart-service`) · `.PHONY` entry · port var(s) allocated with trailing `:` · startup script exists ·
tier-02 manager present when it is a tier-03 service · `@todo env-update` annotation on its version
pin. **Any empty cell is a gap.** This one table catches more real incompleteness in this repo than the
other ten agents combined, because adding a service means touching seven places and the seventh is the
one that gets forgotten. Research only, no writes.

## Step 3: Synthesise the gaps report

```markdown
# /gaps Report — <DATE>
Scanned: <TARGET> | Agents: <letters> | Context: <PROJECT_CONTEXT summary>

## Executive summary
[3-5 sentences: the dominant kind of incompleteness, the most actionable gap, overall completeness feel]

## Completeness matrix (Agent K)
[the per-service table — empty cells are the gaps]

## Priority roadmap
### NOW — blocking or high-impact
| # | Cat | Gap | Location | Effort |
### SOON — important, not blocking
### LATER — nice to have

## Findings by category (A–K)
## [STALE] — still open since <PRIOR_DATE>
## Already tracked in TODO.md (cross-referenced, not re-reported)
## Quick wins (effort=Quick, priority NOW or SOON)
## Coverage gaps (what could not be checked, and why)
```

## Step 4: Save the report

Write to `$REPORT_PATH`. Announce the path. **Do not `git add` it.**

## Step 5: Present the roadmap — hard stop

Show the executive summary, the completeness matrix, the full NOW table, and the quick wins. Then, in
**plain text** per `/ask-human`, and STOP:

```
N gaps found (Now: X | Soon: Y | Later: Z). Nothing has been changed — every finding above is a
proposal.

1. Fill specific gaps (recommended) — name the IDs, e.g. `G1, G3`.
2. Show all SOON items.
3. Show one category in full — name it, e.g. `category K`.
4. Nothing — close the report.

❓ QUESTION — which gaps should I fill?
```

*Never fills anything on its own. The developer decides what to close.*
