#!/bin/bash
# rubygems.sh — RubyGems registry fetcher using the record-index contract.
#
# Exports:   _gs_eu2_fetch_rubygems
# Sources:   core/records.sh  core/semver.sh  core/channel.sh
#            core/tag_flags.sh  core/cache.sh  http/curl.sh
# Deps:      curl, jq  (gem CLI optional — CLI fast path when available)
# Env:       _GS_EU2_CFG[no_cache]  _GS_EU2_HTTP_FIXTURE_DIR
#
# Input:  record index — reads identifier/channel/tag_*/major_hint/major_hint_min/
#                        watch_major_depth/current_version/version_prefix
# Output: writes proposed_version + decision + error_message + latest_unconstrained
#         + using_fallback_major back into record
#
# API (two calls):
#   https://rubygems.org/api/v1/gems/{name}.json      → .version (stable fast path)
#   https://rubygems.org/api/v1/versions/{name}.json  → .[].number, filter yanked=false
# Resilience: versions endpoint failure falls back to stable from gems endpoint.
# Channel selection fallback: if channel selection yields nothing, uses gems .version.

[[ -n "${_GS_EU2_RUBYGEMS_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_RUBYGEMS_SH_LOADED=1

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

# _gs_eu2_fetch_rubygems — main entry point for the rubygems: fetcher type.
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
_gs_eu2_fetch_rubygems() {
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
  local _cache_key="rubygems:${_identifier}:${_major_hint}:${_major_hint_min}:${_channel}:${_wm_depth_ck}"

  # Cache read
  _gs_eu2_cache_try_load "${_idx}" "${_cache_key}" "${_major_hint:-}" "${_major_hint_min:-}" && return 0

  local _gems_url="https://rubygems.org/api/v1/gems/${_identifier}.json"
  local _versions_url="https://rubygems.org/api/v1/versions/${_identifier}.json"

  # CLI fast path: use `gem` when available and not in fixture-test mode.
  # Gate: fixture mode forces API path to keep tests deterministic.
  # Gate: watch-major vars require the full API path so latest_unconstrained is populated;
  #       skip CLI fast path when watch_major_depth is set (correctness over speed).
  if [[ -z "${_GS_EU2_HTTP_FIXTURE_DIR:-}" ]] && command -v gem >/dev/null 2>&1 \
      && [[ -z "${_wm_depth_ck}" ]]; then
    if [[ -z "${_channel}" || "${_channel}" == "stable" ]]; then
      local _cli_out _proposed
      if _cli_out="$(gem search "^${_identifier}$" --versions --all --no-color 2>/dev/null)" \
          && [[ -n "${_cli_out}" ]]; then
        # Output format: "gemname (v1, v2, ...)" — extract latest version
        _proposed="$(printf '%s\n' "${_cli_out}" \
          | grep -E "^${_identifier} " | head -1 \
          | grep -oE '\([^)]+\)' | tr -d '()' | awk -F',' '{print $1}' | tr -d ' ')"
        if [[ -n "${_proposed}" ]]; then
          _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"
          [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"
          return 0
        fi
      fi
    fi
  fi

  # Stable fast path: fetch gems endpoint for current stable version
  local _gems_resp _stable_version=""
  if _gems_resp="$(_gs_eu2_http_get "${_gems_url}" 2>/dev/null)"; then
    _stable_version="$(printf '%s\n' "${_gems_resp}" | jq -r '.version // empty' 2>/dev/null || true)"
  fi

  # If no special channel and we got a stable version, use it directly.
  # Skipped for watch-major vars: they need the full version list to populate
  # latest_unconstrained — returning early here would silently suppress [WATCH].
  if [[ -z "${_wm_depth_ck}" ]] && [[ (-z "${_channel}" || "${_channel}" == "stable") && -n "${_stable_version}" ]]; then
    _gs_eu2_record_set "${_idx}" proposed_version "${_stable_version}"
    [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_stable_version}"
    return 0
  fi

  # Full version list via versions endpoint — exclude yanked
  local _versions_resp _raw_versions=""
  if _versions_resp="$(_gs_eu2_http_get "${_versions_url}" 2>/dev/null)"; then
    _raw_versions="$(printf '%s\n' "${_versions_resp}" \
      | jq -r '.[] | select(.yanked == false) | .number' \
      2>/dev/null || true)"
  fi

  # Fallback: if versions endpoint failed but we have a stable version from gems endpoint
  if [[ -z "${_raw_versions}" ]]; then
    if [[ -n "${_stable_version}" ]]; then
      _gs_eu2_record_set "${_idx}" proposed_version "${_stable_version}"
      [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_stable_version}"
      return 0
    fi
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "fetch failed for rubygems:${_identifier}"
    return 0
  fi

  # Apply tag flags pipeline
  local _versions
  _versions="$(printf '%s\n' "${_raw_versions}" | _gs_eu2_apply_tag_flags_from_record "${_idx}")"

  # (watch-major) — capture unconstrained best from full version list (post-tag_flags, pre-major-pin).
  # Inherits all tag_flags. Auto-detects variant suffix from current_version when no tag-filter set.
  local _wm_depth
  _wm_depth="$(_gs_eu2_record_get "${_idx}" watch_major_depth)"
  if [[ -n "${_wm_depth}" && -n "${_major_hint}" ]]; then
    local _wm_versions="${_versions}"
    local _wm_tag_filter
    _wm_tag_filter="$(_gs_eu2_record_get "${_idx}" tag_filter)"
    if [[ -z "${_wm_tag_filter}" ]]; then
      local _wm_cur _wm_suffix
      _wm_cur="$(_gs_eu2_record_get "${_idx}" current_version)"
      _wm_suffix="$(_gs_eu2_version_tag_suffix "${_wm_cur}")"
      if [[ -n "${_wm_suffix}" ]]; then
        local _wm_suffix_esc
        _wm_suffix_esc="$(printf '%s' "${_wm_suffix}" | sed 's/[.[\*^$()+?{}|]/\\&/g')"
        _wm_versions="$(printf '%s\n' "${_wm_versions}" | grep -E "${_wm_suffix_esc}"'$' || true)"
      fi
    fi
    local _unconstrained_best
    _unconstrained_best="$(_gs_eu2_channel_select_best "${_wm_versions}" "${_channel:-stable}")"
    [[ -n "${_unconstrained_best}" ]] && \
      _gs_eu2_record_set "${_idx}" latest_unconstrained "${_unconstrained_best}"
  fi

  # Save pre-filter version list for fallback-major retry below.
  local _versions_premajor="${_versions}"

  # Major-pin filter
  if [[ -n "${_major_hint}" ]]; then
    _versions="$(printf '%s\n' "${_versions}" | grep -E "^v?${_major_hint}([.^-]|\$)" 2>/dev/null \
      || printf '%s\n' "${_versions}" | awk -F'[v.-]' -v m="${_major_hint}" '
          { v=$0; sub(/^v/,"",v); split(v,a,"[.-]"); if(a[1]==m) print $0 }' || true)"
  fi

  if [[ -z "${_versions}" ]]; then
    if [[ -n "${_major_hint_min}" ]]; then
      local _fallback_versions
      _fallback_versions="$(printf '%s\n' "${_versions_premajor}" \
        | grep -E "^v?${_major_hint_min}([.^-]|\$)" 2>/dev/null \
        || printf '%s\n' "${_versions_premajor}" \
           | awk -F'[v.-]' -v m="${_major_hint_min}" \
               '{ v=$0; sub(/^v/,"",v); split(v,a,"[.-]"); if(a[1]==m) print $0 }' \
        || true)"
      if [[ -n "${_fallback_versions}" ]]; then
        _versions="${_fallback_versions}"
        _gs_eu2_record_set "${_idx}" using_fallback_major "true"
      fi
    fi
    if [[ -z "${_versions}" ]]; then
      _gs_eu2_record_set "${_idx}" decision      "SKIP"
      _gs_eu2_record_set "${_idx}" error_message "no versions matched filters for rubygems:${_identifier}"
      return 0
    fi
  fi

  # Channel selection → proposed
  local _proposed
  _proposed="$(_gs_eu2_channel_select_best "${_versions}" "${_channel}")"

  if [[ -z "${_proposed}" ]]; then
    # Fall back to stable version from gems endpoint if channel selection finds nothing
    if [[ -n "${_stable_version}" ]]; then
      _proposed="${_stable_version}"
    else
      _gs_eu2_record_set "${_idx}" decision      "SKIP"
      _gs_eu2_record_set "${_idx}" error_message "channel selection returned nothing for rubygems:${_identifier}"
      return 0
    fi
  fi

  # Re-prepend version_prefix stripped by tag-strip-prefix
  local _vp
  _vp="$(_gs_eu2_record_get "${_idx}" version_prefix)"
  [[ -n "${_vp}" ]] && _proposed="${_vp}${_proposed}"

  # Write result — proposed_version only; decision left empty for decide.sh
  _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"

  # Cache the result
  [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"

  return 0
}
