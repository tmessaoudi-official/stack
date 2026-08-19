# De-containerization Plan — restore AskUserQuestion + advisor-aware ladder

> # ✅ CLOSED — 2026-08-19
>
> **This program is finished. Do not resume it; read it as the record.** All six repos are
> de-containerized, decontaminated against the global-is-reference ruling, committed and pushed,
> and Phase G is applied. Verified at close-out: `dirty=0 ahead=0` in all six, **zero name
> collisions** against the global 48 skills / 19 hooks / 0 agents, commit identity
> `Takieddine MESSAOUDI <takieddine.messaoudi.official@gmail.com>` in all six.
>
> **One decision (D2) is deliberately deferred, not forgotten** — see the table below; it is
> parked with its conflict intact rather than resolved by default. Everything else that remains
> (the MAXIMAL certification rounds, per-repo Phase D/E) is **per-repo development work**, owned
> by the developer, by ruling of 2026-08-19: *"just finish the claude code bundle correction,
> nothing more — I will finish each repo development on its own."*
>
> **Read § "Decisions Log" for the rulings and § "Execution log" for what happened.** Five of this
> plan's own premises were REFUTED mid-flight; each refutation is recorded in place rather than
> edited away, and that is the most useful thing in this file.

---

## Outcome — the four decisions

