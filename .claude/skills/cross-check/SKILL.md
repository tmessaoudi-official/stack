---
name: cross-check
description: Deep standalone validation of a spec or doc — hunts contradictions, undefined terms, unstated assumptions, missing sections and ambiguities, then certifies the analysis with fresh-context reviewer subagents. Use it on a doc before building from it, or to detect doc-vs-reality drift.
user-invocable: true
args: "<spec-file> [--drift] [--dry-run]"
disallowed-tools: AskUserQuestion
---

<!-- ═══════════════════════════════════════════════════════════════════════════════════
  /stack CONTAINER ADAPTATION (2026-08-05). Imported from the developer's machine bundle
  `claude-setup-global-20260722` (committed at claude-setup/claude-setup-global.tar.gz) via the
  already-container-adapted phorj port. These deltas OVERRIDE the body below wherever they conflict:

  1. QUESTIONS ARE PLAIN TEXT. `AskUserQuestion` TIMES OUT in this container, so a gate that "asks"
     cannot fire. Every "invoke ask-human" below means: print the question, a minimal concrete example,
     numbered options and the recommendation as ordinary prose, then STOP and wait. Protocol:
     `.claude/skills/ask-human/SKILL.md`. Every reply ends with a `❓ QUESTION` / `⏹ NO QUESTION`
     marker as its literal last line.
  2. NO `advisor()` HERE. Independent certification = fresh-context read-only reviewer subagents
     (the 3-lens panel in `.claude/agents/` — `stack-infra-reviewer`, `completeness-reviewer`, `reproducibility-reviewer`; see `CLAUDE.md` § "Certification ladder"). Self-grading is the last resort and MUST be
     DISCLOSED as self-graded in the output.
  3. REPORTS GO TO `var/claude/…` in the repo — gitignored by the blanket `/var` rule, survives
     compaction inside the session, never committed. NOT `~/.claude/projects/…`, which is wiped when
     the container is reclaimed.
  4. THE JIRA MODE IS DELETED. There is no Jira and no Jira MCP server here, so the mode could never
     run — a documented mode that cannot execute is worse than an absent one. Replaced by `--drift`,
     which is the check this project actually needs.
  5. PROJECT RULES WIN on any conflict: `/stack/CLAUDE.md`.
═══════════════════════════════════════════════════════════════════════════════════ -->

## --help

> If ARGUMENTS contains `--help`: output the text below verbatim, then immediately STOP — do not execute any other steps. (`--help` takes precedence over all other flags.)
>
> ```
> /cross-check — Deep standalone validation of a spec or doc: contradictions, undefined terms,
>                unstated assumptions, missing sections, ambiguities. Certified by fresh-context
>                reviewer subagents.
>
> Usage: /cross-check <spec-file> [--drift] [--dry-run]
> ```
>
> Then output the complete flag table from the **"Flags"** section below. Then STOP.

---

# /cross-check — Doc validation

Parse `$ARGUMENTS`:

## Flags

| Flag | Behavior |
|------|----------|
| `<spec-file>` | Path to the doc to validate (required) |
| `--drift` | Also verify every checkable claim against the actual repo state (see Mode B) |
| `--dry-run` | Print findings to conversation only; no output file written |

If `<spec-file>` is not provided: report the error and stop.

Natural targets in this repo: `CLAUDE.md`, `templates/tips/env-update.md`, `templates/tips/env-scan.md`,
`templates/tips/file-layout.md`, `README.md`, `TODO.md`, `docs/**`, any `docs/plans/*.plan.md`, and
`scripts/claude-bootstrap/README.md`.

---

## Mode A — internal consistency (default)

### Step 1 — Read the doc fully

Read `<spec-file>` completely before forming any judgement. Do not skim; a contradiction between
section 2 and section 19 is invisible to a partial read, and that is the class of finding this skill
exists for.

### Step 2 — Independent check

Investigate the three angles yourself, then certify with **fresh-context read-only reviewer subagents**
that read the doc themselves (`advisor()` does not exist here). Loop: investigate → certify → repeat
until a round raises nothing new; cap at 5 rounds, then ask in plain text — never silently proceed.

- **Angle 1** (expanding-context): Are there implicit requirements not explicitly stated? Assumed
  context a reader might not share?
- **Angle 2** (adversarial): What internal contradictions exist? What claim in one section is
  contradicted in another?
- **Angle 3** (blast-radius): What is missing? What should be specified but isn't? Which edge cases
  are unaddressed?

Give the reviewers the doc and the analysis so far. If any raises something new, resolve it and re-run
the round.

### Step 3 — Categorise findings

- **CONTRADICTION** — a claim in section A directly contradicts a claim in section B
- **UNKNOWN** — a term or concept used without definition or reference
- **ASSUMPTION** — an implicit prerequisite not stated
- **MISSING** — a section that should exist but doesn't (error handling, rollback, security…)
- **AMBIGUOUS** — a statement that can be read more than one way
- **STALE** — a claim that was true once and is contradicted by the current tree (only with `--drift`)

---

## Mode B — `--drift`: doc vs reality

This project's docs make many **mechanically checkable** claims, and a stale one is worse than a
missing one because it is trusted. For every such claim in the doc, verify it and record the command
you ran as the evidence. Examples of what is checkable here:

| Claim shape | How to verify |
|---|---|
| "N scripts source the prologue" | `grep -rl 'global-stack-base-prologue.sh' docker/config/dist/bin/ \| wc -l` |
| "env-update has N tests across M sections" | run the suite and read the summary line |
| A file/path layout claim | `ls` / `find` the path; a documented path that does not exist is STALE |
| "`bin/env-scan.sh` is v1.0.0" | `bin/env-scan.sh --version` |
| A `.env` variable name or default | `grep '^GLOBAL_STACK_…=' .env` |
| A port range or "next free slot is N" | `grep -oE '4[12]7[0-9]{2}' .env \| sort -u \| tail` |
| "service X is in COMPOSE_FILE" | `grep COMPOSE_FILE .env` |
| A `make` target exists | `grep -E '^<target>:' Makefile` |
| "N skills / N hooks exist" | `ls .claude/skills/ \| wc -l`, `ls .claude/hooks/` |
| A tool is available | `command -v <tool>` — and note that shellcheck/hadolint/yamllint/shfmt/yamlfmt are ABSENT in the remote container, so any doc claiming they run is conditionally stale |

Report each as **STALE** with: the claim, the command, its actual output, and the corrected value.
Do **not** silently fix the doc — report first. Docs are the project's memory; a correction the
developer has not seen is indistinguishable from a new error.

Counts drift fastest and are the highest-yield thing to check.

---

## Step 4 — Write output

- `--dry-run`: print to conversation only, then stop.
- Otherwise: write to `var/claude/reports/crosscheck-<basename>-<date>.md` (gitignored). Do **not**
  write `<spec-file>.validation.md` next to the source — that path is tracked here and the report is
  session state, not a deliverable.

State in the output whether certification was by reviewer subagents or **self-graded** (and if
self-graded, say why no reviewer was available). Also state which claims you could **not** check and
why — a doc validated with unverifiable claims silently marked OK is the failure mode this skill is
supposed to catch.
