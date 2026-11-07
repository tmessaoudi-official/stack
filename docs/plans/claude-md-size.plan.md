# claude-md-size Plan

Bring the session's always-loaded instruction files (6 files, 155,112 chars on 2026-11-07) under the
150,000-char limit by shrinking `/stack/CLAUDE.md` only, with nothing lost: every line leaves CLAUDE.md
only to land verbatim in a path-scoped `.claude/rules/` file, or because the same fact is stated
elsewhere in CLAUDE.md (the surviving twin is named and checked).

## Decisions Log
- [2026-11-07 14:58] AGREED: Shrink /stack/CLAUDE.md only (global CLAUDE.md, BLAST-RADIUS.md, THINKING.md, RTK*.md untouched); developer's condition: nothing lost, sacrificed or compromised — moves land verbatim in path-scoped rules, dedupes keep a named surviving twin.
- [2026-11-07 15:19] AGREED: Wait for the concurrent local-registry-lifecycle session to commit its CLAUDE.md and host-tooling.md edits before applying any move; then re-baseline the conservation check on the new HEAD.

## Formal Plan

Baseline 2026-11-07: 155,112 chars over 6 files (`wc -m`); `/stack/CLAUDE.md` 71,975. Goal: < 150,000.

**Probe (claude 2.1.319, haiku `-p`, throwaway repo, negative control clean):** a Read of `.env.local`
loads a `paths: ".env*"` rule; RUNNING `bash bin/tests/<suite>` via Bash loads NOTHING. So an index
line for a test-running trap must carry the operative fact itself.

**New rules files** (`paths:` frontmatter + the existing "split out of CLAUDE.md" header convention):
- `.claude/rules/env-files.md` — `.env*`, env-update/env-scan code and tips, `bump-versions`,
  `docker/config/dist/bin/**`, `docker/images/local.*/**`: the § Common Workflows pin-bump comment
  block; the two LOCAL-port gotchas.
- `.claude/rules/claude-config.md` — `.claude/**`, `CLAUDE.md`, `projects/**`, `.gitignore`,
  `claude-setup/**`, `docs/BLAST-RADIUS.md`: the § Claude Code Configuration inventory (the
  `.claude/rules/` list STAYS in CLAUDE.md); the `projects/CLAUDE.md` `git add -f` gotcha; the
  `jq unique` gotcha's narrative.
- `.claude/rules/shell-conventions.md` — `bin/**`, startup-script dirs, `templates/shell/**`,
  `.claude/hooks/**`: § Shell Coding Conventions except the `set` flags, **Dependencies**
  (`reproducibility-reviewer.md:71` points at it) and **Version ordering**.

**Into existing rules files:** the `startup-prologue --section` gotcha → `startup-tests.md`; the
`git grep` gotcha → `docker-images.md`.

**Every Gotchas bullet is ONE line, so every bullet moves WHOLE and verbatim** (never split): the
CLAUDE.md index line is new text — the citable heading phrase, the operative rule (for the test-running
`--section` trap, the rule itself, since running a suite loads no rule), and the `→ rules file` pointer.
Multi-line blocks (the inventory, § Shell Coding Conventions, the pin-bump block) move line-intact.

**Stopping rule:** apply moves largest-first, `wc -m` after each. If the six-file total is still
≥ 150,000 after the last planned move, STOP and ask — the remaining candidates (`env -i make up`,
`drifted cwd`, `node nightly`, `git diff`) have no trigger file, and moving them is the always-loaded
trade the developer excluded. No improvised third tranche.

**Unverified:** whether rules load for files under the gitignored `docker/images/local.*/**` (the
`android.md` precedent was never probed). `env-files.md`'s real trigger is `.env*`, probed above.

**Removed as an exact repeat:** the Gotchas "Spawn reviewer subagents UNNAMED" bullet — every fact is
in § Certification "Spawn reviewers UNNAMED". Nothing else: the other repeats each carry a fragment of
their own (line 391 "none in the repo", line 54 "once per project", line 442 is a pointer on purpose).

