#!/bin/bash
# =============================================================================
# DEPRECATED — bin/env-update.sh
# Use bin/env-update-v2.sh for new version-fetch workflows.
# Propagation of values to Dockerfiles is now handled by bin/env-scan.sh.
#
# REMOVAL CONDITION: safe to remove when env-update-v2.sh implements all
# fetcher types currently used in .env:
#
#   Phase 2 (done): dockerhub (18 entries)
#   Phase 3+ (pending):
#     pecl-git   (100)   github   (73)   npm      (55)
#     pypi       (24)    sdkman   (19)   url       (8)
#     sdkmanager  (5)    rubygems  (4)   quay      (1)   codeberg (1)
#
# Until then this file remains the authoritative checker for non-dockerhub
# types and is still called by /check-versions for those fetcher types.
# =============================================================================
#
# env-update.sh — Automated version update checker for Global Stack.
#
# Reads @todo env-update annotations from .env, fetches latest versions
# from upstream APIs, and optionally auto-applies updates to .env and Dockerfiles.
#
# Usage:
#   bin/env-update.sh [OPTIONS]
#
# Options:
#   --dry-run              Write patch only, no files modified
#   --offline              Cache only, no network
#   --no-cache             Bypass cache reads (still writes)
#   --cache-ttl=<seconds>  Default: 3600
#   --filter=<pattern>     Only process vars matching pattern
#   --type=<types>         Comma-separated fetcher types to run
#   --no-auto-apply        Report all, apply nothing
#   --no-override          Skip override-flagged records entirely
#   --patch-file=<path>    Override patch output path
#   --report-file=<path>   Override JSON report path
#   --github-token=<token> Override GITHUB_TOKEN env var
#   --help

set -eEuo pipefail
trap 'printf "env-update: error in %s at line %d: %s\n" "${BASH_SOURCE[0]}" "${LINENO}" "${BASH_COMMAND}" >&2' ERR

# --------------------------------------------------------------------------
# Script location & library root
# --------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly STACK_DIR
LIB_DIR="${SCRIPT_DIR}/lib/env-update"
readonly LIB_DIR

# --------------------------------------------------------------------------
# Source all library modules
# --------------------------------------------------------------------------
# shellcheck source=lib/env-update/core/report.sh
source "${LIB_DIR}/core/report.sh"
# shellcheck source=lib/env-update/core/cache.sh
source "${LIB_DIR}/core/cache.sh"
# shellcheck source=lib/env-update/core/parse.sh
source "${LIB_DIR}/core/parse.sh"
# shellcheck source=lib/env-update/core/diff.sh
source "${LIB_DIR}/core/diff.sh"
# shellcheck source=lib/env-update/core/channel.sh
source "${LIB_DIR}/core/channel.sh"
# shellcheck source=lib/env-update/core/runtime.sh
source "${LIB_DIR}/core/runtime.sh"
# shellcheck source=lib/env-update/core/tag_flags.sh
source "${LIB_DIR}/core/tag_flags.sh"
# shellcheck source=lib/env-update/core/dockerfile.sh
source "${LIB_DIR}/core/dockerfile.sh"
# shellcheck source=lib/env-update/config/codename_map.sh
source "${LIB_DIR}/config/codename_map.sh"
# shellcheck source=lib/env-update/config/type_map.sh
source "${LIB_DIR}/config/type_map.sh"
# shellcheck source=lib/env-update/config/prerelease_markers.sh
source "${LIB_DIR}/config/prerelease_markers.sh"

# Fetchers
# shellcheck source=lib/env-update/fetchers/dockerhub.sh
source "${LIB_DIR}/fetchers/dockerhub.sh"
# shellcheck source=lib/env-update/fetchers/github.sh
source "${LIB_DIR}/fetchers/github.sh"
# shellcheck source=lib/env-update/fetchers/npm.sh
source "${LIB_DIR}/fetchers/npm.sh"
# shellcheck source=lib/env-update/fetchers/pecl.sh
source "${LIB_DIR}/fetchers/pecl.sh"
# shellcheck source=lib/env-update/fetchers/pecl_git.sh
source "${LIB_DIR}/fetchers/pecl_git.sh"
# shellcheck source=lib/env-update/fetchers/sdkman.sh
source "${LIB_DIR}/fetchers/sdkman.sh"
# shellcheck source=lib/env-update/fetchers/sdkmanager.sh
source "${LIB_DIR}/fetchers/sdkmanager.sh"
# shellcheck source=lib/env-update/fetchers/pypi.sh
source "${LIB_DIR}/fetchers/pypi.sh"
# shellcheck source=lib/env-update/fetchers/quay.sh
source "${LIB_DIR}/fetchers/quay.sh"
# shellcheck source=lib/env-update/fetchers/url.sh
source "${LIB_DIR}/fetchers/url.sh"
# shellcheck source=lib/env-update/fetchers/codeberg.sh
source "${LIB_DIR}/fetchers/codeberg.sh"
# shellcheck source=lib/env-update/fetchers/rubygems.sh
source "${LIB_DIR}/fetchers/rubygems.sh"

# Ubuntu alignment (depends on dockerhub fetcher)
# shellcheck source=lib/env-update/core/ubuntu.sh
source "${LIB_DIR}/core/ubuntu.sh"

