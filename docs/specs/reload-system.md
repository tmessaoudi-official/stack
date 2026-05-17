# Reload System Extension Spec

**Status**: Draft — not yet implemented
**Scope**: Add per-version RELOAD granularity to all runtimes that currently lack it
**Reference implementation**: PHP (complete) + Flutter (partial)

---

## 1. Background and Pattern

The `GLOBAL_STACK_RELOAD_*` system forces full reinstall of a runtime on the next container start. Every variable defaults to `false`; setting it to `true` causes the startup script to delete the relevant success markers, version markers, and installed files before re-running the install/setup sequence.

### 1.1 How RELOAD_ALL works (and its absent bug)

`RELOAD_ALL` is consumed exclusively by two base-tier scripts:

- `docker/config/dist/bin/base-bin/global-stack-base-reload-all.sh` — clears all tools when the stack version changes
- `docker/config/dist/bin/base-bin/global-stack-base-set-permissions.sh` — re-applies filesystem permissions

**Critical finding**: `RELOAD_ALL` is NOT checked in any runtime startup script (`phpbrew-start.sh`, `nvm-start.sh`, `sdkman-start.sh`, `pyenv-start.sh`, `rbenv-start.sh`, `fvm-start.sh`). The existing `RELOAD_PHPBREW` / `RELOAD_NVM` / etc. checks do **not** include `|| "${GLOBAL_STACK_RELOAD_ALL}" == "true"`.

This means setting `RELOAD_ALL=true` does NOT trigger a reinstall of individual runtimes — it only triggers the base-layer cleanup. This is either:
- (a) intentional — base-layer cleanup already removes everything via `global-stack-base-reload-all.sh`, making per-runtime checks redundant when ALL=true; or
- (b) a latent bug — if base-layer cleanup is selective, RELOAD_ALL would silently fail to rebuild specific runtimes.

**Decision needed from user** — see Challenge section §9.1.

### 1.2 The reference pattern (PHP)

PHP is the only fully-implemented example. Its pattern across three layers:

**Layer 1 — .env**: Two separate variables per runtime-family:
```bash
GLOBAL_STACK_RELOAD_PHPBREW=false    # manager (tier 02): wipe whole phpbrew install
GLOBAL_STACK_RELOAD_PHP8_2=false     # version (tier 03): wipe just this PHP version
```

**Layer 2 — compose YAML** (tier 03, e.g. `03php8-2/docker-compose.yaml`): The compose file maps the version-specific `.env` var to the generic `GLOBAL_STACK_RELOAD_PHP` env var consumed by the startup script:
```yaml
- GLOBAL_STACK_RELOAD_PHPBREW=${GLOBAL_STACK_RELOAD_PHPBREW}
- GLOBAL_STACK_RELOAD_PHP=${GLOBAL_STACK_RELOAD_PHP8_2}
```

**Layer 3 — startup script** (`global-stack-phpbrew-start.sh`): The script checks two variables in the appropriate MODE blocks:
- In `MODE=install` (tier 02): checks `GLOBAL_STACK_RELOAD_PHPBREW` → wipes everything
- In `MODE=setup` (tier 03): checks `GLOBAL_STACK_RELOAD_PHP` → wipes just this version's files

The tier 02 container (`02phpbrew`) also receives `GLOBAL_STACK_RELOAD_PHPBREW` so it can wipe the whole manager install.

### 1.3 FVM/Flutter — partial implementation

Flutter has a two-variable model that's partially implemented:

**In `.env`**: `GLOBAL_STACK_RELOAD_FVM` and `GLOBAL_STACK_RELOAD_FLUTTER3`

**In `03flutter3/docker-compose.yaml`**: Both vars are passed through:
```yaml
- GLOBAL_STACK_RELOAD_FVM=${GLOBAL_STACK_RELOAD_FVM}
- GLOBAL_STACK_RELOAD_FLUTTER3=${GLOBAL_STACK_RELOAD_FLUTTER3}
```

**In `global-stack-fvm-start.sh`**:
- In `MODE=install`: checks `GLOBAL_STACK_RELOAD_FVM` — works correctly
- In `MODE=setup`: **`GLOBAL_STACK_RELOAD_FLUTTER3` is never checked** — the version-level reload var is wired in compose but dead in the script

This means `RELOAD_FLUTTER3=true` currently has no effect. It is a bug to fix in the implementation.

---

## 2. Current State Analysis

### 2.1 All existing RELOAD vars — status table

