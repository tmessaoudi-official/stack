#!/bin/bash
# pecl.sh — PECL REST API fetcher for pecl: annotations.
#
# Exports:   _gs_eu2_pecl_fetch_allreleases  _gs_eu2_pecl_parse_stable
#            _gs_eu2_pecl_get_latest_stable  _gs_eu2_pecl_get_release_date
#            _gs_eu2_pecl_check_promotion    _gs_eu2_fetch_pecl
# Sources:   http/curl.sh  core/cache.sh  fetchers/github.sh
# Deps:      curl, grep, sed, sort
# Env:       _GS_EU2_CFG[no_cache]
#
# Input:  record index — reads identifier/channel/git_repo
# Output: writes proposed_version + proposed_sha + proposed_sha_date into record;
#         sets decision=ERROR when no stable release found
#
# PECL REST API:
#   allreleases: https://pecl.php.net/rest/r/{ext}/allreleases.xml
#   per-version: https://pecl.php.net/rest/r/{ext}/{version}.xml
# XML is parsed with grep/sed — no xmllint required (mirrors v1 pattern).
# XML format: <v>VERSION</v><s>stable|beta|alpha|devel</s>
#
# When (git:owner/repo) flag is set, also fetches HEAD SHA from GitHub so
# decide.sh can compare the current SHA against HEAD for pecl-git type vars.

[[ -n "${_GS_EU2_PECL_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_PECL_SH_LOADED=1

# shellcheck source=../http/curl.sh
source "$(dirname "${BASH_SOURCE[0]}")/../http/curl.sh"
# shellcheck source=../core/cache.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/cache.sh"
# shellcheck source=./github.sh
source "$(dirname "${BASH_SOURCE[0]}")/github.sh"

# _gs_eu2_pecl_fetch_allreleases — fetch the allreleases.xml for a PECL extension.
#
# Args:    $1 ext — PECL extension name (e.g. "apcu", "redis")
# Prints:  raw XML from https://pecl.php.net/rest/r/{ext}/allreleases.xml
# Returns: 0 on success; non-zero on HTTP failure
_gs_eu2_pecl_fetch_allreleases() {
  local _ext="${1}"
  local _url="https://pecl.php.net/rest/r/${_ext}/allreleases.xml"
  _gs_eu2_http_get "${_url}"
}

# _gs_eu2_pecl_parse_stable — parse allreleases XML and select highest acceptable version.
#
# Args:    $1 xml     — raw allreleases XML string
#          $2 channel — "stable" (default) or "unstable"
# Prints:  highest version string matching channel, or empty if none
# Returns: 0 always
#
# PECL CHANNEL MODEL — BINARY, NOT GRADUATED:
#   The PECL channel model is binary. Either:
#   - channel = "stable" (default): only releases with stability == "stable" are accepted.
#   - channel = "unstable": ALL stability levels are accepted (stable, beta, alpha, devel).
#   There is no "beta-only" or "alpha-only" mode — unstable means ALL non-stable included.
#   If the annotation uses (channel:unstable), the highest version across all stabilities
#   is returned, which may be a stable release if it is the newest.
_gs_eu2_pecl_parse_stable() {
  local _xml="${1}"
  local _channel="${2:-stable}"
  # Extract all v:s pairs; keep accepted stability entries; sort and pick highest.
  # Two pipefail hazards absorbed with || true:
  #   1. grep exits 1 when no <v>...</v><s>...</s> pairs are found at all.
  #   2. The while body's last iteration may exit 1 when the stability check
  #      is false (non-accepted release) — the [[ ]] && printf pattern leaves
  #      exit code 1 as the last command result, which pipefail propagates.
  printf '%s' "${_xml}" \
    | { grep -oE '<v>[^<]+</v><s>[^<]+</s>' || true; } \
    | sed 's|<v>\([^<]*\)</v><s>\([^<]*\)</s>|\1:\2|g' \
    2>/dev/null \
    | while IFS=: read -r _ver _stab; do
        if [[ "${_channel}" == "unstable" ]]; then
          case "${_stab,,}" in
            stable | beta | alpha | devel) printf '%s\n' "${_ver}" ;;
            *) true ;;
          esac
        else
          [[ "${_stab,,}" == "stable" ]] && printf '%s\n' "${_ver}" || true
        fi
      done \
    | sort -V | tail -1
}

# _gs_eu2_pecl_get_latest_stable — return latest PECL version for an extension.
#
# Args:    $1 ext     — PECL extension name
#          $2 channel — "stable" (default) or "unstable"
# Prints:  latest version string, or empty when no matching release or HTTP fails
# Returns: 0 always (errors are silent — empty output signals failure)
# Side fx: reads/writes cache keyed on "pecl2:{channel}:{ext}"
_gs_eu2_pecl_get_latest_stable() {
  local _ext="${1}"
  local _channel="${2:-stable}"
  # Cache key includes channel so stable and unstable runs never share entries.
  local _cache_key="pecl2:${_channel}:${_ext}"

  # Cache read
  local _no_cache="${_GS_EU2_CFG[no_cache]:-false}"
  if [[ "${_no_cache}" != "true" ]]; then
    local _cached
    if _cached="$(_gs_eu2_cache_read "${_cache_key}" 2>/dev/null)" && [[ -n "${_cached}" ]]; then
      printf '%s' "${_cached}"
      return 0
    fi
  fi

  local _xml
  _xml="$(_gs_eu2_pecl_fetch_allreleases "${_ext}" 2>/dev/null)" || return 0

  local _ver
  _ver="$(_gs_eu2_pecl_parse_stable "${_xml}" "${_channel}")"
  [[ -z "${_ver}" ]] && return 0

  [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_ver}"
  printf '%s' "${_ver}"
}

