# Audit Report — `bin/env-update.sh` + `bin/env-scan.sh`

## Metadata

| Field | Value |
|---|---|
| Date | 2026-05-25 |
| Auditor | global-stack-lead-dev |
| env-update version | 2.0.0 |
| env-scan version | 1.0.0 |
| Audit rounds | 4 + session bugs |
| Total findings | **37** (P0: 6 · P1: 9 · P2: 14 · P3: 8) |

## Overall scores (1-10)

| Dimension | env-update | env-scan | Aggregate |
|---|---|---|---|
| Code structure | 8 | 6 | 7 |
| Error handling | 8 | 8 | 8 |
| Security | 8 | 8 | 8 |
| Performance | 7 | 7 | 7 |
| Naming conventions | 9 | 7 | 8 |
| Test coverage (counts) | 9 | 8 | 8.5 |
| Test quality (depth) | 7 | 7 | 7 |
| Documentation accuracy | 5 | 6 | 5.5 |
| Bash best practices | 9 | 8 | 8.5 |
| Observability | 8 | 7 | 7.5 |
| Maintainability | 7 | 7 | 7 |

## Maturity declaration

**Not 100% mature.** P0 blockers documented below. User decision required for each.

| Blocker | ID | Status |
|---|---|---|
| `--apply --dry-run` advertised by docs, rejected by code | R1-P0-1 | Open |
| `--filter` documented case-insensitive, code is case-sensitive | R1-P0-2 | Open |
| env-scan pipeline has 3 disagreeing phase-numbering schemes | R1-P0-3 | Open |
| `--reference=<invalid>` exits 0 with no output | R1-P0-4 | Open |
| decide.sh sort-V false downgrade on nightly SHA versions | BUG-A | **Fixed** |
| apply.sh LOCK path rewrites annotation for floating current | BUG-B | **Fixed** |

---

## Findings — Severity-ranked

### [BUG-A] decide.sh sort-V false downgrade on nightly SHA versions

- **Severity**: P0 · **Confidence**: 100% · **Status**: Fixed (2026-05-25)
- **Component**: `bin/lib/env-update/core/decide.sh:99-105`, `bin/lib/env-update/main.sh:611-614`
- **Root cause**: GNU `sort -V` splits on digit/non-digit transitions. A nightly version string like `v27.0.0-nightly20260524837910d298` produces sort key `20260524837910` (14 digits — date + leading hex digits). A newer build `v27.0.0-nightly202605252e3daf6e4d` produces key `202605252` (9 digits — date only, stops at `2e`). May-24 key `20260524…` > May-25 key `202605252` → sort says May-24 is newer → real upgrade to May-25 is classified SKIP (false downgrade).
- **Fix**: Inline perl normalization `s/(\d{8})[0-9a-fA-F]+$/$1/` before sort-V in both decide.sh and main.sh. Added `_oldest != _cv_norm` guard so same-date different-SHA builds do not false-positive. Hardcoded `stable` channel in the downgrade message replaced with actual channel from record.
- **Tests**: section 101 (4 tests — t101a through t101d)

### [BUG-B] apply.sh LOCK path rewrites annotation for floating current version

- **Severity**: P0 · **Confidence**: 100% · **Status**: Fixed (2026-05-25)
- **Component**: `bin/lib/env-update/core/apply.sh:231-250`
- **Root cause**: The LOCK path in `_gs_eu2_apply_updates` guards with `[[ -z "${_prop}" || "${_prop}" == "${_cur}" ]] && continue` (idempotency). But when `_cur` is a floating alias (`next`, `edge`, `latest`, …) and `_prop` is a concrete version (e.g., `php-8.5.6`), neither condition fires — the annotation's current_version token is rewritten from `next` to `php-8.5.6`. The `VAR=` line is correctly untouched (annotation_only="true"), but the annotation itself is corrupted. The PHPEDGE annotation explicitly documents this case via its `(lock:)` reason.
- **Fix**: Added `_gs_eu2_is_unversioned "${_cur}" && continue` guard BEFORE the existing idempotency guard. Sourced `semver.sh` from `apply.sh` (was missing — `_gs_eu2_is_unversioned` lives there).
- **Tests**: section 102 (4 tests — t102a through t102d)

