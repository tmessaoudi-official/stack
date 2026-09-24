# pin-bump-reinstall-audit Plan

Developer request 2026-09-24, verbatim: *"I want you to verify all pinned version in .env and their
installation scripts ! all of them for reinstalling on a pin bump without hard restart or remving
version or anything ! is it handled cleanly everywhere ? i want 100 % evidence on every variable
version and its usage ! no implementation yet !"* — AUDIT ONLY; nothing below is implemented.

## Decisions Log
- [2026-09-24 10:45] AGREED: fan-out + verify — mechanical inventories both ways, ≤5 read-only agents trace consumer groups, every "handled" verdict re-verified in the main conversation; report in var/claude/ + summary.
- [2026-09-24 10:45] AGREED: image-level pins PASS when a bump reaches the container via a normal rebuild target (make rebuild / down-n-rebuild*) — no hard-restart, no volume wipe, no manual marker delete.
- [2026-09-24 10:45] AGREED: evidence = static trace + behavioural probes of the SHIPPED gate logic against a tmpdir marker (GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS pinned to a tmpdir, never live tools/); no container touched.
- [2026-09-24 10:45] AGREED: certification tier for this audit's 3C and 6C = advisor() only.
- [2026-09-24 12:40] AGREED: second pass (audit only) = every NON-apt install site in the repo — discover anything unpinned (hardcoded / floating) AND prove each .env-pinned installer actually installs the pinned version; apt installs of any kind are out of scope.
- [2026-09-24 12:55] AGREED: pass-2 certification tier for 3C and 6C = advisor() only.

## Formal Plan
<!-- written at Phase 4 -->

## Status
<!-- progress-block v1 -->
| # | Step | Size | State | Evidence | Files |
|---|------|------|-------|----------|-------|
| 1 | Inventory A (254 annotated pins + aliases) and B (every consumer) | M | done | - | .env |
| 2 | Per-pin reinstall-on-bump trace + gate probes | L | done | - | docker/config/dist/bin/** |
| 3 | Findings report, graded per var | M | done | - | var/claude/** |
| 4 | Pass 2: every non-apt install site honours its pin; anything unpinned; host surface | L | done | - | var/claude/** |
<!-- /progress-block -->
### Blocked
### Needs input
- Which of A1–A7 / B / C to fix, in what order (no implementation authorised yet).
### Needs research
### Fragile
### Known issues
Full report (gitignored): `var/claude/pin-audit/REPORT.md`; per-pin file:line evidence in `var/claude/pin-audit/raw/G*.md`.
Result at HEAD 7b45087 — 254 pins: 168 clean (125 runtime-gated, 39 via `make down-n-rebuild*`, 4 via pull),
33 NOT-HANDLED, 26 PARTIAL, 20 EMPTY, 5 dead, 2 info-only.
- A1 pyenv/rbenv managers never upgrade (`*-iou.sh` clone only when `.git` absent) → PYENV, RBENV, RUBY_BUILD,
  GEMSET bumps are no-ops and PYTHON3/RUBY3/RUBY4 bumps past the frozen definitions delete the old interpreter
  then fail (resolver fallback verified by execution; install failure inferred).
- A2 `phpbrew-install-tools.sh` runs only on a PHPBREW mismatch → 11 tool pins + PHPBREW never applied
  (verified by execution of the shipped block).
- A3 FRANKENPHP bump: build only runs when `php.<AS>` marker absent; launch silently skipped.
- A4 4 caddy plugin pins not in the caddy gate input (live service).
- A5 5 nginx/httpd module pins ungated + MODSECURITY_LIB modules not rebuilt (UNCERTIFIED-BY-EXECUTION).
- A6 `make rebuild` does not push → 00base changes do not cascade; `make down-n-rebuild*` does (tier order verified).
- A7 SDKMAN (installer hardcodes 5.23.0), RUSTUP_INIT (gate behind RUST mismatch), registry/buildkit (manual targets);
  PARTIAL: PHP8_x gate on VERSION_NAME, FVM gate reads an unplumbed var, node raw-pin gate (latent), yarn patch,
  groovy/spark VX2 consumers lack depends_on.
- B install-quality: `Dockerfile:304-308` `|| echo` masks failures; `curl -L` without `-f` in 00base installs;
  go/zig overlay extract; phpbrew ext exit-0 (inferred).
- C escape hatches: `RELOAD_NODE24` / deleted node marker keeps pkg markers → no npm globals (verified by
  execution); `RELOAD_PHP8_x` keeps ext markers.
- PASS 2 (`var/claude/pin-audit/pass2/REPORT.md`) — install-site honours-pin + unpinned discovery:
  rustup-init PIN-IGNORED (`rust-iou.sh:25` sed matches nothing in the 1.29.1 installer — verified by
  execution; fix = export `RUSTUP_VERSION`); android launcher pinned but the real CLI floats to Google's
  latest; host claude 2.1.281 vs pin 2.1.276 (upgrade-only gate + autoUpdates); serverless `^` ranges with no
  tracked lockfile; `phpbrew-iou.sh:24` `composer update` discards phpbrew's lockfile; phpbrew pin locked to
  2.2.0 by the vendored overlay guard (`:16-19`, exit 1); `SDKMAN_NATIVE_VERSION` 0.7.34 has no pin;
  phpMyAdmin pinned to `master` = frozen at first install; awscli/rootAVD/docker-reclaim/mise `usage` float.
  Host surface `templates/shell/global-unu.sh` (~16 tools from the same pins) is delivered only by a manual
  run or `make hard-restart`; the host copy `~/.local/bin/global-unu.sh` is hand-copied, no deploy step.
  Disk→code sweep: every `tools/*` tree and `tools/bin/*` binary maps to a known site — no orphan.
- D doc claims refuted: CLAUDE.md android launcher "yields 1.0.15985488"; CLAUDE.md frankenphp gotcha, RELOAD "full unconditional reinstall", "manager-only
  reinstall"; `rbenv-iou.sh:15-19` comment; MASTER.plan.md:1487 MCP "dead"; `.env:277` MODSECURITY_LIB note.
