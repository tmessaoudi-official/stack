# rules-split Plan

Prune-then-split `/stack/CLAUDE.md` into path-scoped `.claude/rules/*.md` files with the global
`/rules-split` skill — requested directly by the developer on 2026-10-09 (an earlier request for
the same trim came from a peer session and was declined until the developer asked).

## Decisions Log
- [2026-10-09 22:21] AGREED (ratified ASSUMED): Lossless move, not rewrite — moved text stays byte-identical except drifted citations and cross-references, because every past one-off relocation lost or corrupted something (skill history). Alternatives: condense while moving.
- [2026-10-09 22:21] AGREED (ratified ASSUMED): Move 13 gotchas, not the peer's 17 (all >= 900 B): the port-var consumer rule, make-up-only, jq unique, projects git add -f, git grep and drifted-cwd bullets stay because they apply BEFORE any file is read, where a paths: rule has not loaded. Alternatives: move all 17 by size.
- [2026-10-09 22:21] AGREED (ratified ASSUMED): Testing & Verification keeps a one-line-per-suite table (command + rules file) and the general lint/compose/dry-run bullets; the 22 long suite narratives move. Alternatives: keep the bullets, move only the two largest.
- [2026-10-09 22:21] AGREED (ratified ASSUMED): Condense 'The container-era bootstrap is GONE' to its unique facts (settings.json hand-off route, lint hooks live, permission-swap state path, handoffs via the global PreCompact hook, BLAST-RADIUS kept in docs/), heading kept — the rest duplicates § No permission denies and § Claude Code Tooling. Alternatives: the peer's 2 lines; leave it.
- [2026-10-09 22:21] AGREED (ratified ASSUMED): Do not edit .claude/agents/*.md (global Rule 5 needs explicit authorization); their '§ Gotchas' citations still resolve through the index lines left in CLAUDE.md. Alternatives: repoint them to the rules files.
- [2026-10-09 22:37] AGREED (ratified ASSUMED): Index lines of debugging gotchas (phpbrew tmp dir, $HOME chmod) carry the observed error text, so a debugger starting from a log can match them — because the full text only auto-loads when a matching file is READ. Alternatives: index lines without symptoms.
- [2026-10-09 22:45] AGREED (ratified ASSUMED): No stop under /stack-ask-human's weaken-a-gotcha case for the 13 moved gotchas: probes show they load on Read, Write and Bash reads of matching files, so they are not weakened in practice, and the developer requested the split. Alternatives: ask before step 5.

## Formal Plan

Lossless move: moved text is byte-identical to the snapshot except for drifted citations and
cross-references, which become quoted anchors or `→ .claude/rules/<file>.md` pointers. Everything
needed BEFORE a file is read (gates, destructive-command rules, `make up` only, git diff/grep
traps, cwd drift, port-var consumer rule, `RELOAD_*`, token invariant) stays in CLAUDE.md.

| Rules file | Moves |
|---|---|
| `startup-scripts.md` | Shared prologue; gotchas: versions markers, downloaded tools refuse, phpbrew tmp, four images BAKE, `$HOME` chmod, trailing `&&` |
| `startup-tests.md` | startup-prologue, base-install-tools, set-permissions, sonarqube, phpbrew-extract suite narratives |
| `android.md` | rolling window, `--sdk` global option |
| `env-update.md` | env-update + coverage suite narratives, the "upstream index can ANNOUNCE" gotcha |
| `global-unu-opt.md` | Key Scripts paragraph + its suite narrative |
| `docker-images.md` | foreign EOL bases, Dockerfile toggle, mongo9, postgres collation, three docker suite narratives |
| `host-tooling.md` | eight small suite narratives |

Verify: byte-preservation check, live `claude -p` probe per glob shape on a copy (count
`nested_memory` attachments), startup-prologue + env-update suites re-run.

## Status
<!-- progress-block v1 -->
| # | Step | Size | State | Evidence | Files |
|---|------|------|-------|----------|-------|
| 1 | Inventory consumers, prune-sample, glob targets, 3C advisor | S | done | - | - |
| 2 | Generator gen_split.py written and run | M | done | 3d86767 | - |
| 3 | Run generator into scratch, byte-preservation check, review output | M | done | 3d86767 | - |
| 4 | Live claude -p probe on a throwaway copy with the split laid over it: zero-read start set, one read per glob shape (local.*android*/**, env-update*.test.sh, global-unu*.sh, plain **), a negative control, AND a session started at docker/ reading docker/config/dist/bin/* (ancestor rules load? paths resolve from rules root or cwd?) — BEFORE any apply | M | done | 5703004 | - |
| 5 | Apply CLAUDE.md + .claude/rules/*.md; repoint env-update.md:1349 + startup-prologue.test.sh comments :104/:1107; suites re-run | M | done | 9b450fb | CLAUDE.md, .claude/rules/**, templates/tips/env-update.md, bin/tests/startup-prologue.test.sh |
| 6 | One commit, 6C advisor | S | done | 9b450fb | - |
<!-- /progress-block -->

### Resume notes (session restart 2026-10-09 ~22:30)
- Durable copies: `var/claude/rules-split/gen_split.py` (generator) and `var/claude/rules-split/CLAUDE.md.pre-split` (snapshot of CLAUDE.md, 528 lines / 133,731 B, HEAD 29ca13b). CLAUDE.md itself is UNTOUCHED.
- Run: `python3 var/claude/rules-split/gen_split.py var/claude/rules-split/CLAUDE.md.pre-split <outdir>` — writes `<outdir>/CLAUDE.md` + `<outdir>/.claude/rules/*.md`; asserts every substitution hits exactly once. Not yet executed.
- 2026-10-09 resume: step 3 DONE. `var/claude/rules-split/verify_split.py` (independent line accounting, borrows only the *_FIX lists) → `LOST 8` (all bootstrap, intended) / `ADDED 136, unexpected 0`; sabotaged twice (dropped line → LOST-OUTSIDE, duplicated line → UNEXPECTED), both caught. All 40 `paths:` globs match ≥1 file on disk (`local.*android*/**` fs=5, git=0 — gitignored). Sizes: CLAUDE.md 133,731 → 71,891 B; largest rules file startup-tests.md 18,130 B (< 30 KB). No non-.md consumer parses CLAUDE.md text. Index lines for the phpbrew tmp and `$HOME` chmod gotchas now carry the observed symptom (advisor 3C item 5).
- 6C advisor 2026-10-09: probe BEFORE apply (step order swapped) — if paths: rules do not load as claimed, a pushed CLAUDE.md loses 62 KB with nothing loading it back. The subdir probe decides whether moved gotchas survive sessions started at /stack/docker or /stack/projects/CV. Cross-refs verified both directions; difflib → 15 hunks (adjacent moves merge).
- Step 4 probe DONE (2026-10-09, claude 2.1.296, haiku, `disableAllHooks`; ids in `var/claude/rules-split/probe-results.txt`): zero-read start → 0 rules loaded; `local.*android*/**` → android+docker-images; `env-update*.test.sh` → env-update; `global-unu*.sh` → global-unu-opt; plain `**` → startup-scripts; negative control (docs/BLAST-RADIUS.md) → none; session started at `docker/` reading the prologue → startup-scripts (ancestor rules load, paths resolve from the rules root). NOT probed: a session rooted at `/stack/projects/CV` (gitignored, its own project root) — its files match no glob anyway. Start-set saving ≈ 61,840 B ≈ 15.5k tokens [Inferred: bytes/4].
- Step 4 follow-up probes (6C advisor): Bash `head` → startup-scripts loaded; Write of a NEW file under dist/bin → loaded; Grep alone → nothing. Intake line in gen_split.py now says so; verifier re-run clean (LOST 8 bootstrap / unexpected 0); CLAUDE.md output 72,140 B. Step 5's apply script must `cmp` live CLAUDE.md against the snapshot and abort on drift, and regenerate + `diff -r` against the verified output before copying.
- 6C round 2: no `claudeMdExcludes` in /stack/.claude/settings{,.local}.json or ~/.claude/settings.json; tree comment wording aligned with the intake line, verifier clean. Step 5 done-when includes a live probe at cwd /stack (p0 zero-read + p4 Read) AFTER the apply. Unprobed: `sed -i`/python3 rewrite of a matching file with no prior Read; sessions rooted at /stack/projects/CV.
- Step 5 apply script must also: `git add -- CLAUDE.md .claude/rules/ templates/tips/env-update.md bin/tests/startup-prologue.test.sh`, assert `git ls-files .claude/rules | wc -l` == 7 before committing (abort otherwise), one commit for all.
- Step 5 DONE: `/tmp/apply-rules-split-20261009.sh` ran (not classifier-blocked) → `9b450fb`, 10 paths. Post-apply probe on a FRESH worktree of 9b450fb (nothing laid over): zero-read → 0 rules; Read of the prologue → startup-scripts (session ids in probe-results.txt). startup-prologue.test.sh ALL PASSED 1109/1109; env-update batches → `var/claude/rules-split/eu-suite.log`.
- 6C (step 5) → advisor clean. env-update.test.sh 928/928 (162+178+210+177+201). UNCERTIFIED-BY-EXECUTION: rules reaching SUBAGENTS that Read a matching file (matters for the milestone reviewer panel — probe one unnamed agent before the next panel); `sed -i`/python3 rewrite with no prior Read; sessions rooted at /stack/projects/CV; the ≈15.5k-token saving until a `/context` from a fresh /stack session replaces it.
- (was) Still to do in the check: verify every moved bullet appears verbatim (post-fix) in exactly one rules file; grep the output for leftover `above|below|bullet` refs; confirm the `--section` gotchas read right.
- Advisor 3C items still open: probe the partial-segment globs (`local.*android*/**`, `env-update*.test.sh`, `global-unu*.sh`) + one negative control, start set in a separate zero-read call; report tokens as [Inferred: bytes/4]; ask the developer to paste `/context` after applying.
- CLAUDE.md is classifier-blocked: attempt the copy ONCE; on a block hand over `! bash /tmp/apply-rules-split-20261009.sh`.
- env-update suite re-run was in flight → `var/claude/eu-suite-2026-10-09.log` (read only the `ALL PASSED N / N` lines; may be truncated by the restart).
### Blocked
### Needs input
### Needs research
### Fragile
### Known issues
