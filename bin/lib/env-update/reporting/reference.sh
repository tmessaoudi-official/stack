#!/bin/bash
# reference.sh — comprehensive reference for env-update (and env-scan).
#
# Exports:   _gs_eu2_show_reference  _gs_eu2_show_reference_matrix
# Sources:   config/defaults.sh  core/records.sh  core/decide.sh  (via main.sh)
# Deps:      bash 4.3+
# Env:       none
#
# Covers: annotation syntax, fetcher types, CLI flags, all annotation flags,
#         per-fetcher deep-dive, decision types, live decision matrix, worked
#         scenarios, and env-scan pipeline reference.
#
# Replaces: annotations-ref.sh (renamed 2026-05-24)
# Called by: main.sh when --reference[=SECTION] is passed

[[ -n "${_GS_EU2_REFERENCE_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_REFERENCE_SH_LOADED=1

# _gs_eu2_show_reference — print the comprehensive reference for env-update.
#
# Args:
#   $1  section — which section(s) to print; one of:
#         all          print every section (default)
#         syntax       annotation format, fetcher types, major hint syntax
#         flags        all global CLI flags, interactions, mutual exclusions
#         annotations  all annotation flags including 9 previously undocumented
#         fetchers     per-fetcher deep-dive: API, auth, quirks, applicable flags
#         decisions    every decision type and what produces / suppresses it
#         matrix       live decision matrix (runs actual engine, no network)
#         scenarios    worked examples per fetcher type
#         env-scan     env-scan phases, flags, propagation, scenarios
# Returns (stdout): human-readable reference text
# Side-effects: none (read-only)
_gs_eu2_show_reference() {
  local _section="${1:-all}"

  # ──────────────────────────────────────────────────────────────────────────
  # SECTION: syntax
  # ──────────────────────────────────────────────────────────────────────────
  if [[ "${_section}" == "all" || "${_section}" == "syntax" ]]; then
    cat << 'SYNTAX_EOF'
env-update reference — SECTION: syntax
────────────────────────────────────────────────────────────────────────────────

ANNOTATION FORMAT
  Every tracked variable requires a comment on the line immediately above it:

    # @todo env-update [FLAGS] TYPE:IDENTIFIER [MAJOR_HINT] CURRENT_VERSION
    VAR=CURRENT_VERSION

  - TYPE:IDENTIFIER   fetcher type + registry path (see FETCHER TYPES below)
  - MAJOR_HINT        optional: pin to a specific major (e.g. 18) or range (18-19)
  - CURRENT_VERSION   the version currently in the env file (drift detection baseline)
  - FLAGS             zero or more parenthesised flags (see ANNOTATION FLAGS below)

  Example:
    # @todo env-update (manual) dockerhub:_/postgres:18 18.3-alpine3.23
    GLOBAL_STACK_POSTGRES18_VERSION=18.3-alpine3.23


FETCHER TYPES
  dockerhub:OWNER/IMAGE[:TAG_FILTER]
    DockerHub image tags. Use '_' for official images (e.g. dockerhub:_/postgres).
    Optional :TAG_FILTER is a major pin (e.g. :18).

  github:OWNER/REPO
    GitHub releases (latest stable, or prerelease if channel=unstable/rc/etc.).

  npm:PACKAGE
    npm registry. Use scoped packages with quotes if needed (e.g. npm:@types/node).

  pypi:PACKAGE
    PyPI package index.

  rubygems:GEM
    RubyGems.org.

  pecl:EXTNAME [(git:owner/repo)]
    PECL PHP extensions. Optional (git:owner/repo) enables HEAD SHA tracking.
    Does not support major_hint or range syntax.

  sdkman:CANDIDATE
    SDKMAN! (Java, Gradle, Maven, Kotlin…). E.g. sdkman:java, sdkman:gradle.

  sdkmanager:PACKAGE
    Android SDK manager packages (e.g. sdkmanager:build-tools).
    Does not support major_hint or range syntax.

  url:URL
    Fetch version string from a raw URL. Supports 4-tier resolution via annotation
    flags: fetch-extract → fetch-json → github-redirect → url-probe → direct fetch.

  quay:OWNER/IMAGE
    Quay.io container registry.

  codeberg:OWNER/REPO
    Codeberg.org releases (Gitea-based forge).

  Note: codeberg and github support (check-tags) for tag-only releases.


MAJOR HINT — PIN OR RANGE
  Single major:   TYPE:IDENTIFIER 18 CURRENT_VERSION
                  → restrict to major 18.x
  Range (low-high): TYPE:IDENTIFIER 18-19 CURRENT_VERSION
                  → use major 18 (LOW) until any 19.x ships, then promote to 19.
                    LOW must be < HIGH (integers only; dotted ranges unsupported).
                    A [FALLBACK] sub-line is emitted while running on LOW.

SYNTAX_EOF
  fi

  # ──────────────────────────────────────────────────────────────────────────
  # SECTION: flags
  # ──────────────────────────────────────────────────────────────────────────
  if [[ "${_section}" == "all" || "${_section}" == "flags" ]]; then
    cat << 'FLAGS_EOF'
env-update reference — SECTION: flags
────────────────────────────────────────────────────────────────────────────────

GLOBAL CLI FLAGS (env-update)

  Mode flags:
    --check              Fetch + report decisions. Does not write any files.
    --apply              Apply AUTO decisions; implies --check.
    --apply-resolve      When combined with --apply: also pin RESOLVED entries
                         (floating refs resolved to concrete versions). Requires --apply.
    --dry-run            With --apply: simulate writes, print what would happen.
    --force-auto         Bypass (manual)/(override)/HOLD gates. Requires
                         --confirm="Confirm override" with --apply. Does NOT
                         override FROZEN (skip:) or LOCK records. Does NOT promote
                         RESOLVED to AUTO — use --apply-resolve for that.

  Input / scope flags:
    --env-file=PATH      Override env file path (default: .env).
    --filter=REGEX       Process only vars whose name matches REGEX (case-insensitive).
    --no-cache           Bypass HTTP cache (forces fresh fetch for every record).
    --cache-ttl=N        Cache TTL in seconds (default: 3600).
    --scan               After --apply, run bin/env-scan.sh to propagate updates
                         to .env.local and Dockerfiles.

  Output flags:
    --format=text|json   Output format (default: text).
    --changes-only       Suppress up-to-date SKIP records from check output.
    --no-notes           Suppress (note:TEXT) sub-lines.
    --no-drift           Suppress [DRIFT]/[REPLACE-DRIFT] sub-lines.
    --no-fail            Exit 0 even when ERROR decisions exist. Only suppresses
                         fetch-ERROR exits — backup and infrastructure errors remain fatal.
    --with-tags          Show the full tag list for each record (debug mode).
    --dump               Dump all parsed records as JSON; mutually exclusive with
                         --check and --apply.

  Channel flags:
    --unstable[=full|info]
                         full: include prerelease in AUTO decisions.
                         info: show [PRE-RELEASE] sub-lines but AUTO = stable only.
                         (no value): equivalent to --unstable=full.
    --stable[=full|info]
                         full: force stable-only even when annotation uses (channel:rc).
                         info: show channel sub-lines, use annotation channel for AUTO.
                         (no value): equivalent to --stable=full.
                         NOTE: --stable=full + --unstable=full is banned.

  Version lookup:
    --reference[=SECTION]
                         Print this reference and exit (no env file required).
                         Sections: all syntax flags annotations fetchers decisions
                                   matrix scenarios env-scan
    --version            Print env-update version and exit.
    --help               Print flag summary and exit.

  Mutual exclusions:
    --dump    vs --check, --apply
    --stable=full vs --unstable=full
    --apply-resolve requires --apply (standalone exits non-zero)

  Environment variables:
    _GS_EU2_TALLY_FORCE=1
      Environment variable (not a CLI flag). Bypasses the stderr TTY gate so the
      live running tally displays even when stderr is not a terminal.
      Use cases: CI pipelines (GitHub Actions, GitLab CI where stderr has no TTY),
      terminal multiplexers (tmux, screen) that don't expose TTY on stderr,
      any non-interactive shell wanting live progress during a long --check run.
      Default: unset (TTY gate active).
      Note: the column-width gate (--tally=auto requires >= 130 cols) still applies
      unless combined with --tally=full.

FLAGS_EOF
  fi

  # ──────────────────────────────────────────────────────────────────────────
  # SECTION: annotations
  # ──────────────────────────────────────────────────────────────────────────
  if [[ "${_section}" == "all" || "${_section}" == "annotations" ]]; then
    cat << 'ANNO_EOF'
env-update reference — SECTION: annotations
────────────────────────────────────────────────────────────────────────────────

ANNOTATION FLAGS (parenthesised, space-separated, after the @todo keyword)

  Behaviour flags:
    (manual)          Suppress AUTO; decision is MANUAL (human gate).
                      --force-auto bypasses this.
    (override)        Alias for (manual). Same effect.
    (skip:REASON)     Permanently skip this record. Emits FROZEN decision.
                      Immune to --force-auto.
    (lock:REASON)     Lock the current version; annotation CURRENT_VERSION may
                      still be updated by --apply but VAR= is never changed.
                      Immune to --force-auto.

  NOTE: (hold) is NOT a recognized annotation flag. Writing (hold) in an
  annotation corrupts the positional field parsing (it is treated as the
  MAJOR_HINT token). The HOLD decision is produced automatically when the
  proposed version would cross a major_hint boundary (e.g., hint=3 and
  proposed=4.0.0 → HOLD). To require a manual gate, use (manual) or (override).

  Metadata / sub-line flags:
    (note:TEXT)       Attach a human-readable note sub-line. Suppressed by --no-notes.
    (channel:NAME)    Override fetch channel: stable, rc, beta, alpha, nightly, unstable.
                      --stable=full and --unstable=full may override this.

  GitHub-specific:
    (check-tags)      Merge tags API response with releases API (catches tag-only releases).
                      Also available for: codeberg.
    (tag-filter:REGEX)      Include only tags matching REGEX.
    (tag-exclude:REGEX)     Exclude tags matching REGEX.
    (tag-strip-prefix:STR)  Strip leading STR from tag before version parsing.
    (tag-strip-suffix:STR)  Strip trailing STR from tag before version parsing.
    (tag-replace:FROM:TO)   Replace literal FROM with TO in each tag name. Applied
                            after tag-extract/strip. E.g. (tag-replace:jdk-:) strips
                            the jdk- prefix from SDKMAN-style tags.
    (tag-extract:REGEX)     Apply perl capture group 1 to each tag name; discard tags
                            that don't match. Applied in tag pipeline. Use when tags
                            encode version in a non-standard position (e.g., release-1.2.3
                            → capture 1.2.3 with (tag-extract:release-(.+))).
    (tag-channel-prefix:STR) Use STR as channel prefix when matching tag names.

  DockerHub-specific:
    (tag-suffix:SUFFIX)  Keep only tags ending with literal SUFFIX (anchored grep).
                         Applied BEFORE sort. DockerHub only. Use to pin to a
                         specific distro suffix (e.g., -alpine3.23). Multiple
                         values not supported — use (tag-filter:) for complex patterns.

  URL fetcher flags (url: type only):
    (fetch-extract:REGEX)   URL fetcher tier 1: fetch the identifier URL, apply
                            perl regex (capture group 1), sort -V, take highest.
                            For HTML pages with embedded version strings.
    (fetch-json:JQ_PATH)    URL fetcher tier 2: fetch URL as JSON, extract via jq
                            path (e.g., .version). Exact null-match guard: if jq
                            returns the literal string "null", treats as empty.
    (url-probe:BASE_URL)    URL availability probe: tests candidate version URLs
                            (BASE_URL/VERSION/...) for HTTP 200. Finds highest
                            version where the download actually exists.
    (url-probe-depth:N)     Max path segments to probe in url-probe. Default 6.

  PECL-specific:
    (git:OWNER/REPO)    PECL fetcher only: enables HEAD SHA tracking for a
                        GitHub-hosted PECL extension (e.g., pecl:redis (git:phpredis/phpredis)).
                        Sets git_repo on record.

  Version format flags:
    (use-sha)         Track the latest commit SHA instead of a semver tag.
    (prefer-specific) Prefer the most specific (patch-level) version over a
                      shorter floating tag.
    (version-prefix:STR) Strip leading STR when comparing fetched version to
                      CURRENT_VERSION (e.g. "v" for v1.2.3 → 1.2.3).
    (propagate)       After --apply, propagate value to .env.local and Dockerfiles
                      even when the var is normally excluded from propagation.
    (watch-major[:N]) Emit a [WATCH] signal when a new major (or N-th level) is
                      detected. Default depth = 1 (major boundary).
    (replace:TARGET=template)
                      When this var is AUTO-updated, also rewrite TARGET=<expanded>
                      in the same env file. Template tokens: {version} {major} {minor} {patch}.
                      Multiple (replace:) flags may be stacked on one annotation.
                      Missing TARGET → ERROR (--no-fail skips without aborting).
                      Dry-run shows sub-lines but writes no files.
                      Note: tokens are extracted by splitting on '.'. Versions with
                      distro suffixes (e.g. 18.3-alpine3.23) will produce garbled
                      {minor}/{patch} tokens. Use {version} or {major} only for
                      such values.

  Unimplemented stub (parsed but not consumed):
    (depends-on:VAR:constraint)
                      STUB — parsed and stored, not yet implemented. Intended to
                      gate this record's update on another variable's value.
                      Currently a no-op. Do not use in production annotations.

  Tag pipeline order (matters for composed flags):
    filter → exclude → extract → strip-prefix → strip-suffix → replace

ANNO_EOF
  fi

  # ──────────────────────────────────────────────────────────────────────────
  # SECTION: fetchers
  # ──────────────────────────────────────────────────────────────────────────
  if [[ "${_section}" == "all" || "${_section}" == "fetchers" ]]; then
    cat << 'FETCH_EOF'
env-update reference — SECTION: fetchers
────────────────────────────────────────────────────────────────────────────────

PER-FETCHER DEEP-DIVE

  dockerhub:OWNER/IMAGE[:TAG_FILTER]
    API:       https://hub.docker.com/v2/repositories/OWNER/IMAGE/tags/
    Auth:      Rate-limited without auth; set DOCKERHUB_TOKEN env var for
               authenticated access (higher rate limit).
    Namespace: Use '_' for official library images (e.g. dockerhub:_/postgres).
    Pagination: Fetches up to 100 tags per request (post-pagination fix).
    Tags:      (tag-suffix) applied BEFORE sort and version selection.
               (tag-filter/exclude/extract/strip-prefix/suffix/replace) apply to raw tag list.
               (prefer-specific) prefers X.Y.Z over X.Y.
    Quirks:    Some images use non-standard tag formats; combine tag-strip-prefix
               or tag-replace to normalize before semver comparison.
    Cache key: dockerhub:OWNER/IMAGE:TTAG_FILTER

  github:OWNER/REPO
    API:       https://api.github.com/repos/OWNER/REPO/releases
               + https://api.github.com/repos/OWNER/REPO/tags (with check-tags)
    Auth:      GITHUB_TOKEN env var (Bearer auth). Falls back to unauthenticated
               (60 req/hr limit). GIT_ASKPASS tmpfile method used for auth.
    Tags:      (check-tags) merges tags API with releases API to catch tag-only releases.
               Full tag pipeline applies: filter → exclude → extract → strip-prefix
               → strip-suffix → replace → channel-prefix.
               (tag-filter/exclude/strip-prefix/suffix/replace/extract/channel-prefix)
    Channel:   (channel:rc/beta/alpha/nightly/unstable) or --unstable/--stable flags.
    Quirks:    Some repos publish only tags, no releases — always combine with (check-tags).
               EA (Early Access) versions must be filtered out for sdkman-style repos.

  npm:PACKAGE
    API:       https://registry.npmjs.org/PACKAGE
    Auth:      None required for public packages.
    Channel:   (channel:) maps to dist-tag (latest/next/beta/rc).
    Scoped:    Use @scope/name format directly.
    Quirks:    dist-tag normalization: "stable" → "latest". Pre-release detection via
               version field contains - suffix (e.g. 5.0.0-beta.1).

  pypi:PACKAGE
    API:       https://pypi.org/pypi/PACKAGE/json
    Auth:      None required.
    Channel:   (channel:) maps to pre/stable PyPI classifiers.
    Quirks:    .postN suffix stripped before semver comparison. Pre-release detection
               via version field contains a/b/rc/dev suffix.

  rubygems:GEM
    API:       https://rubygems.org/api/v1/gems/GEM.json
               + /api/v1/gems/GEM/versions.json for prerelease
    Auth:      None required.
    Channel:   Prerelease detection via prerelease field in API response.

  pecl:EXTNAME [(git:owner/repo)]
    API:       https://pecl.php.net/rest/r/EXTNAME/allreleases.xml
    Auth:      None required.
    Git SHA:   (git:OWNER/REPO) enables HEAD SHA tracking via GitHub API.
    Limits:    No major_hint or range syntax supported.
    Quirks:    Some extensions publish only on GitHub and lag behind on PECL;
               use (git:) for most accurate HEAD tracking.

  sdkman:CANDIDATE
    API:       https://api.sdkman.io/2/candidates/CANDIDATE/VERSION/resolve
    Auth:      None required.
    Channel:   EA/RC versions use full version string check (slip-through fix applied:
               base version checked, not just prefix match).
    Examples:  sdkman:java, sdkman:gradle, sdkman:maven, sdkman:kotlin
    Quirks:    Java identifiers include distribution suffix (e.g. 21.0.3-tem, 17.0.11-zulu).
               Use exact CANDIDATE:DISTRIBUTION format for distribution-pinned checks.

  sdkmanager:PACKAGE
    API:       Parses sdkmanager --list output from Android SDK container.
    Auth:      Requires running Android SDK container.
    Limits:    No major_hint/range syntax. Package identifier is full Android SDK path.
    Examples:  sdkmanager:build-tools;35.0.0

  url:URL
    4-tier resolution (tried in order until one succeeds):
      Tier 1: (fetch-extract:REGEX) — fetch URL body, extract via perl capture group 1
      Tier 2: (fetch-json:JQ_PATH) — fetch URL as JSON, extract via jq path
      Tier 3: GitHub redirect — if URL points to a GitHub release "latest" redirect
      Tier 4: (url-probe:BASE_URL) — probe candidate version URLs for HTTP 200
      Fallback: direct fetch of URL content
    Auth:      None by default. Use (fetch-extract) or (fetch-json) for authenticated URLs.
    Quirks:    fetch-json: jq "null" string → treated as empty (not version "null").
               url-probe: tries up to url-probe-depth path segments per candidate.

  quay:OWNER/IMAGE
    API:       https://quay.io/api/v1/repository/OWNER/IMAGE/tag/
    Auth:      None required for public images.
    Pagination: 100-item paginated fetch (pagination fix applied).
    Tags:      Same tag pipeline as github/dockerhub.
    Quirks:    Some Quay images use build-timestamp tags; use tag-filter to exclude them.

  codeberg:OWNER/REPO
    API:       https://codeberg.org/api/v1/repos/OWNER/REPO/releases
               + /api/v1/repos/OWNER/REPO/tags (with check-tags)
    Auth:      None required for public repos (Gitea-based).
    Tags:      (check-tags) merges tags + releases, same as github.
    Channel:   Prerelease detection via is_prerelease field.

FETCH_EOF
  fi

  # ──────────────────────────────────────────────────────────────────────────
  # SECTION: decisions
  # ──────────────────────────────────────────────────────────────────────────
  if [[ "${_section}" == "all" || "${_section}" == "decisions" ]]; then
    cat << 'DEC_EOF'
env-update reference — SECTION: decisions
────────────────────────────────────────────────────────────────────────────────

DECISIONS EMITTED BY --check

  AUTO      New version found that is safe to apply.
            Produced when: proposed > current, within major_hint bounds,
            no (manual)/(override) flag, not FROZEN/LOCK.
            --apply writes: both VAR= and annotation CURRENT_VERSION.

  RESOLVED  Current version is a floating ref (latest/stable/lts/nightly/edge/…)
            and the fetcher resolved it to a concrete semver.
            Informational only — NOT written by --apply alone.
            --apply --apply-resolve writes: both VAR= and annotation CURRENT_VERSION.
            Output tag in apply: [PINNED ] (9 chars, including trailing space).
            --force-auto does NOT promote RESOLVED to AUTO.
            Float+DRIFT: RESOLVED entries skip the drift detection path (annotation
            holds the float alias, not a semver baseline — no mismatch possible).

  HOLD      Proposed version would cross the major_hint upper boundary.
            Produced automatically by major_hint range logic — not by any flag.
            (hold) annotation text is NOT a valid flag; it corrupts field parsing.
            --force-auto bypasses HOLD.

  MANUAL    (manual) or (override) flag set — human gate required.
            --force-auto bypasses MANUAL.
            Float+(manual): when current is a float alias AND (manual)/(override)
            is set, decision is MANUAL (not RESOLVED).

  SKIP      Version already up-to-date, or downgrade blocked.
            Produced when: proposed == current, or proposed < current.
            Also produced when current is a float alias AND proposed is also
            unversioned (or no proposed version).
            Suppressed in output by --changes-only.

  FROZEN    (skip:REASON) flag set. Record is permanently frozen.
            Immune to --force-auto.
            --apply never writes a FROZEN record.

  LOCK      (lock:REASON) flag set. VAR= is never changed; annotation
            CURRENT_VERSION may still be updated.
            Immune to --force-auto.

  SHA       (use-sha) record with a new commit SHA available.
            --apply writes: annotation CURRENT_VERSION only (not VAR=).

  FALLBACK  Record is running on LOW of a major_hint range (e.g., 18-19)
            while waiting for HIGH to ship. Shown as a sub-line alongside
            the primary decision (AUTO/HOLD/SKIP).

  ERROR     Fetch failed: network error, auth failure, parse error, or
            missing required container. Exits non-zero unless --no-fail.

  Use --force-auto to bypass HOLD/MANUAL gates (requires --confirm="Confirm override"
  with --apply).

DECISIONS SUMMARY LINE FORMAT
  Summary: N AUTO, [N RESOLVE,] N SHA, N HOLD, N MANUAL, N LOCK, N SKIP, N FROZEN, N FALLBACK, N ERROR  (N checked)
    ↳ N WATCH · N DRIFT (N fixable) · N DOWNGRADE · N FORCE-DOWNGRADE · N REPLACE-DRIFT · N +sha · N +replace [· +resolve N]

  RESOLVE column shown only when > 0 (consistent with FALLBACK handling).
  +resolve N shown in secondary line only when > 0.
  DRIFT       — VAR= in env file differs from annotation's claimed CURRENT_VERSION.
  DOWNGRADE   — VAR= is ahead of annotation (potential downgrade if AUTO applied).
  FORCE-DOWNGRADE — DOWNGRADE records where --apply would actively write a lower version.
  REPLACE-DRIFT — (replace:TARGET) target has wrong value relative to current primary.
  +sha        — AUTO/MANUAL records that also carry a SHA annotation update.
  +replace    — AUTO/SHA records where a (replace:TARGET) cascade write will occur.

DEC_EOF
  fi

  # ──────────────────────────────────────────────────────────────────────────
  # SECTION: matrix (LIVE — runs actual decision engine)
  # ──────────────────────────────────────────────────────────────────────────
  if [[ "${_section}" == "all" || "${_section}" == "matrix" ]]; then
    _gs_eu2_show_reference_matrix
  fi

  # ──────────────────────────────────────────────────────────────────────────
  # SECTION: scenarios
  # ──────────────────────────────────────────────────────────────────────────
  if [[ "${_section}" == "all" || "${_section}" == "scenarios" ]]; then
    cat << 'SCEN_EOF'
env-update reference — SECTION: scenarios
────────────────────────────────────────────────────────────────────────────────

WORKED EXAMPLES

  1. DockerHub — Postgres pinned to major 18
     # @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23
     GLOBAL_STACK_POSTGRES18_VERSION=18.3-alpine3.23

     Behavior: fetches tags matching ^18\..*; AUTO when 18.x+1 ships.
     HOLD when 19.x ships (major boundary). Combine with (tag-suffix:-alpine3.23)
     to restrict to Alpine variants.

  2. GitHub — CLI tool, latest stable release
     # @todo env-update github:cli/cli 2.49.0
     GLOBAL_STACK_GH_CLI_VERSION=2.49.0

     Behavior: fetches /releases, takes latest non-prerelease. With --unstable:
     picks latest including rc/beta. With (check-tags): merges tag list for repos
     that publish only tags.

  3. npm — TypeScript, major 5 only
     # @todo env-update npm:typescript:5 5.4.5
     GLOBAL_STACK_TS_VERSION=5.4.5

     Behavior: fetches npm dist-tags; major_hint=5 restricts to 5.x. When 6.0
     ships: HOLD. Use (channel:next) for pre-release builds.

  4. PyPI — pip, latest stable
     # @todo env-update pypi:pip 24.0
     GLOBAL_STACK_PIP_VERSION=24.0

     Behavior: .postN suffix stripped; dev/rc/beta detected as pre-release.

  5. PECL with GitHub SHA tracking
     # @todo env-update pecl:redis (git:phpredis/phpredis) 6.0.2
     GLOBAL_STACK_PHP_REDIS_VERSION=6.0.2

     Behavior: checks PECL for release + GitHub HEAD for SHA. (use-sha) not
     required when (git:) flag is present — SHA tracking is implicit.

  6. SDKMAN — Java with distribution suffix
     # @todo env-update (lock:LTS policy) sdkman:java 21.0.3-tem
     GLOBAL_STACK_JAVA21_VERSION=21.0.3-tem

     Behavior: LOCK decision — VAR= never changed even if newer 21.x exists.
     Annotation CURRENT_VERSION updated but VAR= stays pinned.

  7. URL — custom release page
     # @todo env-update url:https://releases.example.com/VERSION (fetch-extract:version=([0-9.]+)) 1.2.3
     GLOBAL_STACK_EXAMPLE_VERSION=1.2.3

     Behavior: fetches the URL, applies perl capture group 1, sort -V, highest wins.

  8. Floating ref → RESOLVED
     # @todo env-update dockerhub:_/node:lts latest
     GLOBAL_STACK_NODE_LTS_TAG=latest

     Behavior: fetcher resolves 'latest' to '22.14.0-bookworm'. Emits RESOLVED.
     Not written by --apply; requires --apply --apply-resolve to pin.
     After pinning: annotation CURRENT_VERSION becomes 22.14.0-bookworm.

  9. Range with fallback
     # @todo env-update sdkman:java:18-19 18.0.2-tem
     GLOBAL_STACK_JAVA18_VERSION=18.0.2-tem

     Behavior: FALLBACK sub-line while on LOW=18. Promotes to 19 when any 19.x ships.
     19.x triggers HOLD until manual confirmation, then AUTO on next run.

  10. Quay — Keycloak, major 24
      # @todo env-update quay:keycloak/keycloak:24 24.0.5
      GLOBAL_STACK_KEYCLOAK_VERSION=24.0.5

      Behavior: 100-item paginated tag fetch. tag-filter/exclude apply.

SCEN_EOF
  fi

  # ──────────────────────────────────────────────────────────────────────────
  # SECTION: env-scan
  # ──────────────────────────────────────────────────────────────────────────
  if [[ "${_section}" == "all" || "${_section}" == "env-scan" ]]; then
    cat << 'SCAN_EOF'
env-update reference — SECTION: env-scan
────────────────────────────────────────────────────────────────────────────────

ENV-SCAN — bin/env-scan.sh v1.0.0

OVERVIEW
  env-scan syncs .env → .env.local (adds missing vars, reports conflicts) and
  propagates updated values to ARG lines in Dockerfiles.

  Run after any env-update --apply to propagate new versions to containers.


8-PHASE PIPELINE
  Phase 1: Parse args + validate flags
  Phase 2: Build source file index (detect .env, .env.local, COMPOSE_FILE list)
  Phase 3: Scan docker sources — find all Dockerfiles with matching ARG lines
  Phase 4: Detect conflicts — vars present in both files with different values
  Phase 5: Backup pre-flight — snapshot .env.local + Dockerfiles (unless --backup=false)
  Phase 6: Sync env files — add missing vars from source to dest
  Phase 7: Propagate to Dockerfiles — rewrite ARG VAR=value lines that diverge
           (skipped for vars with ${VAR} expansion in .env value)
  Phase 8: Retention prune — remove old backups beyond --backup-keep=N limit

  --dry-run suppresses: Phase 5 backup, Phase 6 sync write, Phase 7 propagation.
  Phases 1-4 and 8 are always executed (dry-run still prunes to avoid accumulation).


CONFLICT DETECTION
  A conflict is a var present in BOTH source (.env) and dest (.env.local) with
  DIFFERENT values. env-scan reports conflicts but does NOT overwrite by default
  when --sync-values=false.

  With --sync-values=true (default): dest value is overwritten with source value.
  With --sync-values=false: dest value is preserved; conflict is reported only.


PROPAGATION TO DOCKERFILES
  Triggers when: ARG VAR=VALUE in a Dockerfile AND .env has VAR=DIFFERENT_VALUE.
  Skips when: .env value contains ${ (expansion-dependent; cannot be statically inlined).
  Skips when: VAR matches _GS_ES_PATTERN_CONFLICT_IGNORE list.
  Writes: ARG VAR=NEW_VALUE (only the value portion, not the ARG keyword).
  Backup: Dockerfile is backed up before any write (same naming convention as .env).


FLAGS
  --version              Print version and exit.
  --sync-values=true|false
                         true (default): overwrite dest values with source values.
                         false: preserve dest values that differ from source.
  --profile=true|false   Show per-phase timing (default: false).
  --dry-run              Report only — no writes to .env.local or Dockerfiles.
  --no-fail              Always exit 0; propagation errors suppressed.
                         Backup and infrastructure errors remain fatal.
  --backup=true|false    Run backup phase (default: true).
  --backup-keep=N        Keep N newest backups per file (0 = unlimited; default 10).
  --backup-purge=true    Delete all existing <file>.bak.* before run.
  --backup-suffix=STR    Custom backup suffix anchor (default: .bak).


SCENARIOS
  1. New variable in source not in destination (ADD)
     .env:       GLOBAL_STACK_NEW_VAR=value
     .env.local: (missing)
     Result:     GLOBAL_STACK_NEW_VAR=value added to .env.local

  2. Variable exists in both with different values (CONFLICT)
     .env:       GLOBAL_STACK_PG_VERSION=18.3
     .env.local: GLOBAL_STACK_PG_VERSION=17.5
     --sync-values=true:   .env.local updated to 18.3
     --sync-values=false:  conflict reported, .env.local unchanged

  3. Dockerfile ARG differs from .env (PROPAGATE)
     .env:            GLOBAL_STACK_PG_VERSION=18.3
     Dockerfile:      ARG GLOBAL_STACK_PG_VERSION=17.5
     Result:          ARG GLOBAL_STACK_PG_VERSION=18.3 (Dockerfile updated)

  4. Dry-run — all changes reported, nothing written
     env-scan --dry-run
     Prints: what would be added, conflicts, what Dockerfiles would be updated.
     Writes: nothing.

  5. Multi-source-file propagation
     COMPOSE_FILE contains multiple docker-compose.yaml paths; env-scan loops
     per file to propagate to all referenced Dockerfiles (es-F001 loop fix).

SCAN_EOF
  fi
}

# _gs_eu2_show_reference_matrix — live decision matrix using embedded fixtures.
#
# Runs _gs_eu2_classify_decision against synthetic version data.
# No network calls — all data is embedded in this function.
# Side-effects: none (read-only; runs in current shell context)
_gs_eu2_show_reference_matrix() {
  printf 'env-update reference — SECTION: matrix\n'
  printf '%.0s─' {1..80}; printf '\n'
  printf '\n'
  printf 'LIVE DECISION MATRIX (runs actual decision engine, no network)\n'
  printf '\n'

  # Helper: print one matrix row
  # Args: label cur prop result [extra]
  _matrix_row() {
    local _label="${1}" _cur="${2}" _prop="${3}" _result="${4}" _extra="${5:-}"
    printf '  %-38s  %-16s → %-20s  %s%s\n' \
      "${_label}" "${_cur}" "${_prop:-<none>}" "${_result}" \
      "${_extra:+ (${_extra})}"
  }

  printf 'SECTION A — Live classifier fixtures (no network calls)\n'
  printf 'Calls _gs_eu2_classify_decision and _gs_eu2_classify_sha_decision with synthetic data.\n'
  printf 'Output is what the actual engine produces for these inputs.\n'
  printf '%s\n' '─────────────────────────────────────────────────────────────────────────────────────────────'
  printf '\n'

  # ── Fixture 1: Standard semver — stable vs prerelease ──────────────────
  printf 'Fixture 1: Standard semver (default / --unstable / --unstable=full)\n'
  printf '  Mock versions: 4.0.0-rc1 3.2.0-rc2 3.1.0 2.5.0\n'
  printf '  %-38s  %-16s → %-20s  %s\n' 'scenario' 'current' 'proposed' 'decision'
  printf '  %s\n' '----------------------------------------------------------------------'

  local _r
  _r="$(_gs_eu2_classify_decision '3.1.0' '3.1.0' '' '' '')"
  _matrix_row 'up-to-date (SKIP)' '3.1.0' '3.1.0' "${_r}"

  _r="$(_gs_eu2_classify_decision '3.1.0' '3.2.0' '' '' '')"
  _matrix_row 'minor bump (AUTO)' '3.1.0' '3.2.0' "${_r}"

  _r="$(_gs_eu2_classify_decision '3.1.0' '4.0.0' '' '' '')"
  _matrix_row 'major bump no hint (HOLD)' '3.1.0' '4.0.0' "${_r}"

  _r="$(_gs_eu2_classify_decision '3.1.0' '4.0.0' '' '' '3')"
  _matrix_row 'major bump + hint=3 (HOLD)' '3.1.0' '4.0.0' "${_r}"

  _r="$(_gs_eu2_classify_decision '3.2.0-rc2' '3.2.0' '' '' '')"
  _matrix_row 'rc→stable same base (AUTO)' '3.2.0-rc2' '3.2.0' "${_r}"

  _r="$(_gs_eu2_classify_decision '3.1.0' '' '' '' '')"
  _matrix_row 'no proposed version (SKIP)' '3.1.0' '' "${_r}"

  _r="$(_gs_eu2_classify_decision '3.1.0' '3.2.0-rc1' '' '' '')"
  _matrix_row 'prerelease proposed, stable current, default (SKIP)' '3.1.0' '3.2.0-rc1' "${_r}"

  # Major prerelease + unstable_mode=full → still HOLD: major jump check runs after
  # prerelease guard bypass. Only minor/patch prerelease bypasses produce AUTO.
  _r="$(_gs_eu2_classify_decision '3.1.0' '3.2.0-rc1' '' '' '' 'full')"
  _matrix_row 'prerelease proposed, unstable_mode=full, minor (AUTO)' '3.1.0' '3.2.0-rc1' "${_r}" 'unstable_mode=full'

  printf '\n'

  printf 'Note: range hints (e.g. 18-19) are handled by main.sh orchestration BEFORE calling\n'
  printf 'the classifier. Passing a range string directly to _gs_eu2_classify_decision produces\n'
  printf 'incorrect results. Range/FALLBACK behavior is shown in Section B (orchestration).\n'
  printf '\n'

  # ── Fixture 2: Major hint — boundary enforcement ──────────────────────
  printf 'Fixture 2: Major hint boundary\n'
  printf '  %-38s  %-16s → %-20s  %s\n' 'scenario' 'current' 'proposed' 'decision'
  printf '  %s\n' '----------------------------------------------------------------------'

  _r="$(_gs_eu2_classify_decision '3.1.0' '3.2.0' '' '' '3')"
  _matrix_row 'within hint (AUTO)' '3.1.0' '3.2.0' "${_r}"

  _r="$(_gs_eu2_classify_decision '3.1.0' '4.0.0' '' '' '3')"
  _matrix_row 'crosses hint (HOLD)' '3.1.0' '4.0.0' "${_r}"

  _r="$(_gs_eu2_classify_decision '3.1.0' '2.5.0' '' '' '3')"
  _matrix_row 'downgrade (SKIP)' '3.1.0' '2.5.0' "${_r}"

  printf '\n'

  # ── Fixture 3: Floating ref → RESOLVED ───────────────────────────────
  printf 'Fixture 3: Floating ref (RESOLVED / SKIP)\n'
  printf '  %-38s  %-16s → %-20s  %s\n' 'scenario' 'current' 'proposed' 'decision'
  printf '  %s\n' '----------------------------------------------------------------------'

  _r="$(_gs_eu2_classify_decision 'latest' '18.3-alpine3.23' '' '' '')"
  _matrix_row 'float → concrete (RESOLVED)' 'latest' '18.3-alpine3.23' "${_r}"

  _r="$(_gs_eu2_classify_decision 'stable' '3.2.1' '' '' '')"
  _matrix_row 'stable → concrete (RESOLVED)' 'stable' '3.2.1' "${_r}"

  _r="$(_gs_eu2_classify_decision 'lts' '20.18.0' '' '' '')"
  _matrix_row 'lts → concrete (RESOLVED)' 'lts' '20.18.0' "${_r}"

  _r="$(_gs_eu2_classify_decision 'latest' 'latest' '' '' '')"
  _matrix_row 'float → float (SKIP)' 'latest' 'latest' "${_r}"

  _r="$(_gs_eu2_classify_decision 'latest' '' '' '' '')"
  _matrix_row 'float → empty (SKIP)' 'latest' '' "${_r}"

  _r="$(_gs_eu2_classify_decision 'latest' '18.3-alpine3.23' 'true' '' '')"
  _matrix_row 'float + manual=true (MANUAL)' 'latest' '18.3-alpine3.23' "${_r}"

  _r="$(_gs_eu2_classify_decision 'latest' '18.3-alpine3.23' '' 'true' '')"
  _matrix_row 'float + override=true (MANUAL)' 'latest' '18.3-alpine3.23' "${_r}"

  printf '\n'

  # ── Fixture 4: FROZEN / LOCK / MANUAL / AUTO ─────────────────────────
  printf 'Fixture 4: Gate flags\n'
  printf '  %-38s  %-16s → %-20s  %s\n' 'scenario' 'current' 'proposed' 'decision'
  printf '  %s\n' '----------------------------------------------------------------------'

  _r="$(_gs_eu2_classify_decision '3.1.0' '3.2.0' '' 'true' '')"
  _matrix_row '(override)=true (MANUAL)' '3.1.0' '3.2.0' "${_r}"

  _r="$(_gs_eu2_classify_decision '3.1.0' '3.2.0' 'true' '' '')"
  _matrix_row '(manual)=true (MANUAL)' '3.1.0' '3.2.0' "${_r}"

  printf '\n'

  # ── Fixture 5: Downgrade protection ──────────────────────────────────
  printf 'Fixture 5: Downgrade protection\n'
  printf '  %-38s  %-16s → %-20s  %s\n' 'scenario' 'current' 'proposed' 'decision'
  printf '  %s\n' '----------------------------------------------------------------------'

  _r="$(_gs_eu2_classify_decision '3.2.0' '3.1.0' '' '' '')"
  _matrix_row 'proposed < current (SKIP)' '3.2.0' '3.1.0' "${_r}"

  _r="$(_gs_eu2_classify_decision '3.2.0' '3.2.0' '' '' '')"
  _matrix_row 'proposed = current (SKIP)' '3.2.0' '3.2.0' "${_r}"

  printf '\n'

  # ── Fixture 6: SHA annotation classifier (_gs_eu2_classify_sha_decision) ─────────────────
  printf 'Fixture 6: SHA annotation classifier (_gs_eu2_classify_sha_decision)\n'
  printf 'Purpose: classifies whether the annotation sha: field needs updating (git: flag records).\n'
  printf 'Called AFTER the primary classifier. Can upgrade a SKIP decision to SHA.\n\n'

  printf '%-55s  %-12s  %-12s  %s\n' 'Scenario' 'ann_sha' 'prop_sha' 'Result'
  printf '%s\n' '─────────────────────────────────────────────────────────────────────────────────────────────'

  # Case 1 — new SHA available (annotation sha ≠ proposed sha)
  _r="$(_gs_eu2_classify_sha_decision 'abc1234567' 'def9876543')"
  _matrix_row 'new SHA available (SHA)' 'abc1234567' 'def9876543' "${_r}"

  # Case 2 — first time tracking (annotation sha empty)
  _r="$(_gs_eu2_classify_sha_decision '' 'def9876543')"
  _matrix_row 'first tracking, ann sha empty (SHA)' '' 'def9876543' "${_r}"

  # Case 3 — SHA current (annotation sha == proposed sha)
  _r="$(_gs_eu2_classify_sha_decision 'abc1234567' 'abc1234567')"
  _matrix_row 'SHA current, no update needed (SKIP)' 'abc1234567' 'abc1234567' "${_r}"

  # Case 4 — no proposed sha (no git: flag or fetch failed)
  _r="$(_gs_eu2_classify_sha_decision 'abc1234567' '')"
  _matrix_row 'no proposed sha (SKIP)' 'abc1234567' '' "${_r}"

  printf '\n'

  # ── SECTION B — ORCHESTRATION-LAYER SIGNALS (static narrative) ───────────────────────────
  # These states are set by main.sh AFTER the classifier runs. They cannot be demonstrated
  # by calling the classifier in isolation — they require the full pipeline context.
  # Shown with the annotation syntax that triggers each state.

  printf 'SECTION B — Orchestration-layer signals (set by main.sh, not the classifier)\n'
  printf '%s\n' '─────────────────────────────────────────────────────────────────────────────────────────────'
  printf '\n'

  printf '1. FROZEN — (skip:REASON) flag\n'
  printf '   Annotation:  # @todo env-update (skip:Not used) npm:express 4.19.2\n'
  printf '   Trigger:     skip_reason field non-empty → main.sh overrides classifier → FROZEN\n'
  printf '   Immune to:   --force-auto (cannot bypass skip gate)\n'
  printf '   --apply:     never writes this record\n'
  printf '   Summary:     N FROZEN\n'
  printf '\n'

  printf '2. LOCK — (lock:REASON) flag\n'
  printf '   Annotation:  # @todo env-update (lock:LTS policy) sdkman:java 17.0.11-tem\n'
  printf '   Trigger:     lock_reason field non-empty → main.sh overrides → LOCK\n'
  printf '   Immune to:   --force-auto (cannot bypass lock gate)\n'
  printf '   --apply:     MAY update annotation CURRENT_VERSION; NEVER changes VAR=\n'
  printf '   Summary:     N LOCK\n'
  printf '\n'

  printf '3. ERROR — fetch failure\n'
  printf '   Trigger:     fetcher returns non-zero, HTTP >= 400, timeout, or parse failure\n'
  printf '   --apply:     never writes this record\n'
  printf '   --no-fail:   suppresses non-zero process exit; ERROR still shown in output\n'
  printf '   Summary:     N ERROR\n'
  printf '\n'

  printf '4. FALLBACK — range major_hint, currently on LOW, HIGH not yet available\n'
  printf '   Annotation:  # @todo env-update dockerhub:_/node:18-19 18.20.0\n'
  printf '   Trigger:     main.sh parses range; fetcher finds no version in HIGH range → using_fallback_major=true\n'
  printf '   Effect:      primary decision unaffected; FALLBACK is additive\n'
  printf '   --apply:     AUTO within LOW range still applies\n'
  printf '   Summary:     N FALLBACK\n'
  printf '\n'

  printf '5. DRIFT — VAR= value differs from annotation CURRENT_VERSION\n'
  printf '   Example:     annotation says 18.3-alpine3.23 but VAR=18.5-alpine3.21\n'
  printf '   Trigger:     actual_var_value != current_version field\n'
  printf '   Effect:      [DRIFT] sub-line; "fixable" when decision is AUTO\n'
  printf '   --apply:     AUTO apply fixes drift\n'
  printf '   Summary B2:  N DRIFT (N fixable)\n'
  printf '\n'

  printf '6. DOWNGRADE — VAR= is ahead of fetcher'"'"'s proposed version\n'
  printf '   Trigger:     actual_var_value sorts AFTER proposed (env file is manually ahead)\n'
  printf '   Effect:      [DOWNGRADE] sub-line; NOT an error\n'
  printf '   Summary B2:  N DOWNGRADE\n'
  printf '\n'

  printf '7. FORCE-DOWNGRADE — DOWNGRADE record where --apply would write a lower version\n'
  printf '   Trigger:     DOWNGRADE + decision is AUTO\n'
  printf '   Effect:      --apply would overwrite VAR= with a version lower than currently set\n'
  printf '   Note:        distinguishable from DOWNGRADE+SKIP (no write occurs for SKIP)\n'
  printf '   Summary B2:  N FORCE-DOWNGRADE\n'
  printf '\n'

  printf '8. WATCH — (watch-major[:N]) + major boundary crossing detected\n'
  printf '   Annotation:  # @todo env-update (watch-major) github:nodejs/node 20.18.0\n'
  printf '   Trigger:     proposed major > current major (or N-th boundary for watch-major:N)\n'
  printf '   Effect:      [WATCH] sub-line alongside primary decision; does NOT change decision\n'
  printf '   Summary B2:  N WATCH\n'
  printf '\n'

  printf '9. REPLACE-DRIFT — (replace:TARGET=template) target has wrong current value\n'
  printf '   Annotation:  # @todo env-update (replace:ALIAS={version}) npm:typescript 5.4.5\n'
  printf '   Trigger:     current value of TARGET var != what {version} would expand to\n'
  printf '   Effect:      [REPLACE-DRIFT] sub-line; independent of primary decision\n'
  printf '   --apply:     rewrites TARGET= to correct expanded value\n'
  printf '   Summary B2:  N REPLACE-DRIFT\n'
  printf '\n'

  printf '10. +sha sub-signal — AUTO or MANUAL record with stale annotation SHA\n'
  printf '    Trigger:     decision in {AUTO, MANUAL} AND _gs_eu2_classify_sha_decision returns SHA\n'
  printf '    Effect:      appended to primary decision line; annotation sha: updated on --apply\n'
  printf '    Summary B2:  N +sha\n'
  printf '\n'

  printf '11. +replace sub-signal — AUTO or SHA record with (replace:) cascade targets\n'
  printf '    Trigger:     decision in {AUTO, SHA} AND record has replace_targets field set\n'
  printf '    Effect:      arrow (replace) sub-lines; TARGET= vars rewritten on --apply\n'
  printf '    Summary B2:  N +replace\n'
  printf '\n'

  printf '12. PINNED — RESOLVED record applied via --apply --apply-resolve\n'
  printf '    Trigger:     decision=RESOLVED AND --apply AND --apply-resolve both present\n'
  printf '    Tag:         [PINNED ] (9 chars) in apply output\n'
  printf '    --apply:     VAR= rewritten to concrete version; annotation CURRENT_VERSION updated\n'
  printf '    Safety:      --force-auto CANNOT produce PINNED; RESOLVED gate is explicit\n'
  printf '\n'

  printf '13. DEPENDS-ON WARNING — (depends-on:VAR:constraint) annotation present\n'
  printf '    Annotation:  # @todo env-update (depends-on:GLOBAL_STACK_SONARQUBE_VERSION:major) ...\n'
  printf '    Trigger:     depends_on field non-empty\n'
  printf '    Effect:      [WARN] sub-line: "(depends-on:VAR:constraint) not enforced — dependency\n'
  printf '                 ordering unimplemented; verify manually before --apply"\n'
  printf '    NOT suppressed by --no-notes (safety warning)\n'
  printf '    Summary:     N [WARN] depends-on (if > 0)\n'
  printf '    Status:      ANNOTATION IS PARSED AND STORED. Dependency check IS NOT ENFORCED.\n'
  printf '\n'
}
