# env-update — Version Update Checker

`bin/env-update.sh` scans `.env` for `@todo env-update` annotations, fetches
latest versions from upstream APIs, auto-applies patch-level bumps to `.env` and
matching Dockerfile ARGs, and reports everything that needs manual attention.

---

## Quick Start

```bash
bin/env-update.sh                          # fetch + auto-apply safe updates
bin/env-update.sh --dry-run                # fetch + report only, no writes
bin/env-update.sh --no-auto-apply          # fetch everything, apply nothing
bin/env-update.sh --filter=NODE            # only vars whose name matches NODE
bin/env-update.sh --type=npm,pypi          # only run these fetcher types
bin/env-update.sh --offline                # use cache only, no network
bin/env-update.sh --no-cache               # bypass cache reads, re-fetch all
bin/env-update.sh --debug                  # verbose diagnostic output
```

---

## CLI Options

| Option                 | Description                                                               |
| ---------------------- | ------------------------------------------------------------------------- |
| `--dry-run`            | Report changes, write patch file, but do not modify any files             |
| `--offline`            | Use cached results only — no network requests                             |
| `--no-cache`           | Skip cache reads; always re-fetch (still writes to cache)                 |
| `--cache-ttl=N`        | Cache TTL in seconds (default: 3600)                                      |
| `--filter=PATTERN`     | Bash regex; only process `.env` vars whose name matches                   |
| `--type=TYPES`         | Comma-separated fetcher types to run (see Fetcher Types below)            |
| `--no-auto-apply`      | Fetch all; report everything but apply nothing                            |
| `--no-override`        | Skip records marked `(override)` entirely                                 |
| `--patch-file=PATH`    | Override patch output path (default: `/tmp/env-update-<ts>.patch`)     |
| `--report-file=PATH`   | Override JSON report path (default: `/tmp/env-update-<ts>.json`)       |
| `--github-token=TOKEN` | GitHub API token (overrides `GITHUB_TOKEN` / `GLOBAL_STACK_GITHUB_TOKEN`) |
| `--debug`              | Enable `[DEBUG]` output on stderr                                         |
| `--help`               | Show help                                                                 |

Set `GLOBAL_STACK_GITHUB_TOKEN` in `.env.local` to avoid GitHub rate-limits on
unauthenticated runs (60 req/h → 5000 req/h with token).

---

## Annotation Syntax

Annotations are comments in `.env` that appear on the line immediately before the
variable assignment they describe.

### New (preferred) format

```
# @todo env-update [FLAGS] TYPE:IDENTIFIER [HINT] VERSION
VAR_NAME=VALUE
```

### Legacy format (still parsed, auto-migrated)

```
# @todo env-update NAME URL1 [URL2 ...] VERSION
VAR_NAME=VALUE
```

Run `bin/migrate-annotations.sh` to convert legacy lines to the new format.

### Full example

```bash
# @todo env-update github:nodejs/node:22 22.14.0
GLOBAL_STACK_NODE22_VERSION=22.14.0

# @todo env-update (channel:rc) github:php/php-src:8.5 8.5.0RC2
GLOBAL_STACK_PHP85_VERSION=8.5.0RC2

# @todo env-update (channel:unstable) npm:typescript 5.9.0-beta
GLOBAL_STACK_TYPESCRIPT_VERSION=5.9.0-beta

# @todo env-update (override) dockerhub:_/postgres:16 16.3
GLOBAL_STACK_POSTGRES16_VERSION=16.3

# @todo env-update (skip:frozen-upstream) github:owner/repo 1.2.3
GLOBAL_STACK_FROZEN_VERSION=1.2.3
```

---

## Fetcher Types

| Type         | Identifier format                  | Description                                                                    |
| ------------ | ---------------------------------- | ------------------------------------------------------------------------------ |
| `dockerhub`  | `namespace/image` or `_/image`     | Docker Hub tag list (v2 API)                                                   |
| `quay`       | `org/image`                        | Quay.io tag list                                                               |
| `github`     | `owner/repo` or `owner/repo:MAJOR` | GitHub Releases + Tags API                                                     |
| `codeberg`   | `owner/repo`                       | Codeberg (Gitea) Releases + Tags API                                           |
| `npm`        | `package` or `@scope/package`      | npm registry — npm view CLI first (correct Node version via nvm), API fallback |
| `pypi`       | `PackageName`                      | PyPI JSON API — pip CLI first (correct Python version via pyenv), API fallback |
| `rubygems`   | `gem-name`                         | RubyGems.org — gem CLI first (correct Ruby version via rbenv), API fallback    |
| `pecl`       | `extension`                        | PECL XML REST API                                                              |
| `pecl-git`   | `https://github.com/owner/repo`    | Git SHA tracker; suggests PECL promotion                                       |
| `sdkman`     | `candidate` or `candidate:MAJOR`   | SDKMAN CLI first, REST API fallback                                            |
| `sdkmanager` | `build-tools`, `ndk-bundle`, etc.  | Android sdkmanager `--list` parser; channel filtering supported                |
| `url`        | Any URL                            | Tiered HTML/JSON scraper (see url flags)                                       |

