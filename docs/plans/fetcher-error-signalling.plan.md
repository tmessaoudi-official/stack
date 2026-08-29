# Fetcher error-signalling Plan (hunt F1)

`url:`, `sdkman:` and `sdkmanager:` never set `decision "ERROR"`. A hard transport failure
therefore reads as `SKIP` with exit 0, so `bin/env-update.sh --check` — and `/check-versions` in
cron or CI — is **structurally incapable of failing** on those records, whatever happens upstream.

Reproduced on `8cbcb5f`:

```
[SKIP ]  GLOBAL_STACK_T_VERSION  (url: fetch-json jq path 'max_by(.date).version' returned empty …)
  Summary: … 1 SKIP, 0 ERROR  (1 checked)      exit=0
```
versus the `dockerhub:` control under the identical injection:
```
[ERROR]  GLOBAL_STACK_D          (fetch failed for library/postgres (HTTP 503))     exit=1
```

The message is not merely under-classified, it **misdirects**: an HTTP 503 is reported as a jq-path
problem, sending the reader to edit an expression that was never wrong.

## Decisions Log

- [2026-08-29 03:10] AGREED: blast radius is **33 live records, not 28**. The hunt report named
  `url:` (7) and `sdkman:` (21) but omitted `sdkmanager:` (5), even though its own per-fetcher
  table recorded `sdkmanager 0`. Found by stating both inventories independently before comparing.
- [2026-08-29 03:10] AGREED: escalate **transport failures only**. "Matched nothing on a 200",
  "not installed" and filter-mismatch stay `SKIP` — they are not upstream outages, and escalating
  them would fail CI on any machine that simply lacks a local toolchain.
- [2026-08-29 03:10] AGREED: **url tier 3 gets no ERROR of its own.** It is a fallback chain — it
  loops over `urls:` entries and deliberately falls through to tier 4 ("try next urls: entry"), so
  a record whose first URL is dead and whose second is good must still succeed. The terminal
  failure in that chain is tier 4's, which is covered.
- [2026-08-29 03:10] AGREED: **url tier 5 (`url-probe`) stays SKIP.** A probe walks candidate
  paths expecting most to 404; without per-candidate status plumbing it cannot distinguish "all
  absent" from "network down". A deliberate scope cut, recorded rather than silently skipped.
- [2026-08-29 03:10] AGREED: F2 (cache key omits the 7 tag flags) ships as a **separate commit** —
  a different defect on a different surface.

### The ERROR / SKIP boundary

| Site | New | Why |
|---|---|---|
| url tier 1 — `fetch-extract`, HTTP failed | **ERROR** | already distinguished via `_fetch_ok`, just never escalated |
| url tier 2 — `fetch-json`, HTTP failed | **ERROR** | today reports the jq path as the culprit; needs the split *and* a corrected message |
| url tier 4a — `channel:nightly`, HTTP failed | **ERROR** | terminal for the nightly path |
| url tier 4b — directory listing, HTTP failed | **ERROR** | terminal for the svn.apache.org / GNU scrapes |
| sdkman — "API fetch failed for candidate" | **ERROR** | the file already discriminates this from "not installed" |
| sdkmanager — "`--list` returned no output" | **ERROR** | the binary is present (the not-found branch precedes it) and produced nothing |
| url tier 1/2 — pattern or jq empty on a **200** | SKIP | upstream reachable, shape changed; `(stale-after:Nd)` is the guard for that |
| url tier 3 | SKIP | fallback chain, see above |
| url tier 5 — `url-probe` | SKIP | cannot distinguish absent from unreachable |
| url — "no extraction strategy matched" | SKIP | annotation config gap, not an outage |
| sdkman/sdkmanager — "not installed" / "not found" | SKIP | environment, must never fail CI |
| sdkman — fixture-dir set but fixture missing | SKIP | test-seam condition |
| both — "no versions matched filters" | SKIP | filters are the user's own constraint |

### Residual gaps, accepted and recorded

- On a machine with **no sdkman installed**, a dead broker still reads as SKIP — the
  "not installed" branch is evaluated before the "API fetch failed" branch, and the two are
  indistinguishable without a live install. Not fixed here.
- url tier 3's transport failures remain invisible when no tier 4 applies; the record then falls
  to "no extraction strategy matched" (SKIP).

## Formal Plan

1. Tests first, in `bin/tests/env-update.test.sh`. New section covering all three fetchers under
   `_GS_EU2_HTTP_INJECT_STATUS`, asserting the **`[ERROR]` token and exit 1** — not a loose
   `grep -qE 'ERROR|error|injected'`, which the existing section 107 uses and which the inject
   seam's own stderr line satisfies on its own.
2. `fetchers/url.sh` — thread a transport-failure flag through tiers 2, 4a, 4b (tier 1 has one
   already); set `decision "ERROR"` with an accurate message on each.
3. `fetchers/sdkman.sh` — set `decision "ERROR"` on the API-fetch-failed branch only.
4. `fetchers/sdkmanager.sh` — set `decision "ERROR"` on the empty-`--list` branch only.
5. `templates/tips/env-update.md` — correct any claim that these types SKIP on failure.

### Acceptance criteria

1. Each of the three types emits `[ERROR]` and exit 1 under an injected 503.
2. `sdkmanager not found` and `sdkman not installed` still emit `SKIP` and exit 0.
3. A jq path that legitimately matches nothing on a 200 still emits `SKIP`.
4. Every assertion fails first for its own reason; reverting any one `decision "ERROR"` line
   turns the suite red; restores are `cmp`-identical.

### Behaviour change to announce

After this, a cron `/check-versions` **fails on a dead upstream by design**. `--no-fail` is the
documented escape hatch for callers that want the old exit-0 behaviour.

### Rollback

Self-contained commit on `master`; `git revert <sha>`. No `.env`, compose or image change.