# --------------------------------------------------------------------------
# Defaults
# --------------------------------------------------------------------------
readonly _GS_EU_ENV_FILE="${STACK_DIR}/.env"
_GS_EU_DRY_RUN="false"
export _GS_EU_OFFLINE="false"
export _GS_EU_NO_CACHE="false"
export _GS_EU_CACHE_TTL="${_GS_EU_CACHE_TTL:-3600}"
_GS_EU_FILTER=""
_GS_EU_TYPE_FILTER=""
_GS_EU_NO_AUTO_APPLY="false"
_GS_EU_NO_OVERRIDE="false"
_GS_EU_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly _GS_EU_TIMESTAMP
_GS_EU_PATCH_FILE="/tmp/env-update-${_GS_EU_TIMESTAMP}.patch"
_GS_EU_REPORT_FILE="/tmp/env-update-${_GS_EU_TIMESTAMP}.json"
_GS_EU_FETCH_ERROR_FILE="/tmp/env-update-${_GS_EU_TIMESTAMP}.fetch-error"
export _GS_EU_FETCH_ERROR_FILE
_GS_EU_PRERELEASE_HINT_FILE="/tmp/env-update-${_GS_EU_TIMESTAMP}.prerelease-hint"
export _GS_EU_PRERELEASE_HINT_FILE
_GS_EU_ALT_VERSION_FILE="/tmp/env-update-${_GS_EU_TIMESTAMP}.alt-version"
export _GS_EU_ALT_VERSION_FILE
export _GS_EU_DEBUG="${_GS_EU_DEBUG:-false}"
_GS_EU_SHOW_OK="false"
_GS_EU_SHOW_RUNTIME="false"
_GS_EU_SHOW_DATES="false"
_GS_EU_SHOW_PROGRESS="false"
_GS_EU_RELEASE_DATE_FILE="/tmp/env-update-${_GS_EU_TIMESTAMP}.release-date"
export _GS_EU_RELEASE_DATE_FILE
trap 'rm -f /tmp/env-update-'"${_GS_EU_TIMESTAMP}"'.*' EXIT
# GLOBAL_STACK_GITHUB_TOKEN (from .env.local) takes precedence over bare GITHUB_TOKEN
GITHUB_TOKEN="${GLOBAL_STACK_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}"

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
_gs_eu_show_help() {
  cat <<'EOF'
bin/env-update.sh — Global Stack version update checker

Usage:
  bin/env-update.sh [OPTIONS]

Options:
  --dry-run              Write patch only, no files modified
  --offline              Use cache only, no network requests
  --no-cache             Bypass cache reads (still writes on fetch)
  --cache-ttl=<seconds>  Cache TTL in seconds (default: 3600)
  --filter=<pattern>     Only process .env vars matching bash regex
  --type=<types>         Comma-separated list of fetcher types to run
                         Types: dockerhub quay github codeberg npm pecl pecl-git
                                sdkman sdkmanager pypi url rubygems
  --no-auto-apply        Report all changes, apply nothing automatically
  --no-override          Skip override-flagged records entirely
  --patch-file=<path>    Path for patch output file
  --report-file=<path>   Path for JSON report file
  --github-token=<token> GitHub API token (overrides GITHUB_TOKEN env var)
  --debug                Enable debug output
  --show-ok              Include up-to-date entries in summary
  --show-runtime         Show runtime context for dependent packages (e.g. "node 22")
  --show-dates           Fetch and display release dates where available (GitHub, npm)
  --progress             Show fetch progress indicator on stderr
  --help                 Show this help

Annotation flags (in @todo env-update comments):

  Version selection:
  (stable-only)              Propose only non-prerelease; hint if a newer pre-release exists
                             Supported: github, codeberg, npm, pypi, rubygems
  (pre-release)              Include pre-releases; hint toward stable when available
                             Supported: github, codeberg, npm, pypi, rubygems
  (channel:VALUE)            Track a specific channel: rc, beta, alpha, unstable, nightly
                             Comma-separated for OR logic: channel:rc,beta
                             Supported: github, dockerhub, quay, codeberg, npm, pypi, rubygems, url

  Review control:
  (override)                 Fetch for visibility only — never auto-applied
  (skip:REASON)              Skip this variable entirely
  (manual)                   Always require manual review regardless of version delta

  Tag manipulation (github, dockerhub, quay):
  (tag-filter:REGEX)         Keep only tags matching ERE regex
  (tag-exclude:REGEX)        Drop tags matching ERE regex
  (tag-strip-prefix:STR)     Strip literal prefix from each tag
  (tag-strip-suffix:STR)     Strip literal suffix from each tag
  (tag-extract:REGEX)        Extract capture group 1 via perl; discard non-matching
  (tag-replace:FROM:TO)      Replace all occurrences of FROM with TO in each tag
  (tag-suffix:VALUE)         Filter to tags ending with -VALUE (dockerhub only)

  URL fetcher (url: type only):
  (fetch-extract:REGEX)      Fetch URL, extract capture group 1 via perl
  (fetch-json:JQ_PATH)       Fetch URL as JSON, extract via jq expression
  (url-probe:PATH1,PATH2)    Probe URL paths per Ubuntu codename for availability
  (url-probe-depth:N)        Codenames back to probe (default: 6)

  Output and dependency:
  (version-prefix:PREFIX)    Prepend PREFIX to proposed version before comparison
  (depends-on:VAR:major)     Hold update when proposed major differs from VAR's major
  (pecl-ref:NAME)            Override PECL extension name for pecl-git annotations

  Annotation-only metadata (not processed at runtime):
  (propagate)                Migration hint — marks vars that need multi-file propagation
  (compat:RUNTIME>=X.Y)      Migration hint — compatibility constraint recorded as hint text

Examples:
  bin/env-update.sh
  bin/env-update.sh --dry-run --filter=NODE22
  bin/env-update.sh --type=dockerhub,github --no-auto-apply
  bin/env-update.sh --offline  # use cached results only
  bin/env-update.sh --type=npm,pypi,rubygems,codeberg
EOF
}

_gs_eu_parse_args() {
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --dry-run)         _GS_EU_DRY_RUN="true" ;;
      --offline)         _GS_EU_OFFLINE="true" ;;
      --no-cache)        _GS_EU_NO_CACHE="true" ;;
      --cache-ttl=*)     _GS_EU_CACHE_TTL="${arg#*=}" ;;
      --filter=*)        _GS_EU_FILTER="${arg#*=}" ;;
      --type=*)          _GS_EU_TYPE_FILTER="${arg#*=}" ;;
      --no-auto-apply)   _GS_EU_NO_AUTO_APPLY="true" ;;
      --no-override)     _GS_EU_NO_OVERRIDE="true" ;;
      --patch-file=*)    _GS_EU_PATCH_FILE="${arg#*=}" ;;
      --report-file=*)   _GS_EU_REPORT_FILE="${arg#*=}" ;;
      --github-token=*)  GITHUB_TOKEN="${arg#*=}" ;;
      --debug)           _GS_EU_DEBUG="true" ;;
      --show-ok)         _GS_EU_SHOW_OK="true" ;;
      --show-runtime)    _GS_EU_SHOW_RUNTIME="true" ;;
      --show-dates)      _GS_EU_SHOW_DATES="true" ;;
      --progress)        _GS_EU_SHOW_PROGRESS="true" ;;
      --help)            _gs_eu_show_help; exit 0 ;;
      *)
        printf 'Unknown option: %s\n' "${arg}" >&2
        _gs_eu_show_help >&2
        exit 1
        ;;
    esac
  done
  export GITHUB_TOKEN
}

# --------------------------------------------------------------------------
# Resolve {VAR:format} placeholder substitutions in URL strings
# --------------------------------------------------------------------------
_gs_eu_resolve_url_vars() {
  local input="${1}"
  perl -pe '
    s/\{([A-Z_][A-Z0-9_]*)(?::([^}]+))?\}/
      my ($var, $fmt) = ($1, $2 // "");
      my $val = $ENV{$var} // "";
      if ($fmt eq "major") {
        $val =~ s|[.\-].*$||;
      } elsif ($fmt eq "major.minor") {
        $val =~ s|^([0-9]+\.[0-9]+).*$|$1|;
      }
      $val
    /ge
  ' <<< "${input}"
}