### [R1-P0-1] `--apply --dry-run` is a dead code path advertised by docs

- **Severity**: P0 · **Confidence**: 100% · **Status**: Open — awaiting Q1 owner answer
- **Component**: `bin/lib/env-update/core/args.sh:184-187` (rejection) vs `bin/lib/env-update/main.sh:1370-1374` (dead branch) vs `bin/lib/env-update/reporting/help.sh:43,158` and `reference.sh` §flags
- **Evidence**: `args.sh:184-187` rejects `--apply --dry-run` as mutually exclusive; `main.sh:1370-1374` contains the dry-run apply branch that is unreachable from CLI; help and reference both advertise `--dry-run --apply` as the preview path; test 5740 passes vacuously (args.sh rejects before any I/O, assertion that file is unchanged is trivially true)
- **Recommended fix**: see Q1 in the Design Decisions section

### [R1-P0-2] `--filter` documented case-insensitive, implemented case-sensitive

- **Severity**: P0 · **Confidence**: 100% · **Status**: Open — awaiting Q2 owner answer
- **Component**: `bin/lib/env-update/reporting/reference.sh` vs `bin/lib/env-update/core/parse.sh:506`
- **Evidence**: reference says "case-insensitive"; `--filter=postgres` returns 0 records; `--filter=POSTGRES` returns the full record. Bash `[[ var =~ regex ]]` is case-sensitive and `nocasematch` is not set anywhere.
- **Recommended fix**: see Q2

### [R1-P0-3] env-scan pipeline has three disagreeing phase-numbering schemes

- **Severity**: P0 · **Confidence**: 100% · **Status**: Open — awaiting Q3 owner answer
- **Component**: `bin/lib/env-scan/main.sh:12-20`, `bin/lib/env-scan/reporting/reference.sh`, `bin/lib/env-scan/reporting/help.sh`, `bin/lib/env-update/reporting/reference.sh` §env-scan
- **Evidence**: main.sh uses fractional phases (4.5, 6.5); reference uses 8-phase integer; help mixes both; env-update's view uses the integer scheme
- **Recommended fix**: see Q3

### [R1-P0-4] `--reference=<invalid>` silently exits 0 with no output

- **Severity**: P0 · **Confidence**: 100% · **Status**: Open — awaiting Q4 owner answer
- **Component**: `bin/lib/env-update/reporting/reference.sh:34`, `bin/lib/env-scan/reporting/reference.sh`
- **Evidence**: `--reference=blahblah` → 0 lines of output, exit 0 on both tools
- **Recommended fix**: see Q4

### [R1-P1-1] env-scan `--help` is missing `--version` and `--reference`

- **Severity**: P1 · **Confidence**: 100% · **Status**: Open
- **Component**: `bin/lib/env-scan/reporting/help.sh`
- **Evidence**: both flags accepted by args.sh but not listed in help output
- **Recommended fix**: add one-line entries to help output (see Q5)

### [R1-P1-2] env-update `--reference` §flags: `--format` described as "Output format" instead of "Dump format"

- **Severity**: P1 · **Confidence**: 100% · **Status**: Open
- **Component**: `bin/lib/env-update/reporting/reference.sh`
- **Evidence**: `--format=text|json` only affects `--dump`; reference implies it applies to all output
- **Recommended fix**: change "Output format" to "Dump format" in reference §flags (see Q9)

### [R1-P1-3] `--cache-ttl=0` semantics are undocumented and effectively a 0-second TTL, not "no cache"

- **Severity**: P1 · **Confidence**: 100% · **Status**: Open
- **Component**: `bin/lib/env-update/core/cache.sh:53`
- **Evidence**: `(( _age <= _GS_EU2_CACHE_TTL ))` with TTL=0 only accepts files created in this exact second
- **Recommended fix**: see Q6