# _gs_eu2_pecl_get_release_date — return release date for a specific PECL version.
#
# Args:    $1 ext     — PECL extension name
#          $2 version — version string (e.g. "5.3.7")
# Prints:  release date as YYYY-MM-DD, or empty on failure
# Returns: 0 always
# Side fx: reads/writes cache keyed on "pecl2:date:{ext}:{version}"
#
# Fetches https://pecl.php.net/rest/r/{ext}/{version}.xml and extracts <da>...</da>.
_gs_eu2_pecl_get_release_date() {
  local _ext="${1}" _ver="${2}"
  local _cache_key="pecl2:date:${_ext}:${_ver}"

  local _no_cache="${_GS_EU2_CFG[no_cache]:-false}"
  if [[ "${_no_cache}" != "true" ]]; then
    local _cached
    if _cached="$(_gs_eu2_cache_read "${_cache_key}" 2>/dev/null)" && [[ -n "${_cached}" ]]; then
      printf '%s' "${_cached}"
      return 0
    fi
  fi

  local _url="https://pecl.php.net/rest/r/${_ext}/${_ver}.xml"
  local _xml
  _xml="$(_gs_eu2_http_get "${_url}" 2>/dev/null)" || return 0

  # <da>YYYY-MM-DD HH:MM:SS</da>
  local _date
  _date="$(printf '%s' "${_xml}" \
    | grep -oE '<da>[^<]+</da>' \
    | head -1 \
    | sed 's|<da>\([^<]*\)</da>|\1|' \
    | cut -c1-10 \
    2>/dev/null || true)"

  [[ -z "${_date}" ]] && return 0
  [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_date}"
  printf '%s' "${_date}"
}

# _gs_eu2_pecl_check_promotion — check if PECL has released a newer stable version.
#
# Args:    $1 ext         — PECL extension name
#          $2 commit_date — YYYY-MM-DD date of the current git commit (pecl-git baseline)
# Prints:  latest stable PECL version string if release date > commit_date; else empty
# Returns: 0 always
#
# Used by the pecl-git fetcher flow: if PECL released after the current pinned
# git commit, there is likely a newer stable release worth pinning to instead.
_gs_eu2_pecl_check_promotion() {
  local _ext="${1}" _commit_date="${2}"

  local _stable_ver
  _stable_ver="$(_gs_eu2_pecl_get_latest_stable "${_ext}")"
  [[ -z "${_stable_ver}" ]] && return 0

  local _release_date
  _release_date="$(_gs_eu2_pecl_get_release_date "${_ext}" "${_stable_ver}")"

  if [[ -z "${_release_date}" || -z "${_commit_date}" ]]; then
    # No dates available — cannot determine ordering; no promotion hint
    return 0
  fi

  # PECL release is newer than git commit → suggest promotion
  if [[ "${_release_date}" > "${_commit_date}" ]]; then
    printf '%s' "${_stable_ver}"
  fi
  return 0
}

# _gs_eu2_fetch_pecl — main entry point for the pecl: fetcher type.
#
# Args:    $1 record_index — 0-based record index
# Reads:   record fields: identifier, channel, git_repo
# Sets:    record fields: proposed_version, proposed_sha, proposed_sha_date,
#          decision (ERROR only), error_message
# Prints:  nothing
# Returns: 0 always
#
# Identifier = bare PECL extension name (e.g. "apcu", "redis", "imagick").
# Caching is handled by _gs_eu2_pecl_get_latest_stable — not at this level.
# When channel=unstable, beta/alpha/devel releases are accepted alongside stable.
# When git_repo is set, also fetches the HEAD SHA from GitHub for SHA tracking.
_gs_eu2_fetch_pecl() {
  local _idx="${1}"

  local _identifier
  _identifier="$(_gs_eu2_record_get "${_idx}" identifier)"

  # Read channel flag from annotation record (default: stable).
  local _channel
  _channel="$(_gs_eu2_record_get "${_idx}" channel)"
  _channel="${_channel:-stable}"

  local _ver
  _ver="$(_gs_eu2_pecl_get_latest_stable "${_identifier}" "${_channel}")"

  if [[ -z "${_ver}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "pecl: no stable release found for '${_identifier}'"
    return 0
  fi

  _gs_eu2_record_set "${_idx}" proposed_version "${_ver}"

  # If (git:owner/repo) flag is set, fetch HEAD SHA from the repo.
  # HEAD is always preferred over a tagged SHA: the user runs PHP master and
  # installs extensions from PECL anyway (SHA is a reference anchor, not a pin),
  # so we want the freshest commit that works with unreleased PHP versions.
  local _git_repo
  _git_repo="$(_gs_eu2_record_get "${_idx}" git_repo)"
  if [[ -n "${_git_repo}" ]]; then
    local _proposed_sha=""
    _proposed_sha="$(_gs_eu2_github_get_commit_sha "${_git_repo}" "HEAD" 2>/dev/null)" || true
    if [[ -n "${_proposed_sha}" ]]; then
      _gs_eu2_record_set "${_idx}" proposed_sha "${_proposed_sha}"
      local _proposed_sha_date=""
      _proposed_sha_date="$(_gs_eu2_github_get_commit_date "${_git_repo}" "${_proposed_sha}" 2>/dev/null)" || true
      [[ -n "${_proposed_sha_date}" ]] && _gs_eu2_record_set "${_idx}" proposed_sha_date "${_proposed_sha_date}"
    fi
  fi

  return 0
}