### Type auto-detection from legacy annotations

When a URL is present in a legacy annotation, the type is inferred:

| URL domain                     | Inferred type         |
| ------------------------------ | --------------------- |
| `hub.docker.com/_/IMAGE`       | `dockerhub:_/IMAGE`   |
| `hub.docker.com/r/NS/IMAGE`    | `dockerhub:NS/IMAGE`  |
| `quay.io/repository/ORG/IMAGE` | `quay:ORG/IMAGE`      |
| `github.com/OWNER/REPO`        | `github:OWNER/REPO`   |
| `codeberg.org/OWNER/REPO`      | `codeberg:OWNER/REPO` |
| `npmjs.com/package/PKG`        | `npm:PKG`             |
| `pypi.org/project/PKG`         | `pypi:PKG`            |
| `rubygems.org/gems/GEM`        | `rubygems:GEM`        |
| `pecl.php.net/package/EXT`     | `pecl:EXT`            |
| anything else                  | `url:URL`             |

---

## Annotation Flags

Flags are parenthesised tokens placed before the `TYPE:IDENTIFIER` on the annotation
line. Multiple flags can be combined.

### Version selection flags

| Flag              | Supported types   | Description                                                                                                                                                                                                                                                                           |
| ----------------- | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `(channel:VALUE)` | All fetcher types | Track a specific channel. VALUE options: `stable` (default), `unstable` (any pre-release), `rc`, `beta`, `alpha`, `preview`, `pre`, `nightly`, `dev`, `canary`, `snapshot`, `next`, `edge`, `experimental`, `insiders`, `milestone`, `ea`. Comma-separated for OR: `channel:rc,beta`. |

**Channel matching rules** — a version is considered to match channel `rc` if the
keyword appears as a distinct token in the version string (case-insensitive), handling
all common formats: `1.0.0-rc`, `1.0.0rc`, `1.0.0-rc2`, `1.0.0rc2`, `1.0.0-rc.2`.

**Promotion rule** — when a `(channel:rc)` (or any non-stable channel) annotation is tracking
a pre-release version and the stable version has since surpassed it (e.g. `2.0.0` is released
while tracking `2.0.0-rc3`), the stable version is promoted as the main result. No pre-release
hint is shown — the tracked pre-release is considered obsolete.

### Major version pinning

| Pattern                           | Behaviour                                                     |
| --------------------------------- | ------------------------------------------------------------- |
| `github:owner/repo:MAJOR`         | Only consider tags matching `MAJOR.x.y`; pages up to 300 tags |
| `github:owner/repo:MAJOR.MINOR`   | Pin to `MAJOR.MINOR.x`                                        |
| `dockerhub:namespace/image:MAJOR` | Pin to `MAJOR.x`; emits `[HOLD]` when a newer major appears   |
| `sdkman:candidate:MAJOR`          | Pin to `MAJOR.x` SDK version                                  |
| `sdkman:candidate:MAJOR.MINOR`    | Pin to `MAJOR.MINOR.x` SDK version (e.g. `maven:3.9`)         |

### Tag manipulation flags

These flags apply to tag lists before version selection. All supported by `github`,
`dockerhub`, `quay`; `(tag-filter)` and `(tag-exclude)` also supported by `codeberg`.

| Flag                     | Description                                                          |
| ------------------------ | -------------------------------------------------------------------- |
| `(tag-filter:REGEX)`     | Keep only tags matching ERE regex                                    |
| `(tag-exclude:REGEX)`    | Drop tags matching ERE regex                                         |
| `(tag-strip-prefix:STR)` | Strip literal prefix from each tag before comparison                 |
| `(tag-strip-suffix:STR)` | Strip literal suffix from each tag before comparison                 |
| `(tag-extract:REGEX)`    | Extract capture group 1 from each tag via perl; discard non-matching |
| `(tag-replace:FROM:TO)`  | Replace all occurrences of FROM with TO in each tag                  |

