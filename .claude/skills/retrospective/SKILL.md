---
name: retrospective
spotlight: true
description: Use at the end of a long or complex session for deliberate end-of-session learning extraction and memory capture across hidden dependencies, naming surprises, behavioral quirks, and decision rationale.
user-invocable: true
args: "[--quick] [--source=project|all]"
side-effects: Writes memory entries to var/claude/memory/ (gitignored; never committed)
disallowed-tools: AskUserQuestion
---

<!-- ═══════════════════════════════════════════════════════════════════════════════════
  /stack ADAPTATION (2026-08-06) of the rent-watch port (2026-08-06), itself from the twes-in →
  pdfturbo → phorj line, descending from the developer's machine bundle
  `claude-setup-global-20260722` (committed here at claude-setup/claude-setup-global.tar.gz). The
  port's machinery is kept; the memory TARGET is re-pointed and the approval gate removed. These
  deltas OVERRIDE the body below wherever they conflict:

  1. QUESTIONS ARE PLAIN TEXT. `AskUserQuestion` TIMES OUT in this container. Every reply ends with a
     `❓ QUESTION` / `⏹ NO QUESTION` marker as its literal last line. Protocol:
     `.claude/skills/ask-human/SKILL.md`.
  2. THE UPSTREAM MEMORY PIPELINE IS NOT INSTALLED. There is no `~/.claude/hooks/session-remember/`,
     no `MEMORY.md` index, and no `~/.claude/projects/<slug>/memory/`. Entries go to
     **`var/claude/memory/`** in the repo — gitignored via the blanket `/var` rule, surviving
     compaction inside the session and dying with the container, which is the correct lifetime for
     session state. A memory written to `~/.claude/projects/…` is lost exactly when it is needed.
  3. NO APPROVAL GATE. The standing directive for this repo is *no interrupts*, and the write target
     is gitignored and ephemeral, so an unwanted entry costs nothing. Write the entries, then report
     what was written. Upstream stopped for per-entry approval because it wrote to the developer's
     real machine memory; that reason does not apply here.
  4. `--scope=global|both` IS REMOVED: `~/.claude/` here is GENERATED from repo files by
     `scripts/claude-bootstrap/install.sh`.
  5. PROJECT RULES WIN on any conflict: `/stack/CLAUDE.md`.
  6. THE CONTINUITY MECHANISM HERE IS GIT, NOT MEMORY. `var/claude/memory/` dies with the container.
     Anything that must outlive it belongs in `CLAUDE.md` § "Gotchas & Pitfalls", in
     `templates/tips/`, or in a `docs/plans/<topic>.plan.md` `## Decisions Log` — as a reviewed,
     committed change proposed in plain text. This skill never edits those files itself.
═══════════════════════════════════════════════════════════════════════════════════ -->

## --help

> If ARGUMENTS contains `--help`: output the text below verbatim, then immediately STOP — do not execute any other steps.
>
> ```
> /retrospective — End-of-session learning extraction: hidden dependencies, naming surprises,
>                  behavioural quirks, failure patterns, workarounds, decision rationale.
>
> Usage: /retrospective [--quick] [--source=project|all]
>
> Flags:
>   --quick             Two highest-signal lenses only (failure pattern + decision rationale)
>   --source=project    Skip the within-repo duplicate check
> ```
>
> Then STOP.

---

# /retrospective — Session Learning Capture

Manual trigger for end-of-session learning extraction. Companion to the automatic Phase 8 learning
prompt — use this for a deliberate sweep after a long or complex session.

**Flags**:

| Flag | Behavior |
|------|----------|
| `--quick` | The two highest-signal lenses only (Failure pattern + Decision rationale); skips the 6-lens scan and Step 2.5. |
| `--source=project\|all` | (default: `all`) — `all` runs Step 2.5's duplicate check against `var/claude/memory/`; `project` **skips** Step 2.5 entirely. Upstream used this flag to scan *other projects'* `MEMORY.md` indices; there is no memory pipeline and no other project reachable here, so the cross-project half does nothing — but the skip is real, so the flag is not inert. |

---

## Step 1: Reconstruct what happened

```bash
git diff --stat
git log --oneline -10
```

If git shows nothing (a session that only touched gitignored paths — common here, since `tools/`,
`var/` and `.env.local` are all ignored), fall back to recency:

```bash
find "${CLAUDE_PROJECT_DIR:-$PWD}" -mmin -720 -type f \
  \( -name '*.sh' -o -name '*.md' -o -name '*.yaml' -o -name '*.yml' -o -name 'Dockerfile*' \
     -o -name 'Makefile*' -o -name '*.json' \) \
  -not -path '*/.git/*' -not -path '*/var/*' -not -path '*/tools/*' 2>/dev/null | head -20
```

