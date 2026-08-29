# Startup / health-signalling tranche Plan

Closes the "no error signal" cluster from the 2026-08-28 evidence hunt
(`var/claude/hunt/startup-scripts.md`, consolidated in `var/claude/hunt/MASTER-TRIAGE.md`).

All five findings share one shape: **a container fails and nothing writes an error token**, so
`ls tools/errors/` — the documented first step of the debugging runbook — reports nothing wrong
while the container is unhealthy behind a 24 h `start_period`.

## Decisions Log

- [2026-08-29 01:40] AGREED: scope this pass to F5, F6, F2, F7, F1 — the findings whose fix is
  provable without a stack bring-up. F3 (`USE_LOCKS` build-time-only) and F4 (`web-server` marker
  has no error producer) are DEFERRED and stay open: F3 needs a full `00base` + descendants rebuild
  to verify, F4 needs a token-semantics decision first (three alternative producers, one shared
  marker — giving all three `GLOBAL_STACK_ERROR_TOKEN=web-server` means a failure in an unused
  alternative blocks consumers of a healthy one).
- [2026-08-29 01:40] AGREED: F2's `-ne 1` arm and the `_STACK_CAUGHT` re-entry guard land
  **together, never separately**. Verified by execution: the arm is accidentally acting as the
  re-entry guard, so removing it alone makes every reported failure write the error token twice,
  the second write carrying `exit: 1` and the trap's own line number instead of the real ones.
- [2026-08-29 01:40] AGREED: F5 is fixed by sourcing `global-stack-base-prologue.sh` (the
  convention), not by adding a local `stackCatch`. It buys the trap, the chain trace and the
  `GS_STARTUP_DRY_RUN` seam in one move, and puts the script inside the existing prologue suite's
  dynamic discovery. Verified safe: `shellcheck -i SC2086,SC2206,SC2046` reports nothing on the
  script, both `while read` loops set their own `IFS=`, and both `for` loops iterate a quoted
  literal — so the convention's `IFS=$'\n\t'` cannot change its behaviour.
- [2026-08-29 01:40] AGREED: F6 is fixed with the literal
  `rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"`, byte-matching
  the 10 existing sites rather than a new prologue helper — the convention audit that found the gap
  greps for exactly that string, and a helper would make the two new sites invisible to it.
  No `sudo rm -rf successes/<name>` is added: that would change restart-window health semantics
  for `05stable`/`05edge`, which is outside the finding.

## Formal Plan

### Changes

| # | File | Change |
|---|---|---|
| F1 | `base-bin/global-stack-base-prologue.sh:213` | `GLOBAL_INTTERNAL_` → `GLOBAL_INTERNAL_` (dead dedup guard) |
| F2 | 8 web-server scripts (`caddy-bin/`, `nginx-bin/`, `httpd-bin/`) | add the `_STACK_CAUGHT` re-entry guard; drop `&& $exit_code -ne 1` |
| F5 | `serverless-bin/global-stack-serverless-framework-start.sh` | adopt the convention header + `source global-stack-base-prologue.sh` |
| F6 | `serverless-bin/…-start.sh`, `alltogether/global-stack-alltogether-start.sh` | clear the stale error token at startup |
| F7 | `rbenv-bin/global-stack-rbenv-find-latest.sh:13` | `${CURRENT_RUBY_VERSION}` → `${RBENV_CURRENT_RUBY_VERSION}` |
| doc | prologue header comment | exemption is `141` only; serverless leaves the exemption list |

### Acceptance criteria

1. Serverless writes `tools/errors/serverless` when it fails, and honours `GS_STARTUP_DRY_RUN=1`.
2. A stale `tools/errors/<token>` is gone after a successful restart of serverless / alltogether.
3. A web-server script exiting 1 reports — **exactly once**, with the real line number.
4. `rbenv-find-latest.sh 3.4` resolves `3.4.10` instead of echoing back `3.4`.
5. Every assertion above fails first, for its own stated reason, and a sabotage of each guarantee
   turns the suite red.

### What this tranche does NOT deliver

F2 gives the web-server scripts **stdout + `tools/elapsed` visibility only**. They still write no
error token, because `01caddy`/`01nginx`/`01httpd` define no `GLOBAL_STACK_ERROR_TOKEN` at all —
that is F4, deferred.

### Rollback

Every change is a self-contained commit on `master`; `git revert <sha>` restores prior behaviour.
No `.env`, compose or image change is involved, so nothing requires a rebuild to roll back.