Example — Ruby uses underscore tags (`v3_4_3`); `tag-extract` converts them:

```bash
# @todo env-update (tag-extract:^v([0-9]+_[0-9]+_[0-9]+)$) (tag-replace:_:.) github:ruby/ruby 3.4.3
GLOBAL_STACK_RUBY_VERSION=3.4.3
```

### URL fetcher flags

Only apply to `url:` type annotations.

| Flag                          | Description                                                                                                                                                          |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `(fetch-extract:REGEX)`       | Fetch the URL body, collect all capture group 1 matches via perl, return the highest via `sort -V`. Takes full priority over all other tiers.                        |
| `(fetch-json:JQ_PATH)`        | Fetch URL as JSON and extract via jq expression. Takes full priority.                                                                                                |
| `(url-probe:PATH1,PATH2,...)` | Probe URL paths for each Ubuntu codename starting from the current and falling back to progressively older releases. Used for repo availability (e.g. CRI-O, kubic). |
| `(url-probe-depth:N)`         | How many codenames back to probe (default: 6).                                                                                                                       |

URL path templates for `url-probe`:

- `{codename}` → Ubuntu codename (e.g. `noble`)
- `{codename-version}` → Ubuntu version number (e.g. `24.04`)

Example:

```bash
# @todo env-update (url-probe:stable/xUbuntu_{codename-version},unstable/xUbuntu_{codename-version}) url:https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable 1.0.0
GLOBAL_STACK_CRIO_REPO_CHANNEL=stable/xUbuntu_24.04
```

### Docker Hub specific flags

| Flag                 | Description                                                                 |
| -------------------- | --------------------------------------------------------------------------- |
| `(tag-suffix:VALUE)` | Filter to tags ending with `-VALUE` (e.g. `developer` for `18.3-developer`) |

Docker Hub also auto-detects:

- **Alpine suffix** — if current version has `-alpine3.NN`, only propose tags with the same alpine version suffix
- **Ubuntu codename** — if current version contains a codename (e.g. `jammy`), only propose tags with the same codename; emits upgrade hint when a newer codename is available on Docker Hub

### Review control flags

| Flag                     | Description                                                                                                  |
| ------------------------ | ------------------------------------------------------------------------------------------------------------ |
| `(override)`             | Always fetch for visibility but never auto-apply. Shown as `[OVRRD]`. Use for intentionally pinned versions. |
| `(skip:REASON)`          | Skip this variable entirely. Shown as `[SKIP]`.                                                              |
| `(manual)`               | Always require manual review regardless of what is fetched. Shown as `[MANUAL]`.                             |
| `(depends-on:VAR:major)` | Hold the update if the proposed major differs from VAR's current major.                                      |
| `(pecl-ref:NAME)`        | Override the PECL extension name used for PECL promotion check in `pecl-git` annotations.                    |

### Annotation-only metadata flags

These flags are written by `bin/migrate-annotations.sh` and are preserved in `.env` as
informational metadata. `env-update.sh` does not act on them at runtime — they are
silently ignored.

| Flag                    | Origin    | Purpose                                                                                                                                                                           |
| ----------------------- | --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `(propagate)`           | Migration | Marks variables that need to be updated in multiple places (Dockerfiles, other env files). Signals to future tooling that a version bump should propagate beyond `.env`.          |
| `(compat:RUNTIME>=X.Y)` | Migration | Compatibility constraint carried over from legacy hint text (e.g. `compat:php>=8.0`, `compat:node<=14.21`). Purely informational — visible in the annotation for human reference. |

### Version output flags

| Flag                      | Description                                                      |
| ------------------------- | ---------------------------------------------------------------- |
| `(version-prefix:PREFIX)` | Prepend PREFIX to the proposed version string before comparison. |

---

## Auto-apply Logic

A proposed version is auto-applied (`[AUTO]`) when all of the following hold:

1. No manual/skip/override flag is set
2. The proposed version is strictly **newer** than current (by `sort -V`)
3. The proposed is not a pre-release while current is stable (those become `[HOLD]`)
4. No `(depends-on)` constraint blocks it
5. The type is not `sdkmanager` (always manual) or `sdkman` with multi-major identifier