### [R1-P1-4] `--force-auto --apply --confirm` still requires the 30-min dry-run gate

- **Severity**: P1 · **Confidence**: 100% · **Status**: Open
- **Component**: `bin/lib/env-update/main.sh:1228-1244`
- **Evidence**: dry-run gate fires on any `--apply` without marker; `--confirm` is not treated as an alternative gate
- **Recommended fix**: see Q7

### [R1-P1-5] `--force-auto` alone exits 0 with advisory (not an error)

- **Severity**: P1 · **Confidence**: 100% · **Status**: Open
- **Component**: `bin/lib/env-update/core/args.sh:204-206`
- **Evidence**: `--force-auto` without `--check` or `--apply` → exit 0, advisory to stderr, no output
- **Recommended fix**: see Q8

### [R1-P1-6] Recent 3-bug fix (RELOAD_RBENV rename, RELOAD anchor, Forward Check 2) absent from docs

- **Severity**: P1 · **Confidence**: 100% · **Status**: Open
- **Component**: `templates/tips/env-scan.md`, `bin/lib/env-scan/reporting/reference.sh`
- **Evidence**: `grep RELOAD_RBENV templates/tips/*.md` → 0 matches; code has it at `defaults.sh:74,188`
- **Recommended fix**: add RELOAD_RBENV, RELOAD anchor pattern, Forward Check 2 to tips and reference

### [R2-P1-1] `--destination-file-merged-suffix` has zero test coverage

- **Severity**: P1 · **Confidence**: 100% · **Status**: Open
- **Component**: `bin/lib/env-scan/core/args.sh:85`, `bin/lib/env-scan/core/merge.sh:58`
- **Recommended fix**: add smoke tests for suffix override in env-scan.test.sh

### [R2-P1-2] `--exclude-local-pattern` has zero test coverage

- **Severity**: P1 · **Confidence**: 100% · **Status**: Open
- **Component**: `bin/lib/env-scan/core/args.sh:100`, `bin/lib/env-scan/core/merge.sh:182`
- **Recommended fix**: add smoke tests covering the canonical use case (protecting GLOBAL_STACK_LOCAL_* vars)

### [R2-P1-3] Fetcher error paths (HTTP 4xx, timeout, malformed JSON) are largely untested

- **Severity**: P1 · **Confidence**: 90% · **Status**: Open
- **Component**: `bin/lib/env-update/fetchers/*.sh`, `bin/lib/env-update/http/curl.sh`
- **Evidence**: `_GS_EU2_HTTP_FIXTURE_DIR` seam only returns success or absent-file errors; no way to inject 429/503/malformed JSON without extending the harness
- **Recommended fix**: add `_GS_EU2_HTTP_INJECT_STATUS=429` env var to curl.sh for error injection

### [R2-P1-4] The `--apply --dry-run` test (test 5740) passes vacuously

- **Severity**: P1 · **Confidence**: 100% · **Status**: Open (tied to R1-P0-1)
- **Component**: `bin/tests/env-update.test.sh:5739-5742`
- **Evidence**: `|| true` swallows the args.sh rejection; assertion that file was unchanged passes because no I/O occurred
- **Recommended fix**: remove or rewrite to test actual behavior (rejection or dry-run semantics per Q1)

### [R1-P2-1] `--scan` does not forward `--filter` to env-scan (documented gap)

- **Severity**: P2 · **Confidence**: 100% · **Status**: Open — see Q10
- **Component**: `bin/lib/env-update/main.sh:1430-1438`

### [R1-P2-2] `--quiet` not forwarded from env-update `--scan` to env-scan

- **Severity**: P2 · **Confidence**: 100% · **Status**: Open — see Q10

### [R1-P2-3] `_GS_EU2_TALLY_FORCE` documented in reference but not in `--help`