# --------------------------------------------------------------------------
# Write an alt-version hint to the per-fetch temp file.
# Fetchers call this instead of _gs_eu_set_prerelease_hint directly.
# direction: "also" (stable tracking a newer pre-release)
#            "stable" (pre-release tracking toward stable)
# --------------------------------------------------------------------------
_gs_eu_write_alt_version() {
  local direction="${1}"  # "also" or "stable"
  local version="${2}"
  [[ -n "${_GS_EU_ALT_VERSION_FILE:-}" && -n "${version}" ]] && \
    printf '%s:%s\n' "${direction}" "${version}" > "${_GS_EU_ALT_VERSION_FILE}" 2>/dev/null || true
}
export -f _gs_eu_write_alt_version

# --------------------------------------------------------------------------
# Type filter check
# --------------------------------------------------------------------------
_gs_eu_type_is_enabled() {
  local type="${1}"
  if [[ -z "${_GS_EU_TYPE_FILTER}" ]]; then
    return 0
  fi
  local enabled_type
  local enabled_types=()
  IFS=',' read -ra enabled_types <<< "${_GS_EU_TYPE_FILTER}"
  for enabled_type in "${enabled_types[@]}"; do
    [[ "${enabled_type}" == "${type}" ]] && return 0
  done
  return 1
}

# --------------------------------------------------------------------------
# Nightly version fetcher — returns latest nightly build identifier
# Currently handles Node.js nightly; returns empty for unknown identifiers
# --------------------------------------------------------------------------
_gs_eu_fetch_nightly_version() {
  local type="${1}"
  local identifier="${2}"

  if [[ "${_GS_EU_OFFLINE}" == "true" ]]; then
    return 1
  fi

  # Node.js nightly: https://nodejs.org/download/nightly/index.json
  if [[ "${type}" == "github" && "${identifier}" =~ ^nodejs/node ]]; then
    local url="https://nodejs.org/download/nightly/index.json"
    local response
    if response="$(curl --silent --location --fail --max-time 10 --retry 2 "${url}" 2>/dev/null)"; then
      local version
      version="$(printf '%s' "${response}" | jq -r '.[0].version // empty' 2>/dev/null || true)"
      [[ -n "${version}" ]] && echo "${version}" && return 0
    fi
    return 1
  fi

  # Unknown type for nightly — no special handler
  return 1
}

# --------------------------------------------------------------------------
# Dispatch to the appropriate fetcher.
# Clears _GS_EU_ALT_VERSION_FILE before the call, reads it after, and
# translates any written hint into the shared prerelease-hint file keyed
# by env_var.  Fetchers never need env_var_name anymore.
# --------------------------------------------------------------------------
_gs_eu_fetch_latest_version() {
  local type="${1}"
  local identifier="${2}"
  local current_version="${3}"
  local pecl_ref="${4:-}"
  local ref_urls="${5:-}"
  local tag_suffix="${6:-}"
  local tag_filter="${7:-}"
  local tag_exclude="${8:-}"
  local tag_strip_prefix="${9:-}"
  local tag_strip_suffix="${10:-}"
  local tag_extract="${11:-}"
  local env_var="${12:-}"
  local fetch_extract="${13:-}"
  local fetch_json="${14:-}"
  local url_probe="${15:-}"
  local url_probe_depth="${16:-6}"
  local tag_replace_from="${17:-}"
  local tag_replace_to="${18:-}"
  local channel="${19:-}"
  local version_prefix="${20:-}"

  # Reset last fetch error and alt-version hint before each call
  rm -f "${_GS_EU_FETCH_ERROR_FILE}" 2>/dev/null || true
  rm -f "${_GS_EU_ALT_VERSION_FILE}" 2>/dev/null || true

  local _fetched_result=""

  case "${type}" in
    dockerhub)
      _fetched_result="$(_gs_eu_dockerhub_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_EU_OFFLINE}" "${_GS_EU_NO_CACHE}" "${tag_suffix}" "" \
        "${tag_filter}" "${tag_exclude}" "${tag_strip_prefix}" "${tag_strip_suffix}" "${tag_extract}" \
        "${tag_replace_from}" "${tag_replace_to}" "${channel}" "${version_prefix}")"
      ;;
    quay)
      _fetched_result="$(_gs_eu_quay_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_EU_OFFLINE}" "${_GS_EU_NO_CACHE}" \
        "${tag_filter}" "${tag_exclude}" "${tag_strip_prefix}" "${tag_strip_suffix}" "${tag_extract}" \
        "${tag_replace_from}" "${tag_replace_to}" "${channel}" "${version_prefix}")"
      ;;
    github)
      local gh_id="${identifier}" gh_pin=""
      if [[ "${identifier}" =~ ^([^:]+):([0-9]+(\.[0-9]+)*)$ ]]; then
        gh_id="${BASH_REMATCH[1]}"; gh_pin="${BASH_REMATCH[2]}"
      fi
      _fetched_result="$(_gs_eu_github_fetch_latest "${gh_id}" "${current_version}" \
        "${_GS_EU_OFFLINE}" "${_GS_EU_NO_CACHE}" "${gh_pin}" \
        "${tag_filter}" "${tag_exclude}" "${tag_strip_prefix}" "${tag_strip_suffix}" "${tag_extract}" \
        "${tag_replace_from}" "${tag_replace_to}" "${channel}" "${version_prefix}")"
      # Apply version_prefix — github fetcher returns bare version
      if [[ -n "${version_prefix}" && -n "${_fetched_result}" ]]; then
        _fetched_result="${version_prefix}${_fetched_result}"
      fi
      ;;
    npm)
      _fetched_result="$(_gs_eu_npm_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_EU_OFFLINE}" "${_GS_EU_NO_CACHE}" "${channel}" "${env_var}")"
      ;;
    pecl)
      _fetched_result="$(_gs_eu_pecl_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_EU_OFFLINE}" "${_GS_EU_NO_CACHE}" "${channel}")"
      ;;
    pecl-git)
      _fetched_result="$(_gs_eu_pecl_git_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_EU_OFFLINE}" "${_GS_EU_NO_CACHE}" "${pecl_ref:-}")"
      ;;
    sdkman)
      _fetched_result="$(_gs_eu_sdkman_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_EU_OFFLINE}" "${_GS_EU_NO_CACHE}" "${channel}")"
      ;;
    sdkmanager)
      _fetched_result="$(_gs_eu_sdkmanager_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_EU_OFFLINE}" "${_GS_EU_NO_CACHE}" "${channel}")"
      ;;
    pypi)
      _fetched_result="$(_gs_eu_pypi_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_EU_OFFLINE}" "${_GS_EU_NO_CACHE}" "${channel}" "${env_var}")"
      ;;
    url)
      local _resolved_identifier="${identifier}"
      if [[ "${identifier}" == *'{'* ]]; then
        _resolved_identifier="$(_gs_eu_resolve_url_vars "${identifier}")"
      fi
      _fetched_result="$(_gs_eu_url_fetch_latest "${_resolved_identifier}" "${current_version}" \
        "${_GS_EU_OFFLINE}" "${_GS_EU_NO_CACHE}" "${ref_urls}" \
        "${fetch_extract}" "${fetch_json}" "${url_probe}" "${url_probe_depth}" \
        "${channel}" "${version_prefix}")"
      ;;
    codeberg)
      _fetched_result="$(_gs_eu_codeberg_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_EU_OFFLINE}" "${_GS_EU_NO_CACHE}" "${channel}")"
      ;;
    rubygems)
      _fetched_result="$(_gs_eu_rubygems_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_EU_OFFLINE}" "${_GS_EU_NO_CACHE}" "${channel}" "${env_var}")"
      ;;
    *)
      _gs_eu_log_debug "Unknown fetcher type: ${type}"
      ;;
  esac

  # Read alt-version hint written by fetcher and translate to per-var hint file
  if [[ -n "${env_var}" && -f "${_GS_EU_ALT_VERSION_FILE}" ]]; then
    local _alt_line _alt_dir _alt_ver
    _alt_line="$(< "${_GS_EU_ALT_VERSION_FILE}")"
    _alt_dir="${_alt_line%%:*}"
    _alt_ver="${_alt_line#*:}"
    # Apply version_prefix to alt version for github fetcher (returns bare version)
    if [[ "${type}" == "github" && -n "${version_prefix}" && -n "${_alt_ver}" ]]; then
      _alt_ver="${version_prefix}${_alt_ver}"
    fi
    if [[ -n "${_alt_ver}" ]]; then
      # Bug 3: suppress hints where the alt version is a floating/unversioned ref
      # (e.g. "latest", "nightly") — they carry no actionable version information.
      if _gs_eu_is_unversioned "${_alt_ver}"; then
        _alt_ver=""
      fi
    fi
    if [[ -n "${_alt_ver}" ]]; then
      # Hint suppression rule: if the alt version is not actually newer than
      # the proposed/fetched result, suppress the hint — it adds no useful info.
      # Example: stable=1.7.0, alt=1.7.0-RC1 (RC became the release) → suppress.
      local _suppress_hint=false
      local _hint_cmp
      _hint_cmp="$(_gs_eu_semver_compare "${_alt_ver}" "${_fetched_result}" 2>/dev/null || echo "equal")"
      if [[ "${_alt_dir}" == "also" ]]; then
        # "also" hint: alt is a pre-release supposedly newer than stable.
        # Suppress if alt ≤ stable (pre-release was actually promoted, or it's stale).
        if [[ "${_hint_cmp}" == "older" || "${_hint_cmp}" == "equal" ]]; then
          _suppress_hint=true
        fi
      elif [[ "${_alt_dir}" == "stable" ]]; then
        # "stable" hint: alt is the stable, pointing away from a pre-release.
        # Suppress if alt ≤ proposed (stable not actually better than what we'd propose).
        if [[ "${_hint_cmp}" == "older" || "${_hint_cmp}" == "equal" ]]; then
          _suppress_hint=true
        fi
      fi
      # Non-semver alt versions: semver_compare returns "older"/"equal" unreliably —
      # if _fetched_result is empty, never suppress (nothing to compare against).
      if [[ -z "${_fetched_result}" ]]; then
        _suppress_hint=false
      fi
      if [[ "${_suppress_hint}" == "false" ]]; then
        _gs_eu_set_prerelease_hint "${env_var}" "${_alt_ver}" "${_alt_dir}"
      fi
    fi
  fi

  echo "${_fetched_result}"
}