When auto-applied, both `.env` and every matching `ARG VAR_NAME=` line in
`docker/images/*/Dockerfile` are updated in-place.

### Decision outcomes

| Symbol     | Meaning                                                                                        |
| ---------- | ---------------------------------------------------------------------------------------------- |
| `[AUTO ]`  | Version bumped automatically in `.env` + Dockerfiles                                           |
| `[MANUAL]` | Update found; requires human review before applying                                            |
| `[HOLD ]`  | Pre-release proposed against stable current; review required                                   |
| `[SKIP ]`  | No check performed (flagged, unversioned, or no change)                                        |
| `[FLOAT]`  | Version is a floating ref (`master`, `latest`, `nightly`, etc.) — always current by definition |
| `[WARN ]`  | API/network error; could not fetch                                                             |
| `[NORES]`  | Fetch succeeded but returned no usable version                                                 |
| `[ERROR]`  | Hard failure                                                                                   |
| `[OVRRD]`  | Override-pinned; fetched for visibility only                                                   |
| `[UBUNTU]` | Ubuntu codename alignment update                                                               |

Pre-release hint lines (`↳`) are printed below any `[AUTO]`, `[MANUAL]`, `[HOLD]`,
`[WARN]`, `[NORES]`, or `[SKIP]` line for a variable where a pre-release hint was
recorded. They are purely informational.

---

## SDKMAN Notes

- Java requires the SDKMAN CLI to be available (`SDKMAN_DIR` must point to a working
  installation). The REST API does not support Java distribution versioning.
- Non-java candidates try CLI first, fall back to the SDKMAN REST API.
- Identifiers without a major constraint (`sdkman:gradle`) infer the major from the
  current version. Use `sdkman:gradle:8` to pin explicitly.
- All SDKMAN multi-major results are `[MANUAL]` — the developer must choose the
  distribution and run `sdk install` manually.

---

## pecl-git Notes

Use `pecl-git:https://github.com/owner/repo` for PHP extensions installed from a
GitHub commit SHA (not from a PECL release). The fetcher:

1. Fetches the latest commit SHA from the repo's default branch
2. Checks PECL for a stable release of the same extension
3. If stable PECL release exists and its release date is newer than the commit date,
   emits a `[PROMOTE]` suggestion to switch from git SHA to semver

Add `(pecl-ref:EXTNAME)` if the extension name on PECL differs from the repo name.

---

## Cache

Cache lives in `/tmp/global-stack-env-update-cache/`. Each entry is keyed by
`type:identifier:flags` and expires after `--cache-ttl` seconds (default 3600).

```bash
# Bypass all cached results for a fresh run
bin/env-update.sh --no-cache

# Set a shorter TTL for this run
bin/env-update.sh --cache-ttl=300
```

---

## Output Files

After each run two files are written to `/tmp/`:

| File                       | Contents                                        |
| -------------------------- | ----------------------------------------------- |
| `env-update-<ts>.patch` | Unified diff of all auto-applied `.env` changes |
| `env-update-<ts>.json`  | Machine-readable JSON report with all outcomes  |

---

## Annotation Migration

Convert legacy URL-based annotations to the current format:

```bash
bin/migrate-annotations.sh          # migrate + create .env.bak
bin/migrate-annotations.sh --dry-run
bin/migrate-annotations.sh --no-backup
```

The migrator handles all URL patterns listed in the auto-detection table above and
preserves existing flags.

---

## Environment Variables

| Variable                         | Description                                                 |
| -------------------------------- | ----------------------------------------------------------- |
| `GLOBAL_STACK_GITHUB_TOKEN`      | GitHub API token (set in `.env.local`)                      |
| `GLOBAL_STACK_SDKMAN_DIR`        | Path to SDKMAN installation                                 |
| `GLOBAL_STACK_PYENV_ROOT`        | Path to pyenv root                                          |
| `GLOBAL_STACK_NVM_DIR`           | Path to NVM installation                                    |
| `GLOBAL_STACK_ANDROID_HOME`      | Path to Android SDK root                                    |
| `GLOBAL_STACK_DOCKER_TOOLS_PATH` | Base path for tools (NVM, pyenv, etc.)                      |
| `_GS_EU_DEBUG`                   | Set to `true` to enable debug output without `--debug` flag |
| `_GS_EU_CACHE_DIR`               | Override cache directory                                    |
| `_GS_EU_CACHE_TTL`               | Override cache TTL                                          |

---