- **Severity**: P2 · **Confidence**: 100% · **Status**: Open
- **Component**: `bin/lib/env-update/reporting/help.sh:61-65`

### [R3-P2-1 through R3-P2-11] 11 undocumented annotation × decision × CLI flag intersections

- **Severity**: P2 · **Confidence**: 85-95% · **Status**: Open — see Q11
- Includes: `(skip:R)` + use-sha; `(lock:R)` + SHA classifier ordering; float current + `(watch-major)`; `(replace:)` + RESOLVED; `--dump --dry-run` silent ignore; `--force-auto` × RESOLVED; `(hold)` anti-pattern detection

### [R4-P2-1] `_gs_eu2_run_check` is ~900 lines of nested logic

- **Severity**: P2 · **Confidence**: 100% · **Status**: Open
- **Component**: `bin/lib/env-update/main.sh` — `_gs_eu2_run_check` function
- **Recommended fix**: split per-signal sub-line handlers into `_gs_eu2_signal_<name>` family

### [R4-P2-2] env-scan `args.sh:33-167` is 130+ lines of boilerplate

- **Severity**: P2 · **Confidence**: 100% · **Status**: Open — see Q17
- **Recommended fix**: table-driven dispatcher; see Q17

### [R4-P2-3] `dump.sh` calls `jq -Rs '.'` ~14,000 times for a full .env

- **Severity**: P2 · **Confidence**: 100% · **Status**: Open — see Q18
- **Component**: `bin/lib/env-update/reporting/dump.sh:52-53`
- **Recommended fix**: single jq invocation; see Q18

### [R4-P2-4] 41-file env-update library has no top-level architecture diagram

- **Severity**: P2 · **Confidence**: 100% · **Status**: Open
- **Recommended fix**: add a `# Architecture` block in `bin/env-update.sh` or `bin/lib/env-update/README.md`

### [R2-P2-1 through R2-P2-5] Low-coverage env-scan flags (1 test ref each)

- **Severity**: P2 · **Confidence**: 100% · **Status**: Open
- Flags: `--remove-trailing-spaces`, `--include-docker-args`, `--scan-var-prefix`, `--scan-ignore-pattern`, `--source-merged-file`

### [R4-P3-1] `github.sh:86-93` — chmod after write (defensive order wrong)

- **Severity**: P3 · **Confidence**: 100% · **Status**: Open
- **Component**: `bin/lib/env-update/fetchers/github.sh:86-93`
- **Evidence**: mktemp (0600 by default) → write token → chmod 700. chmod after write is ordering-wrong for defense-in-depth; mktemp default 0600 makes this a non-issue in practice
- **Recommended fix**: move chmod to immediately after mktemp, before any write

### [R4-P3-2] `apply.sh:178` — mktemp without `umask 0077`

- **Severity**: P3 · **Confidence**: 100% · **Status**: Open
- **Recommended fix**: wrap `mktemp` with `umask 0077` ... `umask <restore>` for defense-in-depth

### [R4-P3-3] env-scan public/private function naming inconsistency

- **Severity**: P3 · **Confidence**: 100% · **Status**: Open — see Q15
- **Component**: `bin/lib/env-scan/*.sh`

### [R4-P3-4] `_p` temp variable in env-scan `defaults.sh:39,64`

- **Severity**: P3 · **Confidence**: 100% · **Status**: Open
- **Recommended fix**: rename to `_gs_es_pattern_buf`

### [R2-P3-1 through R2-P3-7] Low-coverage env-scan flags (2 test refs each)

- **Severity**: P3 · **Confidence**: 100% · **Status**: Open
- Flags: `--diff-ignore-pattern`, `--scan-var-ignore-pattern`, `--reverse-check-ignore-pattern`, `--forward-check-ignore-pattern`, `--exclude-explicit-empty`, `--conflict-ignore-pattern`, `--backup-suffix`

---

## Decision Matrix (Round 3 excerpt)

### Decision × CLI flag matrix

See the full 10×13 matrix in the original audit work. Key undocumented cells:

