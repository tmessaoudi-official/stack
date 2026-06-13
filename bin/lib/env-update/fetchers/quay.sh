#!/bin/bash
# quay.sh — Quay.io tag fetcher using the record-index contract.
#
# Exports:   _gs_eu2_qy_fetch_tags  _gs_eu2_fetch_quay
# Sources:   core/records.sh  core/semver.sh  core/channel.sh
#            core/tag_flags.sh  core/cache.sh  http/curl.sh
# Deps:      curl, jq
# Env:       _GS_EU2_CFG[no_cache]
#
# Input:  record index — reads identifier/channel/tag_*/major_hint/major_hint_min/
#                        watch_major_depth/current_version/version_prefix
# Output: writes proposed_version + decision + error_message + latest_unconstrained
#         + using_fallback_major back into record
#
# API: https://quay.io/api/v1/repository/{org}/{image}/tag/?limit=100&onlyActiveTags=true
# Pagination: follows has_additional=true across pages until exhausted.

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

# _gs_eu2_qy_fetch_tags — fetch all active tags for an org/image from Quay.io.
#
# Args:    $1 identifier — "org/image" string
# Prints:  newline-separated tag names
# Returns: 0 on success; non-zero on HTTP failure
# Side fx: may read/write cache (via _gs_eu2_http_get)
#
# Follows has_additional pagination (page=1, page=2, ...) until exhausted.
# Only active tags are fetched (onlyActiveTags=true); limit=100 per page.
_gs_eu2_qy_fetch_tags() {
  local _identifier="${1}"
  local _base="https://quay.io/api/v1/repository/${_identifier}/tag/?limit=100&onlyActiveTags=true"
  local _all_tags="" _resp _page_tags _has_more _page=1

  while true; do
    local _url="${_base}&page=${_page}"
    if ! _resp="$(_gs_eu2_http_get "${_url}" 2>/dev/null)"; then
      return 1
    fi

    if ! _page_tags="$(printf '%s\n' "${_resp}" | jq -r '.tags[].name' 2>/dev/null)"; then
      return 1
    fi
    _all_tags="${_all_tags}${_page_tags}"$'\n'

    _has_more="$(printf '%s\n' "${_resp}" | jq -r '.has_additional // false' 2>/dev/null || true)"
    [[ "${_has_more}" != "true" ]] && break
    (( _page++ ))
  done

  printf '%s' "${_all_tags}"
}

# _gs_eu2_fetch_quay — main entry point for the quay: fetcher type.
#
# Args:    $1 record_index — 0-based record index
# Reads:   record fields: identifier, channel, major_hint, major_hint_min,
#          watch_major_depth, current_version, version_prefix, tag_filter,
#          tag_exclude, tag_strip_prefix, tag_strip_suffix, tag_extract,
#          tag_replace_from, tag_replace_to
# Sets:    record fields: proposed_version, decision (ERROR/SKIP only),
#          error_message, latest_unconstrained, using_fallback_major
# Prints:  nothing
# Returns: 0 always
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
  _gs_eu2_cache_try_load "${_idx}" "${_cache_key}" "${_major_hint:-}" "${_major_hint_min:-}" && return 0

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
