#!/bin/bash
# annotations-ref.sh — structured reference for env-update annotation syntax

[[ -n "${_GS_EU2_ANNOTATIONS_REF_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_ANNOTATIONS_REF_SH_LOADED=1

_gs_eu2_show_annotations_ref() {
  cat << 'EOF'
env-update annotation reference
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
    Fetch version string from a raw URL.

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


ANNOTATION FLAGS (parenthesised, space-separated, after the @todo keyword)
  Behaviour flags:
    (manual)          Suppress AUTO; decision is MANUAL (human gate).
                      --force-auto bypasses this.
    (override)        Alias for (manual). Same effect.
    (hold)            Same as (manual) — emits HOLD decision.
    (skip:REASON)     Permanently skip this record. Immune to --force-auto.
    (lock:REASON)     Lock the current version; annotation may still be updated
                      by --apply but VAR= is never changed. Immune to --force-auto.

  Metadata / sub-line flags:
    (note:TEXT)       Attach a human-readable note sub-line. Suppressed by --no-notes.
    (channel:NAME)    Override fetch channel: stable, rc, beta, alpha, nightly, unstable.
                      --stable=full and --unstable=full may override this.

  GitHub-specific:
    (check-tags)      Merge tags API response with releases API (catches tag-only releases).
                      Also available: codeberg.
    (tag-filter:REGEX)      Include only tags matching REGEX.
    (tag-exclude:REGEX)     Exclude tags matching REGEX.
    (tag-strip-prefix:STR)  Strip leading STR from tag before version parsing.
    (tag-strip-suffix:STR)  Strip trailing STR from tag before version parsing.
    (tag-channel-prefix:STR) Use STR as channel prefix when matching tag names.

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


INLINE SYNTAX EXAMPLES
  # @todo env-update dockerhub:_/postgres:18 18.3-alpine3.23
  # @todo env-update github:cli/cli 2.49.0
  # @todo env-update npm:typescript:5 5.4.5
  # @todo env-update npm:@types/node:25-26 25.8.0
  # @todo env-update pypi:pip 24.0
  # @todo env-update rubygems:rails:7 7.1.3
  # @todo env-update pecl:redis (git:phpredis/phpredis) 6.0.2
  # @todo env-update sdkman:gradle:8 8.7
  # @todo env-update quay:keycloak/keycloak:24 24.0.5
  # @todo env-update codeberg:forgejo/forgejo (check-tags) 7.0.5
  # @todo env-update (manual) (note:Pinned for compat) github:hashicorp/terraform 1.8.0
  # @todo env-update (channel:rc) github:nodejs/node 23.0.0-rc1
  # @todo env-update (lock:LTS policy) sdkman:java 17.0.11-tem
  # @todo env-update (skip:Not used) npm:express 4.19.2


DECISIONS EMITTED BY --check
  AUTO    new version found; will be applied by --apply
  HOLD    (manual)/(hold)/(override) flag set — human gate required
  SKIP    version already up-to-date
  ERROR   fetch failed (network, auth, parse error)
  MANUAL  same as HOLD; emitted when annotation has (manual) or (override)
  SHA     use-sha record with a new commit SHA

  Use --force-auto to bypass HOLD/MANUAL gates (requires --confirm="Confirm override" with --apply).


SUMMARY LINE FORMAT
  Summary: N AUTO, N SHA, N HOLD, N MANUAL, N LOCK, N SKIP, N FROZEN, N FALLBACK, N ERROR  (N checked)
    ↳ N WATCH · N DRIFT (N fixable) · N DOWNGRADE · N +sha

  FALLBACK   — currently running on LOW while waiting for HIGH major to ship.
  DRIFT      — VAR= in env file differs from annotation's claimed current version.
  DOWNGRADE  — VAR= is ahead of annotation (potential downgrade if AUTO applied).
  +sha       — AUTO/MANUAL records that also carry a SHA annotation update.


SEE ALSO
  bin/env-update.sh --help        full CLI flag reference
  templates/tips/env-update.md   extended tips and patterns
EOF
}