## Architecture & Internals

### File Structure

Main entry point: `bin/env-update.sh` (~963 lines)

Core modules (`bin/lib/env-update/core/`):
| File | Purpose |
|---|---|
| `parse.sh` | Reads `.env` annotations → populates `_GS_EU_RECORDS_*[]` arrays |
| `diff.sh` | Version comparison (`_gs_eu_semver_compare`), action decision (`_gs_eu_decide_action`) |
| `report.sh` | Terminal output + JSON report writer; all `_gs_eu_log_*` functions |
| `cache.sh` | File-based TTL cache in `/tmp/global-stack-env-update-cache/` |
| `tag_flags.sh` | Tag filter/transform pipeline (tag-filter, tag-exclude, tag-strip-prefix, etc.) |
| `channel.sh` | Channel selection engine; `_gs_eu_channel_select_best()` used by all fetchers |
| `runtime.sh` | Runtime derivation + `_gs_eu_cli_with_fallback()` wrapper for CLI-first fetchers |

Config (`bin/lib/env-update/config/`):
| File | Purpose |
|---|---|
| `prerelease_markers.sh` | Centralized ERE regex fragments for `_gs_eu_is_prerelease()` |
| `codename_map.sh` | Ubuntu codename ↔ version lookup tables |
| `type_map.sh` | URL → type:identifier inference for legacy annotations |

Fetchers (`bin/lib/env-update/fetchers/`):
| File | API or CLI | Channel support | Notes |
|---|---|---|---|
| `github.sh` | API only | Full | Also defines shared utilities: `_gs_eu_version_matches_channel`, `_gs_eu_set_fetch_error`, `_gs_eu_set_prerelease_hint` |
| `dockerhub.sh` | API only | Full | Auto-detects alpine suffix and Ubuntu codename from current version |
| `quay.sh` | API only | Full | Used for Keycloak and Quay-hosted images |
| `codeberg.sh` | API only | Full | Gitea-compatible API |
| `npm.sh` | CLI first (`npm view --json`), API fallback | Full | Runtime: nvm, version from variable name prefix |
| `pypi.sh` | CLI first (`pip index versions --pre`), API fallback | Full | Runtime: pyenv, version from variable name prefix |
| `rubygems.sh` | CLI first (`gem search --versions --all`), API fallback | Full | Runtime: rbenv, version from variable name prefix |
| `pecl.sh` | API only (PECL XML REST) | None | Uses XML stability tags, not version string markers |
| `pecl_git.sh` | GitHub API + PECL API | None | SHA tracker; channel not applicable |
| `sdkman.sh` | CLI-first (`sdk list`), API fallback | Full | Java candidates: CLI only (API blocked); non-Java: CLI then REST API |
| `sdkmanager.sh` | CLI only (`sdkmanager --list`) | Full | No API fallback; always `[MANUAL]` |
| `url.sh` | HTTP fetch (multi-tier) | Partial | channel:nightly handled; other channels via fetch-extract/fetch-json |

### Channel Selection Engine (`core/channel.sh`)

All fetchers use `_gs_eu_channel_select_best(all_versions, channel)` for version selection:

1. Versions are split into stable and pre-release using `_gs_eu_is_prerelease()`
2. Default/stable: highest stable returned; pre-release hint written if newer pre exists
3. Specific channel (rc, beta, etc.): highest matching version returned; stable hint written
4. **Promotion**: if stable > channel match (by semver) → stable is returned, no pre-release hint
5. `channel=unstable`: highest pre-release returned regardless of specific qualifier

**Known exceptions** (use their own selection logic):

- `pecl.sh` — PECL XML provides explicit `<s>stable</s>`/`<s>beta</s>` stability tags
- `sdkman.sh` Java path — Java distribution suffixes (`-tem`, `-zulu`) require distribution-aware selection

### CLI-First Runtime Activation (`core/runtime.sh`)

`_gs_eu_cli_with_fallback(cli_fn, api_fn, env_var, ...)` derives the runtime from the variable name:

- Activates the correct tool version before running the CLI (nvm/pyenv/rbenv)
- Falls back to API on any CLI failure (debug-level log only, not a warning)
- Skipped entirely in `--offline` mode

### Prerelease Detection

`_gs_eu_is_prerelease(version)` in `diff.sh` uses `_GS_EU_PRERELEASE_REGEX` from
`config/prerelease_markers.sh`. Matches (case-insensitive, ERE fragments joined with `|`):

