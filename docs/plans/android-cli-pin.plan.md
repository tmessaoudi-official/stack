# Pin the Android CLI (`android-cli`) in .env

## Status

- State: done — committed and pushed 5001761 (re-sign pending); host on the pin 2026-11-24.
  Open: the fetch-extract verify-asset follow-up (Decisions Log)
- Started: 2026-11-24
- Size: Large (grew from Medium when scope became container + host)

### Needs input

- [x] W1. Redeploy templates/shell/global-unu-opt.sh to ~/.local/bin (backup first) — DONE 2026-11-24: cmp == template, 755, backup .bak-20261124, --check → missing android_cli → 1.1.16919734
- [x] W2. Run ~/.local/bin/global-unu-opt.sh --apply --only=android_cli — DONE 2026-11-24: record 1.1.16919734 + sha 9803784d… = binary sha, --check current, `android --version` 1.1.16919734, `android info` no update message

## Problem

`android` is a 4.8 MB Rust **launcher** (1.0.15498356) shipped in the pinned
`commandlinetools-linux-${GLOBAL_STACK_ANDROID_SDK_BUILD}_latest.zip`. On first run it downloads
the ~80 MB **real CLI** from `https://dl.google.com/android/cli/latest/linux_x86_64/android-cli`
into `${ANDROID_USER_HOME:-$HOME/.android}/bin/android-cli` and execs it. That binary is pinned
nowhere:

- host: `~/.android/bin/android-cli` is 1.0.15985488 (sha256 = Google's
  `1.0.15985488/linux_x86_64/android-cli.sha256`, 2026-11-24), installed by nothing in /stack —
  it printed "A new version of Android CLI is available (1.1.16919734)";
- containers: `$HOME` is container-local, so every recreate re-downloads whatever `latest` is.

## Evidence (2026-11-24)

| Fact | Grade |
|---|---|
| Launcher execs a PRESENT `android-cli` with no version check and no network (sandbox, stub CLI, dead proxy: cases A/B); downloads `latest` only when absent (case C) | Verified |
| Google serves immutable `cli/<ver>/linux_x86_64/android-cli` + `.sha256` (64 bare hex, no newline) for 1.0.15498356, 1.0.15985488, 1.1.16919734; `cli/latest/linux_x86_64/METADATA` = `version=…` | Verified (curl) |
| The CLI's own updater always asks for `latest`; `ANDROID_CLI_DOWNLOAD_URL` only swaps the root | Verified on the 1.0.15985488 jar (`javap`); Inferred for 1.1 |
| `(fetch-extract:version=([0-9][0-9.]*)) url:…/latest/linux_x86_64/METADATA` → `1.0.15985488 → 1.1.16919734 [AUTO]` | Verified (live `--check --no-cache`, throwaway env file) |
| startup-prologue §47 discovers SDK inputs from setup.sh ONLY | Verified (read) |

## Design

One sync script, three callers. The pin is NOT part of `GS_ANDROID_SDK_WANT` (a CLI bump must never
wipe the SDK) and is never referenced from `global-stack-android-setup.sh` (§47).

1. `docker/config/dist/bin/android-bin/global-stack-android-cli-sync.sh --installed --dest=FILE | --apply --pin=V --dest=FILE --cache=DIR`
   (100755 via `git add --chmod=+x`; `set -euo pipefail`; `${1:-}`; reads no env file).
   - empty pin → `unmanaged`, WARN, exit 0 (launcher behaviour unchanged);
   - empty/relative `--dest`/`--cache` → refused before anything runs;
   - current ⇔ record `<dest dir>/.android-cli.gs-pin` = `<pin> <sha>` AND `sha256(dest)` = sha — offline;
     a host `android update` changes the bytes → `--installed` prints nothing (drift), `--apply` restores the pin;
   - cache `<cache>/<pin>/{android-cli,android-cli.sha256}`: filled by `curl -f` of the versioned URL +
     `.sha256` into temp files in that dir, sha256 checked, then `mv`; a cached binary is re-checked
     against its stored sha before every copy;
   - copy → `<dest>.gs-tmp`, re-hash, `chmod 755`, atomic `mv`, record written LAST;
   - prune: only version-shaped dirs strictly inside `<cache>`, only after success (`_opt_rm_staging` shape);
   - any failure → FATAL, old dest untouched.
