---
name: converge
spotlight: true
description: Run the project's MAXIMAL certification ladder (CLAUDE.md § "Certification ladder"), or a deeper tunable convergence sweep, over an audit/migration/gate. Defaults ARE the /stack ladder — 3 adversarial evidence-based lenses, TWO consecutive fully-clean rounds, cap 5 rounds, certified by fresh-context reviewer subagents. Override with --cycles/--converge/--angles/--certify. Runs AUTONOMOUSLY by default and reports progress every cycle; --ask restores the approval gate. Escalates in PLAIN TEXT if it cannot converge.
user-invocable: true
args: "[--cycles=N] [--converge=K] [--scope=ladder|3C|6C|custom] [--angles='angle1;angle2;angle3'] [--certify=reviewer|self] [--ask] [--auto-cap=N]"
side-effects: None — read-only analysis loop; findings incorporated into conversation context only.
disallowed-tools: AskUserQuestion
---

<!-- ═══════════════════════════════════════════════════════════════════════════════════
  /stack ADAPTATION (2026-08-06) of the rent-watch port (2026-08-06), itself from the twes-in
  (2026-07-29) → pdfturbo (2026-07-27) → phorj (2026-07-22) line, all descending from the
  developer's machine bundle `claude-setup-global-20260722` (committed here at
  claude-setup/claude-setup-global.tar.gz). These deltas OVERRIDE the body below wherever they
  conflict:

  1. QUESTIONS ARE PLAIN TEXT. `AskUserQuestion` TIMES OUT in this container, so a gate that "asks"
     cannot fire. Every question is: context → a minimal concrete example → numbered options →
     recommended option FIRST with its reason → a visible "none of these / challenge the premise"
     escape → then STOP. Protocol: `.claude/skills/ask-human/SKILL.md`. Every reply ends with a
     `❓ QUESTION` / `⏹ NO QUESTION` marker as its literal last line.
  2. NO `advisor()` HERE — the tool does not exist in this environment, so the fresh-context
     reviewer-subagent tier is the TOP rung of the availability chain, not a fallback. /stack's three
     lenses are `stack-infra-reviewer`, `completeness-reviewer` and `reproducibility-reviewer`. All
     three are REAL agent definitions in `.claude/agents/` — spawn them by name via the Agent tool
     rather than re-describing their charter inline, so each lens's attack surface stays in one place.
     Self-grading is the last resort and MUST be disclosed as self-graded.
  3. REPORTS GO TO `var/claude/…` in the repo — gitignored via the blanket `/var` rule, survives
     compaction inside the session, never committed. NOT `~/.claude/projects/…`: that is wiped when
     the container is reclaimed. Never `git add` a report regardless — being ignored is what keeps
     them out of history, not what makes staging them harmless.
  4. `--scope=global|both` IS REMOVED wherever it appears: `~/.claude/` in this container is
     GENERATED from repo files by `scripts/claude-bootstrap/install.sh`, so auditing it audits a copy.
  5. ≤5 concurrent subagents (10 caused ~50% rate-limit failures upstream). Every pipeline agent
     writes its raw output to `var/claude/<stage>/raw/` BEFORE returning — autocompact fires here and
     in-conversation results do not survive it.
  6. PROJECT RULES WIN on any conflict: `/stack/CLAUDE.md`. It EXISTS and is authoritative — READ IT.
     It carries the certification ladder (including the STANDARD carve-out this skill honours), the
     git-autonomy override, the tier model, the token invariant, the env cascade, and the in-repo plan
     home (`docs/plans/<topic>.plan.md`, each plan carrying its own `## Decisions Log`).
  7. WHAT CANNOT BE VERIFIED FROM A CONTAINER SESSION, and must be said rather than assumed:
     **Docker is not running** and `make up` cannot be exercised, so "the stack comes up healthy" is
     unverifiable; and **shellcheck, hadolint, yamllint, shfmt and yamlfmt are not installed**, so
     `/lint`, `/fmt` and the five PostToolUse hooks all silently no-op. What always works:
     `bash -n`, `bin/tests/*.test.sh`, `GS_STARTUP_DRY_RUN=1 bash <startup-script>`,
     `bin/env-scan.sh --dry-run`, `make check-image-versions`, `jq empty`. A lens that reports a
     runtime or lint claim it could not execute has produced a false verdict, which is worse than an
     empty one. Fetching static shellcheck/shfmt binaries into a scratch dir is legitimate and
     preferred — then say which tool actually ran.
  8. THE CHARACTERISTIC /stack FAILURE IS SILENT, and that is why the ladder's default tier is
     MAXIMAL here. A token mismatch yields a container that works while reporting unhealthy for 24h
     (masked by `start_period`); a drifted Dockerfile `ARG` yields a stale image while `.env` looks
     correct; one startup-script edit lands on the tier-02 installer AND every tier-03 consumer at
     once. None of these is caught by a green test suite, and none is confined to one service. Treat
     each as /stack's P0 class.
  9. DO NOT REPORT DOCUMENTED DELIBERATE TRADE-OFFS as findings: `privileged: true` on all containers,
     `start_period: 24h` + `retries: 99999`, `password = username` for local credentials,
     `core.fileMode=false`, `set -xeE -o pipefail` without `-u` in startup scripts, `|| true` on
     `log_obs` writes, and the PreCompact hook's unconditional `exit 0`. All are in `CLAUDE.md`
     § Gotchas with rationale. A round padded with these trains the reader to skim past real findings.