# --------------------------------------------------------------------------
# Handle pecl-git promotion suggestion
# --------------------------------------------------------------------------
_gs_eu_handle_pecl_git_promotion() {
  local env_var="${1}"
  local identifier="${2}"
  local current_sha="${3}"
  local proposed="${4}"
  local hint="${5:-}"
  local line_number="${6:-}"
  local pecl_git_meta="${7:-}"

  # proposed looks like "__pecl_promotion__:imagick:3.9.0"
  if [[ "${proposed}" =~ ^__pecl_promotion__:([^:]+):(.+)$ ]]; then
    local ext_name="${BASH_REMATCH[1]}"
    local pecl_version="${BASH_REMATCH[2]}"

    # Determine the _NAME variable (same prefix, _NAME suffix)
    local name_var="${env_var/_VERSION/_NAME}"

    printf '\n%b\n' "${_GS_EU_CLR_CYAN}[PROMOTE]${_GS_EU_CLR_RESET} pecl-git → pecl stable detected for ${ext_name}:"
    printf '  Suggested changes (MANUAL — both lines must be updated together):\n'
    printf '  %s=%s  →  %s=%s\n' "${name_var}" "${identifier}" "${name_var}" "${ext_name}"
    printf '  %s=%s  →  %s=%s\n' "${env_var}" "${current_sha}" "${env_var}" "${pecl_version}"
    printf '  Annotation should change to:\n'
    printf '    # @todo env-update pecl:%s %s\n' "${ext_name}" "${pecl_version}"
    if [[ -n "${hint}" ]]; then
      printf '    (hint: %s)\n' "${hint}"
    fi
    # Display rich metadata if available
    if [[ -n "${pecl_git_meta}" ]]; then
      printf '  Metadata: %s\n' "${pecl_git_meta}"
    fi

    _gs_eu_log_manual "${env_var}" "pecl-git:${identifier}" \
      "${current_sha}" "${pecl_version}" \
      "PROMOTE: pecl stable available — update _NAME and _VERSION together"
  fi
}

