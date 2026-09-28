# sdkman-java-build-ids Plan

Found 2026-09-28: `03java27-zulu` exhausted `on-failure:5` on `sdk install java 27.0.0-zulu`
("has not been released yet"), leaving 04android, 04serverless-framework, 05edge, 05stable and the
local 05 image in `Created`. The pin was the value env-update's `(watch-major)` suggested while the
record was still on Java 26.

## Decisions Log
- [2026-09-28 13:53] AGREED: Fix Java 27 by option 1: pin 27.0.0+35-zulu now, then fix the sdkman fetcher test-first so it never proposes a +build-less id SDKMAN does not serve (developer answer 2026-09-28).
- [2026-09-28 13:53] ASSUMED (review): Fetcher proposes the LISTED id verbatim and keeps a legacy base-form pin of the same release, rather than probing the broker per record — because every listed id validates and downloads while a probe adds an HTTP call per record. Alternatives: probe broker and strip only when base form is served; strip only when current pin is base-form.

## Evidence
- SDKMAN `/2/candidates/java/linux/versions/all` lists Zulu 27 ONLY as `27.0.0+35-zulu`.
- `validate/java/27.0.0-zulu/linuxx64` → `invalid`; broker GET → 404. `27.0.0+35-zulu` → `valid`, 302 to
  `cdn.azul.com/…zulu27.28.101-ca-jdk27.0.0-linux_x64.tar.gz` (raw `+`, as `sdkman-install.sh:130` builds it).
- Reproduced with the shipped functions on the live list: `_gs_eu2_sdkman_select_java` → `27.0.0-zulu`
  (the listed id minus `+35`), via `_gs_eu2_sdkman_strip_build` — also on the `(watch-major)` path
  (`latest_unconstrained`), which is how a Java 26 record suggested the id.
- The strip rule's premise ("broker serves only the base form") no longer holds: `26.0.2+1.1-zulu` → 302
  today. Base forms still resolve for releases that predate SDKMAN's `+build` ids (`17.0.20-zulu`,
  `21.0.12-zulu`, `26.0.2-zulu` validate) — they are legacy aliases; a new release gets none.
- `_gs_eu2_version_older 27.0.0+35-zulu 27.0.0-zulu` → OLDER, so a hand-fixed pin would be "upgraded"
  back to the broken id by the next `--apply`.

## Formal Plan
1. **Pin** — `.env:449-450` → `27.0.0+35-zulu` (developer's own edit, 13:46). Done.
2. **Fetcher** — `bin/lib/env-update/fetchers/sdkman.sh`: propose the LISTED identifier verbatim (pin
   and `latest_unconstrained`); when the current pin is the legacy base form of the same release, keep
   the pin (no false downgrade). The bug is "always strip", not "strip" — never flip it to "never accept
   a base-form pin". Tests first in `env-update.test.sh` §32, then a sabotage check.
3. **Bring-up** — start `03java27-zulu` and its five dependents through a CLEAN environment (`make up`, or
   `env -i HOME=$HOME PATH=$PATH docker compose …`). A plain `docker compose` from an interactive shell
   inherits `~/.bashrc`'s unquoted eval of `.env.local` (`GLOBAL_STACK_DOCKER_USER_NAME=Takieddine`,
   split at the space), which compose prefers over `--env-file`: every service's hash looked changed and
   the three containers first started that way carried the truncated name. Clean-env hashes match every
   `make`-created container exactly.

## Status
<!-- progress-block v1 -->
| # | Step | Size | State | Evidence | Files |
|---|------|------|-------|----------|-------|
| 1 | Java 27 pin → 27.0.0+35-zulu | S | done | 0f5371b | .env |
| 2 | sdkman fetcher keeps listed +build ids | M | done | 4458481 | bin/lib/env-update/fetchers/sdkman.sh, bin/tests/env-update.test.sh |
| 3 | Start Java 27 dependents | S | doing | - | - |
<!-- /progress-block -->
### Blocked
### Needs input
### Needs research
### Fragile
### Known issues
- The interactive shell's copy of `.env.local` word-splits values with spaces, and compose prefers it over
  `--env-file`: never run `docker compose up` for this stack from a normal shell without `env -i`.
- Even `env -i docker compose` is not `make up`: for QUOTED `.env.local` values make passes the quotes
  through literally (`PHP_CONFIG_PACKAGE_04_GD_COMMAND_SUFFIX="-- --enable-gd …"` in 03php8-4) while compose's
  dotenv strips them, so a raw clean-env `up` would recreate 03php8-4/8-5/edge too. Compare hashes through
  make: `env -i HOME=$HOME PATH=$PATH make GLOBAL_STACK_DOCKER_CLI_EXEC=config GLOBAL_STACK_DOCKER_CLI_EXEC_FLAGS="--hash '*'" GLOBAL_STACK_DOCKER_CLI='docker compose' GLOBAL_STACK_DOCKER_CLI_FLAGS='--env-file .env.local' docker-cli --silent`
  → 44 compared, only the six Java-27 containers differed (2026-09-28).
