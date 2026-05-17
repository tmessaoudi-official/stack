# Stack TODO Checklist

Generated: 2026-05-17 — tracks items from the package audit + runtime tier update sprint.

---

## 🧪 Requires container testing

Run these manually after the next rebuild. Each has a specific command.

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
