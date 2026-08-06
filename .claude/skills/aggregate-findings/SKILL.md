---
name: aggregate-findings
spotlight: true
description: Cross-stage synthesis of review reports — deduplicates findings that appear across /inspect, /sleuth, /gaps, /sweep and /cross-check runs. Produces one prioritized master list with cross-references instead of N separate reports. Use after running two or more of those skills.
user-invocable: true
args: "[--top=N] [--since=<date>]"
side-effects: Writes a consolidated report to var/claude/reports/aggregate-<date>.md (gitignored; never committed)
disallowed-tools: AskUserQuestion
---

<!-- ═══════════════════════════════════════════════════════════════════════════════════
  /stack CONTAINER ADAPTATION (2026-08-05). Imported from the developer's machine bundle
  `claude-setup-global-20260722` (committed at claude-setup/claude-setup-global.tar.gz) via the
  already-container-adapted phorj port. These deltas OVERRIDE the body below wherever they conflict:

  1. QUESTIONS ARE PLAIN TEXT. `AskUserQuestion` TIMES OUT in this container. Any "ask" is plain prose
     per `.claude/skills/ask-human/SKILL.md`; every reply ends with a `❓ QUESTION` / `⏹ NO QUESTION`
     marker as its literal last line.
  2. NO `advisor()` HERE. Independent certification = fresh-context read-only reviewer subagents
     (`.claude/agents/stack-infra-reviewer.md`); self-grading must be DISCLOSED as self-graded.
  3. REPORTS GO TO `var/claude/…` in the repo — gitignored by the blanket `/var` rule, never committed.
  4. ≤5 concurrent subagents, and every agent writes its raw output under `var/claude/reports/raw/`
     BEFORE returning — autocompact fires here and in-conversation results do not survive it.
  5. `/mega-analysis` WAS NOT IMPORTED, so there is no umbrella run to key off: the stage set is
     simply whatever reports exist under `var/claude/`.
  6. PROJECT RULES WIN on any conflict: `/stack/CLAUDE.md`.
═══════════════════════════════════════════════════════════════════════════════════ -->

## --help

> If ARGUMENTS contains `--help`: output the text below verbatim, then immediately STOP — do not execute any other steps. (`--help` takes precedence over all other flags.)
>
> ```
> /aggregate-findings — Cross-stage synthesis of review reports: deduplicates findings across
>                       /inspect, /sleuth, /gaps, /sweep and /cross-check into one prioritized
>                       master list.
>
> Usage: /aggregate-findings [--top=N] [--since=<date>]
> ```
>
> Then output the complete flag table from the **"Flags"** section below. Then STOP.

---

# /aggregate-findings

## When to use

Run after **two or more** of `/inspect`, `/sleuth`, `/gaps`, `/sweep`, `/cross-check` have produced
reports, to synthesise them into one deduplicated, prioritised master list.

## Flags

| Flag | Behavior |
|------|----------|
| `--top=N` | Show only the top N unique findings (default: all) |
| `--since=<date>` | Only aggregate reports dated on/after this (default: the most recent report per skill) |

## Step 0 — Locate reports

```bash
# Reports live in the repo under var/ (gitignored) — see the adaptation header.
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
REPORT_ROOT="$REPO_ROOT/var/claude"
mkdir -p "$REPORT_ROOT/reports/raw"
# Enumerate what actually exists — this list IS the stage set:
find "$REPORT_ROOT" -name '*.md' -not -path '*/reports/*' | sort
```

Enumerate every report found and **state the count before reading** — an unlisted report is a coverage
gap, and a silently dropped one turns this skill into a confident lie.

If fewer than two reports exist, say so and stop: there is nothing to cross-reference, and a single
report needs no synthesis.

## Step 1 — Read all stage reports (batches of ≤5)

Read every report from Step 0 in batches of at most 5 files (the concurrency ceiling for LLM-backed
agents here). Typical stage set: `/sweep`, `/sleuth`, `/inspect`, `/gaps`, `/cross-check`.

