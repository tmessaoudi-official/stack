#!/bin/bash
# sdkmanager.sh — Android SDK Manager version fetcher using the record-index contract.
#
# Exports:   _gs_eu2_sdkmanager_get_list  _gs_eu2_sdkmanager_parse_versions
#            _gs_eu2_fetch_sdkmanager
# Sources:   core/records.sh  core/semver.sh  core/channel.sh  core/cache.sh
# Deps:      sdkmanager (Android cmdline-tools)
# Env:       _GS_EU2_CFG[no_cache]  _GS_EU2_SDKMANAGER_CMD_FIXTURE (test seam)
#            ANDROID_HOME  GLOBAL_STACK_ANDROID_HOME  GLOBAL_STACK_DOCKER_TOOLS_PATH
#
# Input:  record index — reads identifier/channel
# Output: writes proposed_version + error_message back into record
#         (decision is NOT written — owned by decide.sh)
#
# Strategy:
#   1. If _GS_EU2_SDKMANAGER_CMD_FIXTURE is set, cat that file (test seam).
#   2. Otherwise find sdkmanager binary in this order:
#        a. PATH (profile.sh may have added cmdline-tools/bin)
#        b. ${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager
#        c. ${ANDROID_HOME}/cmdline-tools/bin/sdkmanager
#        d. ${ANDROID_HOME}/tools/bin/sdkmanager
#   3. Run: sdkmanager --list (or cat fixture) and parse for the component.
#
# When sdkmanager is not found, error_message is set and proposed_version stays empty.
# decide.sh classifies an empty proposed as SKIP (not ERROR) — tool may simply not
# be installed on this machine.

