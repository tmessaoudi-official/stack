# verify-asset on the fetch-extract tier — Plan

## Status

- Size: Medium
- State: done — pending the developer's commit request (spec mode)
- Origin: `docs/plans/android-cli-pin.plan.md` Decisions Log 2026-11-24 15:13 (the gap: env-update reads
  `latest/METADATA`, the sync fetches `cli/<version>/…`, so an announced-but-unpublished version would be
  proposed and 04android would FATAL on a cold cache).

## Goal

`(verify-asset:URL_TEMPLATE)` gates the url fetcher's Tier 1 (`fetch-extract`) as it already gates Tier 2
(`fetch-json`), and `GLOBAL_STACK_ANDROID_CLI_VERSION` carries it, so env-update never proposes an Android CLI
version whose versioned artifact is not published.

## Steps

| # | Step | State | Evidence |
|---|------|-------|----------|
| 1 | Failing tests in `bin/tests/env-update.test.sh` §123 (t123c reshaped; Tier 1 accept / walk / none-published / regex-nothing / WARN / ungated) | done | red first: 7 failed for the stated reasons (t123n's first red was a test bug — `err=$(…)` subshell — fixed) |
| 2 | `core/parse.sh` guard accepts fetch-json OR fetch-extract | done | §123 19/19; sabotage M6/M7 red t123k/t123c |
| 3 | `fetchers/url.sh` Tier 1 gated branch: newest-first, deduped list → `_gs_eu2_url_verify_walk`; distinct "matched, none published" message | done | sabotage M1–M5 each red (t123l/l2/o, o, m, l/m/o/p, o); live on a .env copy: real template → up to date, broken → WARN + SKIP naming the flag |
| 4 | Docs: `templates/tips/env-update.md`, `reporting/reference.sh`, `url.sh` header, `.claude/rules/env-update.md`, `.claude/rules/android.md`, `android-cli-pin.plan.md` | done | |
| 5 | `.env` annotation + `android-cli-sync.test.sh` 11n via a developer-run hand-off script (asserts the new guard first) | done | developer ran `/tmp/apply-android-cli-verify-asset-20261124.sh` 18:4x; `.env` diff = the one annotation line, non-comment lines identical to the backup; suites reading `.env`: android-cli-sync 87/87, open-all-envs 22/22, check-image-versions 30/30, env-scan 188/188, compose-env-plumbing 26/26, startup-prologue 1124/1124, postgres-healthcheck 7/7, env-update 937/937 |

## Verification

- Full `env-update.test.sh` + `env-update-coverage.test.sh`; sabotage: revert the Tier 1 branch → new tests red.
- Live, on a copy of `.env`, `--no-cache`: real template → up to date; broken template → SKIP naming the flag.
- Live probes 2026-11-24: `cli/1.1.16919734/linux_x86_64/android-cli.sha256` → 200, `cli/9.9.99999999/…` → 404
  (HEAD); `latest/…/METADATA` holds one `version=` line, so the walk has a single candidate and can only SKIP.

## Residuals (not certified by execution)

- Only the `.sha256` is probed: a binary published after its checksum still passes the gate.
- METADATA names one version: the gate can only SKIP, never fall back to an older one.
- A real announced-early release was simulated (fixtures, a broken template), never observed.

## Rollback

`git revert <sha>`; the `.env` annotation line reverts to the plain fetch-extract form.

## Decisions Log
- [2026-11-24 17:46] AGREED: Medium plan gate passed: implement as written, .env annotation via a developer-run hand-off script (developer: Go).
- [2026-11-24 17:46] AGREED: 3C/6C certification tier = advisor() only.
- [2026-11-24 18:39] AGREED: Design kept after the developer's challenge (host row vs container, lock like ndk-bundle): container sync + host copy from the shared cache, annotation gated with (verify-asset:); developer is running the hand-off script.

