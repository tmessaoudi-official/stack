#!/bin/bash
# dockerhub.sh — Docker Hub tag fetcher using the record-index contract
#
# Input:  record index — reads type/identifier/channel/tag_*/major_hint etc.
# Output: writes proposed_version + decision + error_message back into record

[[ -n "${_GS_EU2_DOCKERHUB_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_DOCKERHUB_SH_LOADED=1

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

# Normalise _/imagename → library/imagename; user/image stays as-is
_gs_eu2_dh_namespace() {
  local _id="${1}"
  if [[ "${_id}" == _/* ]]; then
    printf 'library/%s' "${_id#_/}"
  else
    printf '%s' "${_id}"
  fi
}

# Fetch all tags for a namespace/image from Docker Hub.
# C1: Follows the "next" pagination link until null, accumulating all tag names.
# Returns newline-separated list of tag names on stdout, non-zero on failure.
_gs_eu2_dh_fetch_tags() {
  local _ns="${1}"
  local _url="https://registry.hub.docker.com/v2/repositories/${_ns}/tags?page_size=100&ordering=last_updated"
  local _all_tags="" _resp _page_tags _next_url

  while [[ -n "${_url}" ]]; do
    if ! _resp="$(_gs_eu2_http_get "${_url}")"; then
      return 1
    fi
    if ! _page_tags="$(printf '%s\n' "${_resp}" | jq -r '.results[].name' 2>/dev/null)"; then
      return 1
    fi
    _all_tags="${_all_tags}${_page_tags}"$'\n'
    _next_url="$(printf '%s\n' "${_resp}" | jq -r '.next // empty' 2>/dev/null)"
    _url="${_next_url}"
  done

  printf '%s' "${_all_tags}"
}

# Main fetcher entry point — takes one argument: record index.
# Reads record fields, fetches, applies tag flags + channel selection,
# writes proposed_version + decision + error_message back.
_gs_eu2_fetch_dockerhub() {
  local _idx="${1}"

  local _identifier _channel _major_hint _current _no_cache
  _identifier="$(_gs_eu2_record_get "${_idx}" identifier)"
  _channel="$(_gs_eu2_record_get "${_idx}" channel)"
  _major_hint="$(_gs_eu2_record_get "${_idx}" major_hint)"
  _current="$(_gs_eu2_record_get "${_idx}" current_version)"
  _no_cache="${_GS_EU2_CFG[no_cache]:-false}"

  local _ns
  _ns="$(_gs_eu2_dh_namespace "${_identifier}")"

  # tag_suffix: if set, must be the record's tag_suffix field — used for cache key + filter
  local _tag_suffix
  _tag_suffix="$(_gs_eu2_record_get "${_idx}" tag_suffix)"

  # Build cache key
  local _cache_key="dockerhub:${_ns}:${_tag_suffix}:${_major_hint}:${_channel}"

  # Cache read
  if [[ "${_no_cache}" != "true" ]]; then
    local _cached
    if _cached="$(_gs_eu2_cache_read "${_cache_key}")" && [[ -n "${_cached}" ]]; then
      _gs_eu2_record_set "${_idx}" proposed_version "${_cached}"
      _gs_eu2_record_set "${_idx}" decision         "AUTO"
      return 0
    fi
  fi

  # Fetch tags
  local _raw_tags
  if ! _raw_tags="$(_gs_eu2_dh_fetch_tags "${_ns}" 2>/dev/null)"; then
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "fetch failed for ${_ns}"
    return 0
  fi

  if [[ -z "${_raw_tags}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "no tags returned for ${_ns}"
    return 0
  fi

  # Apply tag-suffix filter first (before full tag_flags pipeline)
  local _tags="${_raw_tags}"
  if [[ -n "${_tag_suffix}" ]]; then
    _tags="$(printf '%s\n' "${_tags}" | grep -F -- "${_tag_suffix}" || true)"
  fi

  # Apply full tag flags pipeline
  _tags="$(printf '%s\n' "${_tags}" | _gs_eu2_apply_tag_flags_from_record "${_idx}")"

  # C3: Major-pin filter — anchor end of major component with ([.^-]|$) to prevent
  # major_hint="18" from matching "180.0" (the | was missing the $ end-of-string case).
  if [[ -n "${_major_hint}" ]]; then
    _tags="$(printf '%s\n' "${_tags}" | grep -E "^${_major_hint}([.^-]|\$)" 2>/dev/null \
      || printf '%s\n' "${_tags}" | awk -F'[.-]' -v m="${_major_hint}" '$1 == m' || true)"
  fi

  if [[ -z "${_tags}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "SKIP"
    _gs_eu2_record_set "${_idx}" error_message "no tags matched filters for ${_ns}"
    return 0
  fi

  # Detect all-unversioned tag set (e.g. oracle-xe image has only "latest")
  local _has_versioned=false _utag
  while IFS= read -r _utag; do
    [[ -z "${_utag}" ]] && continue
    if ! _gs_eu2_is_unversioned "${_utag}"; then _has_versioned=true; break; fi
  done <<< "${_tags}"
  if [[ "${_has_versioned}" == "false" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "SKIP"
    _gs_eu2_record_set "${_idx}" error_message "no versioned tags available for ${_ns}"
    return 0
  fi

  # Channel selection → proposed
  local _proposed
  _proposed="$(_gs_eu2_channel_select_best "${_tags}" "${_channel}")"

  if [[ -z "${_proposed}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "SKIP"
    _gs_eu2_record_set "${_idx}" error_message "channel selection returned nothing for ${_ns}"
    return 0
  fi

  # B3: re-prepend version_prefix stripped by tag-strip-prefix (e.g. "v" for moby/buildkit)
  local _vp
  _vp="$(_gs_eu2_record_get "${_idx}" version_prefix)"
  [[ -n "${_vp}" ]] && _proposed="${_vp}${_proposed}"

  # Write result
  _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"

  # C3: Classify decision: if major_hint set and proposed has different major → HOLD
  # Use ([.^-]|$) anchor to prevent "18" matching "180.x".
  if [[ -n "${_major_hint}" && ! "${_proposed}" =~ ^${_major_hint}([.^-]|$) ]]; then
    _gs_eu2_record_set "${_idx}" decision "HOLD"
  else
    _gs_eu2_record_set "${_idx}" decision "AUTO"
  fi

  # Cache the result
  [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"

  return 0
}
