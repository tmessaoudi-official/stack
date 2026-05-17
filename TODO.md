# Stack TODO Checklist

Generated: 2026-05-17 — tracks items from the package audit + runtime tier update sprint.

---

## 🧪 Requires container testing

Run these manually after the next rebuild. Each has a specific command.

- [ ] **giget and tsx install on all Node tiers** — added to `node-packages.compose.yaml` (Fix 3, 2026-05-17) but never container-tested. Verify both packages install and are usable on every node tier:
  ```bash
  make login-03node22
  giget --version && tsx --version

  make login-03node24
  giget --version && tsx --version

  make login-03node26
  giget --version && tsx --version

  make login-03nodeedge
  giget --version && tsx --version
  ```
  If any tier fails, check npm compatibility for `giget@3.2.0` / `tsx@4.22.1` on that Node version and add a per-tier override in the relevant `docker-compose.yaml` (empty value = disabled).
  Note: only fires on fresh containers or after clearing `tools/versions/node.<VERSION_AS>` marker.

- [ ] **env-scan `${` guard — no false "multiple values" after rebuild** — Fix 1 (2026-05-17) adds a guard in `gs_es_detect_multiple_defaults` that skips expansion-dependent `.env` values from comparison. The guard relies on awk `FS="="` being active in that context; 104/104 tests pass but FS was not directly verified by reading the awk header. After rebuild, run env-scan and confirm zero "multiple values" warnings for `GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS`:
  ```bash
  bin/env-scan.sh --dry-run 2>&1 | grep -i "multiple\|REGISTRY_ALIAS"
  ```
  Expected: no output. If `REGISTRY_ALIAS` still appears, the awk FS assumption is wrong — add `GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS` to `_GS_ES_PATTERN_EXCLUDE_MULTIPLE_VALUES` in `bin/lib/env-scan/config/defaults.sh` as a fallback.

- [ ] **ember-cli 6.11.0 on Node 26** — v6.10 introduced `isbinaryfile@6.0.0` (requires Node ≥24) as a transitive dep; v6.11 may fix it but is unconfirmed. Test:
  ```bash
  make login-03node26
  npm install -g ember-cli@6.11.0
  ```
  If it fails, pin NODE26 tier to `ember-cli@6.9.x` (last known-good) via per-tier env override.

