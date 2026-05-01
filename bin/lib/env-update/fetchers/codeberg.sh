#!/bin/bash
# codeberg.sh — Codeberg (Gitea) releases/tags fetcher using the record-index contract
#
# Input:  record index — reads type/identifier/channel/tag_*/major_hint etc.
# Output: writes proposed_version + decision + error_message back into record
#
# API: https://codeberg.org/api/v1/repos/{owner}/{repo}/releases?limit=50&page=1
# Fallback to tags endpoint when releases array is empty.

[[ -n "${_GS_EU2_CODEBERG_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_CODEBERG_SH_LOADED=1

# shellcheck source=./../core/records.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/records.sh"
# shellcheck source=./../core/semver.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/semver.sh"
# shellcheck source=./../core/channel.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/channel.sh"
# shellcheck source=./../core/tag_flags.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/tag_flags.sh"
# shellcheck source=./../core/cache.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/cache.sh"
# shellcheck source=./../http/curl.sh
source "$(dirname "${BASH_SOURCE[0]}")/../http/curl.sh"

# Fetch tag list from Codeberg tags endpoint (fallback / explicit).
# Returns newline-separated tag names. Non-zero on HTTP failure.
_gs_eu2_cb_fetch_tags() {
  local _identifier="${1}"
  local _url="https://codeberg.org/api/v1/repos/${_identifier}/tags?limit=50"
  local _resp

  if ! _resp="$(_gs_eu2_http_get "${_url}" 2>/dev/null)"; then
    return 1
  fi

  printf '%s\n' "${_resp}" | jq -r '.[].name' 2>/dev/null || true
}

# Main fetcher entry point — takes one argument: record index.
_gs_eu2_fetch_codeberg() {
  local _idx="${1}"

  local _identifier _channel _major_hint _no_cache
  _identifier="$(_gs_eu2_record_get "${_idx}" identifier)"
  _channel="$(_gs_eu2_record_get "${_idx}" channel)"
  _major_hint="$(_gs_eu2_record_get "${_idx}" major_hint)"
  _no_cache="${_GS_EU2_CFG[no_cache]:-false}"

  # Build cache key — same shape as dockerhub for consistency
  local _cache_key="codeberg:${_identifier}:${_major_hint}:${_channel}"

  # Cache read
  if [[ "${_no_cache}" != "true" ]]; then
    local _cached
    if _cached="$(_gs_eu2_cache_read "${_cache_key}")" && [[ -n "${_cached}" ]]; then
      _gs_eu2_record_set "${_idx}" proposed_version "${_cached}"
      return 0
    fi
  fi

  # Fetch releases endpoint — write JSON to temp file to avoid subshell variable leak.
  # We need to inspect both the return code AND the content (empty array vs real failure).
  local _releases_tmp
  _releases_tmp="$(mktemp)"
  local _releases_ok=false _releases_empty=false
  local _releases_url="https://codeberg.org/api/v1/repos/${_identifier}/releases?limit=50&page=1"
  if _gs_eu2_http_get "${_releases_url}" 2>/dev/null > "${_releases_tmp}"; then
    _releases_ok=true
    local _count
    _count="$(jq 'length' "${_releases_tmp}" 2>/dev/null || printf '0')"
    [[ "${_count}" == "0" ]] && _releases_empty=true
  fi

  local _raw_tags=""
  if [[ "${_releases_ok}" == "true" && "${_releases_empty}" == "false" ]]; then
    # Non-empty releases: extract tag_name from non-draft entries (prerelease included)
    _raw_tags="$(jq -r '.[] | select(.draft == false) | .tag_name' "${_releases_tmp}" 2>/dev/null || true)"
  else
    # Releases failed or empty → fall back to tags endpoint
    if ! _raw_tags="$(_gs_eu2_cb_fetch_tags "${_identifier}")"; then
      rm -f "${_releases_tmp}"
      _gs_eu2_record_set "${_idx}" decision      "ERROR"
      _gs_eu2_record_set "${_idx}" error_message "fetch failed for codeberg:${_identifier}"
      return 0
    fi
  fi
  rm -f "${_releases_tmp}"

  if [[ -z "${_raw_tags}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "no tags returned for codeberg:${_identifier}"
    return 0
  fi

  # Apply full tag flags pipeline
  local _tags
  _tags="$(printf '%s\n' "${_raw_tags}" | _gs_eu2_apply_tag_flags_from_record "${_idx}")"

  # Major-pin filter
  if [[ -n "${_major_hint}" ]]; then
    _tags="$(printf '%s\n' "${_tags}" | grep -E "^v?${_major_hint}([.^-]|\$)" 2>/dev/null \
      || printf '%s\n' "${_tags}" | awk -F'[v.-]' -v m="${_major_hint}" '
        { v=$0; sub(/^v/,"",v); split(v,a,"[.-]"); if(a[1]==m) print $0 }' || true)"
  fi

  if [[ -z "${_tags}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "SKIP"
    _gs_eu2_record_set "${_idx}" error_message "no tags matched filters for codeberg:${_identifier}"
    return 0
  fi

  # Channel selection → proposed
  local _proposed
  _proposed="$(_gs_eu2_channel_select_best "${_tags}" "${_channel}")"

  if [[ -z "${_proposed}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "SKIP"
    _gs_eu2_record_set "${_idx}" error_message "channel selection returned nothing for codeberg:${_identifier}"
    return 0
  fi

  # Re-prepend version_prefix stripped by tag-strip-prefix (mirrors dockerhub B3)
  local _vp
  _vp="$(_gs_eu2_record_get "${_idx}" version_prefix)"
  [[ -n "${_vp}" ]] && _proposed="${_vp}${_proposed}"

  # Write result — proposed_version only; decision left empty for decide.sh
  _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"

  # Cache the result
  [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"

  return 0
}