═══════════════════════════════════════════════════════════════════════════════════ -->

## --help

> If ARGUMENTS contains `--help`: output the text below verbatim, then immediately STOP — do not execute any other steps. (`--help` takes precedence over all other flags.)
>
> ```
> /converge — Run the project's MAXIMAL certification ladder (3 adversarial evidence-based lenses,
>             TWO consecutive clean rounds, cap 5, fresh-context reviewer subagents), or a deeper
>             tunable convergence sweep. Every parameter is overridable. Runs autonomously by
>             default; --ask restores the approval gate.
> ```
>
> Then output the complete flag table from the **"Flags"** section below. Then STOP.

---

# /converge — Convergence Loop

Runs a structured multi-angle convergence loop. **Autonomous by default** — it announces its
parameters and proceeds; `--ask` restores the upstream approval gate. Progress is reported after every
cycle: autonomy suppresses `ask-human` pauses, never output.

**Relationship to the project's Phase 3C/6C gates.** Project `CLAUDE.md` § "Certification ladder"
mandates a 3-lens reviewer panel with two consecutive fully-clean rounds at every 3C and 6C gate, and
without this skill that ladder is hand-rolled from memory each time. Running `/converge` with its
defaults **IS** that gate, executed mechanically instead of remembered. Reach for the flags when you
want more than the mandated tier: a wider lens set, a higher clean-round threshold, or an enumerated
custom scope for a large audit or migration.

**Honour the ladder's STANDARD carve-out.** Before running, check
`git diff --name-only`. If it touches **no operational surface** — only docs, `CLAUDE.md`,
`templates/tips/`, `docs/`, `.claude/**` or `scripts/claude-bootstrap/**` — then `CLAUDE.md` says
STANDARD is enough: one reviewer, three lenses in a single pass, one clean round. Say so and run
`--cycles=1 --converge=1` rather than burning a MAXIMAL panel on a docs commit. Anything under
`docker/`, `bin/`, `Makefile`, `.env` or `docker-compose.yaml` gets the full default.

## Flags

