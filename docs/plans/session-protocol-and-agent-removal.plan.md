# Session protocol adaptation + `global-stack-lead-dev` removal Plan

Two changes ruled together on 2026-08-19: adapt the developer's standing session protocol
(no per-task reviewer panels, executable evidence between gates, compact-point prompts) to
`/stack`, and delete the `global-stack-lead-dev` orchestrator agent with its live references.

## Decisions Log

- [2026-08-19 --:--] AGREED: the standing protocol transfers to `/stack` **unchanged** — one
  `advisor()` call per 3C/6C gate, no reviewer panel per task, failing-test-first plus a
  sabotage/mutation check between gates, and the full three-lens panel ONCE at the milestone
  boundary against a frozen commit — with **one `/stack`-specific addition**: when a change's
  guarantee cannot be exercised by an executable check (container runtime health, an `.env`
  cascade landing on tier-03 consumers), either bring the stack up as the evidence or name the
  dimension `UNCERTIFIED-BY-EXECUTION: <guarantee>` in the completion report.
- [2026-08-19 --:--] AGREED: the protocol lives in project memory
  (`~/.claude/projects/-stack/memory/economize-tokens-panels-and-compaction.md`), **not** folded
  into the global framework yet — to be reassessed once it has proven itself across projects.
  Because `CLAUDE.md` § "Certification ladder" mandated the opposite (MAXIMAL per task) and this
  file wins on conflict, a **single pointer line** was added to that section marking the per-task
  tier superseded and naming the memory file. The section's three-lens table and tier definitions
  were deliberately KEPT — they are what the milestone panel executes.
- [2026-08-19 --:--] AGREED: `global-stack-lead-dev` is deleted along with its live references.
  All `/stack` work is handled directly in the main conversation; the three read-only reviewer
  agents are unaffected.
- [2026-08-19 --:--] AGREED (implementation ruling, not asked): **dated records are not
  references.** `docs/audit.md` (2026-05-25), the two closed plans in `docs/plans/`, and the dated
  artifacts under `~/.claude/projects/*/audits|inspections|forge|meta-reports|<session-uuid>` still
  name the agent on purpose — rewriting them would falsify a record of what was true then. Left
  unedited, and listed explicitly in the completion report so the ruling is visible and reversible.
- [2026-08-19 --:--] AGREED (implementation ruling, not asked): `~/.claude/agent-memory/global-stack-lead-dev/`
  held four genuine `/stack` domain memories (env-update HTTP layer, GHCR auth, `LOCAL_` var
  pattern, url.sh fetch-tier precedence), none duplicated in the main index. They were **migrated**
  into `~/.claude/projects/-stack/memory/` before the directory was removed — deleting the agent
  must not delete knowledge the agent merely happened to store.

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