**Listed exception to "verbatim":** the moved inventory line `.claude/hooks/ # PostToolUse + PreCompact
hook scripts` becomes `PostToolUse hook scripts` — `.claude/settings.json` registers only
`PostToolUse` [Verified: `jq '.hooks|keys'`].

**Kept in place (would break pointers):** the web-server token exception (6 citers), the port-var
CONSUMER gotcha (quoted by `subagent-brief.md:4`, `env-scan.md:339`), § Testing (running a suite
loads no rule), § Certification, every gate/destructive/git trap.

**Proof of "nothing lost"** — `var/claude/claude-md-size/claude-md-conservation.py` (gitignored;
`python3 -I` it), written FIRST:
1. every non-blank line of `HEAD:CLAUDE.md` is present (whitespace-normalised) in the new CLAUDE.md
   or a rules file; the listed exceptions are allowed only with their twin/replacement asserted present;
2. every new `paths:` glob matches at least one file on disk;
3. the six-file total is < 150,000 chars (RED at baseline);
4. sabotage, one per branch: delete one moved line from a rules copy → check 1 red naming that line;
   add a bogus glob → check 2 red naming it.

Rollback: `git checkout -- CLAUDE.md .claude/rules/` and `rm` the three new files — ONLY once HEAD
holds every other session's work (check `git status --porcelain -- CLAUDE.md .claude/rules/` is empty
before the moves start); a checkout over someone's uncommitted lines destroys them.

## Status
<!-- progress-block v1 -->
| # | Step | Size | State | Evidence | Files |
|---|------|------|-------|----------|-------|
| 1 | Conservation/glob/size check written, red on size only | S | done | - | |
| 2 | Moves largest-first into env-files, claude-config, shell-conventions, startup-tests, docker-images; one exact repeat removed | M | done | 6d78c5d | CLAUDE.md, .claude/rules/**, .claude/agents/completeness-reviewer.md |
| 3 | Check green + two sabotages red; total < 150,000 | S | done | - | |
<!-- /progress-block -->
### Blocked
- RESOLVED 2026-11-07 15:40 (that session committed `34a2001`; the moves landed in `6d78c5d`).
  Historical: step 2 waited for the local-registry-lifecycle session to COMMIT its uncommitted edits to `CLAUDE.md`
  and `.claude/rules/host-tooling.md` (seen 2026-11-07 15:08). Resume: re-run
  `python3 -I <scratchpad>/claude-md-conservation.py` against the new HEAD (expect red on size only),
  re-measure (baseline grew to 156,129 / CLAUDE.md 72,992 with their edits), then apply the moves.
  The check script lives in the session scratchpad; if it is gone, rebuild it from § Formal Plan "Proof".
### Needs input
### Needs research
### Fragile
### Known issues
- Result 2026-11-07 15:5x (applied by `var/claude/claude-md-size/apply.py` on HEAD `34a2001`): CLAUDE.md
  72,992 → 64,245 chars; six-file total 156,129 → **147,382** — headroom only **2,618**. New lessons must
  keep going to `.claude/rules/` (the § Gotchas intake rule) or the warning returns.
- [Unverified] whether Claude Code counts path-scoped rules toward the same 150k once they load
  mid-session; only the startup total was measured. The real check is a fresh interactive `/stack`
  session showing no size warning (never reproduce it with `claude -p` in `/stack`).
- [Unverified] whether rules load for files under the gitignored `docker/images/local.*/**` (a secondary
  trigger of `env-files.md`; its main trigger `.env*` was probed).
- PRE-EXISTING, out of scope: `.claude/agents/stack-infra-reviewer.md:99-110` describes a repo
  "never-fail PreCompact hook" (`set -uo pipefail`, unconditional `exit 0`) — `/stack` has none since the
  2026-08-18 global-is-reference ruling (`.claude/settings.json` registers only `PostToolUse`). Fixing it
  is an agent-def edit and needs the developer's authorization.