- [ ] **playwright on NODEEDGE (Node 27 nightly)** — was confirmed broken on Node 26 (GH issues #40724, #40868). Verify status on Node 27:
  ```bash
  make login-03nodeedge
  npx playwright install && npx playwright --version
  ```
  If broken, add NODEEDGE per-tier override in `03nodeedge/docker-compose.yaml`:
  ```yaml
  - NODE_INSTALL_PACKAGE_PLAYWRIGHT_VERSION=
  ```

- [ ] **Flask on Python 3.14** — Flask 3.x declares `>=3.9` but no Python 3.14 CI coverage. Verify:
  ```bash
  make login-03python3
  python3.14 -c "import flask; print(flask.__version__)"
  ```
  If it fails, add a per-tier Python 3.14 flask override or annotate with `(lock:...)`.

---

## 👁️ Monitor — no action yet, check periodically

- [ ] **Micronaut 5.0.0 on SDKMAN** — 5.0.0 GA released 2026-05-13 (requires Java 25+ minimum, compatible with Java 26). SDKMAN only has RC1 as of 2026-05-17. When SDKMAN publishes stable:
  1. Update `.env` `GLOBAL_STACK_JAVA_DEFAULT_MICRONAUT_VERSION` from `4.10.14` → `5.0.0`
  2. Add per-tier override to `03java17-zulu` and `03java21-zulu` to **pin to 4.10.14** (5.0.0 requires Java 25+)
  3. Java 26 tier gets 5.0.0 automatically from the new default
  Check: `bin/env-update.sh --check --filter=MICRONAUT`

- [ ] **Spark 4.x stable on SDKMAN** — Apache released Spark 4.2.0 but SDKMAN only has `4.0.0-preview2`. The annotation `(channel:unstable) sdkman:spark:4` is correct and will detect when a stable 4.x is published.
  Check: `bin/env-update.sh --check --filter=SPARK`

- [ ] **`@types/node` 26.x on npm** — Node 26 types not yet published (npm `latest` is still 25.8.0 as of 2026-05-17). When 26.x ships:
  1. Update `GLOBAL_STACK_NODE26_INSTALL_PACKAGE_TYPES_NODE_VERSION` to `26.x.y`
  2. Consider updating `GLOBAL_STACK_NODEEDGE_INSTALL_PACKAGE_TYPES_NODE_VERSION` to `26.x.y` or `27.x.y` depending on what's available
  Check: `npm view @types/node dist-tags`

---

## 🤔 Decision pending

- [ ] **Yarn 1.22.22** — Classic is frozen since Jan 2020; `pnpm` 11.1.2 is already in the stack. Options:
  - **Remove** `yarn` from the stack (pnpm covers all use cases)
  - **Upgrade to Yarn v4** (breaking — different semantics, requires `nodeLinker: node-modules` in `.yarnrc.yml` for ecosystem compat)
  - **Keep Classic** as-is (frozen but functional)

  If upgrading to v4, in `.env`:
  ```bash
  # @todo env-update (watch-major) npm:yarn 4.9.1
  GLOBAL_STACK_NODE_DEFAULT_YARN_VERSION=4.9.1
  ```
  Test with a project that has `nodeLinker: node-modules` in `.yarnrc.yml` before committing.

- [ ] **pomchecker 1.15.0 on SDKMAN** — `1.15.0-SNAPSHOT` is the in-development version; SDKMAN stable may only have `1.14.0`. Verify before next rebuild:
  ```bash
  make login-03java25-zulu
  sdk list pomchecker
  ```
  If `1.15.0` is not listed as a SDKMAN candidate, downgrade in `.env`:
  ```bash
  GLOBAL_STACK_JAVA_DEFAULT_POMCHECKER_VERSION=1.14.0
  ```

---

## 🔮 Backlog — no timeline

Items carried over from the original `@todo.md` notes file.

- [ ] **Add Amazon CloudFront + CloudWatch to LocalStack** — extend the LocalStack service or add a dedicated AWS simulation service for CloudFront distribution testing and CloudWatch metrics. Check LocalStack Pro tier requirements.

- [ ] **Nginx OIDC integration** — install `cjose` from source (required by `mod_auth_openidc`), install `liboauth2 ≥ 2.0` from source, then configure OIDC auth for Nginx. See `docker/images/01nginx/` for the Nginx service. Dependencies must be compiled against the container's OpenSSL version.

- [ ] **`05edge` Java version** — currently `05edge` depends on `03java26-zulu` (waits for tools setup) but activates `JAVA_VERSION=${GLOBAL_STACK_JAVA25_VERSION}` (Java 25). Decide: should `05edge` use Java 26 as its active runtime? If yes, update `JAVA_VERSION*` vars in `docker/images/05edge/docker-compose.yaml`.

- [ ] **Maven VX3 vestigial slot** — `java-packages.compose.yaml` still carries slot `SDKMAN_CONFIG/INSTALL_PACKAGE_04_MAVEN_VX3_*` even though the version is disabled (`=` empty) in `.env`. The slot is dead code: SDKMAN startup skips empty versions, so it never installs. Safe to remove in a cleanup sprint (delete the two VX3 lines from `java-packages.compose.yaml` and the two var lines from `.env`). Not urgent — removing vestigial slot is purely cosmetic.

- [ ] **TDR image Maven version** — `local.05clts-grdf-tdr-b6tdr/docker-compose.yaml` intentionally uses `SDKMAN_INSTALL_PACKAGE_04_MAVEN_VERSION=${GLOBAL_STACK_JAVA_INSTALL_PACKAGE_MAVEN_VX2_VERSION}` (Maven 3.9.x) rather than VX1 (Maven 4.0.0-rc-5). Add a comment in that file explaining why (e.g., `# Maven 3.9.x (VX2) — b6tdr project requires Maven 3.x; 4.0.x RC not yet stable for this project`).

- [ ] **Spark 3.5.3 (VX2) retirement** — EOL since April 2026, excluded from Java 25/26 tiers, only runs on Java 17/21. Once Spark 4.x lands on SDKMAN stable, remove VX2 slot entirely. Until then it's harmless but carrying dead weight.

---

## 🔁 Reload system — implement spec at `docs/specs/reload-system.md`

Full spec with exact diffs, marker inventory, and testing checklist already written. Implement in risk order.

### Decisions required first

- [ ] **RELOAD_ALL cascade** — currently `RELOAD_ALL=true` only triggers base-layer cleanup (`global-stack-base-reload-all.sh`); it does NOT propagate into runtime startup scripts. Decide: should it also act as a shortcut that force-reloads every runtime? If yes, add `|| [ "${GLOBAL_STACK_RELOAD_ALL:-}" = "true" ]` to every reload check in every startup script. If no, base cleanup is sufficient and individual reload vars remain independent (recommended — `make hard-restart` is the nuclear option).

- [ ] **Ruby reload naming** — `GLOBAL_STACK_RELOAD_RUBY` currently does double duty: it controls both the tier-02 RbEnv manager (in `02rbenv`) and the tier-03 Ruby version (in `03ruby3`, `03ruby4`). Spec proposes splitting into `RELOAD_RBENV` (manager) + `RELOAD_RUBY3` / `RELOAD_RUBY4` (per-version). Two options:
  - **Option A (recommended)**: rename `RELOAD_RUBY` → `RELOAD_RBENV`, add `RELOAD_RUBY3` and `RELOAD_RUBY4`. Breaking change — old `RELOAD_RUBY=true` has no effect after the rename.
  - **Option B**: keep `RELOAD_RUBY` as a "nuke all Ruby" alias, add `RELOAD_RUBY3`/`RELOAD_RUBY4` on top. Backward-compatible but semantically ambiguous.

- [ ] **Per-version reload depth** — for Node: per-version reload currently deletes only the version marker, causing re-run of the packages/setup step. The NVM binary itself (`${NVM_DIR}/versions/node/<version>`) is NOT re-downloaded. For Python and Ruby, the spec includes deleting the binary too. Decide: should Node version reload also delete and re-download the NVM binary? (Spec recommendation: no — keeps Node reload fast; use `RELOAD_NVM` for a full re-download.)

### Implementation (ordered by risk — lowest first)

- [ ] **1. `.env` additions** — add all new RELOAD vars with `=false` defaults:
  - After `RELOAD_NVM`: `RELOAD_NODE22`, `RELOAD_NODE24`, `RELOAD_NODE26`, `RELOAD_NODEEDGE`
  - After `RELOAD_SDKMAN`: `RELOAD_JAVA17`, `RELOAD_JAVA21`, `RELOAD_JAVA25`, `RELOAD_JAVA26`
  - After `RELOAD_PYENV`: `RELOAD_PYTHON3`
  - Replace `RELOAD_RUBY`: `RELOAD_RBENV`, `RELOAD_RUBY3`, `RELOAD_RUBY4`
  - Full target block shown in spec §3.1

- [ ] **2. Flutter bug fix** — `GLOBAL_STACK_RELOAD_FLUTTER3` is wired in `03flutter3/docker-compose.yaml` but **never checked in `fvm-start.sh`** — setting it to `true` currently has zero effect. Add 5-line setup-mode block to `docker/config/dist/bin/fvm-bin/global-stack-fvm-start.sh`. See spec §5.5.

- [ ] **3. Node per-version reload** — add `GLOBAL_STACK_RELOAD_NODE=${GLOBAL_STACK_RELOAD_NODE<N>}` to each of `03node22/24/26/nodeedge` compose files; add reload block to `nvm-bin/global-stack-nvm-start.sh` setup mode (deletes `tools/versions/node.<VERSION_AS>`). See spec §4.1 + §5.1.

- [ ] **4. Java per-version reload** — add `GLOBAL_STACK_RELOAD_JAVA=${GLOBAL_STACK_RELOAD_JAVA<N>}` to each of `03java17/21/25/26-zulu` compose files (note: these compose files currently pass NO reload var at all); add reload block to `sdkman-bin/global-stack-sdkman-start.sh` setup mode (deletes version marker + SDKMAN candidate dir). See spec §4.2 + §5.2.

- [ ] **5. Python per-version reload** — add `GLOBAL_STACK_RELOAD_PYTHON=${GLOBAL_STACK_RELOAD_PYTHON3}` to `03python3/docker-compose.yaml`; add reload block to `pyenv-bin/global-stack-pyenv-start.sh` setup mode. See spec §4.3 + §5.3.

- [ ] **6. Ruby reload split (highest risk)** — atomic 3-file update: rename `RELOAD_RUBY` → `RELOAD_RBENV` in `02rbenv/docker-compose.yaml` and in `rbenv-start.sh` install mode; replace `RELOAD_RUBY` with split vars in `03ruby3` + `03ruby4` compose files; add per-version reload block in `rbenv-start.sh` setup mode. All three files must change together. See spec §4.4 + §5.4.

---

## 🏗️ Scaffolding gaps — found 2026-05-17

- [x] **`node26-bin/` missing** — `docker/config/dist/bin/node26-bin/` was absent; `nvm-start.sh` unconditionally calls `global-stack-nvm-node26-setup.sh` at lines 102, 106, 118 — causing `03node26` (and the local node26 image) to fail with "command not found" on every fresh start. **Fixed 2026-05-17**: created all 3 scripts from node24-bin template. Bind-mounted dir — no rebuild needed, restart is sufficient.

- [x] **`java25bin/` → `java25-bin/`** — naming inconsistency (missing hyphen vs all other java*-bin dirs). **Fixed 2026-05-17** via `git mv`. No runtime impact (sync script copies files by path, not by dir name).

- [x] **`java21-bin/` and `java26-bin/` missing** — stub scripts added for naming consistency. `sdkman-start.sh` does not call these scripts at runtime; they exist as extension points matching the `java17-bin/` and `java25-bin/` pattern.

---

## 🔍 Architecture findings — from 2026-05-17 audit

- [ ] **jbang and scala absent from `05stable` and `05edge` inline SDKMAN lists** — `05stable/05edge` inline their own SDKMAN package slots (legacy pattern, do not extend `java-packages.compose.yaml`). Slots 12 (jbang) and 13 (scala), added in this sprint, are not present in those inline lists. These tools ARE installed into the shared `tools/` volume by `03java25-zulu` / `03java26-zulu`, so `05stable`/`05edge` can use them via that volume — but they are not installed by the monolith images themselves. Add a comment in `05stable/docker-compose.yaml` and `05edge/docker-compose.yaml` noting: `# jbang and scala installed by 03java25-zulu/03java26-zulu via shared tools/ volume — not installed here`.

- [ ] **`05stable` requires `03node24` always in `COMPOSE_FILE`** — `05stable` depends on `03node24` and activates `NODE_VERSION=${GLOBAL_STACK_NODE24_VERSION}`. If `03node24` is ever removed from `COMPOSE_FILE` while `05stable` remains active, the container will wait for a success marker that never comes. Safe currently (03node24 is in COMPOSE_FILE), but worth documenting: add a comment in `05stable/docker-compose.yaml` on the `03node24` depends_on line.

- [ ] **Zig version drift in `00base`** — `env-scan --dry-run` reports `GLOBAL_STACK_ZIG_VERSION` has two different values inside `docker/images/00base/` (Dockerfile vs docker-compose). Clean up in a dedicated commit after verifying which value is canonical.

---

## 📦 Per-tier package decisions

- [ ] **Yarn 1.22.22 → v4 or removal** — see "Decision pending" section above. If upgrading to v4: update `GLOBAL_STACK_NODE_DEFAULT_YARN_VERSION` to `4.9.1` (annotate `(watch-major) npm:yarn`), add `nodeLinker: node-modules` guidance in `.env` comment. Test against a Yarn-Classic project before committing.

- [ ] **`@types/node` 26.x per-tier** — `GLOBAL_STACK_NODE26_INSTALL_PACKAGE_TYPES_NODE_VERSION` is pinned to `25.8.0` with `(watch-major)` annotation. When `26.x` ships on npm: update to `26.x.y`. Check: `npm view @types/node dist-tags`. Same evaluation needed for `NODEEDGE_INSTALL_PACKAGE_TYPES_NODE_VERSION`.

- [ ] **Micronaut 5.0.0 per-tier drift** — when SDKMAN publishes stable 5.0.0: update `GLOBAL_STACK_JAVA_DEFAULT_MICRONAUT_VERSION` to `5.0.0`, add per-tier overrides for `03java17-zulu` and `03java21-zulu` pinning to `4.10.14` (5.0.0 requires Java 25+). See "Monitor" section above.

- [ ] **Spark 4.x per-tier drift** — when SDKMAN publishes stable Spark 4.x: update `GLOBAL_STACK_JAVA_DEFAULT_SPARK_VX1_VERSION`; re-enable `03java25-zulu` and `03java26-zulu` overrides if those tiers gain Spark 4 support. Remove VX2 slot after confirming VX1 covers all active tiers.

- [ ] **Gradle VX2 re-enable on Java 25/26** — `GLOBAL_STACK_JAVA25_SDKMAN_INSTALL_PACKAGE_GRADLE_VX2_VERSION` and `JAVA26_*` are empty (Gradle 8 crashes on Java 25+). Monitor Gradle 8.x patch releases for Java 25/26 fix. When a compatible Gradle 8 version ships: restore the version values in `.env`. Check: `https://github.com/gradle/gradle/issues/29199`.

- [ ] **Groovy VX2 re-enable on Java 25/26** — same situation: `GLOBAL_STACK_JAVA25/26_SDKMAN_INSTALL_PACKAGE_GROOVY_VX2_VERSION` are empty (not in Java 25/26 test matrix). Monitor Groovy 4.x for Java 25/26 compatibility.