| Variable | Controls | Tier | Script location | Rating |
|---|---|---|---|---|
| `RELOAD_ALL` | Base cleanup + permissions | Base | `base-bin/global-stack-base-reload-all.sh` | PARTIAL — base only, not runtimes |
| `RELOAD_PERMISSIONS` | Filesystem permissions | Base | `base-bin/global-stack-base-set-permissions.sh` | COMPLETE |
| `RELOAD_PHPBREW` | PHPBrew manager + all PHP versions | 02 manager | `phpbrew-bin/global-stack-phpbrew-start.sh` (install mode) | COMPLETE |
| `RELOAD_PHP8_2` | PHP 8.2 version only | 03 runtime | compose → `GLOBAL_STACK_RELOAD_PHP` → phpbrew-start.sh (setup mode) | COMPLETE |
| `RELOAD_PHP8_3` | PHP 8.3 version only | 03 runtime | same path | COMPLETE |
| `RELOAD_PHP8_4` | PHP 8.4 version only | 03 runtime | same path | COMPLETE |
| `RELOAD_PHP8_5` | PHP 8.5 version only | 03 runtime | same path | COMPLETE |
| `RELOAD_PHPEDGE` | PHP edge version only | 03 runtime | same path | COMPLETE |
| `RELOAD_PHPMYADMIN` | phpMyAdmin | 04 tools | (not verified in this spec) | UNKNOWN |
| `RELOAD_NVM` | NVM manager + all Node versions | 02 manager | `nvm-bin/global-stack-nvm-start.sh` (install mode) | MANAGER-ONLY |
| `RELOAD_SDKMAN` | SDKMAN manager + all Java versions | 02 manager | `sdkman-bin/global-stack-sdkman-start.sh` (install mode) | MANAGER-ONLY |
| `RELOAD_RUST` | Rust (single version, no versioning) | 02 (flat) | `rust-bin/global-stack-rust-start.sh` | COMPLETE |
| `RELOAD_PYENV` | PyEnv manager AND python versions | 02+03 (dual) | `pyenv-bin/global-stack-pyenv-start.sh` | CONFLATED — same var used for both tiers |
| `RELOAD_RUBY` | RbEnv manager AND ruby versions | 02+03 (dual) | `rbenv-bin/global-stack-rbenv-start.sh` | CONFLATED — same var used for both tiers |
| `RELOAD_FVM` | FVM manager | 02 manager | `fvm-bin/global-stack-fvm-start.sh` (install mode) | COMPLETE |
| `RELOAD_FLUTTER3` | Flutter 3 version | 03 runtime | compose wires it, but script never checks it | BUG — var is dead |
| `RELOAD_ANDROID` | Android SDK | 04 tools | `android-bin/global-stack-android-start.sh` | (not verified in this spec) |
| `RELOAD_HTTPD` | Apache httpd | 01 infra | (not verified in this spec) | UNKNOWN |
| `RELOAD_HTTP_COMMON` | Shared HTTP config | 01 infra | (not verified in this spec) | UNKNOWN |
| `RELOAD_NGINX` | Nginx | 01 infra | (not verified in this spec) | UNKNOWN |
| `RELOAD_CADDY` | Caddy | 01 infra | (not verified in this spec) | UNKNOWN |

### 2.2 Missing per-version vars (runtimes with gap)

| Missing variable | Would control | Current workaround | Startup script target |
|---|---|---|---|
| `RELOAD_NODE22` | Node 22 version only | Must use `RELOAD_NVM` (nukes all versions) | `nvm-start.sh` setup mode |
| `RELOAD_NODE24` | Node 24 version only | same | same |
| `RELOAD_NODE26` | Node 26 version only | same | same |
| `RELOAD_NODEEDGE` | Node edge version only | same | same |
| `RELOAD_JAVA17` | Java 17 version only | Must use `RELOAD_SDKMAN` (nukes all versions) | `sdkman-start.sh` setup mode |
| `RELOAD_JAVA21` | Java 21 version only | same | same |
| `RELOAD_JAVA25` | Java 25 version only | same | same |
| `RELOAD_JAVA26` | Java 26 version only | same | same |
| `RELOAD_PYTHON3` | Python 3 version only | Must use `RELOAD_PYENV` (also nukes the manager) | `pyenv-start.sh` setup mode |
| `RELOAD_RUBY3` | Ruby 3 version only | Must use `RELOAD_RUBY` (also nukes the manager) | `rbenv-start.sh` setup mode |
| `RELOAD_RUBY4` | Ruby 4 version only | same | same |

Also: `RELOAD_RBENV` (see §9.2 challenge on Ruby naming).

### 2.3 Runtimes with no RELOAD vars at all

The following tier-02 images exist but have no RELOAD var in `.env`:

| Image | Manager | Has RELOAD var? |
|---|---|---|
| `02sonarqube` | SonarQube | No — infra tool, likely not needed |
| `02keycloak-keycloak` | Keycloak | No — infra tool |
| `02mongoclient-mongoclient` | Mongo client | No — infra tool |
| `02dpage-pgadmin4` | pgAdmin | RELOAD_PHPMYADMIN exists but for the wrong service (see §9.3) |