[[ -n "${_GS_EU2_SDKMANAGER_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_SDKMANAGER_SH_LOADED=1

# shellcheck source=../core/records.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/records.sh"
# shellcheck source=../core/semver.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/semver.sh"
# shellcheck source=../core/channel.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/channel.sh"
# shellcheck source=../core/cache.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/cache.sh"

# _gs_eu2_sdkmanager_get_list — return sdkmanager --list output (or fixture).
#
# Args:    none
# Prints:  raw sdkmanager --list output
# Returns: 0 on success; non-zero if sdkmanager is not available (no fixture set)
# Side fx: runs sdkmanager --sdk_root=... --list when binary is found
_gs_eu2_sdkmanager_get_list() {
  # Test seam: fixture override
  if [[ -n "${_GS_EU2_SDKMANAGER_CMD_FIXTURE:-}" ]]; then
    cat "${_GS_EU2_SDKMANAGER_CMD_FIXTURE}"
    return 0
  fi

  # Locate sdkmanager binary
  local _sdk_root="${ANDROID_HOME:-${GLOBAL_STACK_ANDROID_HOME:-${GLOBAL_STACK_DOCKER_TOOLS_PATH:-/stack/tools}/android}}"
  local _sdkmanager_bin=""

  if command -v sdkmanager >/dev/null 2>&1; then
    _sdkmanager_bin="$(command -v sdkmanager)"
  else
    local _candidates=(
      "${_sdk_root}/cmdline-tools/latest/bin/sdkmanager"
      "${_sdk_root}/cmdline-tools/bin/sdkmanager"
      "${_sdk_root}/tools/bin/sdkmanager"
    )
    local _p
    for _p in "${_candidates[@]}"; do
      if [[ -x "${_p}" ]]; then
        _sdkmanager_bin="${_p}"
        break
      fi
    done
  fi

  if [[ -z "${_sdkmanager_bin}" ]]; then
    return 1
  fi

  "${_sdkmanager_bin}" "--sdk_root=${_sdk_root}" --list 2>/dev/null
}

# _gs_eu2_sdkmanager_parse_versions — extract version strings for a component.
#
# Args:    $1 output    — raw sdkmanager --list output
#          $2 component — component name (e.g. "platform-tools", "build-tools", "ndk")
# Prints:  newline-separated sorted version list (sort -uV)
# Returns: 0 always (prints nothing if no match)
#
# Handles two output line formats:
#   "  platform-tools  | 37.0.0  | ..."   (bare component name)
#   "  build-tools;37.0.0  | 37.0.0  | ..." (component;version form — multiple rows)
_gs_eu2_sdkmanager_parse_versions() {
  local _output="${1}" _component="${2}"
  local _versions=()

  # Match bare name line: "  COMPONENT  | VERSION | ..."
  local _bare_ver
  _bare_ver="$(printf '%s\n' "${_output}" \
    | grep -E "^[[:space:]]+${_component}[[:space:]]*\|" \
    | head -1 \
    | awk -F'|' '{gsub(/[[:space:]]/, "", $2); print $2}' 2>/dev/null || true)"
  [[ -n "${_bare_ver}" ]] && _versions+=("${_bare_ver}")

  # Match component;VERSION lines: "  COMPONENT;VERSION  | ..."
  local _re="${_component};([0-9][^[:space:]|]*)"
  local _line _ver
  while IFS= read -r _line; do
    if [[ "${_line}" =~ ${_re} ]]; then
      _ver="${BASH_REMATCH[1]}"
      _ver="${_ver%%|*}"
      _ver="${_ver//[[:space:]]/}"
      [[ -n "${_ver}" ]] && _versions+=("${_ver}")
    fi
  done <<< "${_output}"

  if [[ ${#_versions[@]} -gt 0 ]]; then
    printf '%s\n' "${_versions[@]}" | sort -uV
  fi
}

# _gs_eu2_fetch_sdkmanager — main entry point for the sdkmanager: fetcher type.
#
# Args:    $1 record_index — 0-based record index
# Reads:   record fields: identifier, channel
# Sets:    record fields: proposed_version, error_message
#          (decision is NOT written — owned by decide.sh)
# Prints:  nothing
# Returns: 0 always
_gs_eu2_fetch_sdkmanager() {
  local _idx="${1}"

  local _identifier _channel _no_cache
  _identifier="$(_gs_eu2_record_get "${_idx}" identifier)"
  _channel="$(_gs_eu2_record_get "${_idx}" channel)"
  _no_cache="${_GS_EU2_CFG[no_cache]:-false}"

  # Build cache key
  local _cache_key="sdkmanager:${_identifier}:${_channel}"

  # Cache read
  _gs_eu2_cache_try_load "${_idx}" "${_cache_key}" "${_major_hint:-}" "${_major_hint_min:-}" && return 0

  # Get sdkmanager list output
  local _list_output
  if ! _list_output="$(_gs_eu2_sdkmanager_get_list 2>/dev/null)"; then
    _gs_eu2_record_set "${_idx}" error_message "sdkmanager not found"
    return 0
  fi

  if [[ -z "${_list_output}" ]]; then
    _gs_eu2_record_set "${_idx}" error_message "sdkmanager --list returned no output"
    return 0
  fi

  # Parse versions for this component
  local _versions
  _versions="$(_gs_eu2_sdkmanager_parse_versions "${_list_output}" "${_identifier}")"

  if [[ -z "$(printf '%s\n' "${_versions}" | grep -v '^$' || true)" ]]; then
    _gs_eu2_record_set "${_idx}" error_message "no versions found for sdkmanager:${_identifier}"
    return 0
  fi

  # Channel selection → proposed
  local _proposed
  _proposed="$(_gs_eu2_channel_select_best "${_versions}" "${_channel}")"

  if [[ -z "${_proposed}" ]]; then
    _gs_eu2_record_set "${_idx}" error_message "channel selection returned nothing for sdkmanager:${_identifier}"
    return 0
  fi

  # Write result — proposed_version only; decision left empty for decide.sh
  _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"

  # Cache the result
  [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"

  return 0
}
