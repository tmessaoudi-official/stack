#!/bin/bash
# rubygems.sh — RubyGems registry fetcher using the record-index contract
#
# Input:  record index — reads type/identifier/channel/tag_*/major_hint etc.
# Output: writes proposed_version + decision + error_message back into record
#
# API (two calls):
#   https://rubygems.org/api/v1/gems/{name}.json      → .version (stable fast path)
#   https://rubygems.org/api/v1/versions/{name}.json  → .[].number, filter yanked=false
# Resilience: if versions endpoint fails, fall back to single stable from gems endpoint.

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

# Main fetcher entry point — takes one argument: record index.
_gs_eu2_fetch_rubygems() {
  local _idx="${1}"

  local _identifier _channel _major_hint _no_cache
  _identifier="$(_gs_eu2_record_get "${_idx}" identifier)"
  _channel="$(_gs_eu2_record_get "${_idx}" channel)"
  _major_hint="$(_gs_eu2_record_get "${_idx}" major_hint)"
  _no_cache="${_GS_EU2_CFG[no_cache]:-false}"

  # Build cache key
  local _cache_key="rubygems:${_identifier}:${_major_hint}:${_channel}"

  # Cache read
  if [[ "${_no_cache}" != "true" ]]; then
    local _cached
    if _cached="$(_gs_eu2_cache_read "${_cache_key}")" && [[ -n "${_cached}" ]]; then
      _gs_eu2_record_set "${_idx}" proposed_version "${_cached}"
      return 0
    fi
  fi

  local _gems_url="https://rubygems.org/api/v1/gems/${_identifier}.json"
  local _versions_url="https://rubygems.org/api/v1/versions/${_identifier}.json"

  # CLI fast path: use `gem` when available and not in fixture-test mode.
  # Gate: fixture mode forces API path to keep tests deterministic.
  if [[ -z "${_GS_EU2_HTTP_FIXTURE_DIR:-}" ]] && command -v gem >/dev/null 2>&1; then
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

  # If no special channel and we got a stable version, use it directly
  if [[ (-z "${_channel}" || "${_channel}" == "stable") && -n "${_stable_version}" ]]; then
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

  # Major-pin filter
  if [[ -n "${_major_hint}" ]]; then
    _versions="$(printf '%s\n' "${_versions}" | grep -E "^v?${_major_hint}([.^-]|\$)" 2>/dev/null \
      || printf '%s\n' "${_versions}" | awk -F'[v.-]' -v m="${_major_hint}" '
          { v=$0; sub(/^v/,"",v); split(v,a,"[.-]"); if(a[1]==m) print $0 }' || true)"
  fi

  if [[ -z "${_versions}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "SKIP"
    _gs_eu2_record_set "${_idx}" error_message "no versions matched filters for rubygems:${_identifier}"
    return 0
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