| Category        | Markers                                                                                                            |
| --------------- | ------------------------------------------------------------------------------------------------------------------ |
| Standard SemVer | `alpha`, `beta`, `rc[0-9]*`, `preview`, `pre`, `nightly`, `edge`, `canary`, `snapshot`, `experimental`, `insiders` |
| Python PEP 440  | `\.dev`, `-dev`, `[0-9]a[0-9]`, `[0-9]b[0-9]`                                                                      |
| Maven / Java    | `milestone`, `[.-]m[0-9]`, `-cr[0-9]`, `-ea`                                                                       |
| npm / Node.js   | `-next\.`, `next` (standalone dist-tag version)                                                                    |

### Channel Matching

`_gs_eu_version_matches_channel(version, channel)` in `fetchers/github.sh` (shared by all fetchers):

- `channel=unstable` → delegates to `_gs_eu_is_prerelease()` (matches any prerelease)
- `channel=rc,beta` → comma-separated OR logic; each qualifier matched as a distinct token:
  pattern `(^|[-._[:digit:]])QUALIFIER([[:digit:]._-]|$)`

### Alt-Version / Hint IPC

Fetchers communicate secondary version hints to the display layer via two temp files:

1. **`_GS_EU_ALT_VERSION_FILE`** — per-fetch; fetcher writes `direction:version` (e.g. `also:2.0.0-rc1`)
2. **`_GS_EU_PRERELEASE_HINT_FILE`** — global; dispatch layer translates alt-version entries here after each fetch, applying suppression logic (suppresses if alt is unversioned or not actually newer)

Display: `_gs_eu_print_prerelease_hint()` in `report.sh` prints `↳ VERSION (message)` after each result line.

**Directions:**

- `also` — stable result; hint points at a newer pre-release: `↳ 2.0.0-rc1 (pre-release available — use channel:rc to track)`
- `stable` — channel result; hint points at latest stable: `↳ 1.9.0 (stable)`

### Runtime Variable Prefix Map

Package manager annotations embed the runtime version in the `.env` variable name prefix:

| Prefix                    | Runtime          | Version source                                     |
| ------------------------- | ---------------- | -------------------------------------------------- |
| `GLOBAL_STACK_NODE22_*`   | Node.js via nvm  | `GLOBAL_STACK_NODE22_VERSION`                      |
| `GLOBAL_STACK_NODE24_*`   | Node.js via nvm  | `GLOBAL_STACK_NODE24_VERSION`                      |
| `GLOBAL_STACK_NODEEDGE_*` | Node.js via nvm  | `GLOBAL_STACK_NODEEDGE_VERSION`                    |
| `GLOBAL_STACK_PYTHON3_*`  | Python via pyenv | `GLOBAL_STACK_PYTHON3_VERSION`                     |
| `GLOBAL_STACK_RUBY3_*`    | Ruby via rbenv   | `GLOBAL_STACK_RUBY3_VERSION`                       |
| `GLOBAL_STACK_RUBY4_*`    | Ruby via rbenv   | `GLOBAL_STACK_RUBY4_VERSION`                       |
| `GLOBAL_STACK_JAVA11_*`   | Java via sdkman  | `GLOBAL_STACK_JAVA11_INSTALL_PACKAGE_JAVA_VERSION` |
| `GLOBAL_STACK_JAVA17_*`   | Java via sdkman  | `GLOBAL_STACK_JAVA17_INSTALL_PACKAGE_JAVA_VERSION` |
| `GLOBAL_STACK_JAVA25_*`   | Java via sdkman  | `GLOBAL_STACK_JAVA25_INSTALL_PACKAGE_JAVA_VERSION` |

This prefix is used to activate the correct runtime before CLI-based version checks.

### Global Variable Conventions

All globals use the `_GS_EU_` prefix. All functions use the `_gs_eu_` prefix.

Key record arrays populated by `parse.sh` (indexed 0..N-1):
`_GS_EU_RECORDS_ENV_VAR[]`, `_GS_EU_RECORDS_CURRENT_VERSION[]`, `_GS_EU_RECORDS_TYPE[]`,
`_GS_EU_RECORDS_IDENTIFIER[]`, `_GS_EU_RECORDS_FLAGS[]`, `_GS_EU_RECORDS_CHANNEL[]`,
`_GS_EU_RECORDS_DEPENDS_ON[]`, `_GS_EU_RECORDS_URLS[]`, and more.
