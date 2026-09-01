# Claude bundle — cross-repo audit and unification plan (`/stack` copy)

> Audit of the Claude global/project bundle across all five `tmessaoudi-official` repos, to find what
> each copy is missing. **This file is the portable artefact**: the same tables apply when unifying any
> of the other repos, with the `stack` column swapped for the target.
>
> Round 1 written 2026-08-06 from fresh full clones. Round 2 written the same day after the developer
> updated all four siblings, re-measured against their new HEADs.
>
> Sibling copies exist at `phorj/docs/plans/claude-bundle-cross-repo-audit.plan.md` and
> `rent-watch/docs/plans/claude-bundle-cross-repo-audit.plan.md`. **rent-watch's is the most accurate on
> chronology** — prefer it over phorj's, which orders by the `.claude/` date rather than the bundle date.
> Both of theirs contain one factual error about `stack`; see § Corrections.

## Decisions Log

- [2026-08-06] AGREED: port the bundle + skills + agents into `/stack` from the sibling line (developer request); `rent-watch` is the reference, being newest.
- [2026-08-06] AGREED: directory is `scripts/claude-bootstrap/` — cross-repo path parity beats `/stack`'s own `bin/` convention, because `settings.json`'s hook path is then identical in all five repos.
- [2026-08-06] AGREED: allow-list only — no `deny`, no `ask`.
- [2026-08-06] AGREED: full 13-skill core + the 3-lens certification panel (round 2 closed `/converge`, `/forge`, `/retrospective`).
- [2026-08-06] AGREED: commit identity is `Takieddine MESSAOUDI <takieddine.messaoudi.official@gmail.com>`, no `Co-Authored-By`; push with plain `git push`, never `-u`. Both were wrong in round 1 and corrected in round 2.
- [2026-08-06] AGREED (P1, applied): **the repo is always the truth** — `install.sh` copies unconditionally (`cp -f`), replacing `cp -u`, with a one-time `.pre-bootstrap.bak` snapshot. Ported from rent-watch, which listed it as port-OUT item 0 for all four siblings. New suite `bin/tests/install.test.sh`, 26 assertions, sabotage-verified.
- [2026-08-06] AGREED (P1, applied): `log_obs` default moved from `~/.claude/logs/` (wiped on container reclaim) to the in-repo `var/claude/logs/`.
- [2026-08-06] AGREED (P1, applied): the `<!-- manual -->` handoff guard, honoured on **both** hook write paths.
- [2026-08-06] **RULED — REJECTED for `/stack`**: rent-watch's `Read`/`Edit(./.env)` denies, which their audit lists as a P2 for all four siblings. Developer ruling: *"there should be no permissions denies! … if you are denied to do something i can't run it myself! so there must be full autonomy!"* Independently, `env-update`/`env-scan`/`env-diff` must read and write `.env` as their core function. `.claude/hooks/env-guard-on-write.sh` is the right mechanism — it warns, it does not block. See `CLAUDE.md` § "No permission denies".
- [2026-08-06] OPEN (rent-watch's question, answered here): `/stack` keeps `claude-setup/<bundle>.tar.gz` committed. It is the provenance record for the three framework docs and is verified scrubbed. Whether the siblings adopt it is theirs to rule.

## Chronology — bundle order, measured

`scripts/claude-bootstrap/` first appearance, which is the container bundle (not `.claude/`, which is
much older in `stack` and misleads):

| repo | bundle first appears | order |
|---|---|---|
| **phorj** | 2026-07-23 | **1st — origin of the container port** |
| **pdfturbo** | 2026-07-28 | 2nd |
| **twes-in** | 2026-08-02 | 3rd |
| **stack** | 2026-08-06 10:03 | 4th |
| **rent-watch** | 2026-08-06 12:00 | **5th — newest, the reference** |

**The lineage that matters:** phorj invented the container port; pdfturbo hardened it (deleted the
credential copy-out, added `apply-pending-settings.sh`); twes-in added the `LATEST_IS_MANUAL` guard, the
handoff test suite and the repo-local `log_obs`; **stack invented `/cross-check --drift`**; rent-watch
combined twes-in's bootstrap with stack's `cross-check`, then ruled *the repo is always the truth*.

Every repo shares the same wiring — `SessionStart → install.sh`, `PreCompact → precompact-handoff.sh`
(both matchers). **The mechanism was already unified everywhere.** What diverged was content.

## Feature matrix — `/stack` after round 2

| capability | stack | pdfturbo | phorj | twes-in | rent-watch |
|---|---|---|---|---|---|
| `scripts/claude-bootstrap/` wiring | ✅ | ✅ | ✅ | ✅ | ✅ |
| handoff-hook test suite | ✅ **42** | ❌ | ✅ 34 | ✅ 35 | ✅ 35 |
| `<!-- manual -->` handoff guard | ✅ (r2) | ❌ | ✅ | ✅ | ✅ |
| `log_obs` → in-repo `var/claude/logs/` | ✅ (r2) | ❌ | ✅ | ✅ | ✅ |
| credential copy-out block absent | ✅ | ✅ | ✅ | ✅ | ✅ |
| THINKING.md "edit the REPO copy" rule | ✅ (r2) | ❌ | ❌ | ✅ | ✅ |
| `## Memory System Toggles — NOT APPLICABLE` | ✅ (r2) | ❌ | ❌ | ✅ | ✅ |
| 3-lens reviewer panel | ✅ **3** | ✅ 3 | ✅ 3 (r2) | ✅ 3 | ✅ 3 |
| `permissions.deny` | ❌ **by ruling** | ❌ | ❌ | ❌ | ✅ `.env` only |
| write-time `PostToolUse` hooks | ✅ **5** | ✅ 2 | ❌ 0 | ❌ 0 | ✅ 3 |
| `/cross-check` | ✅ **(invented here)** | ❌ | ✅ | ✅ | ✅ |
| `/converge` · `/retrospective` · `/forge` | ✅ (r2) | ✅ | ✅ | ✅ | ✅ |
| `/qa-sweep` | ❌ (no UI) | ✅ | ❌ | ❌ | ❌ (no UI) |
| bundle tarball committed | ✅ **only one** | ❌ | ❌ | ❌ | ❌ |
| unconditional install (repo is truth) | ✅ (r2) | ❌ | ❌ | ❌ | ✅ |
| `install.sh` test suite | ✅ **26** | ❌ | ❌ | ❌ | ✅ 17 |

Skill count: 23 = 10 `/stack` domain skills + the 13-skill core shared with all four siblings.

## Corrections to the siblings' audits

Both sibling copies get one thing wrong about `stack`; fix these when unifying them:

> ⚠️ **Items 1 and 2 were themselves overtaken by events — corrected in place 2026-08-21.** This is
> an *imperative* section: it tells a future session what to write into `phorj` and `rent-watch`.
> Two of its three entries had gone stale and would have propagated facts that are no longer true —
> including the name of an agent that no longer exists. Verify against the live tree before acting
> on any row here.

1. ~~**"stack has no `test-precompact-handoff.sh`" is a false negative.**~~ **No longer applicable.**
   The original point was that `/stack` had the suite at `bin/tests/precompact-handoff.test.sh`
   rather than beside the hook. Both the repo's PreCompact hook and that 42-assertion suite were
   **removed 2026-08-18** (`52f579f`) under the global-is-reference ruling: handoffs are the GLOBAL
   `~/.claude/hooks/precompact-handoff.sh`'s job and the repo carries no copy. The siblings' "no
   such file" is now simply correct for `/stack`, for a different reason. The general lesson still
   holds: **measure by capability, not by path.**
2. **"stack's panel is 2 agents, 1 of which is a lead-dev"** was true when written and is now wrong
   in the opposite direction. `/stack` has exactly **three** agents, all read-only reviewer lenses
   (`stack-infra-reviewer`, `completeness-reviewer`, `reproducibility-reviewer`). The
   `global-stack-lead-dev` orchestrator was **deleted 2026-08-19** and must not be recreated or
   ported anywhere — all `/stack` work is done directly in the main conversation.
3. **phorj's plan orders `stack` 1st and calls it the ancestor.** That uses `stack`'s `.claude/` date
   (April, genuinely oldest) rather than its bundle date (Aug 6, second-newest). Ordering by the wrong
   column is what let it conclude "phorj is a week stale".

## What to port OUT of `/stack`, per repo

The actionable half when running this exercise on the siblings.

### → `pdfturbo` and `phorj` (P1)

1. **`install.sh` does not install `hooks/log-helpers.sh` into `~/.claude/hooks/`.** `/stack` is the only
   repo that does. It matters wherever project `PostToolUse` hooks `source
   "$HOME/.claude/hooks/log-helpers.sh"` and fall back to a no-op `log_obs` — their Rule 13 logging is
   then silently dead in every container session. pdfturbo (2 hooks) and rent-watch (3 hooks) should
   check whether theirs do this; `/stack`'s five did.

### → all four (P2)

2. **Put the handoff-hook suite in the project's own test harness** rather than beside the hook. It gets
   run with the rest of the suite instead of being a special case, and it is discoverable where a
   developer already looks for tests.
3. **A domain-state block in the handoff.** `/stack`'s hook emits `tools/` health markers — the state
   `git status` cannot see, and the fastest explanation for a red stack after a compaction. The
   *pattern* generalises: whatever your project's out-of-git runtime state is, put it in the handoff.
4. **`/cross-check --drift`** — invented here, now in phorj/twes-in/rent-watch. pdfturbo still lacks
   `/cross-check` entirely. The `--drift` mode verifies every mechanically-checkable claim in a doc
   against the real tree; counts rot fastest and are the highest-yield thing to check.
5. **Comment-strip before scanning your own script in a test.** `/stack`'s `install.test.sh` asserts the
   absence of the credential copy-out against a comment-stripped copy, because the header *quotes* the
   forbidden block on purpose so it cannot be silently reintroduced. rent-watch hit this exact false
   positive; `/stack` hit it again on the first run of the ported suite. Both the `cp -u` and
   "never clobbered" assertions need the same treatment.
6. **Sabotage-verify a new guard.** Both `/stack` suites were checked by breaking the thing they guard:
   reverting `install_doc` to `cp -u` fails 4 assertions, and removing the `<!-- manual -->` guard fails
   exactly 2. A guard whose test still passes when the guard is removed is not a guard.

## Open — needs a ruling

1. ~~**`SubagentStop` reminder hook** (`/stack` only). Fires for one named agent, so not portable as-is.
   rent-watch recommends skipping it since its reviewers already end with an explicit `PANEL VERDICT`
   line. `/stack` keeps it; low priority either way.~~ **MOOT 2026-08-22** — the named agent was
   `global-stack-lead-dev`, deleted 2026-08-19, and the hook went with it: `.claude/settings.json`
   now registers `PostToolUse` only [Verified: `grep -oE '"(PostToolUse|PreToolUse|SubagentStop|Stop|PreCompact|SessionStart)"'` returns `"PostToolUse"` alone].
   Nothing to port and nothing to rule on.
2. **Whether the siblings adopt `claude-setup/<bundle>.tar.gz`.** `/stack` commits the 517 KB scrubbed
   bundle as the provenance record for its three framework docs. Verified safe (all credential values are
   placeholders; only `*_SSL_VERIFY` is non-placeholder). Con: a binary in git that embeds internal MCP
   service topology, albeit scrubbed to `<mcp-client-N>` names.