| Column | Issue |
|---|---|
| `--dry-run --apply` | **Rejected** — but docs claim this works (R1-P0-1) |
| `--force-auto` × RESOLVED | No PINNED upgrade; only `--apply-resolve` promotes |
| `--dry-run --dump` | dry-run silently ignored (no writes in dump anyway) |
| `(lock:R)` × SHA classifier | SHA classifier runs unconditionally AFTER lock gate — possible LOCK→SHA edge not documented |
| float + `(watch-major)` | Calls `_gs_eu2_version_prefix "latest" "1"` — undefined behavior |
| `(replace:)` + RESOLVED | Replace cascade does NOT fire for RESOLVED records |

---

## Open Questions / Design Decisions (Q1–Q25)

These questions are for the owner. No answers assumed. The owner fills in responses; questions are then refined into sprint tasks.

### P0 questions — block 100% maturity until answered

**Q1. `--apply --dry-run` reconciliation [R1-P0-1]**

Three sources of truth in conflict: `args.sh:184-187` rejects it; `main.sh:1370-1374` has a dead branch for it; help/reference advertise it; test 5740 passes vacuously.

> (a) Re-enable `--apply --dry-run`: remove the args.sh rejection; the existing main.sh branch runs. The 30-min gate becomes unnecessary. Test 5740 becomes meaningful.
> (b) Keep the rejection: remove all references from help/reference/examples; delete the dead main.sh branch; rewrite test 5740 to assert the rejection itself.
> (c) Something else.
>
> Owner answer: ___

**Q2. `--filter` case sensitivity [R1-P0-2]**

Reference says case-insensitive; code is case-sensitive.

> (a) Fix code: enable `shopt -s nocasematch` inside the match block.
> (b) Fix docs: remove "case-insensitive" claim; add note to use UPPER-CASE for GLOBAL_STACK_* convention.
> (c) Add per-call opt-in (e.g., `--filter-case=insensitive`).
>
> Owner answer: ___

**Q3. env-scan pipeline phase numbering [R1-P0-3]**

Three schemes co-exist: fractional (main.sh), 8-integer (reference), mixed (help).

> (a) Standardize on 8-phase integer — renumber main.sh comments and help.
> (b) Standardize on fractional — renumber reference and env-update's view.
> (c) 9-phase integer (treat 4.5 and 6.5 as distinct phases).
>
> Owner answer: ___

**Q4. `--reference=<invalid-section>` behavior [R1-P0-4]**

Currently exits 0 with zero output.

> (a) Error: print `unknown reference section: <name> (valid: all, syntax, flags, ...)` to stderr and exit 1.
> (b) Fall through to `=all`.
> (c) Print closest-match suggestion.
> (d) Silent no-op (keep current behavior, document it).
>
> Owner answer: ___

### P1 questions — shape next sprint

**Q5. env-scan `--help` missing `--version` and `--reference` [R1-P1-1]**

> (a) No, oversight — add to help with one-line descriptions.
> (b) Yes, intentionally hidden — leave.
> (c) Add `--help-all` flag that includes them.
>
> Owner answer: ___

**Q6. `--cache-ttl=0` semantics [R1-P1-3]**

`(( _age <= 0 ))` is not "no cache" — it is a 0-second TTL.

> (a) Alias for `--no-cache` (bypass entirely).
> (b) Strict write-through (no reads, cache still written).
> (c) Keep current behavior; document explicitly.
> (d) Reject `0`; require `--no-cache` instead.
>
> Owner answer: ___

**Q7. `--force-auto --apply --confirm` and the 30-min dry-run gate [R1-P1-4]**

Should explicit `--confirm` be an alternative to the marker?

> (a) Yes — `--confirm` is already an explicit gate; skip the marker requirement when present.
> (b) No — keep both gates; force-auto bypasses many guards, extra safety is warranted.
> (c) Add `--no-dry-run-gate` for opt-out.
>
> Owner answer: ___

