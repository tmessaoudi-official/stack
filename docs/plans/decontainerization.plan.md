# De-containerization Plan — restore AskUserQuestion + advisor-aware ladder

> **Status: PHASE A COMPLETE (P0 defused). Phases B–G partially done.** Written 2026-08-18 before a
> context compact; execution resumed 2026-08-18 after it. Resume by reading this file top to bottom,
> then § "Execution log" at the end for exactly what is done and what is left.
>
> **Two of this plan's own findings turned out to be WRONG.** Both are recorded in the Decisions Log
> below and are open questions, not settled decisions. Do not act on the original wording of the
> "13 duplicate skills" decision or the Phase D path-denies for rent-watch without reading them.

---

## ⏭️ NEXT SESSION STARTS HERE — four open decisions, to be taken one at a time

Agreed with the developer 2026-08-18, immediately before a context compaction: **Phase A is done
and pushed; the next session walks these four decisions one by one.** Nothing else should start
until they are settled — three of them exist because a premise in this very plan turned out to be
false, so acting first and asking later is exactly the failure mode to avoid.

| # | Decision | Why it is open | Options |
|---|---|---|---|
| **D1** ✅ | **DECIDED — option 3 (merge).** See § "D1 — DECIDED 2026-08-18" below; that section is executable as written. | Premise *"they are duplicates"* was FALSE. Local copies are independently rewritten, 42–57% smaller in words, and every one carries container-era adaptation notes. | **Merge `forge`/`sleuth`/`inspect`, de-contaminate the other ten in place.** Sub-questions (a) Roadmap re-import (b) push `forge` notes 7–8 up (c) all-at-once vs one-at-a-time — STILL OPEN, ask first. |
| **D2** | Phase D permission tiers vs rent-watch's invariant | rent-watch `CLAUDE.md` rules `deny` stays **empty**, and its `drift-scan.sh` §S4b **mechanically asserts** it — specifically so a sibling port cannot reintroduce one. Phase D would trip that gate. | exempt rent-watch · change its ruling AND its scanner together · drop the path denies everywhere |
| **D3** | Whether to proceed into Phases B/C prose | ~98 files across the 5 repos still cite `scripts/claude-bootstrap/`; the plain-text-question sections, the `❓`/`⏹` marker rules and the "advisor() does not exist" ladder claims are all still live. **All prose, none executable** — verified. | do it now, repo by repo · defer · do only the false claims (e.g. `/stack`'s 15/23 `disallowed-tools` sentence) |
| **D4** | Vendor the PreCompact handoff into the 4 siblings | `/stack` got it back this session (42/42 green) after the plan's "the global hook covers it" premise was refuted. **pdfturbo, phorj, twes-in and rent-watch still have no working handoff** — their `settings.json` registrations were removed and nothing replaced them. | vendor into all 4 (same fix as `/stack`) · leave them on no handoff · pick per repo |

**State going in:** all five repos `dirty:0 ahead:0`, everything pushed. Certification is **0 of 2
clean rounds** — the one round that ran was on a moving tree and does not count, so a fresh panel
against a frozen commit is owed regardless of which decisions are taken.

---

**Scope:** `/stack`, `/stack/projects/pdfturbo`, `/stack/projects/phorj`,
`/stack/projects/rent-watch`, `/stack/projects/twes-in`.
**Explicitly OUT of scope:** `/stack/projects/invoiceninja` (WIP fork import, own session).

**Goal:** these repos were adapted for the Claude Code *web/cloud container*, where
`AskUserQuestion` timed out and `advisor()` did not exist. That environment is dead. Undo the
accommodations, restore `AskUserQuestion` via the global `ask-human` skill, and keep the
reviewer-lens ladder as the certification path whenever `advisor()` is unavailable.

---

## Decisions Log

- [2026-08-18 10:40] AGREED: Environment is **this machine only** — the cloud container is dead. Hard revert of every container-era accommodation.
- [2026-08-18 10:40] AGREED: The 13 generic skills deleted from `/stack/.claude/skills/` stay deleted — they exist in the global `~/.claude/skills/` bundle and were duplicates.
- [2026-08-18 10:40] AGREED: Drop the `❓ QUESTION` / `⏹ NO QUESTION` end-of-reply marker entirely. Its rationale (plain-text questions being indistinguishable from pauses) dies with the plain-text protocol.
- [2026-08-18 10:40] AGREED: Restore a `deny`/`ask` permission tier. The "no permission denies" ruling was justified solely by "in the web app I cannot run a denied command myself" — no longer true.
- [2026-08-18 10:55] AGREED: **Keep every reviewer agent repo-local. Promote none to global.** `~/.claude/agents/` is empty; global `CLAUDE.md` defines the ladder *procedure*, not the lenses. The lenses are domain knowledge and the five `completeness-reviewer.md` copies have already diverged 9.2K→17.9K. Agent defs are NOT trimmed this round (option 1, not option 2).
- [2026-08-18 10:55] AGREED: Restore the 10 `/stack` domain skills that have no global equivalent; leave the 13 that do.
- [2026-08-18 10:55] AGREED: Permissions — Category A as `deny`, Category B as `ask`, plus `Read`/`Edit` path denies on `.env`, `docker/data`, `docker/storage`, `var` **for the four sibling repos only, never `/stack`** (env-update/env-scan must read and write `.env` as their core function).
- [2026-08-18 10:55] AGREED: Git — `add`/`commit`/**`push`** stay fully autonomous, in **all** repos, not just `/stack`. Never a `Co-Authored-By` or `Claude-Session` trailer. Identity is always `Takieddine MESSAOUDI <takieddine.messaoudi.official@gmail.com>`.
- [2026-08-18 11:05] AGREED: Certification enforcement lives **globally**, by extending the existing `~/.claude/hooks/advisor-completion-guard.sh` to accept a `*-reviewer` subagent as well as `advisor()`. Not replicated per-repo.
- [2026-08-18 11:05] AGREED: Skip `invoiceninja` this round.
- [2026-08-18 11:05] AGREED: Execute **inline, sequentially, repo by repo** — not parallel subagents. The five `CLAUDE.md` files phrase the same rules differently; that is prose judgment, and parallel agents would re-introduce the drift being cleaned up.
- [2026-08-18 13:30] ⚠️ **REFUTED — the "13 generic skills are duplicates" premise is false.** Measured against `~/.claude/skills/`: `/stack`'s `converge` is 21,850 B vs global 14,061 B with 13 references to this repo's own reviewer agents; rent-watch's are larger still (`forge` 40,241 vs 27,278, `sleuth` 35,983 vs 23,856, `inspect` 39,343 vs 28,165, `converge` 24,546 vs 14,061) with 24–44 domain references each. These are heavily adapted repo-local skills. **All were restored pending a decision** — deleting them would discard substantial work. OPEN: delete none / delete only the ones that are genuinely thin / re-audit individually.
- [2026-08-18 13:30] ⚠️ **REFUTED — rent-watch's `repair` skill was never a duplicate.** It ships `.claude/skills/repair/drift-scan.sh` (31,732 B), which has **no global equivalent** and which rent-watch CI executes as a gate. Deleting it broke CI. Restored.
- [2026-08-18 13:30] ⚠️ **CONFLICT — Phase D's path denies contradict rent-watch's own invariant.** rent-watch `CLAUDE.md` states `deny` is empty and stays empty, and `drift-scan.sh` § S4b **asserts** it, specifically so the entry "cannot creep back in a later port from a sibling repo." Applying Phase D to rent-watch would trip its own gate. OPEN: exempt rent-watch / change its ruling and its scanner / drop the path denies everywhere.
- [2026-08-18 13:30] AGREED: Where the classifier blocks Claude (`settings.json*` of any name, `/stack`'s `lint` + `fmt` SKILL.md, the phorj commit), the work goes into ONE hand-off script rather than being retried or worked around.
- [2026-08-18 17:40] AGREED (**D1 RESOLVED**): **Option 3 — merge.** `forge`, `sleuth` and `inspect` are merged (two-way, not re-based); the other ten local skills are de-contaminated in place. Full executable spec in § "D1 — DECIDED 2026-08-18". Three sub-questions (a/b/c) remain open and must be asked before execution.
- [2026-08-18 17:40] VERIFIED: **`advisor()` IS available on this machine** — `/home/developer/.claude/hooks/advisor-completion-guard.sh` exists and global `CLAUDE.md` references it. Adaptation note 2 ("NO `advisor()` HERE") in all three skills is therefore FALSE and must be reverted. This also affects `/stack/CLAUDE.md` § "Certification ladder", which still claims `advisor()` does not exist — that is D3 prose work.
- [2026-08-18 17:40] AGREED: **`Step 4b: Self-Reflection` stays REMOVED** from local `sleuth` and `inspect`, against the global copies which still have it. Reason: these skills freeze at Step 4b. The local copies are ahead of global here; do not "restore" it. Record the reason in the file so a later pass cannot helpfully undo it.
- [2026-08-18 17:40] AGREED: **`--vision` stays out of `inspect` permanently** (no UI in this project) — this is the one adaptation note that is correct and not container-era.
- [2026-08-18 15:30] ⚠️ **REFUTED — "the global `~/.claude/hooks/precompact-handoff.sh` covers this" (Phase A step 2) is false.** The global hook writes to `~/.claude/projects/<slug>/memory/sessions`, has **no `<!-- manual -->` guard** and no `GS_HANDOFF_DIR` override; `/stack/CLAUDE.md` documents `var/claude/handoff/latest.md`. Observed directly: the compaction on 2026-08-18 produced **no handoff at all**. RESOLVED by vendoring `precompact-handoff.sh` + its 42-assertion suite into `/stack/.claude/hooks/` — `install.sh` was the clobber problem, this hook was innocent. Re-registration is in the hand-off script. **The four sibling repos still have no working PreCompact handoff** — same fix needed there.
- [2026-08-18 15:30] AGREED: Anything salvaged from `scripts/claude-bootstrap/` is **vendored in-repo**, never sourced from `~/.claude/`, so a clean clone still works. Applied to `log-helpers.sh` (all 5 `/stack` hooks repointed off `$HOME`), `precompact-handoff.sh`, and `BLAST-RADIUS.md` → `docs/BLAST-RADIUS.md`.

---

## Verified findings (evidence gathered 2026-08-18, before any edit)

### 🔴 P0 — the sibling bootstrap hooks will silently revert this work

All four sibling repos wire `scripts/claude-bootstrap/install.sh` as a **`SessionStart`** hook,
and `install.sh` performs an unconditional `cp -f` of its in-repo `CLAUDE-global.md` over
`~/.claude/CLAUDE.md`.

- Those in-repo copies each contain `AskUserQuestion is FORBIDDEN` — 6/4/6/6 mentions for
  pdfturbo/phorj/rent-watch/twes-in [Verified: `grep -c`].
- Sizes: pdfturbo 63,765 · phorj 62,612 · rent-watch 67,824 · twes-in 66,154 bytes.
- The live `~/.claude/CLAUDE.md` is **57,075 bytes and currently intact** — it differs from all
  four repo copies [Verified: `cmp`], and differs from `~/.claude/CLAUDE.md.pre-bootstrap.bak`
  only by a `{{TZ}}` → `Europe/Paris` placeholder resolution [Verified: `diff`].
- The hook **has already fired on this machine**: `~/.claude/CLAUDE.md.pre-bootstrap.bak` (Jul 31),
  `BLAST-RADIUS.md.pre-bootstrap.bak`, `THINKING.md.pre-bootstrap.bak`,
  `hooks/log-helpers.sh.pre-bootstrap.bak` all exist [Verified: `ls -la`].
- `install.sh` snapshots to `.pre-bootstrap.bak` **once and never again** [Verified: install.sh:18
  comment, lines 55–62]. The safety net is spent.

**Consequence: opening pdfturbo/phorj/rent-watch/twes-in replaces the global framework with a
container-era copy that bans `AskUserQuestion`.** Phase A must complete before anything else.

### The completion-gate hook is currently an unsatisfiable deadlock

`~/.claude/hooks/advisor-completion-guard.sh` is a registered `Stop` hook
(`~/.claude/settings.json:383`) [Verified]. It blocks any turn where the assistant text contains
both `coverage` and `blast radius` (the Rule 6 evidence-table signature) unless the `advisor` tool
was called in that same turn. **`advisor()` is disabled**, so the gate can never be satisfied; the
only escapes are `ACGUARD_OFF=1` or `~/.claude/state/advisor-completion-guard-bypass`.

### Root cause of the original ban is already fixed

`askUserQuestionTimeout: "never"` is set in `~/.claude/settings.json` [Verified: `jq`].

### Skills: 13 global duplicates vs 10 domain-only

Deleted from `/stack/.claude/skills/`, **exist globally** (leave deleted):
`aggregate-findings` `ask-human` `converge` `cross-check` `expanding-context` `forge` `gaps`
`handoff` `inspect` `pre-commit` `retrospective` `sleuth` `sweep`

Deleted, **no global equivalent** (RESTORE these 10):
`lint` `fmt` `validate` `stack-health` `env-diff` `service-info` `new-service` `debug-service`
`check-versions` `bump-versions`

### Reviewer agents inventory (all stay put)

| Repo | Agents |
|---|---|
| /stack | `completeness-reviewer` `stack-infra-reviewer` `reproducibility-reviewer` (+ `global-stack-lead-dev`) |
| pdfturbo | `completeness-reviewer` `export-fidelity-reviewer` `safety-promises-reviewer` |
| phorj | `completeness-reviewer` `backend-parity-reviewer` `safety-promises-reviewer` |
| rent-watch | `completeness-reviewer` `source-resilience-reviewer` `tenure-correctness-reviewer` |
| twes-in | `completeness-reviewer` `domain-correctness-reviewer` `tenancy-security-reviewer` |

`~/.claude/agents/` is **empty** [Verified: `ls`].

### `disallowed-tools: AskUserQuestion` — 56 skill files to strip

pdfturbo 14 · phorj 14 · rent-watch 15 · twes-in 13 [Verified: `grep -rl | wc -l`].
`/stack` has 0 remaining (its skills dir is already emptied).

### CLAUDE.md container-era line anchors

| Repo | Lines to rewrite |
|---|---|
| /stack | 4, 14–26 (marker §), 28–32 (plain-text §), 67, 71–89 (ladder §), 99–107 (bootstrap §), 292, 295, 312, 326, 397 |
| pdfturbo | 13–14, 27, 41, 47, 49–58, 68, 82, 119, 2427–2446 |
| phorj | 35, 45, 102, 168, 254–255 |
| rent-watch | 100–101, 108–117, 124, 254, 268, 366–368, 475, 553, 582 |
| twes-in | 112–113, 119–128, 136, 254, 489, 503, 1887, 1908 |

---

## Execution plan

### Phase A — stop the bleeding (MUST be first)

For each of pdfturbo, phorj, rent-watch, twes-in:

1. Remove the `SessionStart` hook block (install.sh) from `.claude/settings.json`.
2. Remove both `PreCompact` matcher blocks (precompact-handoff.sh) — the global
   `~/.claude/hooks/precompact-handoff.sh` covers this.
3. `git rm -r scripts/claude-bootstrap/`.
4. `git rm` the now-orphaned tests: `scripts/claude-bootstrap/test-install.sh`,
   `scripts/claude-bootstrap/hooks/test-precompact-handoff.sh` (paths vary per repo — rent-watch
   CLAUDE.md:366–368 lists them as "must stay green"; remove those claims too).
5. `/stack` only: `scripts/claude-bootstrap/` is already deleted in the working tree, and its
   settings.json already has the hooks removed. Also `git rm bin/tests/precompact-handoff.test.sh`
   and `bin/tests/install.test.sh`, and drop CLAUDE.md:292 + the two `bin/tests` lines at 397+.
6. Verify afterwards: `cmp ~/.claude/CLAUDE.md` still 57,075 bytes and unchanged.

**Do not delete the `~/.claude/*.pre-bootstrap.bak` files** — harmless, and they are the only
record of the pre-bootstrap state.

### Phase B — questions and markers (all 5 repos)

1. Delete the `## Questions are plain text — AskUserQuestion is FORBIDDEN` section; replace with a
   short pointer: questions use `AskUserQuestion` via the global `/ask-human` skill.
2. Delete the `## Every reply ends with a status marker` section and every `❓`/`⏹` reference.
3. Strip `disallowed-tools: AskUserQuestion` from the 56 sibling skill frontmatters.
4. `/stack`: `git restore` the 10 domain skills listed above; leave the 13 generic ones deleted;
   rewrite the skills list in CLAUDE.md (currently lines ~305–326) to show only what exists, and
   drop the "no `~/.claude/skills/` in a remote container" note at line 326.

### Phase C — certification ladder (all 5 repos + global)

1. Rewrite each ladder section to: **`advisor()` if available → the repo's named reviewer agents →
   disclosed self-graded**, deferring to global `CLAUDE.md` line 82 rather than re-defining the
   ladder. Keep each repo's tier (MAXIMAL/STANDARD) and its lens table verbatim.
2. Delete the "advisor() does not exist in this environment" claim and the "Docker is not running
   in the remote container / linters not installed" caveat (both false on this machine).
3. **Global**: extend `~/.claude/hooks/advisor-completion-guard.sh` so the gate is satisfied by
   `advisor` **or** by ≥1 `Agent` tool call whose `subagent_type` matches `*-reviewer`. Keep the
   filename, the `ACGUARD_OFF=1` escape and the bypass sentinel path so the existing
   `settings.json:383` registration and muscle memory keep working. Add a test under
   `~/.claude/hooks/tests/`.

### Phase D — permissions (all 5 repos)

**Category A → `deny`:** `sudo`, `rm -rf`, `git clean -fdx`, `git reset --hard`,
`git push --force*`, `chmod 777`, `make hard-restart`, `make soft-restart`, `docker volume rm`,
`docker volume prune`, `docker system prune`, `docker image prune`, `docker container prune`,
`docker network prune`, `docker rmi`, `docker compose down -v`, twes-in `make destroy`.

**Category B → `ask`:** `make up`/`down`/`down-n-rebuild-force-recreate`/`restart-*`, `make save`,
`bin/env-update.sh --apply`, `docker buildx prune`, `npm install`, `pip install --upgrade`,
`composer update`, `npm publish`, `cargo publish`, `gh pr create`, destructive SQL.

**Path denies (4 siblings only, NOT /stack):** `Read`/`Edit` on `./.env`, `docker/data`,
`docker/storage`, `var`.

Then delete the `## No permission denies — full autonomy is required` section from every CLAUDE.md
and document the new tiers instead.

> **Blocker to expect:** `.claude/settings.json` is classifier-blocked for Claude to write. The old
> route was `scripts/claude-bootstrap/settings.json.pending` + `apply-pending-settings.sh`, which
> Phase A deletes. New route: write the proposed JSON to
> `.claude/settings.json.proposed`, validate with `jq`, and hand over a single
> `! bash /tmp/apply-settings-<repo>-20260818.sh` line for manual execution.

### Phase E — git identity and autonomy (all 5 repos)

1. `git config user.name "Takieddine MESSAOUDI"` and
   `git config user.email "takieddine.messaoudi.official@gmail.com"` in each repo.
2. Add/normalise a `## Git autonomy` section in all five CLAUDE.md files (currently only `/stack`
   has one): `add`/`commit`/`push` autonomous on the default branch; no `Co-Authored-By`; no
   `Claude-Session`; plain `git push`, never `-u`; force-push and PR-opening still excluded.
3. Keep `/stack`'s "master is the only branch" rule; check each sibling's actual default branch
   before copying that clause.

### Phase F — verification

1. `bash -n` every touched shell script; `jq empty` every settings.json.
2. `grep -rn` for dangling references: `claude-bootstrap`, `AskUserQuestion is FORBIDDEN`,
   `NO QUESTION`, `plain text`, `advisor() does not exist`, `remote container`, `cloud container`,
   and each of the 13 removed `/stack` skills.
3. Run the reviewer panel per repo (`.claude/agents/*-reviewer`), two consecutive clean rounds for
   any repo whose diff touches an operational surface.
4. Produce the Rule 6 four-dimension evidence table.
5. One commit per repo, conventional-commit subject, correct identity.

### Phase G — ONE bundled hand-off script (developer runs it)

Two things Claude cannot do here: `git push` is **denied by this machine's permission layer**
[Verified 2026-08-18: plain `git push` and a compound form both refused], and
`.claude/settings.json` is classifier-blocked for Claude to write. Both are handed over **together,
in a single script written at the very end** — decided 2026-08-18, not one script per repo and not
a push-only script beforehand.

Write `/tmp/apply-decontainerization-<YYYYMMDD>.sh` (`#!/usr/bin/env bash`, `set -euo pipefail`)
that, for each of the 5 repos:

1. Validates `.claude/settings.json.proposed` with `jq empty`, backs up the live
   `.claude/settings.json` to `.bak.$(date +%s)`, moves the proposal into place, deletes the
   proposal. Skips cleanly if no proposal exists for that repo.
2. Runs `git push` on the default branch. **Plain `git push`, never `-u`.**
3. Prints a per-repo PASS/FAIL summary and exits non-zero if any step failed.

Hand over exactly one line: `! bash /tmp/apply-decontainerization-<YYYYMMDD>.sh`.

Two carry-overs this script must not drop:

- The planning commit `a243989` is **unpushed** (`master` ahead 1) and rides along in step 2.
- `/stack`'s remote is misspelled **`orgin`**, not `origin`. Do **not** silently rename it inside
  the script — surface it in the summary and let the developer decide.

Note for Phase D: the ruling is that `git push` *is* authorised in these repos, so if the denial
turns out to come from a `deny`/`ask` rule the developer controls, the honest fix is a settings
change — not a permanent manual step. Investigate while the permission tiers are open anyway, and
if it resolves, step 2 becomes unnecessary.

---

## Execution log — 2026-08-18 (post-compact session)

### Done and committed

| Repo | Commit | What |
|---|---|---|
| /stack | `aa13971` | bootstrap removed; `bin/tests/{install,precompact-handoff}.test.sh` removed; 10 domain skills restored; 8 of them stripped of the AskUserQuestion ban |
| rent-watch | `a8cfae7` | bootstrap removed; `ci.yml` + `test-ci-workflow.sh` + `drift-scan.sh` S1 corrected for it |
| pdfturbo | `3bb130b` | bootstrap removed |
| twes-in | `b1d2069` | bootstrap removed |
| phorj | — | staged only; commit classifier-blocked ×3, rides in the hand-off script |

**P0 is defused.** `scripts/claude-bootstrap/` no longer exists in any of the five repos, so the
still-registered `SessionStart` hooks find nothing and exit 127 harmlessly. Verified by simulating
the hook exactly as registered: `~/.claude/CLAUDE.md` stayed 57,075 bytes with 0 `FORBIDDEN`
mentions.

### Verified facts that correct this plan

- `~/.claude/CLAUDE.md` was **never clobbered** — 57,075 B, 0 `FORBIDDEN`, differs from
  `.pre-bootstrap.bak` only by the `{{TZ}}` → `Europe/Paris` resolution.
- The 10-vs-13 `/stack` skill split in this plan is **exactly right** — reproduced independently
  by diffing every deleted skill against `~/.claude/skills/`.
- `shellcheck`, `yamllint`, `shfmt` and `hadolint` are all **PRESENT** on this machine, so Phase C's
  instruction to delete the "linters not installed" caveat is correct.
- `askUserQuestionTimeout` is `"never"` — confirmed.

### Hand-off script — executed 2026-08-18, two bugs found by running it

`/tmp/apply-decontainerization-20260818.sh` ran and applied everything it was meant to, but the run
exposed two defects that static review had not:

1. **Step 2 had no commit step.** It stripped the `AskUserQuestion` ban from `/stack`'s `lint` and
   `fmt` SKILL.md and left them uncommitted, so the repo was pushed without them. Closed by
   `029d5d2`. Every mutating step in a hand-off script needs its own commit — the script had them
   for steps 1 and 2b and it was easy to miss the one that didn't.
2. **`git commit` commits the whole index, not just the added path.** Step 1 ran
   `git add .claude/settings.json && git commit`, but phorj's index already held its staged
   bootstrap deletions and hook fixes — so phorj's entire de-containerization landed under the
   short message *"unregister the deleted claude-bootstrap hooks"* instead of its own detailed one.
   Content is correct and complete; only the message is thin. **Not amended** — force-push is not
   authorised, and the commit is on its way to the remote.

The run was also **killed part-way through phorj's `pre-push`** (it compiles
`clippy --all-features` from scratch, several minutes). Nothing was left half-applied: every repo
was committed and clean, three were simply unpushed. Finished by
`/tmp/push-remaining-20260818.sh`.

Gates that ran green on the way: pdfturbo `206 files / 2370 tests`; phorj size-gate, surface-ratchet,
wasm-check, doc-guards and microbench-gate all OK.

### Collateral finding — phorj's PHP oracle had drifted (fixed, `e0d5b9be`)

phorj's `pre-push` gate blocked the de-containerization push with two failing tests
(`conformance_single_file_golden`, `all_examples_transpile_and_match_php`). **Not caused by this
work** — the phorj commit touches zero source files and its source tree is byte-identical to its
parent.

`scripts/toolchain.env` pinned `php-8.5.8` literally. The stack moved to **php-8.5.9**, that path
stopped existing, and the candidate loop fell through to `php8.5` on PATH — `/bin/php8.5`, an
**8.5.4 build with no bcmath**. The transpiler emits ~42 `bc*()` calls, so the PHP leg could not run
at all. One transpiled `conformance/lang/decimal.phg`, two interpreters:

| PHP | Result |
|---|---|
| `/bin/php8.5` (what the gate used) | `Call to undefined function bcmul()`, exit 255 |
| `php-8.5.9` | byte-identical to `phg run`, exit 0 |

Fixed by resolving the oracle **by capability rather than by pinned version**: glob `php-8.5.*`
newest-first, require `bcmath`, reject a candidate without it, and warn loudly if none qualifies.
Re-pinning to 8.5.9 was rejected as a fix — `toolchain.env` records the *same* misdiagnosis on
2026-07-09, so a fresh pin only resets the timer. Gate now reports `[pre-push] OK` with
43 WIN / 0 blocking regressions.

**Lesson worth keeping: a "failing test" in this stack is as likely to be a drifted toolchain as
broken code, and the fallback that hid it turned "oracle missing" into "gate against something that
cannot run the output".**

### Certification status — NOT certified

One `completeness-reviewer` round ran and returned **11 findings (2×P0, 3×P1, 3×P2, 3×P3)**. All the
substantive ones are fixed (`b12a9a7`, `a81ac23`, phorj staged). But per § "Certification ladder",
**this round does not count**: the reviewer observed the tree change under it three times while it
read — the author was fixing the log-helpers break mid-round. A round on a moving tree cannot count
toward the two-consecutive-clean requirement.

**Next certification must freeze a commit first, then run the panel from that frozen ref.** Clean
rounds so far: **0 of 2**.

Reviewer findings still OPEN (all disclosed Phase B/C scope, none executable):

- `/stack/CLAUDE.md` § "Questions are plain text" still claims every skill declares
  `disallowed-tools: AskUserQuestion` — now 15/23, not 23/23.
- The four sibling repos have **no working PreCompact handoff** and a dead `BLAST-RADIUS.md`
  pointer (rent-watch cites it 3× incl. § Credentials, plus a broken `README.md:34` link).
- ~98 files across the 5 repos still cite `scripts/claude-bootstrap/`; the skill/agent adaptation
  headers all still say `~/.claude/` "is generated by install.sh, so auditing it audits a copy".

### Left to do

1. ~~Run `/tmp/apply-decontainerization-20260818.sh`~~ — **DONE 2026-08-18.** All five repos
   committed and pushed; the script is spent and `/tmp` is not durable, do not look for it.
2. Resolve **D1–D4** in § "NEXT SESSION STARTS HERE" at the top of this file — one at a time.
   **D1 is DECIDED** (option 3, merge) — its executable spec is § "D1 — DECIDED 2026-08-18" near
   the end of this file. **D2, D3 and D4 are still open.**
3. Phase B/C prose: the five `CLAUDE.md` files still carry the plain-text-question section, the
   `❓`/`⏹` marker rule, the ladder's "advisor() does not exist" claim, and now-stale
   `scripts/claude-bootstrap/` references. **None of this is started.**
4. Phase D permissions and Phase E `## Git autonomy` sections — not started.

---

## D1 — DECIDED 2026-08-18: option 3 (merge), spec below is EXECUTABLE AS WRITTEN

> **Developer chose option 3** of the D1 option set: merge the three regressed skills
> (`forge`, `sleuth`, `inspect`) rather than keep-as-is or delete. The other ten local skills
> are de-contaminated in place, unchanged in structure.
>
> **This section is self-contained.** Everything needed to execute it was measured on
> 2026-08-18 and is written out below — no prior conversation context is required.

### Measurements (all [Verified] 2026-08-18)

| skill | global words | local words | local is | `diff -u` hunks | lines in common |
|---|---|---|---|---|---|
| `forge` | 3,946 | 2,277 | −42% | 1 | 77 / ~230 |
| `sleuth` | 3,529 | 1,883 | −47% | 1 | 45 / ~230 |
| `inspect` | 4,111 | 1,754 | −57% | 1 | 52 / ~230 |

Local paths: `/stack/.claude/skills/<n>/SKILL.md`.
Global paths: `/home/developer/.claude/skills/<n>/SKILL.md`.

**These are independently rewritten documents sharing a skeleton, not edited copies.** A
line-level three-way merge is the WRONG tool and must not be attempted. The merge spec is
driven by the numbered *adaptation-note block* at the top of each local file, which states
exactly why it diverged.

### The adaptation notes, graded

**DEAD — container-era rationale, revert these:**

| note | local line numbers (`forge` / `sleuth` / `inspect`) | claim | why it is dead |
|---|---|---|---|
| 1 | 23 / 16 / 17 | "`AskUserQuestion` TIMES OUT in this container" | the container is gone |
| 2 | 27 / 21 / 20 | "NO `advisor()` HERE" | **`/home/developer/.claude/hooks/advisor-completion-guard.sh` EXISTS on this machine** [Verified: `ls`]; global `CLAUDE.md` references `advisor()` |
| 4 | 32 / 26 / 24 | "`--scope=global\|both` IS REMOVED: `~/.claude/` is GENERATED from repo files by `scripts/claude-bootstrap/install.sh`" | that directory was **deleted** this session; `~/.claude/` is now the developer's real persistent install, so scoping to it is meaningful again |
| 7 (`inspect` only) | — / — / 29 | "THE LINTERS ARE ABSENT IN THIS CONTAINER" | shellcheck, hadolint, yamllint, shfmt, yamlfmt are all installed here |

**LIVE — genuine `/stack` adaptation, KEEP (renumber after deletions):**

- note 3 (30 / 23 / 22) — reports to `var/claude/<skill>/`, gitignored by the blanket `/var` rule
- ≤5 concurrent subagents in two sequential batches, raw output written to disk BEFORE returning
  (`forge` 34, `sleuth` 28, `inspect` 27) — matches the global cap rule and the known hang
- "PROJECT RULES WIN on any conflict: `/stack/CLAUDE.md`" (`forge` 36, `sleuth` 31, `inspect` 32)
- `forge` note 7 (line 37) — the WHY-corpus reader (`## Gotchas` + `templates/tips/`). **This is
  better than anything in the global copy** — it is what the Chesterton's Fence gate feeds on.
- `forge` note 8 (line 43) — "INFRASTRUCTURE IS NOT APPLICATION CODE; do not import
  object-oriented or functional-purity critiques"
- `inspect` note 5 (line 26) — `--vision` IS REMOVED, this project has no UI. **Permanent, correct,
  do NOT re-import the `--vision` blocks from global.**

### The finding that cuts the other way — DO NOT "FIX" THIS BACK

`## Step 4b: Self-Reflection` exists in **global** `sleuth` and `inspect` and is **absent from both
local copies** [Verified: `grep -Eic 'self-reflection|step 4b'` → 0 in all three local files]. No
adaptation note explains the removal, but it matches a known, recorded failure mode: these skills
**freeze at Step 4b**, not at synthesis.

On this point the LOCAL copy is AHEAD of global, silently. A naive "re-base onto global" would
reintroduce the hang. **This is a two-way merge, not a re-basing.**

### The merge spec — 5 points, per file

1. **Delete dead notes 1, 2, 4** (and `inspect`'s 7) and the behaviour each one justifies:
   restore `AskUserQuestion`; restore `advisor()` as the PRIMARY certifier with the three
   reviewer subagents as the documented fallback; restore `--scope=global|both`.
2. **Re-import from global ONLY what note 4 suppressed** — the `--scope` argument block
   (~8 lines each). Nothing else is imported wholesale.
3. **Keep Step 4b OUT**, and add a one-line note recording WHY (the freeze), so a later pass
   does not helpfully restore it.
4. **Keep every live note**, renumbered contiguously.
5. **Leave `--vision` out of `inspect`** permanently.

Expected size: **~40–60 changed lines per file, not ~500.** Nothing from the global copy is lost
except what was removed for a stated cause.

### The other ten skills — de-contaminate in place

`aggregate-findings`, `ask-human`, `converge`, `cross-check`, `expanding-context`, `gaps`,
`handoff`, `pre-commit`, `retrospective`, `sweep`. Same treatment for the dead notes only; do not
restructure them. [Verified 2026-08-18: **all 13** local skills mention the plain-text protocol and
`AskUserQuestion`; nine also write to `var/claude/**`.]

### Sub-questions still OPEN — ask the developer before executing

- **(a)** Global `inspect` has a `### Roadmap` output section (this week / this sprint / this
  quarter) that the local copy dropped with **no stated reason**. Re-import it, or leave it out?
  *Recommended: re-import.*
- **(b)** Should `forge`'s WHY-corpus reader (note 7) and "infra ≠ app code" (note 8) be pushed
  **UP** into the global copies, so `pdfturbo` / `phorj` / `twes-in` benefit? *Recommended: log it
  as follow-up, do not do it inside D1.*
- **(c)** Execution shape: all three files at once with diffs shown before commit, or one file at a
  time (`forge` first as the template, then the other two)? *Recommended: `forge` first as a
  checkpoint, since the same pattern is then applied three times.*

### After the merge

The change touches `.claude/**` only, which is the **STANDARD** carve-out in `/stack/CLAUDE.md`
§ "Certification ladder" — one reviewer, three lenses, one clean round. It does NOT require the
MAXIMAL two-clean-round panel. **However**, the outstanding MAXIMAL debt from Phase A is
independent and still owed (see § "Certification status").

## Resume checklist after a compact

- [ ] Phase A — 4 sibling settings.json unwired, `scripts/claude-bootstrap/` removed everywhere
- [ ] Phase B — question/marker sections gone in 5 CLAUDE.md; 56 frontmatters stripped; 10 /stack skills restored
- [ ] Phase C — 5 ladder sections rewritten; global `advisor-completion-guard.sh` extended + tested
- [ ] Phase D — deny/ask tiers proposed in 5 repos; apply scripts handed over
- [ ] Phase E — git identity set in 5 repos; autonomy documented in all 5
- [ ] Phase F — greps clean, panel clean, evidence table, 5 commits
