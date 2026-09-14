# android-boot-warnings Plan

Developer request 2026-09-14, verbatim: *"I restaarted the stack ! the android image works ! but there
are some warnings/deprecations ! not urgent ! can you take a look and present me a solid plan to fix
them ! no implementation yet !!"* — MASTER.plan.md row 47. Plan only; nothing below is implemented.

## Decisions Log
- [2026-09-14 12:30] PROPOSED: S1 explicit versioned `avdmanager`, S2 PATH reorder +
  dead-entry removal, S3 guarded licence call (implementation not yet authorised).
- [2026-09-14 12:40] AGREED (S4): leave "Emulator version unknown" as is — no libpulse0, no KVM group.
- [2026-09-14 12:40] AGREED (S5): keep the Flutter telemetry banner — no FLUTTER_SUPPRESS_ANALYTICS.
- [2026-09-14 12:40] AGREED (S6): runtime fix only (S1-S3) — bootstrap unzip layout unchanged.

## Findings (04android boot log, 7,493 lines; a warm boot — the reinstall branch did not run)

| # | Symptom | Per-boot count | Root cause | Grade |
|---|---|---|---|---|
| F1 | `inconsistent location`, `corrupted package.xml`, `invalid package.xml` (mostly phpbrew's XML), DOCTYPE stack traces, `Could not load devices.xml` | 69 + 135 + 135 + 27 + 18 | `setup-dist.sh:70` runs a bare `avdmanager`; PATH lists the unversioned bootstrap `cmdline-tools/bin` first, whose launcher derives SDK root `APP_HOME/../..` = `/stack/tools`, so it scans the whole tools tree | Verified: the versioned `cmdline-tools/23.0/bin/avdmanager` ran the real production verb (`create avd --force --name gs_probe --package system-images;android-37.1;google_apis_ps16k;x86_64 --device pixel_7_pro`) → rc 0, **0** warn/error/exception lines; probe AVD deleted, the 3 real AVDs intact |
| F1' | The sweep doc's fix "pass the SDK root explicitly" | — | `avdmanager` has no usable SDK-root flag: `--sdk_root` rejected globally and after the verb; `ANDROID_SDK_ROOT` env alone still warns | Verified (earlier probes this session) |
| F2 | `sdkmanager is deprecated` + `--licenses option is no longer needed` | 2 | `android-start.sh:181` `flutter doctor --android-licenses` (runs `sdkmanager --licenses`) | Verified: licence file present (`tools/android/licenses/android-sdk-license`, 41 B); Flutter's check falls back to disk (`android_workflow.dart`) |
| F3 | `Emulator version unknown` in `flutter doctor -v` | 1 | `libpulse.so.0` absent from the image; `/dev/kvm` is `root:992`, `developer` not a member | Verified (ldd with bundled lib64 dirs → only libpulse missing) |
| F4 | Dead PATH entries `cmdline-tools/tools/bin`, `tools`, `tools/bin` + wrong order | 5 sites | legacy SDK layout | Verified: `android-start.sh:48,55`, `alltogether-start.sh:30,35`, `templates/shell/profile.sh:193`, deployed `/etc/profile.d/stack.sh` |
| F5 | Flutter telemetry banner | 1 | container `$HOME` not persisted → "first run" each boot | Inferred (`unified_analytics.dart:32` honours `FLUTTER_SUPPRESS_ANALYTICS`) |
| F6 | The `android` CLI floats | info | the pinned 5 MB zip is a launcher that downloads whatever Google serves (1.0.15985488 measured 09-11, 1.0.16261425 today) | Verified (probe printed "Downloading Android CLI… Unpacking") — informational, no step |

## Formal Plan

- **S1 (F1)** `global-stack-android-setup-dist.sh`: call
  `"${ANDROID_HOME}/cmdline-tools/${GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION}/bin/avdmanager"`;
  fail loudly (error token via the handler) if it is not executable. Pin check: `.env`/`.env.local`
  `23.0` == on-disk dir `23.0` == container env `23.0` [Verified]. Keep the lines 33-38 comment
  (avdmanager stays — `android emulator create` still takes only a profile).
- **S2 (F1 + F4)** at all 5 PATH sites: versioned `cmdline-tools/<ver>/bin` BEFORE unversioned
  `cmdline-tools/bin`; delete the 3 dead entries. The unversioned dir STAYS on PATH — a reinstall's
  bare `android` needs it before 23.0 exists. Blast radius: `alltogether-start.sh` ships in 05edge,
  05stable and the gitignored local.05 image. Host `/etc/profile.d/stack.sh` needs sudo → hand-off
  `! bash /tmp/<script>.sh`.
- **S3 (F2)** `android-start.sh:181` → guarded:
  `[ -n "$(ls -A "${ANDROID_HOME}/licenses" 2>/dev/null)" ] || flutter doctor --android-licenses`.
  Not a deletion: F6 means a future CLI might stop writing the licence on a fresh install, and
  `flutter doctor -v` under `set -e` would then error the container.
- **S4 (F3) — RULED: leave as is (no step).** Recommended: leave as is — the emulator binary is for the HOST
  (host-container binding); `libpulse0` only fixes a headless version probe, and KVM access needs
  the host gid 992 baked into the image (machine-bound). Alternative: add `libpulse0` to
  04android (+ local.05) Dockerfile and `group_add` the kvm gid.
- **S5 (F5) — RULED: keep the banner (no step).** `FLUTTER_SUPPRESS_ANALYTICS=true` in 04android's compose environment.
- **S6 — RULED: out of scope (runtime fix only).** Unzip the bootstrap to `cmdline-tools/latest/` (Google's
  documented layout; root derives correctly and Flutter looks there first) so the unversioned tree
  never exists on a new install. Existing trees keep S1+S2.

## Tests (red first, then sabotage)

- `startup-prologue.test.sh` `_andd_probe`: stub moves to
  `${d}/sdk/cmdline-tools/<ver>/bin/avdmanager`; pin `GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION`
  explicitly (it is `env`, not `env -i`); add a decoy `avdmanager` exiting 99 first on PATH → must
  red against HEAD. 43u non-vacuity unchanged.
- New §54: discover every android PATH line in `dist/bin` **and** `templates/shell/profile.sh`;
  red if versioned index > unversioned index, any dead entry present, or a live
  `--android-licenses` call lacks the guard; `>= 3` sites floor. §48 (`::`, glued `${PATH}`) must
  stay green after the reorder.
- Sabotage: swap the order back at one site → §54 reds naming it; revert S1 to bare → decoy reds;
  restore byte-for-byte.
- Suite runs: startup-prologue (full, ignores `--section`), `bash -n`, `shellcheck`;
  `docker compose --env-file .env.local config -q` only if S4/S5 touch compose/Dockerfile.

## Verification (after `make restart-04android`)

`docker logs` counts, each expected 0: `inconsistent location`, `package.xml`, `DOCTYPE`,
`devices.xml`, `sdkmanager) is deprecated`, `--licenses option`; plus `flutter doctor -v` still
shows `All Android licenses accepted`, 3 `global_stack_auto_*` AVDs, `tools/successes/` token
present. S2's 05edge/05stable consumers: UNCERTIFIED-BY-EXECUTION until they restart.

## Rollback

`git revert <sha>`; host profile via the hand-off script's `.bak.<ts>`.

## Docs

Correct `docs/container-sweep-2026-09-13.md` item #1 (recommendation 1 disproven); update memory
`project_android_avdmanager_sdk_root.md`; MASTER row 47 → done with sha.

## Status

S1-S3 implemented in `a689c68` (2026-09-14): startup-prologue 637/637, red first (9), sabotage reds 43v-43y/54b/54e. Owed: host `/etc/profile.d/stack.sh` via `/tmp/fix-profile-android-path-20260914.sh`; live log verification after restarting 04android (and 05edge/05stable, UNCERTIFIED-BY-EXECUTION until they restart).

## Side effect disclosed

A read-only `android --help` probe downloaded the CLI (87 MB) into container-local
`/home/developer/.android/bin/android-cli` and may have sent Google usage metrics; lost on recreate.
