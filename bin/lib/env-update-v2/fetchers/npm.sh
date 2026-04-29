#!/bin/bash
# npm.sh — npm registry fetcher using the record-index contract
#
# Input:  record index — reads type/identifier/channel/tag_*/major_hint etc.
# Output: writes proposed_version + decision + error_message back into record
#
# API: https://registry.npmjs.org/{package}
# Scoped packages (@scope/name) are URL-encoded: @ → %40, / → %2F
# Stable fast path: dist-tags.latest
# Full channel path: .versions keys[], excluding deprecated entries

[[ -n "${_GS_EU2_NPM_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_NPM_SH_LOADED=1

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

# URL-encode a package name for the npm registry:
#   @scope/name → %40scope%2Fname
_gs_eu2_npm_encode_pkg() {
  local _pkg="${1}"
  # Replace @ with %40 and / with %2F (only chars needing encoding in pkg names)
  _pkg="${_pkg//@/%40}"
  _pkg="${_pkg//\//%2F}"
  printf '%s' "${_pkg}"
}

# Main fetcher entry point — takes one argument: record index.
_gs_eu2_fetch_npm() {
  local _idx="${1}"

  local _identifier _channel _major_hint _no_cache
  _identifier="$(_gs_eu2_record_get "${_idx}" identifier)"
  _channel="$(_gs_eu2_record_get "${_idx}" channel)"
  _major_hint="$(_gs_eu2_record_get "${_idx}" major_hint)"
  _no_cache="${_GS_EU2_CFG[no_cache]:-false}"

  # Build cache key
  local _cache_key="npm:${_identifier}:${_major_hint}:${_channel}"

  # Cache read
  if [[ "${_no_cache}" != "true" ]]; then
    local _cached
    if _cached="$(_gs_eu2_cache_read "${_cache_key}")" && [[ -n "${_cached}" ]]; then
      _gs_eu2_record_set "${_idx}" proposed_version "${_cached}"
      return 0
    fi
  fi

  # URL-encode the package name for the registry URL
  local _encoded_pkg
  _encoded_pkg="$(_gs_eu2_npm_encode_pkg "${_identifier}")"
  local _url="https://registry.npmjs.org/${_encoded_pkg}"

  # CLI fast path: use `npm view` when available and not in fixture-test mode.
  # Gate: fixture mode forces API path to keep tests deterministic.
  if [[ -z "${_GS_EU2_HTTP_FIXTURE_DIR:-}" ]] && command -v npm >/dev/null 2>&1; then
    local _cli_out
    if [[ -z "${_channel}" || "${_channel}" == "stable" ]]; then
      if _cli_out="$(npm view "${_identifier}" dist-tags.latest 2>/dev/null)" \
          && [[ -n "${_cli_out}" ]]; then
        local _proposed="${_cli_out}"
        _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"
        [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"
        return 0
      fi
    fi
  fi

  # Fetch the full registry document
  local _resp
  if ! _resp="$(_gs_eu2_http_get "${_url}" 2>/dev/null)"; then
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "fetch failed for npm:${_identifier}"
    return 0
  fi

  # Stable fast path via dist-tags.latest when no special channel requested
  if [[ -z "${_channel}" || "${_channel}" == "stable" ]]; then
    local _latest
    _latest="$(printf '%s\n' "${_resp}" | jq -r '."dist-tags".latest // empty' 2>/dev/null || true)"
    if [[ -n "${_latest}" ]]; then
      _gs_eu2_record_set "${_idx}" proposed_version "${_latest}"
      [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_latest}"
      return 0
    fi
  fi

  # Full version list — exclude deprecated entries
  local _raw_versions
  _raw_versions="$(printf '%s\n' "${_resp}" \
    | jq -r '.versions | to_entries[] | select((.value.deprecated // "") == "") | .key' \
    2>/dev/null || true)"

  if [[ -z "${_raw_versions}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "no versions returned for npm:${_identifier}"
    return 0
  fi

  # Apply tag flags pipeline (strip-prefix, exclude, etc.)
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
    _gs_eu2_record_set "${_idx}" error_message "no versions matched filters for npm:${_identifier}"
    return 0
  fi

  # Channel selection → proposed
  local _proposed
  _proposed="$(_gs_eu2_channel_select_best "${_versions}" "${_channel}")"

  if [[ -z "${_proposed}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "SKIP"
    _gs_eu2_record_set "${_idx}" error_message "channel selection returned nothing for npm:${_identifier}"
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
