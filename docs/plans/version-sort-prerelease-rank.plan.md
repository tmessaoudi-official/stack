# version-sort-prerelease-rank Plan

## Decisions Log
- [2026-09-14 16:49] AGREED: Pre-release markers rank in explicit ordered tiers (0 dev/snapshot/nightly/canary/edge/experimental/insiders/next < 1 alpha < 2 beta/preview/pre/ea < 3 milestone < 4 rc/cr < stable), never by alphabet.
- [2026-09-14 16:49] AGREED: An unknown suffix is ranked by the known marker found inside it (13.0.1-resolute-rc → rc tier); a suffix with no marker is a variant and keeps today's sort order.
- [2026-09-14 16:49] AGREED: Every raw `sort -V` decision site in env-update moves to one shared ranked comparator, not only the three gates groovy hits.
- [2026-09-14 16:49] AGREED: The use-sha SHA misclassification (hex matching `[0-9]a[0-9]`/`[0-9]b[0-9]`) is fixed in this same plan.
- [2026-09-14 16:49] AGREED: Task sized Large; Phase 3C certified by advisor() only.

## Formal Plan

**Problem.** `GLOBAL_STACK_JAVA_DEFAULT_GROOVY_VX1_VERSION=6.0.0-beta-3` never proposes `6.0.0-RC-2`:
`sort -V` compares raw bytes, `R` (0x52) < `b` (0x62). Reproduced on `/bin/sort` (uutils 0.8.0) and
`gnusort` (GNU 9.7). Lowercasing alone ranks `snapshot` > `rc`, so it is not a fix.

**Mechanism.** Keep `sort -V`, rewrite the KEY. `sort -V` orders `~` before end-of-string, so a
pre-release gets key `base~<tier><lowercased suffix>` (measured on both binaries:
`6.0.0~2beta-3 < 6.0.0~4rc-2 < 6.0.0~4rc-10 < 6.0.0`). A string the prerelease classifier does not
flag keeps key == input, so its order is exactly today's. One awk pass, config via ENVIRON.

**Classifier.** `_gs_eu2_is_prerelease` returns 1 for `(^|@)[0-9a-f]{7,40}$` (5 of 6 use-sha pins
misclassified today; predicted no decision delta — the decision path compares versions, not SHAs).

**Regression evidence.** Full-`.env` `--check --dry-run --no-cache --format=json` before and after,
diffed per record; identity tests on a non-prerelease corpus; GNU `sort` certification of the keys;
red-first tests; five sabotages restored byte-identically.

## Status
<!-- progress-block v1 -->
| # | Step | Size | State | Evidence | Files |
|---|------|------|-------|----------|-------|
| 1 | Baseline full-.env run captured | S | done | f20cdfe | var/claude/version-sort/** |
| 2 | Red-first tests (tiers, identity, GNU keys, groovy, SHA, t12d) | M | done | f20cdfe | bin/tests/env-update.test.sh |
| 3 | Shared key helpers + classifier guard | M | done | f20cdfe | bin/lib/env-update/core/semver.sh bin/lib/env-update/config/prerelease_markers.sh |
| 4 | Convert sort -V sites | M | done | f20cdfe | bin/lib/env-update/** |
| 5 | Green suite + sabotage | S | done | 50e264a | bin/tests/env-update.test.sh |
| 6 | After run + diff | S | done | f20cdfe | var/claude/version-sort/** |
| 7 | Docs + memory | S | done | f20cdfe | templates/tips/env-update.md templates/tips/env-laws.md bin/lib/env-update/reporting/reference.sh CLAUDE.md |
<!-- /progress-block -->
### Blocked
### Needs input
### Needs research
### Fragile
- `/bin/sort` is uutils here; key design must also hold on GNU `sort` (clean Ubuntu clone).
### Known issues
- Before/after full-`.env` diff (2026-09-14): exactly two record deltas. `GROOVY_VX1` SKIP → AUTO
  `6.0.0-beta-3 → 6.0.0-RC-2` (the fix). `IMAGE_KEYCLOAK_KEYCLOAK` AUTO → ERROR `fetch failed for
  quay:keycloak/keycloak` — NOT caused by this change: HEAD's code (extracted via `git archive`)
  returns the same ERROR at the same moment, and quay.io's tag and repository endpoints all
  answered HTTP 504. The five `(use-sha)` records are unchanged, as predicted.
