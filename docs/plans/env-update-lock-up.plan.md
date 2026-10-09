# env-update-lock-up Plan

## Decisions Log
- [2026-10-09 14:51] AGREED: Lock with a newer upstream version shows the 9-char tag [LOCK+UP] (developer choice).
- [2026-10-09 14:51] AGREED: [LOCK+UP] fires only before --apply; after apply the plain [LOCK] behaviour is unchanged (developer choice).
- [2026-10-09 14:51] AGREED: Fix only the summary breakdown (N LOCK (M with update)); DRIFT advice, dead-lock DRIFT counting, apply line and tips 8-char paragraph stay as they are (developer choice).
- [2026-10-09 14:51] ASSUMED (review): A LOCK with a non-newer proposed (downgrade/prerelease) keeps its existing arrow line byte-identical — scoped out by the developer; pinned by a test. Alternatives: swap to the (reason) form.
- [2026-10-09 14:51] ASSUMED (review): [LOCK+UP] keeps LOCK's cyan colour. Alternatives: yellow like HOLD/MANUAL.
- [2026-10-09 14:51] ASSUMED (review): Live tally keeps the plain LOCK total; only the final summary gets the breakdown. Alternatives: mirror it in tally.sh.

## Formal Plan

1. `(lock:)` record whose pre-lock classifier verdict was AUTO/HOLD/MANUAL (a real newer upstream, not a downgrade/prerelease/float) displays `[LOCK+UP]` (9 chars, cyan) with `← locked, update VAR= by hand: <reason>`. Decision stays `LOCK`; apply path untouched.
2. Fires only BEFORE `--apply` (annotation version != upstream). After apply the record shows plain `[LOCK   ]` as today.
3. Summary: `N LOCK (M with update)` only when M > 0 — zero-case byte-identical.
4. Tests: env-update.test.sh section 128 (red first) + refit t63b1/t63c3/t63d1; tips doc rows.

## Status
<!-- progress-block v1 -->
| # | Step | Size | State | Evidence | Files |
|---|------|------|-------|----------|-------|
| 1 | [LOCK+UP] tag + summary breakdown + tests + docs | M | done | 797ef5b | bin/lib/env-update/**, bin/tests/env-update.test.sh, templates/tips/env-update.md |
<!-- /progress-block -->
### Blocked
### Needs input
### Needs research
### Fragile
### Known issues