## Step 2 — Spawn 3 synthesis agents (parallel, ≤5)

Each agent writes its raw output to `var/claude/reports/raw/<agent>-<date>.md` **before** returning.

### Agent 1: Deduplication detector
"You are given N stage reports from this project's review skills. Identify findings that appear in 2
or more reports — these are the highest-confidence issues. For each, list: the finding name/ID, which
stages mention it, what each stage says (noting contradictions), and a deduplicated one-sentence
summary. Output a markdown table. Only report findings appearing in ≥2 stages."

### Agent 2: Priority ranker
"You are given N stage reports. Produce a single master priority list of ALL unique findings, ranked
by (1) severity (CRITICAL/P0 before WARNING/P1), (2) fix cost (Quick before Long), (3) breadth of
impact. Remove exact duplicates. Format: numbered list with severity badge, one-line description,
estimated fix time, and the originating stage. Cap at 50 entries."

### Agent 3: Quick wins extractor
"You are given N stage reports. Extract every 'quick win': WARNING severity or higher AND fix cost
≤30 min. Output a table: finding, stage, exact file/line, exact fix, minutes. At most 20 rows, ranked
by impact."

## Step 2b — /stack severity reconciliation

Before ranking, normalise against this project's real severity anchors, because the stage skills use
slightly different vocabularies and an un-anchored merge produces a meaningless ordering:

- **CRITICAL** — token-invariant violation, a startup-script change landing on every tier-03 consumer
  unintentionally, trailing `;` in `COMPOSE_FILE`, a port var missing its `:`, a committed secret,
  shell injection, anything that risks `tools/` or DB volume data.
- **WARNING** — incomplete env cascade (`.env` changed but `.env.local`/Dockerfile `ARG` not), missing
  test, unquoted expansion, missing `.PHONY` entry, an unguarded `bin/lib/` include.
- **NOTE** — naming, style, doc polish.
- **NOT A FINDING — drop it, and say you dropped it**: `privileged: true`, `start_period: 24h`,
  `retries: 99999`, `password = username`, `core.fileMode=false`, `set -xeE` without `-u` in startup
  scripts, `|| true` on `log_obs` writes, the PreCompact hook's unconditional `exit 0`. These are
  documented deliberate trade-offs (`CLAUDE.md` § Gotchas). If a stage reported one, collapse it here
  with the reason — leaving them in trains the reader to skim past real findings.

## Step 3 — Synthesise the consolidated report

```markdown
# Aggregate Findings — <date>
Generated: <timestamp> | Stages: <N, named> | Raw findings: ~<N> | Unique after dedup: ~<N>
Dropped as documented-deliberate: <N, named>
Certification: <reviewer subagents | SELF-GRADED — reason>

## Top 10 Cross-Stage Findings (appear in ≥2 stages — highest confidence)
[Agent 1 table]

## Quick Wins (WARNING+ / ≤30 min fix)
[Agent 3 table]

## Master Priority List (all unique findings, ranked)
[Agent 2 list]

## Conflicting severities
[Findings where stages disagreed — see Self-reflection]

## Coverage gaps
[Reports that existed but could not be parsed; dimensions no stage covered]
```

## Step 4 — Save and report

Save to `var/claude/reports/aggregate-<date>.md` (gitignored — never `git add` it).

Report to the developer:
- Total unique findings, and how many cross-stage duplicates were collapsed
- The top 5 quick wins
- How many findings were dropped as documented-deliberate, and which
- Any report that existed but could not be parsed — **a silently dropped stage is a coverage lie**
- Suggest: "Run `/aggregate-findings --top=10` for just the highest-priority items"

## Self-reflection

After saving, note every finding where the stages disagreed (one calls it CRITICAL, another NOTE) and
flag it as "conflicting severity". Disagreement between two independent passes is signal, not noise —
it usually means the finding's blast radius is genuinely unclear, which is itself worth reporting.
