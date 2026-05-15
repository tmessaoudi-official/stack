#!/bin/bash
# pypi.sh — PyPI registry fetcher using the record-index contract
#
# Input:  record index — reads type/identifier/channel/tag_*/major_hint etc.
# Output: writes proposed_version + decision + error_message back into record
#
# API: https://pypi.org/pypi/{package}/json
# Stable fast path: .info.version
# Full channel path: .releases keys[], excluding yanked releases

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

# Main fetcher entry point — takes one argument: record index.
_gs_eu2_fetch_pypi() {
  local _idx="${1}"

  local _identifier _channel _major_hint _no_cache
  _identifier="$(_gs_eu2_record_get "${_idx}" identifier)"
  _channel="$(_gs_eu2_record_get "${_idx}" channel)"
  _major_hint="$(_gs_eu2_record_get "${_idx}" major_hint)"
  _no_cache="${_GS_EU2_CFG[no_cache]:-false}"

  # Build cache key
  local _cache_key="pypi:${_identifier}:${_major_hint}:${_channel}"

  # Cache read
  if [[ "${_no_cache}" != "true" ]]; then
    local _cached
    if _cached="$(_gs_eu2_cache_read "${_cache_key}")" && [[ -n "${_cached}" ]]; then
      _gs_eu2_record_set "${_idx}" proposed_version "${_cached}"
      return 0
    fi
  fi

  local _url="https://pypi.org/pypi/${_identifier}/json"

  # CLI fast path: use `pip index versions` when available and not in fixture-test mode.
  # Gate: fixture mode forces API path to keep tests deterministic.
  if [[ -z "${_GS_EU2_HTTP_FIXTURE_DIR:-}" ]] && command -v pip >/dev/null 2>&1; then
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

  # Stable fast path via .info.version when no special channel requested
  if [[ -z "${_channel}" || "${_channel}" == "stable" ]]; then
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

  # Major-pin filter
  if [[ -n "${_major_hint}" ]]; then
    _versions="$(printf '%s\n' "${_versions}" | grep -E "^v?${_major_hint}([.^-]|\$)" 2>/dev/null \
      || printf '%s\n' "${_versions}" | awk -F'[v.-]' -v m="${_major_hint}" '
          { v=$0; sub(/^v/,"",v); split(v,a,"[.-]"); if(a[1]==m) print $0 }' || true)"
  fi

  if [[ -z "${_versions}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "SKIP"
    _gs_eu2_record_set "${_idx}" error_message "no versions matched filters for pypi:${_identifier}"
    return 0
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