2. `global-stack-android-start.sh`: call `--apply` on EVERY boot, outside the SDK gate, before setup.sh.
3. `alltogether/global-stack-alltogether-start.sh` (05edge/05stable/local.05): call after the wait-for on
   `successes/android` (cache already filled → no download).
4. Compose: pass `GLOBAL_STACK_ANDROID_CLI_VERSION` in 04android, 05edge, 05stable and the gitignored
   `local.05…` file.
5. `templates/shell/global-unu-opt.sh`: row `android_cli`, kind `androidcli` with its own install hook
   delegating to the sync script; seams `GS_UNU_OPT_ANDROID_CLI_{SYNC,DEST,CACHE}`; no launcher.
6. `.env` (annotation + var, beside `GLOBAL_STACK_ANDROID_SDK_BUILD`), then `bin/env-scan.sh` → `.env.local`.

### New network dependency at boot (FATAL, deliberate)

A boot needs the network when the cache lacks the pin while the SDK marker is current: a CLI pin bump,
a hand-deleted cache, or a restore from an older `var/tools` snapshot. FATAL, consistent with every
`gs_version_gate` pin bump. A warm boot (record current) never touches the network.

## Tests (red first)

- new `bin/tests/android-cli-sync.test.sh`: stub curl (exit 22 under -f on unknown URLs), temp dirs;
  fresh install, current (curl stub must not be called), drift after `android update`, pin change,
  sha mismatch (dest byte-identical), 404, cached-bytes tampered, empty pin, empty/relative paths
  refused, prune confined (refusal proven on a disposable sibling), record written last; wiring:
  start.sh calls it outside the gate before setup.sh, alltogether after the wait-for, the pin absent
  from setup.sh and from `GS_ANDROID_SDK_WANT`, 4 compose files pass it.
- `bin/tests/global-unu-opt.test.sh`: `--check` reports, `--apply` installs through the REAL sync
  script with the suite's stub curl and the seams; real `~/.android/bin` fingerprinted before/after.
- `env-update.test.sh`: METADATA fixture → the annotation resolves.
- Sabotage: each new guard reddened once (`/sabotage-check`).

## Certification

- by execution: the finished sync into a sandbox `ANDROID_USER_HOME`, then the REAL launcher's
  `--version` there → the pin.
- UNCERTIFIED-BY-EXECUTION unless brought up: the compose passthrough and the 04android/05* boots
  (no containers exist on 2026-11-24).
- Host half takes effect only after the developer redeploys `~/.local/bin/global-unu{,-opt}.sh` and runs
  `global-unu-opt.sh --apply` (or a hard restart).

### Certified so far (2026-11-24)

- Suites: `android-cli-sync` 77/79 (the 2 reds are 11m/11n, the `.env` pin itself); `global-unu-opt`
  129/129; `env-update --section=38` 3/3 (new t38c, offline fixture); `startup-prologue` 1124/1124;
  `base-set-permissions` 8/8 (sync script staged 100755); `claude-rules-paths` 81/81.
- Sabotage: 8 mutants (sha check always true, `--installed` ignoring bytes, prune of any dir, record
  before copy, current check skipped, sync moved inside the SDK gate, engine ignoring the install
  hook, METADATA shape) — each reddened its own check after M4 found a gap: a DIRECTORY at dest made
  `mv -f` move the binary into it and write a record. Fixed with `mv -T` at all four renames; 6e/6f/6g
  pin the dest, record and cached-binary sites (each reverted alone reds its test); the `.sha256`
  sidecar site is untested (it fails closed: a non-file sidecar is fetched again).
- Live: the sync fetched 1.1.16919734 from Google (79,497,240 bytes, sha = published), a second run
  said `current` behind a dead proxy, and the REAL launcher in `tools/` printed `1.1.16919734` with
  `ANDROID_USER_HOME` on the sandbox. Contrast: pinned to 1.0.15985488, `android info` printed the
  developer's exact banner; pinned to 1.1.16919734 with the check forced, no banner.
