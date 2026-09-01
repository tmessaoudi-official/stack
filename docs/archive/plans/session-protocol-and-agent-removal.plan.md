# Session protocol adaptation + `global-stack-lead-dev` removal Plan

Two changes ruled together on 2026-08-19: adapt the developer's standing session protocol
(no per-task reviewer panels, executable evidence between gates, compact-point prompts) to
`/stack`, and delete the `global-stack-lead-dev` orchestrator agent with its live references.

## Decisions Log

- [2026-08-19 21:00] AGREED: the standing protocol transfers to `/stack` **unchanged** — one
  `advisor()` call per 3C/6C gate, no reviewer panel per task, failing-test-first plus a
  sabotage/mutation check between gates, and the full three-lens panel ONCE at the milestone
  boundary against a frozen commit — with **one `/stack`-specific addition**: when a change's
  guarantee cannot be exercised by an executable check (container runtime health, an `.env`
  cascade landing on tier-03 consumers), either bring the stack up as the evidence or name the
  dimension `UNCERTIFIED-BY-EXECUTION: <guarantee>` in the completion report.
- [2026-08-19 21:00] AGREED: the protocol lives in project memory
  (`~/.claude/projects/-stack/memory/economize-tokens-panels-and-compaction.md`), **not** folded
  into the global framework yet — to be reassessed once it has proven itself across projects.
  Because `CLAUDE.md` § "Certification ladder" mandated the opposite (MAXIMAL per task) and this
  file wins on conflict, a **single pointer line** was added to that section marking the per-task
  tier superseded and naming the memory file. The section's three-lens table and tier definitions
  were deliberately KEPT — they are what the milestone panel executes.
- [2026-08-19 21:00] AGREED: `global-stack-lead-dev` is deleted along with its live references.
  All `/stack` work is handled directly in the main conversation; the three read-only reviewer
  agents are unaffected.
- [2026-08-19 21:00] AGREED (implementation ruling, not asked): **dated records are not
  references.** `docs/audit.md` (2026-05-25), the two closed plans in `docs/plans/`, and the dated
  artifacts under `~/.claude/projects/*/audits|inspections|forge|meta-reports|<session-uuid>` still
  name the agent on purpose — rewriting them would falsify a record of what was true then. Left
  unedited, and listed explicitly in the completion report so the ruling is visible and reversible.
- [2026-08-19 21:00] AGREED (implementation ruling, not asked): `~/.claude/agent-memory/global-stack-lead-dev/`
  held four genuine `/stack` domain memories (env-update HTTP layer, GHCR auth, `LOCAL_` var
  pattern, url.sh fetch-tier precedence), none duplicated in the main index. They were **migrated**
  into `~/.claude/projects/-stack/memory/` before the directory was removed — deleting the agent
  must not delete knowledge the agent merely happened to store.
- [2026-08-21 15:30] AGREED: **the protocol SPLITS — global workflow half, per-repo evidence half.**
  This supersedes the 2026-08-19 "lives in project memory" ruling above, which the milestone panel
  refuted from two independent lenses (D2): `CLAUDE.md` had acquired a hard normative dependency
  (*"read that file before running any gate here"*) on a file that is outside the repo, **untracked
  even in the home checkout**, and bundle-excluded by `skills/bundle/SKILL.md:135` — so a clean
  clone declared its own § Certification ladder superseded and named a successor that was not
  there. The split follows the repo's existing global-is-reference ruling and Rule 5's agent-def
  guidance: generic content lives once, globally; a repo carries only its delta.
  - **Global** (`~/.claude/CLAUDE.md`, Phases 3C/6C): one `advisor()` per gate, never a panel per
    task; the three-lens panel ONCE at the milestone boundary against a frozen commit;
    failing-test-first confirmed red for the stated reason; the sabotage/mutation check; and the
    execution-certification disclosure in the completion report.
  - **Per-repo** (`<repo>/CLAUDE.md`): the evidence-surface table, the repo's own sabotage shapes,
    and when `UNCERTIFIED-BY-EXECUTION` fires. Landed for `/stack` in § "Certification".
- [2026-08-21 15:30] AGREED: fix scope after the milestone panel is **code and tests first** — the
  two P1 message defects plus the clone-safety of the new tests — then the correctness-of-content
  items (B1 cross-repo plan, D1 exec bit, C4 false memory). Cosmetic and orphan-placeholder items
  (C3) come last.
- [2026-08-21 17:00] AGREED — **DIRECTIVE, STILL IN FORCE: no reviewer panels until the developer
  explicitly asks for one.** Verbatim: *"No panels! not yet! ... wait for my explicit instruction
  about panels! use advisor for now!"* A round 2 over `d63f437..d7e3e6b` is *owed* but must **NOT**
  be started on a future session's own initiative — it has already been started and stopped twice
  against this instruction. Until the developer says otherwise, `advisor()` is the gate at 3C and
  6C, and executable evidence (failing test first, confirmed red for the stated reason, plus a
  sabotage check) does the refuting. **If you are reading this after a `/compact` or in a new
  session: do not spawn the panel.** — **SUPERSEDED 2026-08-21 18:00 by the choice-gate ruling
  below**, which turns "explicit instruction" into a question asked at every gate. The prohibition
  survives in its stronger form: never spawn a panel that was not chosen in an answer to that
  question.
