#!/bin/bash
# quay.sh — Quay.io tag fetcher using the record-index contract
#
# Input:  record index — reads type/identifier/channel/tag_*/major_hint etc.
# Output: writes proposed_version + decision + error_message back into record
#
# API: https://quay.io/api/v1/repository/{org}/{image}/tag/?limit=50&onlyActiveTags=true

[[ -n "${_GS_EU2_QUAY_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_QUAY_SH_LOADED=1

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

# Fetch all tags for an org/image from Quay.io.
# Returns newline-separated list of tag names on stdout, non-zero on HTTP failure.
_gs_eu2_qy_fetch_tags() {
  local _identifier="${1}"
  local _url="https://quay.io/api/v1/repository/${_identifier}/tag/?limit=50&onlyActiveTags=true"
  local _resp

  if ! _resp="$(_gs_eu2_http_get "${_url}" 2>/dev/null)"; then
    return 1
  fi

  printf '%s\n' "${_resp}" | jq -r '.tags[].name' 2>/dev/null || true
}

# Main fetcher entry point — takes one argument: record index.
_gs_eu2_fetch_quay() {
  local _idx="${1}"

  local _identifier _channel _major_hint _major_hint_min _no_cache
  _identifier="$(_gs_eu2_record_get "${_idx}" identifier)"
  _channel="$(_gs_eu2_record_get "${_idx}" channel)"
  _major_hint="$(_gs_eu2_record_get "${_idx}" major_hint)"
  _major_hint_min="$(_gs_eu2_record_get "${_idx}" major_hint_min)"
  _no_cache="${_GS_EU2_CFG[no_cache]:-false}"

  # watch_major_depth read early for cache key: watch-major runs must not share
  # a cache entry with non-watch-major runs (cache-hit returns before latest_unconstrained
  # is populated, so a shared entry would silently suppress WATCH on subsequent runs).
  local _wm_depth_ck
  _wm_depth_ck="$(_gs_eu2_record_get "${_idx}" watch_major_depth)"

  # Build cache key — include major_hint_min so range annotations don't collide.
  local _cache_key="quay:${_identifier}:${_major_hint}:${_major_hint_min}:${_channel}:${_wm_depth_ck}"

  # Cache read
  if [[ "${_no_cache}" != "true" ]]; then
    local _cached
    if _cached="$(_gs_eu2_cache_read "${_cache_key}")" && [[ -n "${_cached}" ]]; then
      if [[ -n "${_major_hint_min}" && -n "${_cached}" \
            && "${_cached}" =~ ^v?"${_major_hint_min}"([.^_-]|$) \
            && ! "${_cached}" =~ ^v?"${_major_hint}"([.^_-]|$) ]]; then
        _gs_eu2_record_set "${_idx}" using_fallback_major "true"
      fi
      _gs_eu2_record_set "${_idx}" proposed_version "${_cached}"
      return 0
    fi
  fi

  # Fetch tags
  local _raw_tags
  if ! _raw_tags="$(_gs_eu2_qy_fetch_tags "${_identifier}")"; then
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "fetch failed for quay:${_identifier}"
    return 0
  fi

  if [[ -z "${_raw_tags}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "no tags returned for quay:${_identifier}"
    return 0
  fi

  # Apply full tag flags pipeline
  local _tags
  _tags="$(printf '%s\n' "${_raw_tags}" | _gs_eu2_apply_tag_flags_from_record "${_idx}")"

  # (watch-major) — capture unconstrained best from full tag set (post-tag_flags, pre-major-pin).
  # Inherits all tag_flags (already applied to _tags). Auto-detects variant suffix from
  # current_version when no explicit tag-filter is present.
  local _wm_depth
  _wm_depth="$(_gs_eu2_record_get "${_idx}" watch_major_depth)"
  if [[ -n "${_wm_depth}" && -n "${_major_hint}" ]]; then
    local _wm_tags="${_tags}"
    local _wm_tag_filter
    _wm_tag_filter="$(_gs_eu2_record_get "${_idx}" tag_filter)"
    if [[ -z "${_wm_tag_filter}" ]]; then
      local _wm_cur _wm_suffix
      _wm_cur="$(_gs_eu2_record_get "${_idx}" current_version)"
      _wm_suffix="$(_gs_eu2_version_tag_suffix "${_wm_cur}")"
      if [[ -n "${_wm_suffix}" ]]; then
        local _wm_suffix_esc
        _wm_suffix_esc="$(printf '%s' "${_wm_suffix}" | sed 's/[.[\*^$()+?{}|]/\\&/g')"
        _wm_tags="$(printf '%s\n' "${_wm_tags}" | grep -E "${_wm_suffix_esc}"'$' || true)"
      fi
    fi
    local _unconstrained_best
    _unconstrained_best="$(_gs_eu2_channel_select_best "${_wm_tags}" "stable")"
    if [[ -n "${_unconstrained_best}" ]]; then
      local _vp_wm
      _vp_wm="$(_gs_eu2_record_get "${_idx}" version_prefix)"
      [[ -n "${_vp_wm}" ]] && _unconstrained_best="${_vp_wm}${_unconstrained_best}"
      _gs_eu2_record_set "${_idx}" latest_unconstrained "${_unconstrained_best}"
    fi
  fi

  # Save pre-filter tag list for fallback-major retry below.
  local _tags_premajor="${_tags}"

  # Major-pin filter — anchor prevents "18" matching "180.x"
  if [[ -n "${_major_hint}" ]]; then
    _tags="$(printf '%s\n' "${_tags}" | grep -E "^${_major_hint}([.^-]|\$)" 2>/dev/null \
      || printf '%s\n' "${_tags}" | awk -F'[.-]' -v m="${_major_hint}" '$1 == m' || true)"
  fi

  if [[ -z "${_tags}" ]]; then
    if [[ -n "${_major_hint_min}" ]]; then
      local _fallback_tags
      _fallback_tags="$(printf '%s\n' "${_tags_premajor}" \
        | grep -E "^${_major_hint_min}([.^-]|\$)" 2>/dev/null \
        || printf '%s\n' "${_tags_premajor}" \
           | awk -F'[.-]' -v m="${_major_hint_min}" '$1 == m' \
        || true)"
      if [[ -n "${_fallback_tags}" ]]; then
        _tags="${_fallback_tags}"
        _gs_eu2_record_set "${_idx}" using_fallback_major "true"
      fi
    fi
    if [[ -z "${_tags}" ]]; then
      _gs_eu2_record_set "${_idx}" decision      "SKIP"
      _gs_eu2_record_set "${_idx}" error_message "no tags matched filters for quay:${_identifier}"
      return 0
    fi
  fi

  # Detect all-unversioned tag set
  local _has_versioned=false _utag
  while IFS= read -r _utag; do
    [[ -z "${_utag}" ]] && continue
    if ! _gs_eu2_is_unversioned "${_utag}"; then _has_versioned=true; break; fi
  done <<< "${_tags}"
  if [[ "${_has_versioned}" == "false" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "SKIP"
    _gs_eu2_record_set "${_idx}" error_message "no versioned tags available for quay:${_identifier}"
    return 0
  fi

  # Channel selection → proposed
  local _proposed
  _proposed="$(_gs_eu2_channel_select_best "${_tags}" "${_channel}")"

  if [[ -z "${_proposed}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "SKIP"
    _gs_eu2_record_set "${_idx}" error_message "channel selection returned nothing for quay:${_identifier}"
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
