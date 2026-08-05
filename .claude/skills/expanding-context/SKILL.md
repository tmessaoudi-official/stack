---
name: expanding-context
description: Use at the start of Phase 1 Brainstorm for any task. Widens context before committing to an approach — ensures no blind spots. Silent by default; surfaces only surprises, material risks, or wrong-problem signals.
user-invocable: true
disallowed-tools: AskUserQuestion
---

<!-- ═══════════════════════════════════════════════════════════════════════════════════
  /stack CONTAINER ADAPTATION (2026-08-05). Imported from the developer's machine bundle
  `claude-setup-global-20260722` (committed at claude-setup/claude-setup-global.tar.gz) via the
  already-container-adapted phorj and pdfturbo ports. These deltas OVERRIDE the body below wherever
  they conflict:

  1. QUESTIONS ARE PLAIN TEXT. `AskUserQuestion` TIMES OUT in this container. Any "ask the user"
     below means plain prose: context, a minimal concrete example, numbered options, recommended
     option FIRST with its reason — then STOP. Protocol: `.claude/skills/ask-human/SKILL.md`.
     Every reply ends with a `❓ QUESTION` / `⏹ NO QUESTION` marker as its literal last line.
  2. THE STANDING DIRECTIVE IS `no interrupts`. This skill is SILENT by default; surfacing a finding
     is the exception, and only for a material risk or a wrong-problem signal.
  3. PROJECT RULES WIN on any conflict: `/stack/CLAUDE.md`.
═══════════════════════════════════════════════════════════════════════════════════ -->

## --help

> If ARGUMENTS contains `--help`: output the text below verbatim, then STOP — do not execute any other steps.
>
> ```
> /expanding-context — Widen context before committing to an approach. Silent by default;
>                      surfaces only surprises, material risks, or wrong-problem signals.
>
> No flags — invoked automatically by Claude during the reasoning workflow.
> ```

---

# Expanding Context

You are about to commit to an approach. This skill ensures you see the full territory before you do.

**What this skill does**: runs the expansion framework internally (self-contained — the standalone
`/expand` skill was not imported; the six groups below ARE the framework). You do NOT output the full
expansion to the user — you use the findings to inform your Phase 1 and Phase 2 thinking. Produce only
a brief internal summary (3–5 bullets) then proceed.

**When to surface the full expansion**: only if the developer explicitly asked for it (e.g. "what am I
missing?", "give me the full picture", "expand this"). Otherwise keep it internal and continue with
the enriched context.

---

## Internal expansion (run silently)

Quickly sweep these 6 groups — 1–2 observations each, focus on surprises and non-obvious items only.
Skip dimensions where nothing is notable.

**I — Identity**: Is the scope what it appears to be? Is the mental model obvious?

**II — Structure**: What depends on this? What does this depend on? Any hidden contracts?

**III — Behavior**: What are the non-obvious failure modes? What edge cases exist?

**IV — Quality**: Any known issues, dark observability, or test gaps that matter here?

**V — Context**: What constraints or assumptions are load-bearing for this decision?

**VI — Discovery**: Any gaps, risks, or contradictions worth surfacing before proceeding?

**Questions**: Generate 2–3 internal questions — especially Strategic ones. If any question would
materially change the approach, surface it before continuing.

---

## /stack dimensions — check these every time

This project's blind spots are structural and repeat. Sweep them explicitly:

- **Tier ordering.** Does this touch a tier-03 runtime whose tier-02 manager must be healthy first
  (`02nvm`→`03node*`, `02phpbrew`→`03php*`, `02sdkman`→`03java*`)? Is that manager in `COMPOSE_FILE`?
- **The two-phase model.** Tier 02 runs `MODE=install`, tier 03 runs `MODE=setup`, and **both use the
  same startup script**. A change to `nvm-start.sh` therefore lands on `02nvm` AND every `03node*`.
  This is the single most common source of unintended blast radius here.
- **Token invariant.** Any health-signalling change: does the success write still use the same
  identifier as `GLOBAL_STACK_ERROR_TOKEN`? A mismatch yields a permanently-unhealthy-yet-functional
  container, masked for 24h by `start_period`.
- **Env cascade.** Does this touch `.env`? Then `.env.local` and Dockerfile `ARG` lines are downstream
  via `env-scan`, and `${VAR}` expansion means order of definition matters.
- **Port vars.** A set port var must end with `:` — the compose template is `${VAR:-}PORT`, so
  omitting the colon silently concatenates digits rather than failing.
- **Shared mutable state.** `tools/` is bind-mounted into *every* container. Is the change safe when
  two containers hit it concurrently, and is it idempotent across a restart?
- **What is deliberate, not broken.** `privileged: true` on all containers, `start_period: 24h`,
  `retries: 99999`, and `core.fileMode=false` are all intentional. Do not "fix" them.
- **Machine-local overrides.** `docker-compose*.local.yaml`, `local.*` image dirs and `local.Makefile`
  are gitignored and can silently change behaviour. Check whether one exists before concluding
  anything about how a service actually runs.

---

## Decision gate

After the internal sweep:

- **No surprises found**: proceed to Phase 2 with enriched context. No output needed.
- **1–2 notable findings**: mention them briefly inline ("One thing worth noting before we
  proceed: …") then continue.
- **Material risk or wrong-problem signal**: STOP and surface it explicitly, in plain text per
  `/ask-human`. This is more valuable than any implementation.

---

## Skip conditions

Do NOT invoke this skill when:
- Input is already broad ("review the whole stack", "audit the compose files")
- Task is a simple lookup or rename with no design decisions
- You already ran this skill in the current session for the same topic
- The developer explicitly said "just do it" (Small task signal — respect it)