| # | Decision | Outcome |
|---|---|---|
| **D1** ✅ | Merge vs delete the 13 "duplicate" skills | **RESOLVED, then SUPERSEDED.** Decided as option 3 (merge) on the strength of the refuted-duplicates finding; superseded hours later by the **global-is-reference ruling** (2026-08-18 19:17), under which a repo may not carry any artifact that exists in `~/.claude/` unless renamed and heavily repurposed. Executed as extract-then-delete with per-repo prefixes (`stack-` `rw-` `pdf-` `phg-` `twes-` `in-`). The § "D1 — DECIDED" spec below is kept as the record of the reasoning, **not as instructions** — do not execute it. |
| **D2** ⏸️ | Phase D permission tiers vs rent-watch's invariant | **DEFERRED BY CHOICE, 2026-08-19 — still genuinely open.** rent-watch's `CLAUDE.md` rules `deny` stays **empty** and its `rw-repair/drift-scan.sh` § S4b **mechanically asserts** it, precisely so a sibling port cannot reintroduce one; Phase D would trip that gate. Nothing in this program prejudged it — `deny` is still `[]` in every repo's settings [Verified at close-out]. The three options stand unchanged: exempt rent-watch · change its ruling AND its scanner together · drop the path denies everywhere. **Note the enforcement that DID land is global-layer only** (Phase G's five tool denies in `~/.claude/settings.json`), chosen deliberately so S4b's repo-scope assertion stays untouched. |
| **D3** ✅ | Proceed into the Phase B/C prose | **DONE, all six repos.** Question sections, `❓`/`⏹` marker rules, "advisor() does not exist" ladder claims and dead bootstrap pointers are gone from every `CLAUDE.md` and every `.claude/**`. Final sweep: 0 live `disallowed-tools: AskUserQuestion`, 0 marker rules, 0 no-advisor claims. Remaining `claude-bootstrap` mentions are dated retirement notes plus invoiceninja's stays-gone assertion — read individually, not swept. |
| **D4** ❌ | Vendor the PreCompact handoff into the 4 siblings | **CANCELLED** by the global-is-reference ruling. Handoffs are the GLOBAL `~/.claude/hooks/precompact-handoff.sh`'s job, writing into the developer's memory pipeline; the copy briefly vendored into `/stack` was removed again the same day, and no repo carries one. |

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
- [2026-08-18 19:05] AGREED (developer, verbatim intent): **no dynamic workflows and no agent teams** — work is done inline or with normal (plain `Agent`-tool) subagents only. Enforcement mechanism is PENDING a decision (options: global `~/.claude/CLAUDE.md` prose rule; global `~/.claude/settings.json` deny entries for `SendMessage`/`ScheduleWakeup`/`CronCreate`/`CronDelete`/`RemoteTrigger` — global layer deliberately, so rent-watch's S4b repo-scope assertion is untouched [Verified 2026-08-18: S4b reads only the repo's own `.claude/settings.json`]; optional PreToolUse hook). Both global files are classifier-blocked for Claude → the mechanism ships as ONE hand-off script.
- [2026-08-18 19:05] AGREED: **`/stack/projects/invoiceninja` is now IN scope** (developer reversed the earlier skip). Its contamination is tiny — no `.claude/`, no bootstrap, `FORBIDDEN=0`; only the `## Reply convention` marker section (CLAUDE.md:106–~125, ruled 2026-08-12 *without* the plain-text ban, so the "marker dies with the plain-text protocol" rationale does not automatically cover it — ask before deleting). **HARD GATE: the repo is mid interactive-rebase (`-S` signing/author-rewrite pass, `backup/pre-author-rewrite-*` branch, 5,441 staged paths) — touch NOTHING there until the developer finishes or aborts that rebase.**
- [2026-08-18 19:20] AGREED (via AskUserQuestion — which WORKS on this machine, mechanically confirmed by the ask-human-question-guard Stop hook firing): **execution order is rent-watch slice FIRST** (single-repo decontamination: CLAUDE.md container sections, 15 skill frontmatters, vendored PreCompact handoff), then the same recipe per repo; enforcement script and D1 follow. Push of `/stack` explicitly approved.
- [2026-08-18 19:17] AGREED (developer, verbatim intent — **supersedes D1's keep-repo-local shape and CANCELS D4**): **global `~/.claude/` and `~/.claude.json` are THE reference — any artifact that exists there must NOT exist in any repo, unless renamed and heavily repurposed.** Audit run against both inventories: **73 violations** — /stack 15 (2 hooks + 13 skills), rent-watch 16 (2 hooks + 14 skills), pdfturbo 14, phorj 15 (1 hook + 14 skills), twes-in 13, invoiceninja 0. Repo agents are compliant (`~/.claude/agents/` is empty); the 10 /stack domain skills, rent-watch's `add-source`, and all uniquely-named hooks stay.
- [2026-08-18 19:45] AGREED (**executed on rent-watch — THIS IS THE SIBLING RECIPE**): remediation shape is **extract-then-delete**, four commits, each green in isolation: (1) `e524516` hooks source the GLOBAL `log-helpers.sh` with the existing missing-file/no-op guard (CI-safe), repo copy deleted; (2) `f71dd12` name-colliding-but-heavily-repurposed skills survive by **`rw-` prefix rename** (`repair`→`rw-repair` with drift-scan.sh, `ask-human`→`rw-ask-human`) with ALL references moved in the same commit; (3) `89a3cd2` the repo-specific payload of the 12 remaining duplicates (review dimensions, sleuth lens K, repo conventions) extracts into ONE new **`rw-lenses`** skill, the 12 delete (−3,252 lines), and CLAUDE.md carries the load-bearing bridge ("load `/rw-lenses` before any global review skill"); (4) `3c965a8` handoff prose → global PreCompact hook; the classifier-blocked settings.json dereg + hook deletion ship as ONE hand-off script (`/tmp/remove-precompact-rent-watch-20260818.sh`). **No merge-up was needed**: global sleuth/inspect already carry the Step-4b write-to-file freeze fix. Per-sibling scoping: phorj has the `log-helpers.sh` hook collision (same repoint), pdfturbo/twes-in are skills-only; check each for a `<repo>-lenses`-worthy domain payload before deleting — do not assume rent-watch's shape. Phase D/E stay out (D2 open). Certification: advisor() CLEAN ×2 (pre-work + completion), gates pasted (drift P0=0 P1=0 P2=0, ci-workflow 11/11, tenure-guard 66/66, bash -n clean; PHP suite skipped — no src/tests changes).
- [2026-08-18 20:15] **RECIPE EXECUTED ON ALL FIVE REPOS — the program's remediation phase is COMPLETE.** pdfturbo `b139d7d`+`4f61932` (pushed, pre-push gate type-check+lint+test green); phorj `d6ee6db9`+`c5cded43` (pushed, FULL pre-push gate green incl. PHP oracle; hook test 22/22 after the log-helpers repoint — first attempt broke it by dropping the `root` var, caught by baselining against clean HEAD); twes-in `a4cc5bc` (pushed; pre-existing failure disclosed: test-hooks-on-write 27/28, php-cs-fixer style drift in `api/src/Domain/Money/Money.php`, present on clean HEAD); /stack `424f5ec`+`87190a2`+`0d01306` (pushed). Per-repo prefixes: `rw-`, `pdf-`, `phg-`, `twes-`, `stack-`. Surviving repo skills: lenses + ask-human everywhere, plus pdf-qa-sweep, phg-qa-sweep, rw-repair, and /stack's 10 domain skills. All ask-human conversions re-invert to AskUserQuestion with repo illustrations preserved. Cross-repo live-claim sweep: 0 hits in all five. **EXECUTED (developer, 2026-08-18): both remove-precompact scripts ran** — `/stack` `52f579f`, rent-watch `7656cc6` (settings.json PreCompact dereg + vendored hook/suite deletion; verified: 0 precompact refs in either settings.json, hook files gone). **Still open at this entry's time:** D2 (sibling permission tiers), Phase G, invoiceninja — see the 2026-08-18/19 entries below.
- [2026-08-18 22:30] **invoiceninja DECONTAMINATED (staged; commit blocked for Claude this session — hand-off script `/tmp/commit-invoiceninja-20260818.sh`).** The plan's premise for this repo ("no .claude/, no bootstrap, FORBIDDEN=0") was STALE — the finished rebase surfaced a full contaminated `.claude/` (15 global-name duplicate skills, 3 agents, 4 hooks) AND the LIVE P0: `scripts/claude-bootstrap/install.sh` still wired as SessionStart with `cp -f --remove-destination` over `~/.claude/CLAUDE.md` (2 AskUserQuestion-ban hits in its CLAUDE-global.md; `.pre-bootstrap.bak` spent). Defused on disk: SessionStart + both PreCompact matchers removed from settings.json, bootstrap git rm'd. Recipe applied (prefix `in-`): payload → `/in-lenses` (three-zone dims, PHP/TS totals mirror, fork lens K, forge lenses, per-skill notes); `ask-human`→`/in-ask-human` (re-inverted); `repair`→`/in-repair` (drift-scan S1b rewritten to assert the bootstrap STAYS gone; CITE gained removed|deleted); `qa-sweep`→`/in-qa-sweep`; 12 duplicates deleted (−4,730 lines). CLAUDE.md Reply-convention/plain-text RETIRED + superseding ledger entry; README/PROMPTS pointers fixed. Gates: drift-scan MISSING=0 STALE=0 OBSOLETE=0; bin/drift-check exit 0; bash -n clean; settings valid.
- [2026-08-18 22:35] **Phase G script WRITTEN** — `/tmp/apply-no-teams-enforcement-20260818.sh` (global settings.json deny for SendMessage/RemoteTrigger/ScheduleWakeup/CronCreate/CronDelete; backup + jq + validate + rollback). ⚠ header documents the trade-off: ScheduleWakeup/Cron denies also kill /loop self-pacing and /schedule — the DENY_TOOLS array is editable before running. NOT yet applied (developer's `!` relay did not execute; run from a plain terminal).
- [2026-08-18 22:40] **twes-in pre-existing red ROOT-CAUSED and fixed (staged; hand-off `/tmp/commit-twes-in-20260818.sh`).** test-hooks-on-write 27/28 was never style drift: a pre-TWES_UID root container left `api/var` root:root 755 via the bind mount; php-cs-fixer's cache writer @touch-fails silently there and dies ENOENT inside whatever file it checks. Money.php was clean all along ("0 of 1 files can be fixed"). Fix at the single funnel: `.php-cs-fixer.dist.php` claims var/ for the invoking user or refuses loudly naming the root-container cause; stale root-owned empty dir rmdir'd. Hook suite 28/28; fixer 0 on Money.php and the config; php -l clean.
- [2026-08-19 00:05] **MAXIMAL certification ROUND 1 COMPLETE for /stack + rent-watch (5 reviewers, frozen SHAs 52f579f / 68153a7). Zero P0. Findings → fixed same day:** /stack P1 (all three panel charters still asserted the dead container env + pointed at deleted bootstrap paths — repro:80,104, completeness:25-29,89, infra:25 → all repointed/rewritten) + P2s (.gitignore bootstrap comments, CLAUDE.md settings.json.pending phrase, handoff-destination contradiction [handoffs go to the GLOBAL hook's ~/.claude/projects/<slug>/memory/sessions/, var/claude is reports only], "47 skills" count → derive-don't-count, this plan's stale PENDING). rent-watch P1 (OPEN-QUESTIONS.md:1111 dangled on renamed ask-human; drift-scan S2 blind to `.claude/` paths — both fixed) + P2s (CLAUDE.md:36 + ci.yml:5 "bootstrap self-tests" claim; corpus.json:4 + milestone plan:184 stale BLAST-RADIUS refs). Reviewer positives: stack-lenses payload complete vs git show of deleted skills; global sleuth/inspect carry the Step-4b fix; hooks proven no-op with empty HOME and stripped PATH; rent-watch suite 1285/4666 green, tripwire 66/66, PHPUnit pin verified 4 independent ways. Counter resets: both repos back to 0/2; re-rounds follow the fix pass. pdfturbo/phorj/twes-in/invoiceninja round 1 queued (cap ≤5 concurrent).
- [2026-08-19 03:10] **THE CLAUDE-CODE-BUNDLE DECONTAMINATION IS COMPLETE ACROSS ALL SIX REPOS — scope closed by developer ruling ("just finish the claude code bundle correction, nothing more; I will finish each repo development on its own").** Everything that had been queued into unrun `/tmp` hand-off scripts was committed directly — the classifier did NOT block `git commit` this session, so the scripts were unnecessary: /stack `b7f3857`, rent-watch `976def3`, twes-in `ebcb893`, invoiceninja `01a51ec7c2` (the 32-path decontamination; its guard had silently short-circuited on an identity CASE mismatch — `Takieddine Messaoudi` vs the ruling's `Takieddine MESSAOUDI` — now fixed and warned about in two CLAUDE.md files). A fresh cross-repo sweep then found the sibling reviewer charters had never been de-containerized — the same P1 the /stack panel raised about its own three: twes-in's `completeness-reviewer` sent every round to read Rule 6 out of the DELETED `scripts/claude-bootstrap/CLAUDE-global.md`; twes-in + pdfturbo justified their visual-evidence rule with "the container is reclaimed"; rent-watch's `source-resilience-reviewer` said "a request from this container". Plus the highest-blast-radius live claim left anywhere: `/stack/.claude/skills/validate/SKILL.md` Step 0 told every run the linters are absent, pre-authorising the skill to SKIP its own checks — all six binaries are installed [Verified: `command -v` returns a path for each]. Fixed and committed: /stack `5a06d2c`, twes-in `99fa235`, pdfturbo `310c308`, rent-watch `46099f8`. **Final sweep across all six repos: 0 live `disallowed-tools: AskUserQuestion`, 0 `❓`/`⏹` marker rules, 0 "advisor() does not exist" claims** — every hit on those three is in a plan or decision-log file, i.e. the historical record, which is where it belongs. **`claude-bootstrap` is NOT zero and must not be claimed as zero** — this entry said so for one commit and it was false by construction, since the sweep column was pathspec-limited to `.claude/*` and `CLAUDE.md` and therefore could not have been finding plan files [caught by `advisor()` at the 6C gate, not by me]. Reading all 10 remaining hits individually: every `CLAUDE.md` one is a **dated retirement note** ("removed 2026-08-18" / "is GONE"), and invoiceninja's `in-repair/drift-scan.sh` ones are the **assertion that it stays gone**. Two were genuinely stale and are now fixed: `twes-in/README.md`'s layout table still listed the directory as a live component (`0607571`), and rent-watch's `rw-repair` § S1 was **dead code inside a live gate** — it compared a shipped framework copy that no longer exists, behind a file-absent `sys.exit(0)`, so it could never fire again; inverted to assert the bootstrap stays gone, mutant-pinned (`bc1da7d`). Identity verified `Takieddine MESSAOUDI <takieddine.messaoudi.official@gmail.com>` in all six. **Only `git push` is left** (denied to Claude by the permission layer): `! bash /tmp/push-decontamination-20260819.sh`. STILL OPEN and deliberately NOT done: D2 (sibling permission tiers), Phase D/E beyond identity, Phase G enforcement (`/tmp/apply-no-teams-enforcement-20260818.sh`, still unrun), and the MAXIMAL two-clean-round certification debt (rounds are per-repo development work, now the developer's).
- [2026-08-18 19:17] AGREED: **remediation path = push-then-remediate.** rent-watch's certified closeout (8f2e3e3 + 60e5ec7 + cd046f3) pushes now; **rent-watch is remediated FIRST** (developer works there next), then the siblings. Valuable repo deltas (e.g. the Step-4b freeze fix) merge **UP into the global copies** or survive via rename+repurpose; only then are repo duplicates deleted. `~/.claude` file edits by Claude, commits handed to the developer (classifier). The rent-watch closeout's certification disclosure: reviewer subagent unavailable (3× 529); certified via advisor() — the ladder's first rung on this machine — verdict CLEAN, suites 42/42, 66/66, drift P0=0 P1=0 P2=0, composition check exact.

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

### Left to do — NOTHING IN THIS PROGRAM (closed 2026-08-19)

All four items that stood here are resolved; see § "Outcome — the four decisions" at the top.
Retained below is only what is **deliberately** carried out of this program, so nobody re-opens
the plan looking for it:

| Carried out of scope | Owner | Why it is not here |
|---|---|---|
| **D2** — sibling permission tiers | open decision | Deferred by choice, conflict intact. `deny` is `[]` in every repo, unprejudged. |
| **MAXIMAL certification rounds** — /stack + rent-watch at 0 of 2; the other four never had round 1 | developer, per repo | Per-repo development work by the 2026-08-19 ruling. A round must freeze a commit first. |
| **Phase E beyond identity** — a normalised `## Git autonomy` section in every sibling | developer, per repo | Identity IS done and verified in all six; the prose normalisation is repo-local editing. |
| `/stack`'s remote is spelled **`orgin`** | developer | Surfaced, never silently renamed: `git -C /stack remote rename orgin origin`. |

Hand-off scripts from this program are **spent and deleted** (`/tmp` is not durable — do not look
for them). The one that survives is `/tmp/apply-no-teams-enforcement-20260818.sh`, and it was
**applied 2026-08-19**: `~/.claude/settings.json` `permissions.deny` went 123 → 128, adding exactly
`SendMessage` `RemoteTrigger` `ScheduleWakeup` `CronCreate` `CronDelete`, nothing lost
[Verified: jq set difference; everything outside `.permissions.deny` byte-identical]. Note the
script's `jq unique` **sorts the whole array** as a side effect, so its diff looks enormous and is
almost entirely reordering — check the set, not the diff. Rollback:
`cp -a ~/.claude/settings.json.bak.1787117556 ~/.claude/settings.json`.

---

## D1 — SUPERSEDED. Historical record only — DO NOT EXECUTE THIS SECTION

> ⚠️ **This spec was overtaken hours after it was written**, by the global-is-reference ruling of
> 2026-08-18 19:17: a repo may not carry any artifact that exists in `~/.claude/` unless renamed and
> heavily repurposed. Under that ruling the 13 skills were **deleted**, not merged — their
> repo-specific payload extracted into one `<prefix>-lenses` skill per repo. Its header used to read
> *"spec below is EXECUTABLE AS WRITTEN"*, and it is not; the measurements and the graded adaptation
> notes are kept because the REASONING is the useful part, and because "these are not duplicates"
> was the refutation that changed the whole program's direction.

### The spec as it stood on 2026-08-18 (superseded)

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

### Sub-questions — MOOT (the section they belonged to was superseded)

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

## rent-watch slice — EXECUTED 2026-08-18 (commit `8f2e3e3`; pushed since, along with everything else)

First per-repo de-contamination slice, ruled 2026-08-18 (rent-watch first because the developer
starts working there ASAP). 27 files, +898/−255. What it did:

- **CLAUDE.md**: plain-text §, `❓`/`⏹` marker rule, and the "advisor() does not exist" ladder claim
  all replaced; bootstrap-reinstall claim, dead `BLAST-RADIUS.md` link, and the file-layout /
  Claude-config bootstrap rows corrected; vendored handoff hook + test documented in § "Claude
  config in this repo" (S3 requires that).
- **Skills**: `ask-human` re-inverted to the `AskUserQuestion` protocol (question-QUALITY rules kept
  verbatim); 15 frontmatters stripped; ~13 skill bodies' container-era adaptation notes corrected in
  place (81+ substitutions: plain-text note, NO-advisor note, `--scope` removal note, wiped-container
  rationale, `/home/user/rent-watch` path, "ask in plain text" phrasing). The dormant guarded
  bootstrap code in `drift-scan.sh` (S1 `sys.exit(0)` skip, S3 `-e` guards) was left as-is — green.
- **PreCompact handoff (D4-for-one-repo)**: `/stack`'s hook vendored byte-identical to
  `.claude/hooks/precompact-handoff.sh`; test at `.claude/hooks/tests/test-precompact-handoff.sh`
  (one line adapted: SUT path), 42/42 green in place; modes 100755 in git (`core.fileMode=false`
  here too — `git update-index --chmod=+x` was required).
- **Registration**: `.claude/settings.json.proposed` (valid JSON, delta = the two PreCompact
  matchers) + hand-off `/tmp/apply-settings-rent-watch-20260818.sh`. Until applied, drift-scan
  reports exactly one P2 (unregistered hook) — expected, not drift.
- **OPEN-QUESTIONS.md**: superseding Decisions-Log ruling appended (the 2026-08-06 ban's rationale
  died with the container).
- Verified: drift-scan `P0=0 P1=0 P2=1`; tenure-guard 66/66; ci-workflow 11/11; handoff suite 42/42;
  shellcheck clean. Diff touches no `src/`, `config/` or `tests/` → STANDARD tier (one reviewer,
  three lenses, one clean round).

**D2 note**: S4b untouched — `deny` stays `[]` in both the live settings and the proposal, so the
slice does not prejudge D2.

**The recipe for the remaining repos** (pdfturbo, phorj, twes-in — same disease, same cure): strip
frontmatters → re-invert `ask-human` → correct the numbered adaptation notes in every skill body
(the notes are per-repo rewordings of the same template; whitespace-tolerant regex catches ~90%,
then hand-patch stragglers by grep) → CLAUDE.md sections → dead bootstrap pointers in
README/.gitignore/env/hook comments → vendor handoff + test + settings proposal → full grep sweep +
repo's own gates.

## Final checklist — closed 2026-08-19

- [x] **Phase A** — sibling `settings.json` unwired, `scripts/claude-bootstrap/` removed in all
      **six** repos (invoiceninja's was the last, and a LIVE P0 the plan had recorded as clean)
- [x] **Phase B** — question/marker sections gone from all six `CLAUDE.md`; every
      `disallowed-tools: AskUserQuestion` frontmatter stripped; `/stack`'s 10 domain skills restored
- [x] **Phase C** — ladder sections rewritten against the live machine (`advisor()` IS available
      here); the reviewer-subagent panel is the documented fallback, not the primary
- [ ] **Phase D** — permission tiers: **DEFERRED, D2 open by choice.** `deny` stays `[]` in every
      repo; the enforcement that landed is global-layer only, so rent-watch's S4b is untouched
- [x] **Phase E** — commit identity verified `Takieddine MESSAOUDI` in all six (a CASE mismatch in
      invoiceninja had been silently blocking its commit). Per-repo autonomy prose: carried out.
- [x] **Phase F** — sweeps clean, gates green per repo (pdfturbo 206 files / 2370 tests;
      rent-watch drift-scan P0=0 P1=0 P2=0; twes-in hooks 28/28; invoiceninja drift-scan clean),
      commits landed, all six pushed
- [x] **Phase G** — no-teams enforcement applied to `~/.claude/settings.json` (deny 123 → 128)
- [x] **global-is-reference** — zero name collisions in all six against global's 48 skills /
      19 hooks / 0 agents; survivors renamed with per-repo prefixes

**The certification debt is NOT ticked and is not owed by this plan** — it moved to the developer
with the rest of the per-repo work. Stating that here rather than leaving an unticked box that
reads like an oversight.