- `--cycles=N` — maximum total cycles before escalating (default: **5** — the ladder's cap)
- `--converge=K` — consecutive fully-clean cycles required to declare convergence (default: **2** — the ladder's *two consecutive fully-clean rounds*; any finding resets the counter)
- `--scope=ladder|3C|6C|custom` — which lens set to use (default: **`ladder`**). The `3C`/`6C` names describe the angle *content* and are kept for continuity; `ladder` is the project-mandated panel — running it here IS the 3C/6C gate, performed rather than remembered.
  - `ladder` (**default — the project's ratified ladder**): the 3-lens reviewer PANEL, each lens adversarial and **evidence-based** (the reviewer reads the actual diff/tests/files itself, never the author's narrative). /stack's three lenses, each spawning as a fresh-context read-only subagent under that name:
    1. **`stack-infra-reviewer`** — correctness + regression, aimed at what /stack can silently get *wrong*: the token invariant (success write vs `GLOBAL_STACK_ERROR_TOKEN`), one-script-two-tiers blast radius (`MODE=install` vs `MODE=setup`), version-gate marker drift under `tools/versions/`, the env cascade, compose/Makefile wiring, `ARG`→`ENV`, idempotency and crash safety, and the anti-bandaid gate.
    2. **`completeness-reviewer`** — completeness + blast radius: was the evidence *executed* rather than promised, was the change carried across all three levels of the env cascade, all seven places a service needs, every consumer of a changed startup script, every member of a changed closed set, and every doc claim/count it touches.
    3. **`reproducibility-reviewer`** — does it survive a **clean clone and a cold start** (`tools/`, `var/`, `.env.local`, named volumes and `local.*` are all absent from a fresh checkout), is a destructive addition documented in `BLAST-RADIUS.md` (there is no `deny` list to stop it), and is credential/stateful-data layout honoured.
    All three exist as real agent definitions in `.claude/agents/` — spawn them by name via the Agent tool rather than re-describing their charter in a prompt.
  - `3C`: pre-implementation-style angles (expanding-context, adversarial, blast-radius)
  - `6C`: pre-completion-style angles (expanding-context on result, failure modes, callers/docs)
  - `custom`: angles provided via `--angles`
- `--angles='A;B;C'` — semicolon-separated angle descriptions when `--scope=custom`; for custom scope, at least one angle **must** be prefixed with `enumerate:`. See Angle Requirements below.
- `--certify=reviewer|self` — how a cycle's findings get judged (default: **`reviewer`**)
  - `reviewer` (**default**): each lens is run by a **fresh-context read-only reviewer subagent** that reads the artefacts itself. `advisor()` does not exist in this environment, so this IS the top of the ladder's availability chain here. Convergence still requires `--converge=K` (2) consecutive fully-clean rounds — independence removes the self-grading blind spot, it does not remove the project's two-round requirement.
  - `self`: self-graded CLEAN/RESET/STUCK comparison against the previous cycle. Last resort — a restricted subagent context with no ability to spawn reviewers. **Using it obliges you to state in the output that certification was self-graded and why.**
- `--ask` — opt IN to the Step 0 approval gate (autonomous is the default here; this restores the upstream stop-and-confirm behaviour)
- `--auto-cap=N` — hard safety ceiling for autonomous mode (default: **30**, max: **30**); overrides `--cycles` when autonomous and N > auto-cap; prevents runaway token burn

---

## Angle Requirements

These rules apply to every angle in every cycle, regardless of scope.

### Evidence gate (all scopes)

Every angle result **must** include at least one of:
- A command and its actual output (`grep`, `find`, `ls`, `bash -n`, a test run — something that ran and produced text)
- An explicit enumerated list of items checked with a total count
- A file path + line number citation pointing to the specific location of the finding

**Pure prose reasoning fails the evidence gate.** "I believe X is covered" or "X looks correct" without
a supporting command or citation is not a valid angle result. If an angle produces only prose, re-run it
with concrete evidence before recording the cycle result.

**And in this repo, "I ran the linter" fails the gate unless the linter exists** — `command -v
shellcheck` first. See adaptation note 7.

### Enumeration angle (custom scope — mandatory)

When `--scope=custom`, at least one angle must be designated `enumerate:`. This angle:

1. **Runs an explicit enumeration command** (`ls`, `find`, `grep` on an index file) to list every member of the set being audited
2. **States the total count** — "N members found: [list]"
3. **Cross-checks coverage** — after all other angles complete, compares members visited this cycle against the total enumerated. Any member not visited by any angle is a scope gap.
4. **Scope gaps are findings** — an unvisited member triggers a RESET with "scope gap: <member> not covered"

The enumeration angle cannot be satisfied by memory or assumption. It must show the command that
produced the member list.

**Example** — for an audit that must cover every service (the whole coverage surface of a compose or
health-signalling change):
```
enumerate: run `ls -d docker/images/*/ | wc -l` and list them, then cross-check which of those
           services were actually read or grep'd by the other angles this cycle. For a change to a
           startup script, the authoritative consumer list is
           `grep -rl '<script>' docker/images/*/docker-compose.yaml` — memory is NOT evidence here,
           because the two-phase model means the obvious owner is never the only consumer.
```

---

## Step 0 — Announce and run (autonomous by DEFAULT)

Upstream (and phorj) stop here for approval; that is an interrupt, and the developer's standing
directive for this repo is *no interrupts*. So: parse flags, take the ladder defaults for anything
missing (`--scope=ladder`, `--cycles=5`, `--converge=2`, `--certify=reviewer`), apply the STANDARD
carve-out check above, **print the parameter block, then proceed immediately** — do not wait.

```
[converge] ladder | certify=reviewer | cycles=5 | converge=2 | auto-cap=30
[converge] lenses: 1 stack-infra-reviewer  2 completeness-reviewer  3 reproducibility-reviewer
[converge] tier: MAXIMAL (diff touches docker/ — operational surface)
```

`--ask` opts back INTO the approval gate: print the block plus numbered options (recommended first) as
plain text per `/ask-human`, then STOP and wait. Use it when the scope is large enough that the token
cost itself deserves a decision.

**Autonomous mode is therefore the default**: `autonomous = true` unless `--ask` was passed and the
developer chose a non-autonomous option. The ONLY guaranteed stop in autonomous mode remains the cap
escalation in Step 5 — a stuck independent review is not something autonomy may silently override.

---

## Step 1 — Initialize state

```
TOTAL_CYCLES  = N                          # default 5 — ladder cap
CONVERGE_REQ  = K                          # default 2 — ladder clean rounds
CERTIFY       = reviewer | self            # default reviewer
AUTO_CAP      = min(auto-cap, 30)          # hard safety ceiling for autonomous mode
autonomous    = true                       # /stack DEFAULT (--ask can turn it off)
counter       = 0                          # consecutive clean cycles so far
cycle_num     = 0                          # total cycles run
prev_findings = []                         # findings from the immediately preceding cycle
```

**Freeze the tree first for a MAXIMAL run.** `CLAUDE.md` requires a startup-script or env-cascade
change to be certified against a **frozen commit** — a round run on a moving tree cannot count toward
the two-clean requirement. Record `git rev-parse HEAD` and `git status --porcelain` and state that this
is the frozen subject; if the tree changes mid-loop, the counter resets.

---

## Step 2 — Run one cycle

Increment `cycle_num`.

**Autonomous safety cap check**: if `autonomous == true` AND `cycle_num > AUTO_CAP` → go to Step 5.

Run all angles against the current context. For each angle:
1. Execute it (grep, read, enumerate, run a test — with evidence)
2. **Apply the evidence gate** (above). Re-run without evidence.
3. List findings as bullets. A finding is anything unresolved — a risk, gap, side-effect, inconsistency or scope gap.

**If `--scope=custom` and an `enumerate:` angle is present:** after the other angles, run the
cross-check and add any unvisited member as a scope-gap finding before recording the result.

**After running all angles, emit a progress line:**

```
[converge] Cycle cycle_num/TOTAL_CYCLES | counter/CONVERGE_REQ clean | <status>
```

`<status>` is one of:
- `CLEAN (counter/CONVERGE_REQ)` — no findings at all this cycle
- `RESET (counter → 0) — new: <one-line finding>` — something appeared that was not in prev_findings
- `STUCK — persistent: <one-line finding>` — findings identical to prev_findings, nothing new

*Always emitted, even in autonomous mode. Autonomy suppresses ask-human pauses, not output.*

---

## Step 3 — Evaluate and act

**If `CERTIFY == reviewer`** (default): the reviewer subagents' verdicts ARE the evaluation — do not
self-compare. Spawn one read-only reviewer per lens — `stack-infra-reviewer`,
`completeness-reviewer`, `reproducibility-reviewer` — each given the artefacts (diff, files, tests) and
told to **read them itself** and to try to REFUTE the work:
- Every lens returns zero findings → **Case A (CLEAN)**, `counter += 1`. **Do NOT jump straight to converged** — the ladder requires TWO consecutive fully-clean rounds, so a single clean round is `counter = 1`.
- Any lens raises something not in `prev_findings` → **Case B (RESET)**, `counter = 0`.
- A lens repeats a point after a resolution attempt → **Case C (STUCK)**.

A reviewer verdict of `PANEL VERDICT: CLEAN` that does **not** enumerate what it checked, or that
hides an unverifiable dimension (Docker down, linters absent), is **not** a clean round — treat it as
STUCK and re-run that lens demanding the enumeration.

**If `CERTIFY == self`** (last resort): use the self-graded comparison below, and say in the output
that certification was self-graded and why.

**Case A — CLEAN:**
- `counter += 1`; `prev_findings = []`
- If `counter == CONVERGE_REQ` → Step 4 (converged); else → Step 2

**Case B — RESET (new finding appeared):**
- `counter = 0`; `prev_findings = current_findings`; incorporate the finding
- **If `autonomous == true`**: emit one line and continue without pausing:
  ```
  [converge] ↺ RESET cycle_num — autonomous: <finding summary>. Incorporating and continuing.
  ```
  Go to Step 2.
- **If `autonomous == false`**: print as plain text and STOP until answered:
  ```
  New finding in cycle cycle_num. Counter reset to 0.
  Finding: <description>

  1. Continue — incorporate and retry (recommended)
  2. Continue autonomously — run the rest of the loop without pausing
  3. Escalate — surface it and stop now
  4. None of these / challenge the premise — e.g. the finding is not real, the lens is
     mis-scoped, or the scope should be narrowed. Say so and I will re-run differently.

  ❓ QUESTION — how should the loop handle this finding?
  ```
  Option 4 is REQUIRED, not garnish: `ask-human` § "The five required parts" and `CLAUDE.md`
  § "Questions are plain text" both mandate a visible escape on every option set, and a template that
  omits it is what future sessions will copy.

**Case C — STUCK (same findings, nothing new):**
- `counter` unchanged; `prev_findings` unchanged
- Attempt deeper resolution; emit `[converge] STUCK on cycle cycle_num — attempting deeper resolution`
- Go to Step 2. *(No pause for STUCK in either mode.)*

**Case D — cycle cap reached** (`cycle_num == TOTAL_CYCLES` and `counter < CONVERGE_REQ`) → Step 5.

---

## Step 4 — Converged

```
[converge] ✓ CONVERGED — cycle_num cycles total, counter/CONVERGE_REQ consecutive clean cycles.
```

Report a one-line summary of what was verified across the clean cycles, **and what could not be
verified here** (Docker absent, linters absent, whichever applies). A convergence that hides an
unverifiable dimension is a false certification. Exit.

---

## Step 5 — Cap escalation (could not converge)

**Determine cap type:**
- Autonomous safety cap (`cycle_num > AUTO_CAP`): `[converge] ✗ AUTONOMOUS SAFETY CAP — {AUTO_CAP} cycles reached.`
- Otherwise: `[converge] ✗ CAP REACHED — cycle_num/TOTAL_CYCLES cycles, counter/CONVERGE_REQ clean.`

In both cases list every remaining finding and exit autonomous mode (`autonomous = false`).

**Print as plain text and STOP until answered** — this is the one guaranteed question in autonomous
mode, and per `CLAUDE.md` the cap NEVER silently proceeds:

```
Could not converge in cycle_num cycles (counter/CONVERGE_REQ clean).
<If autonomous safety cap: "Autonomous safety cap of AUTO_CAP cycles reached.">
Remaining findings:
  • <finding 1>
  • <finding 2>

1. Rerun — N more cycles (recommended)            → restart Step 1, same K, new N
2. Rerun autonomously — N more cycles             → restart Step 1 with autonomous = true
3. Decompose — split the subject and converge each part
4. Escalate manually — you review and decide
5. None of these / challenge the premise          → e.g. accept the remaining findings as
   documented risk, drop the clean-round requirement for this scope, or stop the loop because
   the artefact is not worth further rounds. State which and I will record it.

❓ QUESTION — how should I proceed after the cap?
```

Wait for direction. This is the only guaranteed pause in autonomous mode.
