#!/bin/bash
# pypi.sh — PyPI registry fetcher using the record-index contract.
#
# Exports:   _gs_eu2_fetch_pypi
# Sources:   core/records.sh  core/semver.sh  core/channel.sh
#            core/tag_flags.sh  core/cache.sh  http/curl.sh
# Deps:      curl, jq  (pip CLI optional — CLI fast path when available)
# Env:       _GS_EU2_CFG[no_cache]  _GS_EU2_HTTP_FIXTURE_DIR
#
# Input:  record index — reads identifier/channel/tag_*/major_hint/major_hint_min/
#                        watch_major_depth/current_version/version_prefix
# Output: writes proposed_version + decision + error_message + latest_unconstrained
#         + using_fallback_major back into record
#
# API: https://pypi.org/pypi/{package}/json
# Stable fast path: .info.version (skipped for watch-major vars)
# Full channel path: .releases keys[], excluding yanked releases
# Yanked detection: a release is yanked only when ALL its uploaded files are yanked.

[[ -n "${_GS_EU2_PYPI_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_PYPI_SH_LOADED=1

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

# _gs_eu2_fetch_pypi — main entry point for the pypi: fetcher type.
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
#
# Fast paths (tried in order):
#   1. Cache hit
#   2. CLI (pip index versions) — only when pip available, no watch-major
#   3. API .info.version — only for stable channel, no watch-major
# Full path: fetches .releases object, excludes yanked files.
_gs_eu2_fetch_pypi() {
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
  local _cache_key="pypi:${_identifier}:${_major_hint}:${_major_hint_min}:${_channel}:${_wm_depth_ck}"

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

  local _url="https://pypi.org/pypi/${_identifier}/json"

  # CLI fast path: use `pip index versions` when available and not in fixture-test mode.
  # Gate: fixture mode forces API path to keep tests deterministic.
  # Gate: watch-major vars require the full API path so latest_unconstrained is populated;
  #       skip CLI fast path when watch_major_depth is set (correctness over speed).
  if [[ -z "${_GS_EU2_HTTP_FIXTURE_DIR:-}" ]] && command -v pip >/dev/null 2>&1 \
      && [[ -z "${_wm_depth_ck}" ]]; then
    if [[ -z "${_channel}" || "${_channel}" == "stable" ]]; then
      local _cli_out
      # pip index versions exits 0 even on unknown package in some versions; guard with grep
      if _cli_out="$(pip index versions "${_identifier}" 2>/dev/null)" \
          && [[ -n "${_cli_out}" ]]; then
        # Output format: "PACKAGE (VERSIONS)" — extract first version (latest stable)
        local _proposed
        _proposed="$(printf '%s\n' "${_cli_out}" \
          | grep -oE '\([^)]+\)' | head -1 \
          | tr -d '()' | awk -F',' '{print $1}' | tr -d ' ')"
        if [[ -n "${_proposed}" ]]; then
          _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"
          [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"
          return 0
        fi
      fi
    fi
  fi

  # Fetch the full PyPI JSON document
  local _resp
  if ! _resp="$(_gs_eu2_http_get "${_url}" 2>/dev/null)"; then
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "fetch failed for pypi:${_identifier}"
    return 0
  fi

  # Stable fast path via .info.version when no special channel requested.
  # Skipped for watch-major vars: they need the full version list to populate
  # latest_unconstrained — returning early here would silently suppress [WATCH].
  if [[ -z "${_wm_depth_ck}" ]] && [[ -z "${_channel}" || "${_channel}" == "stable" ]]; then
    local _latest
    _latest="$(printf '%s\n' "${_resp}" | jq -r '.info.version // empty' 2>/dev/null || true)"
    if [[ -n "${_latest}" ]]; then
      _gs_eu2_record_set "${_idx}" proposed_version "${_latest}"
      [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_latest}"
      return 0
    fi
  fi

  # Full version list — exclude yanked releases.
  # A release is considered yanked if ALL its files are yanked.
  # .releases is an object: {version: [file_objects, ...]}
  # A file_object has a "yanked" boolean field.
  local _raw_versions
  _raw_versions="$(printf '%s\n' "${_resp}" \
    | jq -r '.releases | to_entries[]
             | select(
                 (.value | length > 0) and
                 (.value | all(.yanked == true) | not)
               )
             | .key' \
    2>/dev/null || true)"

  if [[ -z "${_raw_versions}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "no versions returned for pypi:${_identifier}"
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
    _unconstrained_best="$(_gs_eu2_channel_select_best "${_wm_versions}" "stable")"
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
      _gs_eu2_record_set "${_idx}" error_message "no versions matched filters for pypi:${_identifier}"
      return 0
    fi
  fi

  # Channel selection → proposed
  local _proposed
  _proposed="$(_gs_eu2_channel_select_best "${_versions}" "${_channel}")"

  if [[ -z "${_proposed}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "SKIP"
    _gs_eu2_record_set "${_idx}" error_message "channel selection returned nothing for pypi:${_identifier}"
    return 0
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