# --------------------------------------------------------------------------
# Process a single record
# --------------------------------------------------------------------------
_gs_eu_process_record() {
  local idx="${1}"

  local env_var="${_GS_EU_RECORDS_ENV_VAR[${idx}]}"
  local current_version="${_GS_EU_RECORDS_CURRENT_VERSION[${idx}]}"
  local type="${_GS_EU_RECORDS_TYPE[${idx}]}"
  local identifier="${_GS_EU_RECORDS_IDENTIFIER[${idx}]}"
  local hint="${_GS_EU_RECORDS_HINT[${idx}]:-}"
  local flags="${_GS_EU_RECORDS_FLAGS[${idx}]:-}"
  local line_number="${_GS_EU_RECORDS_LINE_NUMBER[${idx}]:-}"
  local depends_on="${_GS_EU_RECORDS_DEPENDS_ON[${idx}]:-}"
  local pecl_ref="${_GS_EU_RECORDS_PECL_REF[${idx}]:-}"
  local rec_urls="${_GS_EU_RECORDS_URLS[${idx}]:-}"
  local tag_suffix="${_GS_EU_RECORDS_TAG_SUFFIX[${idx}]:-}"
  local skip_reason="${_GS_EU_RECORDS_SKIP_REASON[${idx}]:-}"
  local tag_filter="${_GS_EU_RECORDS_TAG_FILTER[${idx}]:-}"
  local tag_exclude="${_GS_EU_RECORDS_TAG_EXCLUDE[${idx}]:-}"
  local tag_strip_prefix="${_GS_EU_RECORDS_TAG_STRIP_PREFIX[${idx}]:-}"
  local tag_strip_suffix="${_GS_EU_RECORDS_TAG_STRIP_SUFFIX[${idx}]:-}"
  local tag_extract="${_GS_EU_RECORDS_TAG_EXTRACT[${idx}]:-}"
  local fetch_extract="${_GS_EU_RECORDS_FETCH_EXTRACT[${idx}]:-}"
  local fetch_json="${_GS_EU_RECORDS_FETCH_JSON[${idx}]:-}"
  local url_probe="${_GS_EU_RECORDS_URL_PROBE[${idx}]:-}"
  local url_probe_depth="${_GS_EU_RECORDS_URL_PROBE_DEPTH[${idx}]:-6}"
  local tag_replace_from="${_GS_EU_RECORDS_TAG_REPLACE_FROM[${idx}]:-}"
  local tag_replace_to="${_GS_EU_RECORDS_TAG_REPLACE_TO[${idx}]:-}"
  local channel="${_GS_EU_RECORDS_CHANNEL[${idx}]:-}"
  local version_prefix="${_GS_EU_RECORDS_VERSION_PREFIX[${idx}]:-}"
  local type_id="${type}:${identifier}"

  _gs_eu_log_debug "Processing record #${idx}: ${env_var} [${type_id}] current=${current_version}"

  # Type filter
  if ! _gs_eu_type_is_enabled "${type}"; then
    _gs_eu_log_debug "Type ${type} not in filter — skipping ${env_var}"
    return 0
  fi

  # Floating version refs (master/latest/nightly/next/main/HEAD) — always-current by definition
  # Route to [FLOAT] instead of silently skipping, so the developer is aware of them.
  # Exception: nightly with a dedicated nightly fetcher gets special handling below.
  if _gs_eu_is_unversioned "${current_version}"; then
    # nightly: attempt to fetch the latest nightly build identifier for informational display
    if [[ "${current_version,,}" == "nightly" ]]; then
      local nightly_latest=""
      nightly_latest="$(_gs_eu_fetch_nightly_version "${type}" "${identifier}" 2>/dev/null || true)"
      if [[ -n "${nightly_latest}" ]]; then
        _gs_eu_log_manual "${env_var}" "${type_id}" "${current_version}" "${nightly_latest}" \
          "nightly — latest build shown for reference (manual decision required)"
      else
        _gs_eu_log_float "${env_var}" "${type_id}" "${current_version}" \
          "nightly build — check upstream for latest"
      fi
    else
      # Bug 9: for other floating refs (latest, next, edge, etc.), attempt to fetch the
      # actual latest version from upstream so the developer can see what it resolves to.
      # The result is informational only — no auto-apply is ever triggered for floating refs.
      local _float_latest=""
      if [[ "${_GS_EU_OFFLINE}" != "true" ]]; then
        _float_latest="$(_gs_eu_fetch_latest_version "${type}" "${identifier}" "" \
          "${pecl_ref:-}" "${rec_urls}" "${tag_suffix:-}" \
          "${tag_filter}" "${tag_exclude}" "${tag_strip_prefix}" "${tag_strip_suffix}" "${tag_extract}" \
          "${env_var}" \
          "${fetch_extract}" "${fetch_json}" "${url_probe}" "${url_probe_depth}" \
          "${tag_replace_from}" "${tag_replace_to}" "${channel}" "${version_prefix}" \
          2>/dev/null || true)"
      fi
      local _float_detail="floating ref — always latest"
      if [[ -n "${_float_latest}" ]]; then
        _float_detail="floating ref — latest tag: ${_float_latest}"
      fi
      _gs_eu_log_float "${env_var}" "${type_id}" "${current_version}" "${_float_detail}"
    fi
    return 0
  fi

  # Manual/skip flags — support (skip:REASON) with embedded reason
  if [[ "${flags}" =~ skip ]]; then
    local _skip_display="flagged-skip"
    if [[ -n "${skip_reason}" ]]; then
      _skip_display="flagged-skip:${skip_reason}"
    fi
    _gs_eu_log_skip "${env_var}" "${type_id}" "${_skip_display}"
    return 0
  fi

  # Override flag — always fetch latest for visibility, but NEVER write to .env
  if [[ "${flags}" =~ override ]]; then
    if [[ "${_GS_EU_NO_OVERRIDE}" == "true" ]]; then
      _gs_eu_log_skip "${env_var}" "${type_id}" "override-suppressed (--no-override)"
      return 0
    fi
    local proposed=""
    if ! _gs_eu_is_unversioned "${current_version}"; then
      proposed="$(_gs_eu_fetch_latest_version "${type}" "${identifier}" "${current_version}" \
        "${pecl_ref:-}" "${rec_urls}" "${tag_suffix:-}" \
        "${tag_filter}" "${tag_exclude}" "${tag_strip_prefix}" "${tag_strip_suffix}" "${tag_extract}" \
        "${env_var}" \
        "${fetch_extract}" "${fetch_json}" "${url_probe}" "${url_probe_depth}" \
        "${tag_replace_from}" "${tag_replace_to}" "${channel}" "${version_prefix}" \
        2>/dev/null || true)"
    fi
    _gs_eu_log_override "${env_var}" "${type_id}" "${current_version}" "${proposed:-?}" \
      "overridden — not applied"

    # For major-pinned github overrides (e.g. github:php/php-src:8.4), show the
    # absolute latest stable version as an informational hint so the developer
    # can see when a new major line is available.
    if [[ "${type}" == "github" && "${identifier}" =~ ^([^:/]+/[^:]+):([0-9]) ]]; then
      local _base_id="${BASH_REMATCH[1]}"
      local _overall_latest=""
      _overall_latest="$(_gs_eu_github_fetch_latest "${_base_id}" "" \
        "${_GS_EU_OFFLINE}" "${_GS_EU_NO_CACHE}" "" \
        "${tag_filter}" "${tag_exclude}" "${tag_strip_prefix}" "${tag_strip_suffix}" "${tag_extract}" \
        "${tag_replace_from}" "${tag_replace_to}" "${channel}" "" \
        2>/dev/null || true)"
      if [[ -n "${version_prefix}" && -n "${_overall_latest}" ]]; then
        _overall_latest="${version_prefix}${_overall_latest}"
      fi
      if [[ -n "${_overall_latest}" && "${_overall_latest}" != "${proposed:-}" ]]; then
        printf '%b\n' "        ${_GS_EU_CLR_DIM}↳ latest overall: ${_overall_latest}${_GS_EU_CLR_RESET}"
      fi
    fi
    return 0
  fi

  # Fetch latest
  local proposed=""
  if proposed="$(_gs_eu_fetch_latest_version "${type}" "${identifier}" "${current_version}" \
      "${pecl_ref:-}" "${rec_urls}" "${tag_suffix:-}" \
      "${tag_filter}" "${tag_exclude}" "${tag_strip_prefix}" "${tag_strip_suffix}" "${tag_extract}" \
      "${env_var}" \
      "${fetch_extract}" "${fetch_json}" "${url_probe}" "${url_probe_depth}" \
      "${tag_replace_from}" "${tag_replace_to}" "${channel}" "${version_prefix}" \
      2>/dev/null)"; then
    _gs_eu_log_debug "Fetched: ${proposed}"
  else
    local _fetch_err
    _fetch_err="$(cat "${_GS_EU_FETCH_ERROR_FILE}" 2>/dev/null || true)"
    local _warn_msg="API error — check ${identifier} manually"
    if [[ -n "${_fetch_err}" ]]; then
      _warn_msg="${_fetch_err}"
    fi
    _gs_eu_log_warn "${env_var}" "${type_id}" "${_warn_msg}"
    return 0
  fi

  if [[ -z "${proposed}" ]]; then
    _gs_eu_log_debug "No proposed version returned for ${env_var}"
    if [[ "${type}" == "url" ]]; then
      _gs_eu_log_manual "${env_var}" "${type_id}" "${current_version}" "?" "manual-url — check ${identifier}"
    else
      # Distinguish NORES (empty, no error) from WARN (error recorded)
      local _nores_err
      _nores_err="$(cat "${_GS_EU_FETCH_ERROR_FILE}" 2>/dev/null || true)"
      if [[ -z "${_nores_err}" ]]; then
        # Check if an alt-version "also" hint was written — this means the fetcher found
        # a pre-release but no stable. Show in PRE-RELEASE ONLY section instead of NORES.
        local _preonly_alt=""
        if [[ -f "${_GS_EU_PRERELEASE_HINT_FILE}" ]]; then
          local _preonly_hint_line
          _preonly_hint_line="$(grep "^${env_var}:also:" "${_GS_EU_PRERELEASE_HINT_FILE}" 2>/dev/null | head -1 || true)"
          if [[ -n "${_preonly_hint_line}" ]]; then
            # Extract version from "VARNAME:also: VERSION (pre-release available...)"
            _preonly_alt="${_preonly_hint_line#*:also: }"
            _preonly_alt="${_preonly_alt%% (*}"
          fi
        fi
        if [[ -n "${_preonly_alt}" && "${_preonly_alt}" != "${current_version}" ]]; then
          _gs_eu_log_preonly "${env_var}" "${type_id}" "${current_version}" "${_preonly_alt}"
        elif [[ -n "${_preonly_alt}" ]]; then
          # current == pre-release version — no change, stay silent
          _gs_eu_log_debug "PREONLY suppressed for ${env_var}: current=${current_version} == pre=${_preonly_alt}"
        else
          _gs_eu_log_nores "${env_var}" "${type_id}" "no version returned from ${identifier}"
        fi
      else
        _gs_eu_log_warn "${env_var}" "${type_id}" "${_nores_err}"
      fi
    fi
    return 0
  fi

  # Handle dockerhub major-pin hold sentinel
  if [[ "${proposed}" == __hold_newer_major__:* ]]; then
    # Format: __hold_newer_major__:PINNED_MAJOR:NEWEST_MAJOR:BEST_PINNED_VERSION
    local _hm_rest="${proposed#__hold_newer_major__:}"
    local _hm_pinned="${_hm_rest%%:*}"
    _hm_rest="${_hm_rest#*:}"
    local _hm_newest="${_hm_rest%%:*}"
    local _hm_current_best="${_hm_rest#*:}"
    _gs_eu_log_hold "${env_var}" "${type_id}" "${current_version}" "${_hm_current_best}" \
      "newer-major-available: pinned=${_hm_pinned} newest=${_hm_newest}"
    return 0
  fi

  # Handle dockerhub ubuntu codename upgrade hint sentinel
  if [[ "${proposed}" == __codename_upgrade_hint__:* ]]; then
    # Format: __codename_upgrade_hint__:UPGRADE_TAG:SAME_CODENAME_TAG
    local _ch_rest="${proposed#__codename_upgrade_hint__:}"
    local _ch_upgrade_tag="${_ch_rest%%:*}"
    local _ch_current_best="${_ch_rest#*:}"
    # Log the best same-codename version as AUTO/MANUAL as normal
    proposed="${_ch_current_best}"
    # Also log the codename upgrade as a MANUAL note
    _gs_eu_log_manual "${env_var}" "${type_id}" "${current_version}" "${_ch_upgrade_tag}" \
      "codename-upgrade-available"
    # Fall through to normal decision with proposed = _ch_current_best
  fi

  # Handle pecl-git promotion — includes rich metadata annotation
  if [[ "${proposed}" == __pecl_promotion__* ]]; then
    local _pecl_git_meta="${_GS_EU_PECL_GIT_METADATA:-}"
    _gs_eu_handle_pecl_git_promotion "${env_var}" "${identifier}" "${current_version}" \
      "${proposed}" "${hint}" "${line_number}" "${_pecl_git_meta}"
    return 0
  fi

  # For non-promotion pecl-git results, log metadata if available
  if [[ "${type}" == "pecl-git" && -n "${_GS_EU_PECL_GIT_METADATA:-}" ]]; then
    _gs_eu_log_debug "pecl-git metadata: ${_GS_EU_PECL_GIT_METADATA}"
  fi

  # depends-on hold logic
  if [[ -n "${depends_on}" && -n "${proposed}" ]]; then
    local dep_var="${depends_on%%:*}"
    local dep_constraint="${depends_on##*:}"
    local dep_version=""
    local j
    for (( j=0; j<_GS_EU_RECORD_COUNT; j++ )); do
      if [[ "${_GS_EU_RECORDS_ENV_VAR[${j}]}" == "${dep_var}" ]]; then
        dep_version="${_GS_EU_RECORDS_CURRENT_VERSION[${j}]}"
        break
      fi
    done
    if [[ -n "${dep_version}" && "${dep_constraint}" == "major" ]]; then
      local proposed_major="${proposed%%.*}"
      local dep_major="${dep_version%%.*}"
      if [[ "${proposed_major}" != "${dep_major}" ]]; then
        _gs_eu_log_manual "${env_var}" "${type_id}" "${current_version}" "${proposed}" \
          "depends-on:${dep_var}:major — upgrade ${dep_var} first"
        return 0
      fi
    fi
  fi

  # url-probe special comparison — always MANUAL, user must update sources
  if [[ -n "${url_probe}" && -n "${proposed}" ]]; then
    local normalized_current
    normalized_current="$(_gs_eu_url_probe_normalize_current "${current_version}")"
    if [[ "${normalized_current}" == "${proposed}" ]]; then
      # No change
      _gs_eu_log_debug "url-probe: no change for ${env_var} (${proposed})"
    else
      _gs_eu_log_manual "${env_var}" "${type_id}" "${current_version}" "${proposed}" \
        "url-probe: manual update required — check repo availability and update sources"
    fi
    return 0
  fi

  # Ubuntu-tagged versions: delegate to ubuntu module
  if [[ "${type}" == "dockerhub" ]] && _gs_eu_has_distro_codename "${current_version}" && \
     ! _gs_eu_has_non_ubuntu_distro "${current_version}"; then
    local namespace="${identifier%%/*}"
    local image="${identifier##*/}"
    local ubuntu_decision
    ubuntu_decision="$(_gs_eu_ubuntu_process_record \
      "${env_var}" "${current_version}" "${type_id}" \
      "${namespace}" "${image}" \
      "${_GS_EU_NO_AUTO_APPLY}" "${_GS_EU_DRY_RUN}")"

    local ubuntu_action="${ubuntu_decision%%:*}"
    local ubuntu_reason="${ubuntu_decision#*:}"

    if [[ "${ubuntu_action}" == "SKIP" ]]; then
      if [[ "${ubuntu_reason}" != "codename-current" && "${ubuntu_reason}" != "no-change" ]]; then
        _gs_eu_log_debug "Ubuntu SKIP for ${env_var}: ${ubuntu_reason}"
      fi
    elif [[ "${ubuntu_action}" == "MANUAL" ]]; then
      if [[ "${ubuntu_reason}" == "codename-mismatch-no-tag-available" ]]; then
        printf '%b\n' "${_GS_EU_CLR_YELLOW}[UBUNTU]${_GS_EU_CLR_RESET} %-60s codename mismatch — no new-codename tag available  ${_GS_EU_CLR_DIM}(check ${identifier} manually)${_GS_EU_CLR_RESET}" "${type_id}"
        _gs_eu_log_ubuntu "${env_var}" "${current_version}" "${proposed}" "manual: no-tag-for-new-codename"
      else
        _gs_eu_log_ubuntu "${env_var}" "${current_version}" "${proposed}" "manual"
        _gs_eu_log_manual "${env_var}" "${type_id}" "${current_version}" "${proposed}" "${ubuntu_reason}"
      fi
    elif [[ "${ubuntu_action}" == "AUTO" ]]; then
      _gs_eu_log_ubuntu "${env_var}" "${current_version}" "${proposed}" "applied"
      _gs_eu_apply_update "${STACK_DIR}" "${_GS_EU_ENV_FILE}" \
        "${env_var}" "${current_version}" "${proposed}" "${_GS_EU_DRY_RUN}"
      _gs_eu_log_auto "${env_var}" "${type_id}" "${current_version}" "${proposed}" ".env:${line_number}"
    fi
    return 0
  fi

  # Special handling for GLOBAL_STACK_IMAGE_UBUNTU_VERSION (the base image itself)
  if [[ "${env_var}" == "GLOBAL_STACK_IMAGE_UBUNTU_VERSION" && "${type}" == "dockerhub" ]]; then
    local latest_ubuntu
    if latest_ubuntu="$(_gs_eu_ubuntu_fetch_latest_ubuntu_image "${current_version}" "${_GS_EU_UBUNTU_ENV_CODENAME}" 2>/dev/null)"; then
      if [[ -n "${latest_ubuntu}" && "${latest_ubuntu}" != "${current_version}" ]]; then
        if [[ "${_GS_EU_NO_AUTO_APPLY}" == "true" || "${_GS_EU_DRY_RUN}" == "true" ]]; then
          _gs_eu_log_manual "${env_var}" "${type_id}" "${current_version}" "${latest_ubuntu}" "ubuntu-base-image"
        else
          _gs_eu_apply_update "${STACK_DIR}" "${_GS_EU_ENV_FILE}" \
            "${env_var}" "${current_version}" "${latest_ubuntu}" "${_GS_EU_DRY_RUN}"
          _gs_eu_log_auto "${env_var}" "${type_id}" "${current_version}" "${latest_ubuntu}" ".env:${line_number}"
        fi
      fi
    fi
    return 0
  fi

  # Standard decision
  local decision
  decision="$(_gs_eu_decide_action "${type}" "${identifier}" "${flags}" \
    "${current_version}" "${proposed}" "${hint}" "${channel}")"
  local action="${decision%%:*}"
  local reason="${decision#*:}"

  case "${action}" in
    AUTO)
      if [[ "${_GS_EU_NO_AUTO_APPLY}" == "true" || "${_GS_EU_DRY_RUN}" == "true" ]]; then
        _gs_eu_log_manual "${env_var}" "${type_id}" "${current_version}" "${proposed}" "no-auto-apply-mode"
      else
        _gs_eu_apply_update "${STACK_DIR}" "${_GS_EU_ENV_FILE}" \
          "${env_var}" "${current_version}" "${proposed}" "${_GS_EU_DRY_RUN}"
        _gs_eu_log_auto "${env_var}" "${type_id}" "${current_version}" "${proposed}" ".env:${line_number}"
      fi
      ;;
    HOLD)
      _gs_eu_log_hold "${env_var}" "${type_id}" "${current_version}" "${proposed}" "${reason}"
      ;;
    MANUAL)
      _gs_eu_log_manual "${env_var}" "${type_id}" "${current_version}" "${proposed}" "${reason}"
      ;;
    SKIP)
      if [[ "${reason}" == "no-change" ]]; then
        # Inline display: silent UNLESS a prerelease hint exists (e.g. a newer pre-release
        # is available while tracking stable — show as SKIP with hint).
        local _nc_hint=""
        if [[ -n "${_GS_EU_PRERELEASE_HINT_FILE:-}" && -f "${_GS_EU_PRERELEASE_HINT_FILE}" ]]; then
          _nc_hint="$(grep "^${env_var}:" "${_GS_EU_PRERELEASE_HINT_FILE}" 2>/dev/null | head -1 || true)"
        fi
        if [[ -n "${_nc_hint}" ]]; then
          # Has a prerelease hint: show as SKIP (with hint appended) — not in OK list
          _gs_eu_log_skip "${env_var}" "${type_id}" "no-change"
        else
          # Truly up-to-date: record to OK array (displayed with --show-ok)
          _gs_eu_log_ok "${env_var}" "${type_id}" "${current_version}"
        fi
      else
        # proposed-older carries the fetched version as third colon-field
        if [[ "${reason}" == proposed-older:* ]]; then
          local fetched_ver="${reason#proposed-older:}"
          _gs_eu_log_skip "${env_var}" "${type_id}" \
            "proposed-older: fetched=${fetched_ver} < current=${current_version}"
        else
          _gs_eu_log_skip "${env_var}" "${type_id}" "${reason}"
        fi
      fi
      ;;
  esac
}