Also read `var/claude/handoff/latest.md` if present — the PreCompact hook may already have captured the
session's own intent verbatim, which is a better record than reconstruction. And check the conversation
context directly: it is the authoritative record of what was done.

Summarise in one paragraph: the core task, the approach taken, what changed.

---

## Step 2: Extract non-obvious discoveries

**If `--quick`**: scan only "Failure pattern" and "Decision rationale", then jump to Step 3.

For each lens, ask the question and answer honestly — skip any where the answer is "nothing surprising":

| Lens | Question |
|------|----------|
| **Hidden dependency** | Did anything turn out to depend on something undocumented? |
| **Naming surprise** | Was anything named differently than expected (script, var, token, target, path)? |
| **Behavioral quirk** | Did a tool, container, or command behave in a non-obvious way? |
| **Failure pattern** | What broke, and why — and would it be easy to repeat the mistake? |
| **Workaround** | Was something fixed with a workaround a future session should know about? |
| **Decision rationale** | Was a design choice made that is not obvious from the code alone? |

**/stack lenses that tend to pay off** — check these specifically, because they are where this project
actually surprises people:

- **Tier/mode coupling**: did a change reach further than expected because one startup script serves both `MODE=install` and `MODE=setup`?
- **The env cascade**: did a `.env` edit require `.env.local` or a Dockerfile `ARG` you did not expect — or fail to propagate because the value contained `${`?
- **Marker semantics**: did a `tools/versions/`, `successes/` or `errors/` marker behave differently than assumed (e.g. `make down` not clearing `versions/`)?
- **Container-vs-host divergence**: did something work in the container but depend on `/stack` on the host, or fail because a linter/Docker was absent here?
- **An absolute-path or tooling assumption** that was silently inert (the `/stack/var/**` deny rules are the canonical example).

---

## Step 2.5: Within-repo duplicate check (skip if `--source=project` or `--quick`)

```bash
# Exactly ONE memory home exists in this container: the repo's own gitignored var/claude/memory.
ls "${CLAUDE_PROJECT_DIR:-$PWD}"/var/claude/memory/*.md 2>/dev/null
```

**Honest scope note:** with a single memory home this degrades from cross-*project* enrichment to a
within-repo duplicate check — it catches an entry you already wrote in an earlier session of this repo,
and nothing more. Say that rather than implying a fleet-wide scan.

Also compare each candidate against **`CLAUDE.md` § Gotchas and `templates/tips/*`**. If the discovery
is already documented there, it is not a discovery — drop it and say so. That check matters more here
than the memory one, because this repo's gotcha list is long and genuinely good.

Be conservative when matching: only flag on strong textual overlap. When uncertain, keep the entry.

---

## Step 3: Write the entries, then report

Upstream stops here for per-entry approval. **Here: write them all, then state plainly what was
written** (adaptation note 3).

```
[retrospective] wrote N entries → var/claude/memory/
  1. project  — <name>
  2. feedback — <name>
```

Two things this does NOT license:

- **Never write into the repo proper.** No `CLAUDE.md` edit, no `templates/tips/` file, no committed artifact from this skill. A discovery worth keeping permanently is a **`CLAUDE.md` § Gotchas** entry, and that is a real change — propose it in plain text with the exact diff and let the developer rule on it.
- **Never invent a discovery to fill the report.** If nothing non-obvious came up, write nothing and say `No discoveries worth persisting.` A padded retrospective is worse than an empty one, because it teaches the next session to distrust the file.

---

## Step 4: Entry placement

- About **the project** (a quirk, a hidden dependency, a workaround) → `project_*.md`
- About **how to collaborate** (a preference revealed, an approach that worked) → `feedback_*.md`
- About **the developer** (a domain they know deeply, a convention they care about) → `user_*.md`

One fact per entry, with a `Why:` and a `How to apply:`. Write to `var/claude/memory/` — **not**
`MEMORY.md`, which does not exist here.

**The graduation rule**: if a learning is durable enough to outlive the container, it does not belong in
`var/` at all. Propose it as a `CLAUDE.md` § Gotchas entry (or a `templates/tips/` addition, or a
`## Decisions Log` line in the relevant plan) and let it be committed. `var/claude/memory/` is for
things useful *this session and next*, not for institutional knowledge.

---

## Step 5: Report

```
Retrospective complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Session scope     : [1-sentence summary]
Discoveries saved : N
  - [file] → [one-line description]
Already documented: [candidates dropped because CLAUDE.md § Gotchas already covers them]
Nothing to save   : [lenses that returned no findings]
Graduation proposed: [any entry worth promoting to CLAUDE.md, with the exact diff]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If Step 2 found nothing for any lens: report "No non-obvious discoveries — session was routine." and
stop.