**Q8. `--force-auto` alone (no `--check` or `--apply`) [R1-P1-5]**

Currently exits 0 with an advisory — no output generated.

> (a) Exit 1 with usage error.
> (b) Keep advisory.
> (c) Promote to ERROR when stdout is not a TTY.
>
> Owner answer: ___

**Q9. Reference `--format` description [R1-P1-2]**

`--format` is dump-only; reference says "Output format."

> (a) Change to "Dump format."
> (b) Extend `--format` to cover `--check` output (JSON streaming).
>
> Owner answer: ___

### P2 questions — design ambiguities

**Q10. `--quiet` forwarding from `--scan` [R1-P2-2]**

> (a) Add `--quiet` to env-update and forward to env-scan.
> (b) No — env-update is intentionally chatty.
> (c) Add `--quiet-scan` that only affects the forwarded call.
>
> Owner answer: ___

**Q11. Section C cross-product in `--reference=matrix` [R3-P2-1..11]**

11 undocumented intersection cells (decision × annotation × CLI flag).

> (a) Add Section C with all 11 cells.
> (b) Add Section C only for the 11 specific flagged cells.
> (c) No — trust users to infer from Sections A and B.
>
> Owner answer: ___

**Q12. Float current + `(watch-major)` undefined behavior [R3-P2-6]**

`_gs_eu2_version_prefix "latest" "1"` is called — undefined behavior.

> (a) Suppress WATCH for floating-ref records.
> (b) Resolve the float first, then apply WATCH.
> (c) Document as undefined; users should not combine them.
>
> Owner answer: ___

**Q13. `(replace:T=tmpl)` + RESOLVED — replace cascade does not fire [R3-P2-7]**

`--apply --apply-resolve` writes primary VAR= but not the replace target.

> (a) Fire replace cascade for RESOLVED when `--apply-resolve` is used.
> (b) Current behavior is correct — RESOLVED and replace are separate concerns.
> (c) Reject RESOLVED + (replace:) at parse time.
>
> Owner answer: ___

**Q14. `(hold)` anti-pattern error message [R3-P2-8]**

`(hold)` is rejected as "unknown flag" — no special pointer to replacement.

> (a) Add special-case error with hint: "use (manual) or (override) instead."
> (b) Generic error + reference docs are sufficient.
>
> Owner answer: ___

**Q15. env-scan public/private naming convention [R4-P3-3]**

Mixed `gs_es_*` (public) and `_gs_es_*` (private) across the codebase.

> (a) All functions private (`_gs_es_*`); main.sh is the only public entry point.
> (b) Functions called from main.sh stay public; helpers private.
> (c) Top-level functions in each module public; everything else private.
>
> Owner answer: ___

**Q16. Roadmap for `(depends-on)` and `(propagate)` [R4 Maintainability]**

Both parsed but not enforced.

> (a) Implement `(depends-on)` enforcement now (topological sort before apply).
> (b) `(depends-on)` deferred indefinitely; warning sub-line is the contract.
> (c) Add a no-`--scan` propagation path for `(propagate)` inside env-update.
> (d) Status quo — both remain documented partial implementations.
>
> Owner answer: ___

**Q17. env-scan `args.sh` DRY refactor [R4-P2-2]**

130+ lines of near-identical flag-parse boilerplate.

> (a) Table-driven dispatcher — do it now.
> (b) Defer — correct and stable; refactor risk > gain.
> (c) Add `_gs_es_set_bool` / `_gs_es_set_string` helpers but keep case branches.
>
> Owner answer: ___

**Q18. Dump JSON single-jq optimization [R4-P2-3]**

~14,000 `jq` subprocess calls for 241 records × 30 fields.

> (a) Rewrite to single jq invocation.
> (b) Defer — JSON dump rarely used in tight loops.
> (c) Benchmark first; decide based on numbers.
>
> Owner answer: ___

**Q19. Global bandaid audit on `|| true` and `2>/dev/null` [R4 Error handling]**