# --------------------------------------------------------------------------
# Patch file generation
# --------------------------------------------------------------------------
_gs_eu_generate_patch_file() {
  local patch_file="${1}"

  # Create empty patch file
  : > "${patch_file}"

  local entry
  for entry in "${_GS_EU_REPORT_AUTO[@]:-}"; do
    [[ -z "${entry}" ]] && continue
    IFS='|' read -r ev ti ov nv _loc <<< "${entry}"

    # Generate diff for .env change
    local tmpfile
    tmpfile="$(mktemp)"
    cp "${_GS_EU_ENV_FILE}" "${tmpfile}"
    local escaped_old escaped_new
    # shellcheck disable=SC2001
    escaped_old="$(printf '%s' "${ov}" | sed 's|[.[\*^$()+?{|]|\\&|g')"
    # shellcheck disable=SC2001
    escaped_new="$(printf '%s' "${nv}" | sed 's|[&/\]|\\&|g')"
    sed -i "s|^${ev}=${escaped_old}$|${ev}=${escaped_new}|g" "${tmpfile}" 2>/dev/null || true
    diff -u "${_GS_EU_ENV_FILE}" "${tmpfile}" >> "${patch_file}" 2>/dev/null || true
    rm -f "${tmpfile}"
  done
}

# --------------------------------------------------------------------------
# Main execution
# --------------------------------------------------------------------------
main() {
  _gs_eu_parse_args "$@"

  _gs_eu_log_info "Global Stack env-update starting..."
  _gs_eu_log_info "Stack dir: ${STACK_DIR}"
  _gs_eu_log_info "Env file:  ${_GS_EU_ENV_FILE}"

  if [[ ! -f "${_GS_EU_ENV_FILE}" ]]; then
    printf 'ERROR: .env file not found at %s\n' "${_GS_EU_ENV_FILE}" >&2
    exit 1
  fi

  # Initialize temp files
  _gs_eu_cache_init
  # Initialize prerelease hint file (empty)
  : > "${_GS_EU_PRERELEASE_HINT_FILE}" 2>/dev/null || true

  # Initialize Ubuntu codename context
  _gs_eu_ubuntu_init "${_GS_EU_ENV_FILE}"
  if [[ -n "${_GS_EU_UBUNTU_ENV_CODENAME}" ]]; then
    _gs_eu_log_info "Ubuntu target codename: ${_GS_EU_UBUNTU_ENV_CODENAME} (from ${_GS_EU_UBUNTU_ENV_VERSION})"
  fi

  # Set base Ubuntu codename for dockerhub E4 codename-upgrade hints
  _GS_EU_UBUNTU_CODENAME="${GLOBAL_STACK_IMAGE_UBUNTU_VERSION%%-*}"
  export _GS_EU_UBUNTU_CODENAME

  # Build Dockerfile map
  _gs_eu_dockerfile_build_map "${STACK_DIR}"

  # Parse .env file
  _gs_eu_log_info "Parsing .env annotations..."
  _gs_eu_parse_env_file "${_GS_EU_ENV_FILE}" "${_GS_EU_FILTER}"
  _gs_eu_log_info "Found ${_GS_EU_RECORD_COUNT} annotated variables"

  if [[ "${_GS_EU_RECORD_COUNT}" -eq 0 ]]; then
    _gs_eu_log_info "No annotated variables found. Run bin/migrate-annotations.sh first."
    exit 0
  fi

  # Process all records — sequential per type group to avoid mixing output
  _gs_eu_log_info "Checking for updates..."

  # Collect records by type
  declare -A _gs_eu_type_to_indices=()
  local i
  for (( i=0; i<_GS_EU_RECORD_COUNT; i++ )); do
    local t="${_GS_EU_RECORDS_TYPE[${i}]}"
    if [[ -n "${_gs_eu_type_to_indices[${t}]+x}" ]]; then
      _gs_eu_type_to_indices[${t}]+=" ${i}"
    else
      _gs_eu_type_to_indices[${t}]="${i}"
    fi
  done

  # Count total records for progress indicator
  local _total_records=0 _processed_records=0
  if [[ "${_GS_EU_SHOW_PROGRESS:-false}" == "true" && -t 2 ]]; then
    local _type_count
    for _type_count in "${!_gs_eu_type_to_indices[@]}"; do
      if _gs_eu_type_is_enabled "${_type_count}"; then
        local _idx_str="${_gs_eu_type_to_indices[${_type_count}]}"
        local _idx_arr=()
        IFS=' ' read -ra _idx_arr <<< "${_idx_str}"
        (( _total_records += ${#_idx_arr[@]} )) || true
      fi
    done
  fi

  # Process each type group sequentially (output ordering matters)
  local type
  for type in "${!_gs_eu_type_to_indices[@]}"; do
    if ! _gs_eu_type_is_enabled "${type}"; then
      continue
    fi

    local indices_str="${_gs_eu_type_to_indices[${type}]}"
    local indices=()
    # shellcheck disable=SC2207
    IFS=' ' read -ra indices <<< "${indices_str}"

    _gs_eu_log_debug "Processing type ${type}: ${#indices[@]} records"

    local idx
    for idx in "${indices[@]}"; do
      [[ -z "${idx}" ]] && continue
      # Progress indicator (stderr, terminal only)
      if [[ "${_GS_EU_SHOW_PROGRESS:-false}" == "true" && -t 2 && "${_total_records}" -gt 0 ]]; then
        (( _processed_records++ )) || true
        local _prog_ti="${_GS_EU_RECORDS_TYPE[${idx}]:-?}:${_GS_EU_RECORDS_IDENTIFIER[${idx}]:-?}"
        printf '\r\033[K  [%d/%d] %s...' "${_processed_records}" "${_total_records}" "${_prog_ti}" >&2
      fi
      _gs_eu_process_record "${idx}" || true
    done
  done
  # Clear progress line
  if [[ "${_GS_EU_SHOW_PROGRESS:-false}" == "true" && -t 2 ]]; then
    printf '\r\033[K' >&2
  fi

  # Generate patch file
  if [[ ${#_GS_EU_REPORT_AUTO[@]} -gt 0 ]]; then
    _gs_eu_generate_patch_file "${_GS_EU_PATCH_FILE}"
  fi

  # Write JSON report
  _gs_eu_write_json_report "${_GS_EU_REPORT_FILE}"

  # Print summary
  _gs_eu_print_summary "${_GS_EU_PATCH_FILE}" "${_GS_EU_REPORT_FILE}"

  # Cleanup temp files
  rm -f "${_GS_EU_PRERELEASE_HINT_FILE}" 2>/dev/null || true
  rm -f "${_GS_EU_ALT_VERSION_FILE}" 2>/dev/null || true
}

main "$@"
