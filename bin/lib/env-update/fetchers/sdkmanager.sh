#!/bin/bash
# Android sdkmanager --list parser.
# Parses output of sdkmanager --list to find available updates.
# Always MANUAL (per spec) — cannot auto-apply.

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_EU_SDKMANAGER_SH_LOADED:-}" ]] && return 0
readonly _GS_EU_SDKMANAGER_SH_LOADED=1

# Fetch latest version for an Android SDK component
# Usage: _gs_eu_sdkmanager_fetch_latest "build-tools" "37.0.0-rc2"
_gs_eu_sdkmanager_fetch_latest() {
  local identifier="${1}"    # e.g. "build-tools", "cmdline-tools", "ndk", "platform-tools"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"
  local channel="${5:-}"

  local cache_key="sdkmanager:${identifier}:${channel}"

  if [[ "${no_cache}" != "true" ]]; then
    local cached
    if cached="$(_gs_eu_cache_read "${cache_key}" 2>/dev/null)"; then
      echo "${cached}"
      return 0
    fi
  fi

  if [[ "${offline}" == "true" ]]; then
    # Cannot fetch offline without running sdkmanager
    return 1
  fi

  # Find sdkmanager binary
  # ANDROID_HOME is exported by profile.sh (set from GLOBAL_STACK_ANDROID_HOME)
  local sdk_root="${ANDROID_HOME:-${GLOBAL_STACK_ANDROID_HOME:-${GLOBAL_STACK_DOCKER_TOOLS_PATH:-/stack/tools}/android}}"
  local sdkmanager_bin=""

  # Try PATH first (profile.sh adds cmdline-tools/bin to PATH)
  if command -v sdkmanager >/dev/null 2>&1; then
    sdkmanager_bin="$(command -v sdkmanager)"
  else
    # Look in cmdline-tools locations
    local candidate_paths=(
      "${sdk_root}/cmdline-tools/latest/bin/sdkmanager"
      "${sdk_root}/cmdline-tools/bin/sdkmanager"
      "${sdk_root}/tools/bin/sdkmanager"
    )
    local p
    for p in "${candidate_paths[@]}"; do
      if [[ -x "${p}" ]]; then
        sdkmanager_bin="${p}"
        break
      fi
    done
  fi

  if [[ -z "${sdkmanager_bin}" ]]; then
    _gs_eu_log_debug "sdkmanager not found — skipping ${identifier}"
    return 1
  fi

  # Run sdkmanager --list and parse for the component
  local list_output
  if ! list_output="$("${sdkmanager_bin}" "--sdk_root=${sdk_root}" --list 2>/dev/null)"; then
    _gs_eu_log_debug "sdkmanager --list failed"
    return 1
  fi

  local all_versions
  all_versions="$(_gs_eu_sdkmanager_parse_all_versions "${list_output}" "${identifier}")"

  local proposed
  proposed="$(_gs_eu_channel_select_best "${all_versions}" "${channel}")"

  if [[ -n "${proposed}" ]]; then
    _gs_eu_cache_write "${cache_key}" "${proposed}"
    echo "${proposed}"
  fi
}

# Parse sdkmanager --list output and return ALL found versions for a component (newline-separated).
# Used by _gs_eu_sdkmanager_fetch_latest which then passes the list to _gs_eu_channel_select_best.
#
# sdkmanager --list output format:
# "  platform-tools                         | 37.0.0            | Android SDK Platform-Tools"
# "  ndk-bundle                             | 27.2.12479018     | NDK"
# "  ndk;27.2.12479018                      | 27.2.12479018     | NDK (Side by side)"
# "  build-tools;37.0.0                     | 37.0.0            | Android SDK Build-Tools 37"
_gs_eu_sdkmanager_parse_all_versions() {
  local list_output="${1}"
  local component="${2}"

  local versions=()

  # First: try matching the package_name as a bare line prefix (platform-tools, ndk-bundle, etc.)
  # These appear as "  PACKAGE_NAME    | VERSION | ..."
  local bare_match
  bare_match="$(grep -E "^[[:space:]]+${component}[[:space:]]*\\|" <<< "${list_output}" | \
    head -1 | awk -F'|' '{gsub(/[[:space:]]/, "", $2); print $2}' 2>/dev/null || true)"
  [[ -n "${bare_match}" ]] && versions+=("${bare_match}")

  # Fallback / supplement: match component;VERSION lines (e.g. build-tools;37.0.0)
  local _re_component="${component};([0-9][^[:space:]|]*)"
  local line
  while IFS= read -r line; do
    if [[ "${line}" =~ ${_re_component} ]]; then
      local ver="${BASH_REMATCH[1]}"
      ver="${ver%%|*}"
      ver="${ver//[[:space:]]/}"
      [[ -n "${ver}" ]] && versions+=("${ver}")
    fi
  done <<< "${list_output}"

  if [[ ${#versions[@]} -gt 0 ]]; then
    printf '%s\n' "${versions[@]}" | sort -u
  fi
}

# Thin backward-compat wrapper: returns only the single highest stable version.
_gs_eu_sdkmanager_parse_latest() {
  local all_versions
  all_versions="$(_gs_eu_sdkmanager_parse_all_versions "${1}" "${2}")"
  if [[ -n "${all_versions}" ]]; then
    printf '%s\n' "${all_versions}" | sort -V | tail -1
  fi
}
