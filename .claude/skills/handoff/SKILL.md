---
name: handoff
spotlight: true
description: Use at the end of a session to save current state so the next session can continue cleanly without losing context about what was done, what is pending, and any non-obvious gotchas.
user-invocable: true
disallowed-tools: AskUserQuestion
---

<!-- ═══════════════════════════════════════════════════════════════════════════════════
  /stack CONTAINER ADAPTATION (2026-08-05). Imported from the developer's machine bundle
  `claude-setup-global-20260722` (committed at claude-setup/claude-setup-global.tar.gz) via the
  already-container-adapted phorj and pdfturbo ports. These deltas OVERRIDE the body below wherever
  they conflict:

  1. QUESTIONS ARE PLAIN TEXT. `AskUserQuestion` TIMES OUT in this container, so a gate that "asks"
     cannot fire. Every "invoke ask-human" below means: print the question, a minimal concrete
     example, numbered options, and the recommended option FIRST with its reason, as ordinary prose —
     then STOP and wait. Protocol: `.claude/skills/ask-human/SKILL.md`. Every reply also ends with a
     `❓ QUESTION` / `⏹ NO QUESTION` marker as its literal last line.
  2. NO `advisor()` HERE — independent certification = fresh-context read-only reviewer subagents
     (the 3-lens panel in `.claude/agents/` — `stack-infra-reviewer`, `completeness-reviewer`, `reproducibility-reviewer`; see `CLAUDE.md` § "Certification ladder"). Self-grading is the last resort and MUST be disclosed.
  3. REPORTS GO TO `var/claude/…` in the repo — gitignored by the blanket `/var` rule. NOT
     `~/.claude/projects/…`: that is wiped when the container is reclaimed.
  4. PROJECT RULES WIN on any conflict: `/stack/CLAUDE.md` — delegation to `global-stack-lead-dev`,
     the master-only branch policy, and the git-autonomy override.
═══════════════════════════════════════════════════════════════════════════════════ -->

## --help

> If ARGUMENTS contains `--help`: output the text below verbatim, then STOP — do not execute any other steps.
>
> ```
> /handoff — Save session state so the next session continues cleanly: what was done, what is
>            pending, and the non-obvious gotchas.
>
> No flags — invoked without arguments.
> ```

---

Save session state for clean continuation next session.

Write a handoff note so the next session can continue cleanly. Use your knowledge of the current
session — you were here. Write in first person ("I").

**Path:** `var/claude/handoff/latest.md`, in the repo — resolve it as
`"${CLAUDE_PROJECT_DIR:-$PWD}"/var/claude/handoff/latest.md`. Create the directory if absent.

Upstream wrote to `~/.claude/projects/<slug>/memory/sessions/handoff.md`. **Do not.** That path is
wiped when the container is reclaimed, so a handoff written there is lost precisely when it is needed.
`var/claude/` is gitignored — it survives compaction *inside* a session and dies with the container,
which is the correct lifetime for session state.

Also append a timestamped copy at `var/claude/handoff/handoff-$(date +%Y-%m-%d-%H%M%S).md`, matching
what the PreCompact hook (`scripts/claude-bootstrap/hooks/precompact-handoff.sh`) already writes
automatically, so manual and automatic handoffs land in one place and read the same way.

**A handoff is never committed.** If something genuinely needs to survive the container, it belongs in
`CLAUDE.md` § Gotchas, in `templates/tips/`, or in `docs/plans/<topic>.plan.md` — all real changes,
proposed in plain text, not smuggled in as a note.

Format:

```
# Handoff

## State
{What's done, what's not. Files modified, decisions made, branch state. 2-4 lines max.}

## Next
{What to pick up. Priority order. 1-3 items.}

## Stack state
{Only if the stack was touched: which services are up, what is in tools/errors/, whether .env or
 .env.local was modified and whether env-scan has run, whether a rebuild is pending. Skip entirely
 if no stack operation happened this session.}

## Context
{Non-obvious gotchas, blockers, env state from this session. Skip section entirely if nothing.}
```

Rules:
- Under 25 lines total
- Specific: file paths, service names, token names, variable names, `make` targets
- Forward-looking — the next session doesn't care about the journey, only the current state
- **Never claim a verification that did not run.** In this container `shellcheck`/`hadolint`/
  `yamllint`/`shfmt` are absent, so "lint clean" is only true if you fetched a binary and ran it —
  say which tool actually ran, or say `bash -n` only
- **Uncommitted work is the thing most worth recording** — and in this repo the fix is usually to
  commit it rather than hand it off: `git add` / `git commit` / `git push origin master` are
  autonomously authorised. Prefer committing over describing
- If nothing meaningful to hand off, write: "No active work."

Say "Saved." when done — nothing else, plus the mandatory status marker.