These infra-tools are out of scope for this spec (they don't follow the two-phase install model).

---

## 3. New Variables to Add

### 3.1 Exact `.env` additions

Add after line 1334 (`GLOBAL_STACK_RELOAD_NVM=false`), in grouped blocks matching the runtime sections:

```bash
# Node (NVM) — per-version reload
GLOBAL_STACK_RELOAD_NODE22=false
GLOBAL_STACK_RELOAD_NODE24=false
GLOBAL_STACK_RELOAD_NODE26=false
GLOBAL_STACK_RELOAD_NODEEDGE=false
```

Add after line 1342 (`GLOBAL_STACK_RELOAD_SDKMAN=false`):

```bash
# Java (SDKMAN) — per-version reload
GLOBAL_STACK_RELOAD_JAVA17=false
GLOBAL_STACK_RELOAD_JAVA21=false
GLOBAL_STACK_RELOAD_JAVA25=false
GLOBAL_STACK_RELOAD_JAVA26=false
```

Add after line 1344 (`GLOBAL_STACK_RELOAD_PYENV=false`):

```bash
# Python (PyEnv) — per-version reload (manager reload stays RELOAD_PYENV)
GLOBAL_STACK_RELOAD_PYTHON3=false
```

Replace line 1345 (`GLOBAL_STACK_RELOAD_RUBY=false`) with a split block:

```bash
GLOBAL_STACK_RELOAD_RBENV=false      # Tier 02 manager only
GLOBAL_STACK_RELOAD_RUBY3=false      # Ruby 3 version only
GLOBAL_STACK_RELOAD_RUBY4=false      # Ruby 4 version only
```

**Note on Ruby**: See §9.2. The existing `RELOAD_RUBY` var is currently used for both the tier 02 manager (`02rbenv`) and the tier 03 versions. This spec proposes splitting it. The existing var would be retired. This requires a three-step migration (add new vars → update compose/scripts → remove old var).

Full `.env` block after changes (lines 1329–1353 area):

```bash
# =============================================================================
# RELOAD SWITCHES — set true to force full reinstall on next container start
# SLOW: full reinstall can take 10-30+ minutes. Reset to false after use.
# =============================================================================
GLOBAL_STACK_RELOAD_ALL=false
GLOBAL_STACK_RELOAD_PERMISSIONS=false
GLOBAL_STACK_RELOAD_NVM=false
GLOBAL_STACK_RELOAD_NODE22=false
GLOBAL_STACK_RELOAD_NODE24=false
GLOBAL_STACK_RELOAD_NODE26=false
GLOBAL_STACK_RELOAD_NODEEDGE=false
GLOBAL_STACK_RELOAD_PHPBREW=false
GLOBAL_STACK_RELOAD_PHP8_2=false
GLOBAL_STACK_RELOAD_PHP8_3=false
GLOBAL_STACK_RELOAD_PHP8_4=false
GLOBAL_STACK_RELOAD_PHP8_5=false
GLOBAL_STACK_RELOAD_PHPEDGE=false
GLOBAL_STACK_RELOAD_PHPMYADMIN=false
GLOBAL_STACK_RELOAD_SDKMAN=false
GLOBAL_STACK_RELOAD_JAVA17=false
GLOBAL_STACK_RELOAD_JAVA21=false
GLOBAL_STACK_RELOAD_JAVA25=false
GLOBAL_STACK_RELOAD_JAVA26=false
GLOBAL_STACK_RELOAD_RUST=false
GLOBAL_STACK_RELOAD_PYENV=false
GLOBAL_STACK_RELOAD_PYTHON3=false
GLOBAL_STACK_RELOAD_RBENV=false
GLOBAL_STACK_RELOAD_RUBY3=false
GLOBAL_STACK_RELOAD_RUBY4=false
GLOBAL_STACK_RELOAD_FVM=false
GLOBAL_STACK_RELOAD_FLUTTER3=false
GLOBAL_STACK_RELOAD_ANDROID=false
GLOBAL_STACK_RELOAD_HTTPD=false
GLOBAL_STACK_RELOAD_HTTP_COMMON=false
GLOBAL_STACK_RELOAD_NGINX=false
GLOBAL_STACK_RELOAD_CADDY=false
```

---

## 4. Compose File Changes

Each tier-03 service needs the new per-version RELOAD var wired into its compose file, following the exact PHP pattern: map the specific `.env` var to a generic env var that the startup script can read.

### 4.1 Node — all four tier-03 services

**Pattern**: add `GLOBAL_STACK_RELOAD_NODE=${GLOBAL_STACK_RELOAD_NODE<VERSION_AS>}` alongside the existing `GLOBAL_STACK_RELOAD_NVM` line.

`docker/images/03node22/docker-compose.yaml` — add:
```yaml
- GLOBAL_STACK_RELOAD_NODE=${GLOBAL_STACK_RELOAD_NODE22}
```

`docker/images/03node24/docker-compose.yaml` — add:
```yaml
- GLOBAL_STACK_RELOAD_NODE=${GLOBAL_STACK_RELOAD_NODE24}
```

`docker/images/03node26/docker-compose.yaml` — add:
```yaml
- GLOBAL_STACK_RELOAD_NODE=${GLOBAL_STACK_RELOAD_NODE26}
```

`docker/images/03nodeedge/docker-compose.yaml` — add:
```yaml
- GLOBAL_STACK_RELOAD_NODE=${GLOBAL_STACK_RELOAD_NODEEDGE}
```

### 4.2 Java — all four tier-03 services

**Pattern**: add `GLOBAL_STACK_RELOAD_JAVA=${GLOBAL_STACK_RELOAD_JAVA<VERSION_AS>}` alongside existing lines. Note: the Java compose files do NOT currently pass `GLOBAL_STACK_RELOAD_SDKMAN` to the tier-03 container — this is correct (the tier-02 container handles SDKMAN manager reload). Only the version-level var needs to be added.

`docker/images/03java17-zulu/docker-compose.yaml` — add:
```yaml
- GLOBAL_STACK_RELOAD_JAVA=${GLOBAL_STACK_RELOAD_JAVA17}
```

`docker/images/03java21-zulu/docker-compose.yaml` — add:
```yaml
- GLOBAL_STACK_RELOAD_JAVA=${GLOBAL_STACK_RELOAD_JAVA21}
```

`docker/images/03java25-zulu/docker-compose.yaml` — add:
```yaml
- GLOBAL_STACK_RELOAD_JAVA=${GLOBAL_STACK_RELOAD_JAVA25}
```

`docker/images/03java26-zulu/docker-compose.yaml` — add:
```yaml
- GLOBAL_STACK_RELOAD_JAVA=${GLOBAL_STACK_RELOAD_JAVA26}
```

### 4.3 Python

`docker/images/03python3/docker-compose.yaml` — replace the existing:
```yaml
- GLOBAL_STACK_RELOAD_PYENV=${GLOBAL_STACK_RELOAD_PYENV}
```
with:
```yaml
- GLOBAL_STACK_RELOAD_PYENV=${GLOBAL_STACK_RELOAD_PYENV}
- GLOBAL_STACK_RELOAD_PYTHON=${GLOBAL_STACK_RELOAD_PYTHON3}
```

### 4.4 Ruby

Replace the existing single `GLOBAL_STACK_RELOAD_RUBY` pass-through in both ruby compose files.

`docker/images/03ruby3/docker-compose.yaml` — replace:
```yaml
- GLOBAL_STACK_RELOAD_RUBY=${GLOBAL_STACK_RELOAD_RUBY}
```
with:
```yaml
- GLOBAL_STACK_RELOAD_RBENV=${GLOBAL_STACK_RELOAD_RBENV}
- GLOBAL_STACK_RELOAD_RUBY=${GLOBAL_STACK_RELOAD_RUBY3}
```

`docker/images/03ruby4/docker-compose.yaml` — replace:
```yaml
- GLOBAL_STACK_RELOAD_RUBY=${GLOBAL_STACK_RELOAD_RUBY}
```
with:
```yaml
- GLOBAL_STACK_RELOAD_RBENV=${GLOBAL_STACK_RELOAD_RBENV}
- GLOBAL_STACK_RELOAD_RUBY=${GLOBAL_STACK_RELOAD_RUBY4}
```

`docker/images/02rbenv/docker-compose.yaml` — replace:
```yaml
- GLOBAL_STACK_RELOAD_RUBY=${GLOBAL_STACK_RELOAD_RUBY}
```
with:
```yaml
- GLOBAL_STACK_RELOAD_RUBY=${GLOBAL_STACK_RELOAD_RBENV}
```

(The tier-02 container only needs the manager-level reload; individual version reloads are handled by tier-03.)

### 4.5 Flutter (bug fix)

`docker/images/03flutter3/docker-compose.yaml` already passes `GLOBAL_STACK_RELOAD_FLUTTER3`. No compose change needed — only the script change (§5.4) is required.

---

## 5. Startup Script Changes

### 5.1 Node — `docker/config/dist/bin/nvm-bin/global-stack-nvm-start.sh`

Add a per-version reload block in the `MODE=setup` section, after the existing `rm -rf ...successes/node...` and before the `sleep 1`. Model it exactly on the PHP setup-mode pattern:

**Current state of setup block (lines 45–59)**:
```bash
if [ "${NVM_MODE}" = "setup" ]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/node.$([[ ... ]])"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1
  global-stack-base-wait-for.sh ...
  ...lock...
fi
```

**After change** — add a reload block between the `rm -f` error clear and `sleep 1`:
```bash
  if [ "${GLOBAL_STACK_RELOAD_NODE:-}" = "true" ]; then
    echo -e "\nReloading node ${NODE_VERSION:-} ..."
    rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.$([[ -n "${NODE_VERSION_AS:-}" && "" != "${NODE_VERSION_AS:-}" ]] && echo "${NODE_VERSION_AS:-}" || echo "${NODE_VERSION:-}")"
  fi
```

**What gets deleted**: the version marker file only (`tools/versions/node.<VERSION_AS>`). The nvm-installed Node itself lives in `${NVM_DIR}/versions/node/<full_version>` — deleting the marker causes the existing `if [ ! -f ${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.* ]` guard on line 84 to evaluate as false and re-run the install. **No need to delete the NVM directory itself** — that would affect all other Node versions.

**Note**: The success marker is already cleared unconditionally at the top of setup mode (line 46: `sudo rm -rf .../node.<VERSION_AS>`). The reload block only needs to clear the version marker to force reinstall.

### 5.2 Java — `docker/config/dist/bin/sdkman-bin/global-stack-sdkman-start.sh`

The SDKMAN setup mode is more complex: it uses `if [ -f .../java.<VERSION_AS> ]` to decide whether to skip install or just re-`use`. The reload needs to clear the version marker so the "install" path is taken.

Add in the `MODE=setup` section, after the `rm -rf .../java.<VERSION_AS>` and `rm -f ...ERROR_TOKEN` block (lines 50–52), before `sleep 1`:
```bash
  if [ "${GLOBAL_STACK_RELOAD_JAVA:-}" = "true" ]; then
    echo -e "\nReloading java ${JAVA_VERSION:-} ..."
    rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/java.$([[ -n "${JAVA_VERSION_AS:-}" && "" != "${JAVA_VERSION_AS:-}" ]] && echo "${JAVA_VERSION_AS}" || echo "${JAVA_VERSION}")"
    rm -rf "${SDKMAN_DIR}/candidates/java/${JAVA_VERSION}"
  fi
```

**What gets deleted**: version marker + the SDKMAN candidate directory for this Java version. The candidate directory must be deleted to force `sdk install java ${JAVA_VERSION}` to run fresh — SDKMAN considers the version already installed if the directory exists.

### 5.3 Python — `docker/config/dist/bin/pyenv-bin/global-stack-pyenv-start.sh`

The pyenv setup block (lines 94–144) currently uses `GLOBAL_STACK_RELOAD_PYENV` to decide whether to skip or reinstall a Python version (lines 109, 133). This conflates manager reload with version reload.

**Change 1**: Add a new `GLOBAL_STACK_RELOAD_PYTHON` check in the setup block, early in the `MODE=setup` section, after the `rm -rf .../python.<VERSION_AS>` and `rm -f ...ERROR_TOKEN` lines (lines 46–47):

```bash
  if [ "${GLOBAL_STACK_RELOAD_PYTHON:-}" = "true" ]; then
    echo -e "\nReloading python ${PYTHON_VERSION:-} ..."
    rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python.$([[ -n "${PYTHON_VERSION_AS:-}" && "" != "${PYTHON_VERSION_AS:-}" ]] && echo "${PYTHON_VERSION_AS:-}" || echo "${PYTHON_VERSION:-}")"
    rm -rf "${PYENV_ROOT}/versions/${PYTHON_VERSION}"
  fi
```

**What gets deleted**: version marker + the pyenv-managed Python installation directory for this specific version.

**Change 2**: The existing `GLOBAL_STACK_RELOAD_PYENV` usage in the setup block (lines 109, 133) should be left as-is — `RELOAD_PYENV` will continue to act as a "nuke everything" escalation that affects setup mode too. This is intentional: RELOAD_PYENV on a tier-03 container also triggers a version reinstall, matching the current behavior.

**No change needed to install mode** — the existing `RELOAD_PYENV` logic in install mode is correct and complete.

### 5.4 Ruby — `docker/config/dist/bin/rbenv-bin/global-stack-rbenv-start.sh`

**Current naming confusion**: `GLOBAL_STACK_RELOAD_RUBY` is used in both install mode (tier 02) and setup mode (tier 03). This spec splits it into `GLOBAL_STACK_RELOAD_RBENV` (manager) and `GLOBAL_STACK_RELOAD_RUBY` (version, identical name but now version-specific via compose mapping).

**Change 1 — install mode** (lines 40–43): rename the check from `RELOAD_RUBY` to `RELOAD_RBENV`:
```bash
  if [ "${GLOBAL_STACK_RELOAD_RBENV:-}" = "true" ]; then
    rm -rf "${RBENV_ROOT}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/ruby"* \
      "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rbenv" \
      "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby"* \
      "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv" \
      "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/fastlane"
    mkdir -p "${RBENV_ROOT}"
  fi
```

Also update the tool install guard (line 68) and the install-tools call (line 87) from `RELOAD_RUBY` to `RELOAD_RBENV`:
```bash
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv" || "true" = "${GLOBAL_STACK_RELOAD_RBENV:-}" ]]; then
```

**Change 2 — setup mode**: add a per-version reload block early in the `MODE=setup` section, after the `rm -rf .../ruby.<VERSION_AS>` unconditional clear (line 47), before `sleep 1`:

```bash
  if [ "${GLOBAL_STACK_RELOAD_RUBY:-}" = "true" ]; then
    echo -e "\nReloading ruby ${RUBY_VERSION:-} ..."
    rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.$([[ -n "${RUBY_VERSION_AS:-}" && "" != "${RUBY_VERSION_AS:-}" ]] && echo "${RUBY_VERSION_AS:-}" || echo "${RUBY_VERSION:-}")"
    rm -rf "${RBENV_ROOT}/versions/${RBENV_VERSION:-}"
  fi
```

**What gets deleted**: version marker + the rbenv-managed Ruby installation directory for this version.

**Important**: The setup-mode guards on lines 104 and 117 already check `GLOBAL_STACK_RELOAD_RUBY` to force reinstall. After this change, `GLOBAL_STACK_RELOAD_RUBY` in setup mode will come from the compose mapping (e.g. `RELOAD_RUBY3` or `RELOAD_RUBY4`) rather than the old shared `RELOAD_RUBY` var — the script logic is correct as-is, only the source of the value changes.

### 5.5 Flutter — `docker/config/dist/bin/fvm-bin/global-stack-fvm-start.sh` (bug fix)

The `GLOBAL_STACK_RELOAD_FLUTTER3` var is wired in compose but never checked in the script. Add a check in the `FVM_MODE=setup` section (lines 44–58), after `rm -rf .../flutter.<VERSION_AS>` and `rm -f ...ERROR_TOKEN`, before `sleep 1`:

```bash
  if [ "${GLOBAL_STACK_RELOAD_FLUTTER3:-}" = "true" ]; then
    echo -e "\nReloading flutter ${FLUTTER_VERSION:-} ..."
    rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter.$([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}")"
    fvm remove "${FLUTTER_VERSION:-}" 2>/dev/null || rm -rf "${FVM_CACHE_PATH}/versions/${FLUTTER_VERSION:-}"
  fi
```

**What gets deleted**: version marker + the FVM-managed Flutter version directory.

---

## 6. RELOAD_ALL Interaction

### 6.1 Current behavior (unchanged by this spec)

`RELOAD_ALL=true` triggers `global-stack-base-reload-all.sh` which runs on the `00base` container. Looking at the base script, it clears the shared `tools/versions/` and `tools/successes/` directories when the version changes or RELOAD_ALL is true. This effectively forces all runtimes to reinstall by making their version-marker checks fail.

**Implication**: this spec does NOT add `|| RELOAD_ALL` guards to individual runtime startup scripts. The base-layer mechanism already handles the "nuke everything" case. Adding `|| RELOAD_ALL` to every runtime script would be redundant and create maintenance burden.

**Exception**: if the user decides `RELOAD_ALL` should directly trigger a runtime reload without relying on the base-layer (e.g., when running a single container without 00base) — see Challenge §9.1.

### 6.2 Individual variable interaction pattern

Within each startup script, the pattern is:
- In install mode: `if [ "${RELOAD_MANAGER}" = "true" ]` — no OR with ALL needed (base handles it)
- In setup mode: `if [ "${RELOAD_VERSION}" = "true" ]` — same

RELOAD_MANAGER in setup mode still guards reinstall logic (already present in pyenv-start.sh and rbenv-start.sh on lines 109/133/104/117). This remains as a "cascading reload" path: setting the manager-level reload on a tier-03 container also forces reinstall of that version.

---

## 7. Success and Version Marker Names

Full inventory of markers that must be deleted to force reinstall, per runtime:

### 7.1 Node / NVM

| Scope | Marker type | File path | Deleted by |
|---|---|---|---|
| Manager (tier 02) | Success | `tools/successes/nvm` | `RELOAD_NVM` |
| Manager (tier 02) | Version | `tools/versions/nvm` | `RELOAD_NVM` |
| Manager (tier 02) | All node successes | `tools/successes/node*` | `RELOAD_NVM` |
| Manager (tier 02) | All node versions | `tools/versions/node*` | `RELOAD_NVM` |
| Version (tier 03) | Success | `tools/successes/node.<VERSION_AS>` | unconditionally at startup |
| Version (tier 03) | Version marker | `tools/versions/node.<VERSION_AS>` | `RELOAD_NODE<N>` (new) |
| Version (tier 03) | NVM install dir | `${NVM_DIR}/versions/node/<full_version>` | NOT deleted by per-version reload |

Note: `VERSION_AS` values: `22`, `24`, `26`, `edge`
Example: `tools/versions/node.22`, `tools/successes/node.22`

### 7.2 Java / SDKMAN

| Scope | Marker type | File path | Deleted by |
|---|---|---|---|
| Manager (tier 02) | Success | `tools/successes/sdkman` | `RELOAD_SDKMAN` |
| Manager (tier 02) | Version | `tools/versions/sdkman` | `RELOAD_SDKMAN` |
| Manager (tier 02) | All java successes | `tools/successes/java*` | `RELOAD_SDKMAN` |
| Manager (tier 02) | All java versions | `tools/versions/java*` | `RELOAD_SDKMAN` |
| Version (tier 03) | Success | `tools/successes/java.<VERSION_AS>` | unconditionally at startup |
| Version (tier 03) | Version marker | `tools/versions/java.<VERSION_AS>` | `RELOAD_JAVA<N>` (new) |
| Version (tier 03) | SDKMAN candidate dir | `${SDKMAN_DIR}/candidates/java/${JAVA_VERSION}` | `RELOAD_JAVA<N>` (new) |

Note: `VERSION_AS` values: `17`, `21`, `25`, `26`
Example: `tools/versions/java.17`, `tools/successes/java.25`

### 7.3 Python / PyEnv

| Scope | Marker type | File path | Deleted by |
|---|---|---|---|
| Manager (tier 02) | Success | `tools/successes/pyenv` | `RELOAD_PYENV` |
| Manager (tier 02) | Version | `tools/versions/pyenv` | `RELOAD_PYENV` |
| Manager (tier 02) | All python successes | `tools/successes/python*` | `RELOAD_PYENV` |
| Manager (tier 02) | All python versions | `tools/versions/python*` | `RELOAD_PYENV` |
| Version (tier 03) | Success | `tools/successes/python.<VERSION_AS>` | unconditionally at startup |
| Version (tier 03) | Version marker | `tools/versions/python.<VERSION_AS>` | `RELOAD_PYTHON<N>` (new) |
| Version (tier 03) | PyEnv install dir | `${PYENV_ROOT}/versions/${PYTHON_VERSION}` | `RELOAD_PYTHON<N>` (new) |

Note: `VERSION_AS` value: `3` only
Example: `tools/versions/python.3`, `tools/successes/python.3`

### 7.4 Ruby / RbEnv

| Scope | Marker type | File path | Deleted by |
|---|---|---|---|
| Manager (tier 02) | Success | `tools/successes/rbenv` | `RELOAD_RBENV` (renamed from RELOAD_RUBY) |
| Manager (tier 02) | Version | `tools/versions/rbenv` | `RELOAD_RBENV` |
| Manager (tier 02) | All ruby successes | `tools/successes/ruby*` | `RELOAD_RBENV` |
| Manager (tier 02) | All ruby versions | `tools/versions/ruby*` | `RELOAD_RBENV` |
| Manager (tier 02) | Fastlane version | `tools/versions/fastlane` | `RELOAD_RBENV` |
| Version (tier 03) | Success | `tools/successes/ruby.<VERSION_AS>` | unconditionally at startup |
| Version (tier 03) | Version marker | `tools/versions/ruby.<VERSION_AS>` | `RELOAD_RUBY<N>` (new) |
| Version (tier 03) | RbEnv install dir | `${RBENV_ROOT}/versions/${RBENV_VERSION}` | `RELOAD_RUBY<N>` (new) |

Note: `VERSION_AS` values: `3`, `4`
Example: `tools/versions/ruby.3`, `tools/successes/ruby.4`

### 7.5 Flutter / FVM

| Scope | Marker type | File path | Deleted by |
|---|---|---|---|
| Manager (tier 02) | Success | `tools/successes/fvm` | `RELOAD_FVM` |
| Manager (tier 02) | All flutter successes | `tools/successes/flutter*` | `RELOAD_FVM` |
| Manager (tier 02) | All flutter versions | `tools/versions/flutter*` | `RELOAD_FVM` |
| Version (tier 03) | Success | `tools/successes/flutter.<VERSION_AS>` | unconditionally at startup |
| Version (tier 03) | Version marker | `tools/versions/flutter.<VERSION_AS>` | `RELOAD_FLUTTER3` (bug fix) |
| Version (tier 03) | FVM version dir | `${FVM_CACHE_PATH}/versions/${FLUTTER_VERSION}` | `RELOAD_FLUTTER3` (bug fix) |

Note: `VERSION_AS` value: `3`

---

## 8. Implementation Order (Risk-Ranked)

Order by: lowest blast-radius first, then complexity.

| Priority | Change | Risk | Reason |
|---|---|---|---|
| 1 | `.env` — add new vars (all of them) | Very low | Additive only, all default to `false` |
| 2 | Flutter bug fix (`fvm-start.sh` setup mode) | Low | Isolated fix; compose already wired |
| 3 | Node compose + `nvm-start.sh` | Low | Additive only; NVM is well-understood |
| 4 | Java compose + `sdkman-start.sh` | Low | Additive only; SDKMAN setup mode not modified for existing path |
| 5 | Python compose + `pyenv-start.sh` | Medium | Additive; existing RELOAD_PYENV logic untouched in setup mode |
| 6 | Ruby — all three layers | High | Renames existing `RELOAD_RUBY` var; requires coordinated update across `.env`, `02rbenv` compose, both tier-03 composes, and `rbenv-start.sh` |

**Ruby is the highest-risk change** because it retires `GLOBAL_STACK_RELOAD_RUBY` in favor of split vars. All three files (`02rbenv/docker-compose.yaml`, `03ruby3/docker-compose.yaml`, `03ruby4/docker-compose.yaml`) plus the startup script must be updated atomically — a partial update leaves the system in an inconsistent state where `RELOAD_RUBY=true` would have no effect at all.

---

## 9. Challenge Section — Open Questions for the User

### 9.1 Should RELOAD_ALL cascade into runtime startup scripts?

**Current**: `RELOAD_ALL` only triggers base cleanup. Individual runtime RELOAD vars are independent.

**Question**: Should setting `RELOAD_ALL=true` also trigger a full reinstall of every runtime (equivalent to setting all individual RELOAD vars to true)? Or is the current behavior correct — base cleanup alone is sufficient, and users who want to fully reinstall everything should use `make hard-restart` instead?

**Impact**: If yes — add `|| [ "${GLOBAL_STACK_RELOAD_ALL:-}" = "true" ]` to every RELOAD check in every startup script. If no — no change needed.

### 9.2 Ruby naming: should RELOAD_RUBY be retired or kept as an alias?

**Current state**: `GLOBAL_STACK_RELOAD_RUBY=false` is the only Ruby reload var. Both the tier 02 manager (`02rbenv`) and the tier 03 versions check it.

**This spec proposes**: split into `RELOAD_RBENV` (manager) + `RELOAD_RUBY3` / `RELOAD_RUBY4` (versions).

**Risk**: any existing usage of `RELOAD_RUBY=true` in scripts, `.env.local`, runbooks, or personal notes stops working after the rename.

**Alternative A**: keep `RELOAD_RUBY` as a "nuke everything Ruby" shortcut that acts like a combined `RELOAD_RBENV + RELOAD_RUBY3 + RELOAD_RUBY4`, add the new granular vars on top. More backward-compatible but `RELOAD_RUBY` semantics become unclear (does it reload the manager? the versions? both?).

**Alternative B** (this spec's recommendation): rename to `RELOAD_RBENV` for the manager and use `RELOAD_RUBY3`/`RELOAD_RUBY4` for versions. Clean but breaking.

**Decision needed**: A or B?

### 9.3 RELOAD_PHPMYADMIN naming — is this intentional?

`GLOBAL_STACK_RELOAD_PHPMYADMIN=false` exists in `.env` but the service is `04phpmyadmin` (not phpMyAdmin the PHP framework). The naming is slightly inconsistent with the pattern (`PHPMYADMIN` vs expected `PHP_MYADMIN` or just the service name). This spec does not change this variable but flags it for awareness.

### 9.4 Should RELOAD_PYTHON3 be named RELOAD_PYTHON3 or RELOAD_PYTHON?

Currently there is only one Python runtime: `03python3`. The version-specific var could be:
- `RELOAD_PYTHON3` (matches the service name `03python3`) — consistent with `RELOAD_PHP8_2` pattern
- `RELOAD_PYTHON` (generic, since there's only one) — simpler but inconsistent

This spec uses `RELOAD_PYTHON3`. If a `03python3.12` or similar service is ever added, the naming convention would already be established.

### 9.5 Should per-version reload also delete the NVM/pyenv/rbenv installed binary?

For Node: the per-version reload currently only deletes the version marker, causing a re-run of the setup script (package installs, project-specific setup). The actual `nvm install` step is skipped if the NVM version directory already exists.

**Question**: should `RELOAD_NODE22=true` also delete `${NVM_DIR}/versions/node/<full_version>` to force a full re-download of Node itself? Or is it sufficient to just re-run the setup/packages step?

Currently the answer is "only delete the marker" (lighter reload). Full package re-download requires `RELOAD_NVM`.

Same question applies for PyEnv (`${PYENV_ROOT}/versions/${PYTHON_VERSION}`) and RbEnv (`${RBENV_ROOT}/versions/${RBENV_VERSION}`).

This spec includes the deletion of the installed binary directory for Python (pyenv) and Ruby (rbenv) because they're more likely to need a clean install. For Node it omits it (NVM versions are smaller and faster to reinstall). The user should decide the preferred behavior.

For Java, this spec includes deleting the SDKMAN candidate directory because SDKMAN's install guard checks the directory — there's no choice.

### 9.6 node26-bin directory gap — FIXED

`docker/config/dist/bin/node26-bin/` was missing entirely. The nvm-start.sh calls `global-stack-nvm-node26-setup.sh` (line 102), `global-stack-nvm-node26-setup-overrides.sh` (line 106), and `global-stack-nvm-node26-setup-project.sh` (line 118) unconditionally whenever `NODE_VERSION_AS=26`. Without these scripts in `/usr/local/bin/`, `03node26` would fail on every fresh container start with "command not found", writing an error marker and staying permanently unhealthy.

**Fixed 2026-05-17**: Created all 3 scripts in `docker/config/dist/bin/node26-bin/` by copying the node24-bin pattern and renaming the error-message strings to `node26`. Also affects `local.05php8-4-n-node26-n-...` which uses `NODE_VERSION_AS=26`.

---

## 10. Testing Checklist

After implementing, verify each change:

### 10.1 .env additions (for each new var)
- [ ] `grep RELOAD_NODE22 .env` — returns the new var with `=false`
- [ ] `bin/env-scan.sh --dry-run` — no errors, new vars propagate to `.env.local`
- [ ] `docker compose --env-file .env.local config` — no unresolved variable warnings

### 10.2 Compose file changes
For each updated compose file:
- [ ] `docker compose --env-file .env.local config` passes cleanly
- [ ] `grep RELOAD /stack/docker/images/03nodeXX/docker-compose.yaml` shows both `RELOAD_NVM` and `RELOAD_NODE`

### 10.3 Script changes
For each updated startup script:
- [ ] `bash -n <script>` — no syntax errors
- [ ] `shellcheck <script>` — zero warnings (use `${VAR:-}` form for new env vars to avoid `-u` exit on unset)

### 10.4 Functional verification — per runtime

**Node 22 example** (repeat for 24, 26, edge):
1. Start stack normally, wait for `node.22` success marker: `test -f tools/successes/node.22`
2. Note current version: `cat tools/versions/node.22`
3. Set `GLOBAL_STACK_RELOAD_NODE22=true` in `.env.local`
4. Restart only `03node22`: `docker compose --env-file .env.local restart 03node22`
5. Verify: `tools/versions/node.22` is regenerated (same or updated version)
6. Verify: `tools/successes/node.22` is recreated
7. Verify: other Node versions (`node.24`, etc.) are untouched
8. Reset `GLOBAL_STACK_RELOAD_NODE22=false`

**Java 17 example** (repeat for 21, 25, 26):
1-8: Same pattern. Step 5 additionally verify `${SDKMAN_DIR}/candidates/java/<version>` directory exists (was removed and recreated by sdk install).

**Python 3**:
1-8: Same pattern. Additionally verify `${PYENV_ROOT}/versions/<python_version>` is recreated.

**Ruby 3/4**:
- After Ruby rename: verify `RELOAD_RUBY=true` no longer has any effect (confirms old var is retired)
- Verify `RELOAD_RBENV=true` clears `tools/successes/rbenv` and `tools/versions/rbenv`
- Verify `RELOAD_RUBY3=true` only affects `03ruby3`, not `03ruby4`
- Verify `RELOAD_RUBY4=true` only affects `03ruby4`, not `03ruby3`

**Flutter 3 bug fix**:
1. Set `GLOBAL_STACK_RELOAD_FLUTTER3=true` in `.env.local`
2. Restart `03flutter3`
3. Verify `tools/versions/flutter.3` is regenerated (was previously unchanged — this confirms the bug fix)
4. Reset to false

### 10.5 Regression check — manager-only reload still works

After per-version changes, verify the existing manager-level reloads still function:
- [ ] `RELOAD_NVM=true` still clears `tools/successes/nvm` AND all `tools/successes/node.*`
- [ ] `RELOAD_SDKMAN=true` still clears `tools/successes/sdkman` AND all `tools/successes/java.*`
- [ ] `RELOAD_PYENV=true` still clears `tools/successes/pyenv` AND triggers version reinstall in setup mode
- [ ] `RELOAD_RBENV=true` (after rename) still clears `tools/successes/rbenv` AND all `tools/successes/ruby.*`

---

## 11. Files to Touch — Complete List

```
.env                                                         # add new RELOAD vars
.env.local                                                   # updated by env-scan.sh after .env changes

docker/images/03node22/docker-compose.yaml                   # add RELOAD_NODE mapping
docker/images/03node24/docker-compose.yaml                   # add RELOAD_NODE mapping
docker/images/03node26/docker-compose.yaml                   # add RELOAD_NODE mapping
docker/images/03nodeedge/docker-compose.yaml                 # add RELOAD_NODE mapping
docker/images/03java17-zulu/docker-compose.yaml              # add RELOAD_JAVA mapping
docker/images/03java21-zulu/docker-compose.yaml              # add RELOAD_JAVA mapping
docker/images/03java25-zulu/docker-compose.yaml              # add RELOAD_JAVA mapping
docker/images/03java26-zulu/docker-compose.yaml              # add RELOAD_JAVA mapping
docker/images/03python3/docker-compose.yaml                  # add RELOAD_PYTHON mapping
docker/images/03ruby3/docker-compose.yaml                    # replace RELOAD_RUBY with split vars
docker/images/03ruby4/docker-compose.yaml                    # replace RELOAD_RUBY with split vars
docker/images/02rbenv/docker-compose.yaml                    # replace RELOAD_RUBY with RELOAD_RBENV

docker/config/dist/bin/nvm-bin/global-stack-nvm-start.sh    # add setup-mode reload block
docker/config/dist/bin/sdkman-bin/global-stack-sdkman-start.sh  # add setup-mode reload block
docker/config/dist/bin/pyenv-bin/global-stack-pyenv-start.sh    # add setup-mode reload block
docker/config/dist/bin/rbenv-bin/global-stack-rbenv-start.sh    # rename RELOAD_RUBY→RELOAD_RBENV in install mode + add setup-mode reload
docker/config/dist/bin/fvm-bin/global-stack-fvm-start.sh    # fix RELOAD_FLUTTER3 bug
```

Total: 5 startup scripts + 13 compose files + `.env`.

---

*Spec authored: 2026-05-17. Based on direct analysis of phpbrew-start.sh, fvm-start.sh, nvm-start.sh, sdkman-start.sh, pyenv-start.sh, rbenv-start.sh, and all related compose files.*