- [2026-08-21 17:00] AGREED (design ruling): for the Docker Hub anonymous page cap, **document the
  limit, do not redesign the fetch.** A filtered `?name=<major>.` re-query was considered and
  rejected: it needs a major hint that `_/redis` does not have, `name=` is a substring match that
  would need anchoring, and all three currently-affected images were validated correct against
  complete tag lists. The residual — a cap-hit is now *silent*, where it used to be a loud ERROR —
  is recorded as an open item for the developer, not built. Surfacing it would need a new record
  field carried through the reporting path.
- [2026-08-21 15:30] AGREED (implementation ruling, not asked): the panel's **C5 finding was
  refuted, not fixed.** Two lenses independently reported `CLAUDE.md`'s "786 tests" as stale; the
  harness's own `TOTAL=$(( PASS + FAIL ))` proved 786 correct at the time. The 902 and 923 figures
  came from summing per-section tallies and counting `✓` marks, both of which over-count because
  the breakdown repeats section lines. **Two fresh-context reviewers can be confidently wrong in
  the same direction** — the tie-break came from reading the harness, not from either verdict.

- [2026-08-21 18:00] AGREED: **the certification tier is a QUESTION, asked at every certification
  moment.** Before certification runs at any 3C gate, any 6C gate, or the milestone boundary, ask
  via `AskUserQuestion` which tier to run — `advisor()` only / reviewer panel only / both — with a
  recommendation and a visible challenge-the-premise escape. Two sub-rulings, both the developer's
  own choice from the offered options:
  - **Frequency: every certification moment**, with **no carry-forward** of a previous answer. The
    literal reading of the instruction, and the only shape that lets the developer pick `advisor()`
    at 3C and `both` at 6C. Rejected: once-per-task, once-per-session, milestone-only.
  - **Autonomous mode suppresses the question and defaults to `advisor()` only** — a question
    mid-autonomous-run defeats the sentinel's purpose. The 5-round escalation keeps its own
    always-ask carve-out. Rejected: default-to-both (the token waste the economize ruling exists to
    prevent), and always-ask (which would gut autonomous mode).
  This **reconciles the 2026-08-21 17:00 no-panels hold**: choosing the panel in that question *is*
  the explicit instruction the hold was waiting for. The hold's prohibition is not lifted, it is
  generalised — a panel is spawned only when it was chosen in an answer, never on a session's own
  initiative.
  Landed in **both** halves of the split protocol: `~/.claude/CLAUDE.md` § "Per-task gate vs
  milestone panel" (via `/tmp/apply-certification-choice-gate-20260821.sh`, since that file is
  classifier-blocked) and `/stack/CLAUDE.md` § "Certification". Editing only the global half would
  have been inert here — `/stack/CLAUDE.md` wins on conflict and said the opposite.

## Formal Plan

1. **Unblock**: the tree carried 604 lines of unrelated staged env-update work. Ran
   `bin/tests/env-update.test.sh` → green (116 sections, 902 asserts, 0 failures, exit 0);
   committed separately as `b66ed72` so the two changes stay untangled.
2. **Memory** (`~/.claude/projects/-stack/memory/`): extend
   `economize-tokens-panels-and-compaction.md` with § "/stack adaptation" (the surface-vs-evidence
   table, the `UNCERTIFIED-BY-EXECUTION` trigger, the `/stack`-flavoured sabotage examples) rather
   than create a second file for the same fact; add `feedback_stack_routing_direct.md`; delete the
   superseded `feedback_lead_agent.md`; migrate the four agent-memory files; refresh `MEMORY.md`.
3. **Repo**: `git rm .claude/agents/global-stack-lead-dev.md`; rewrite the `CLAUDE.md` header
   routing directive, the `.claude/agents/` file-layout listing and the closing "Remember" line;
   add the § "Certification ladder" supersession pointer; retarget the two `projects/CLAUDE.md`
   isolation clauses; swap the `templates/tips/statusline.md` payload example to
   `stack-infra-reviewer`.
4. **Global `~/.claude/`**: drop the routing-table row and the `settings.json` context string
   (both classifier-blocked → handed over as one `/tmp` script), the `README.md` mentions, the
   `lean-swap.sh` path entry, and the `claude-export` scrub rule with its test and skill doc —
   verified by `bundle-import.test.sh`.
5. **Out of scope, reported not fixed**: `projects/phorj/` and `projects/observability-stack/` are
   separate git repos; their "never route here" clauses are now stale but harmless.

## Verification

- `bash bin/tests/env-update.test.sh` — green before the unblocking commit.
- `bash ~/.claude/bin/tests/bundle-import.test.sh` — green after the scrub-rule removal.
- `bash -n ~/.claude/bin/lean-swap.sh`, `jq . ~/.claude/settings.json` — syntax/validity gates.
- `git grep -n global-stack-lead-dev` — every surviving hit is either a deliberate tombstone or a
  dated record.
- No operational surface (`docker/`, `.env`, compose, `Makefile`) is touched, so there is no
  `UNCERTIFIED-BY-EXECUTION` dimension in this change.