Locations: `dockerhub.sh:149,191,201`, `github.sh:95,98`, `apply.sh:364,373`.

> (a) Require inline `# Anti-bandaid: <evidence>` on each; remove without evidence.
> (b) Audit only the suspicious ones during code review.
> (c) Defer.
>
> Owner answer: ___

**Q20. `templates/tips/*.md` synchronization with `--reference` [R4 Maintainability]**

No automated check that tips files stay in sync with `--reference` output.

> (a) Add CI/test check that diffs `--reference` against tips files; fail on mismatch.
> (b) Replace tips with a thin wrapper script that runs `--reference`.
> (c) Status quo — manual sync.
>
> Owner answer: ___

### Genuine ambiguities (no specific round finding)

**Q21. `--scan` when `--apply` fails partway**

Under `set -e`, if apply rolls back (missing replace target), `--scan` is never reached. With `--no-fail`, env-scan runs on a rolled-back (unchanged) file.

> (a) Current behavior is correct.
> (b) With `--no-fail`, skip env-scan if apply rolled back.
> (c) Add `[APPLY-ROLLED-BACK]` banner so the user knows env-scan ran on a no-change file.
> (d) Print explicit rollback message from apply summary regardless of `--no-fail`.
>
> Owner answer: ___

**Q22. env-scan multi-source-file precedence (first-wins vs last-wins)**

> (a) Keep first-wins.
> (b) Switch to last-wins.
> (c) Error when both files define the same key with different values.
> (d) Document more explicitly with a worked example.
>
> Owner answer: ___

**Q23. `--prune-removed=true` + `--orphan-ignore-pattern` interaction**

`--orphan-ignore-pattern` only suppresses warnings, not the prune decision.

> (a) Current: orphan-ignore for warnings only; prune removes everything.
> (b) Orphan-ignore should also exempt vars from pruning.
> (c) Add separate `--prune-ignore-pattern`.
>
> Owner answer: ___

**Q24. env-scan reference back-link to env-update**

env-scan's `--reference` does not describe how it is called from env-update `--scan`.

> (a) Add `--reference=env-update` section to env-scan.
> (b) No — env-scan is independent.
> (c) Cross-link via a NOTE in each reference's front matter.
>
> Owner answer: ___

**Q25. Backup retention scope for `--apply --scan` cascade**

Both env-update and env-scan create and prune backups independently when `--apply --scan` runs. `--backup-keep=N` applies separately to each tool.

> (a) Keep independent scope.
> (b) env-update should manage unified namespace; pass `--backup-keep=0` to env-scan.
> (c) Add `--backup-scope=tool|run|session` flag.
>
> Owner answer: ___

---

## Appendix — Live commands run during audit

```bash
# Baseline
bin/env-update.sh --help                                      # 180 lines, exit 0
bin/env-update.sh --reference                                 # 726 lines, exit 0
bin/env-scan.sh --help                                        # 77 lines, exit 0
bin/env-scan.sh --reference                                   # 224 lines, exit 0

# Verified P0 bugs
bin/env-update.sh --check --apply --dry-run                   # exit 1 (mutually exclusive)
bin/env-update.sh --filter=postgres --dump 2>&1 | wc -l      # 1 (only banner — case-sensitive)
bin/env-update.sh --reference=blahblah                        # exit 0, 0 lines
bin/env-scan.sh --reference=blahblah                          # exit 0, 0 lines

# Session diagnostics
bin/env-update.sh --filter=PHPEDGE_VERSION --check --dry-run  # [LOCK] next → php-8.5.6
bin/env-update.sh --filter=NODEEDGE_VERSION --check --dry-run # verified SKIP on fresh run

# Tests (post-fix)
bash bin/tests/env-update.test.sh --section=101               # ALL PASSED ✓ 4/4
bash bin/tests/env-update.test.sh --section=102               # ALL PASSED ✓ 4/4
bash bin/tests/env-update.test.sh                             # ALL PASSED ✓ (full suite)
```