- `make check-compose` rc 0 (warns the var is unset until `.env` carries it).
- 6C round 1 (advisor): in the real images the suite gives the same 77/79 (now 82/84) — 04android
  (Ubuntu 26.04.1: GNU `mv` 9.7, uutils `sha256sum`/`mktemp` 0.10.0) and 05edge, `--network none`;
  `dist/bin` reaches `/usr/local/bin` in 04android and 05edge (resolved `config`); start script and
  `make login-*` both run as `developer` (uid 1000, as on the host); the launcher reads only
  `ANDROID_USER_HOME` (its strings), and with the container's `ANDROID_SDK_HOME` set it still ran the
  pinned 1.1. On CLI 1.1, setup.sh's own `--sdk=… sdk install platform-tools build-tools;37.0.0`
  returned rc 0, its verify found both ids, its awk read platform-tools 37.0.3 (= pin). The real host
  `global-unu-opt.sh --check` with default seams reported `missing → 1.1.16919734`, writing nothing.
  The hand-off insert ran on a copy of `.env` (12 lines, env-update `up to date`).
- 6C round 2: `compose-env-plumbing` 26/26; with the pin appended to a copy of `.env.local`,
  `config` resolved through make shows `GLOBAL_STACK_ANDROID_CLI_VERSION=1.1.16919734` in 04android,
  05edge and 05stable (`local.05` is not in COMPOSE_FILE; its file carries the line). A throwaway
  04android container ran the image's own entrypoint (`sync-bin-n-exec.sh`) into the EXACT line from
  `android-start.sh`, with network: it installed the pin with the image's curl and CA, `chown-home`
  left it 700 (exec bit kept), `--installed` read 1.1.16919734, a second run said `current`, and the
  real launcher printed 1.1.16919734; the cache dir is uid 1000, as on the host. `--installed`
  refusals in the host row are now shown (16k), and a failed prune is a WARN (8g); each was
  red-first or sabotaged. The hand-off script verifies every suite that reads the real env files.
- Known exposure, not closed: env-update reads `latest/METADATA` but the sync fetches
  `cli/<version>/…`, so a version announced before its versioned artifacts are published would be
  proposed, and on a cold cache 04android would FATAL (its error token, naming the URL) and 05* wait
  on it. `(verify-asset:)` cannot gate it: `core/parse.sh` refuses it without `(fetch-json:)` and
  METADATA is plain text, not JSON. Mitigation today: before applying a bump, `curl -fsI
  https://dl.google.com/android/cli/<new>/linux_x86_64/android-cli.sha256`. Closing it needs a
  `(fetch-extract:)` + `(verify-asset:)` path in env-update — a separate change.
- Still UNCERTIFIED-BY-EXECUTION: the full start scripts end to end (SDK gate, then the 05* wait
  for `successes/android`), and the error token on a failed sync (Inferred from both callers'
  `set -eE` + ERR trap, not run).

## Rollback

`git revert <sha>`; host: the previous `~/.android/bin/android-cli` is the launcher's to re-download
(delete the file and its `.android-cli.gs-pin`).

## Decisions Log

- [2026-11-24 14:17] AGREED: scope is container + host; the host half is a global-unu-opt.sh row (developer answer to the scope question).
- [2026-11-24 14:17] AGREED: 3C certification tier = advisor() only.
- [2026-11-24 14:18] AGREED: Large plan gate passed: implement as written, FATAL on a boot that must download a new pin offline (developer: Go).
- [2026-11-24 14:33] AGREED: 6C certification tier = advisor() only.
- [2026-11-24 15:13] AGREED: Commit after the developer runs the .env hand-off script (both runs): one green commit with .env included.
- [2026-11-24 15:13] AGREED: The verify-asset gap (fetch-extract cannot be gated) is a separate follow-up task; until then curl the versioned .sha256 before applying a CLI bump.
