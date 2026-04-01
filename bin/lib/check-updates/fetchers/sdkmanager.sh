#!/bin/bash
# Android sdkmanager --list parser.
# Parses output of sdkmanager --list to find available updates.
# Always MANUAL (per spec) — cannot auto-apply.

set -eEuo pipefail

# Fetch latest version for an Android SDK component
# Usage: _sdkmanager_fetch_latest "build-tools" "37.0.0-rc2"
_sdkmanager_fetch_latest() {
  local identifier="${1}"    # e.g. "build-tools", "cmdline-tools", "ndk", "platform-tools"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"

  local cache_key="sdkmanager:${identifier}"

  if [[ "${no_cache}" != "true" ]]; then
    local cached
    if cached="$(_cache_read "${cache_key}" 2>/dev/null)"; then
      echo "${cached}"
      return 0
    fi
  fi

  if [[ "${offline}" == "true" ]]; then
    # Cannot fetch offline without running sdkmanager
    return 1
  fi

  # Find sdkmanager binary
  local sdk_root="${GLOBAL_STACK_ANDROID_HOME:-${GLOBAL_STACK_DOCKER_TOOLS_PATH:-/stack/tools}/android}"
  local sdkmanager_bin=""

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

  if [[ -z "${sdkmanager_bin}" ]]; then
    _log_debug "sdkmanager not found — skipping ${identifier}"
    return 1
  fi

  # Run sdkmanager --list and parse for the component
  local list_output
  if ! list_output="$("${sdkmanager_bin}" "--sdk_root=${sdk_root}" --list 2>/dev/null)"; then
    _log_debug "sdkmanager --list failed"
    return 1
  fi

  local proposed
  proposed="$(_sdkmanager_parse_latest "${list_output}" "${identifier}")"

  if [[ -n "${proposed}" ]]; then
    _cache_write "${cache_key}" "${proposed}"
    echo "${proposed}"
  fi
}

# Parse sdkmanager --list output to find latest version of a component
_sdkmanager_parse_latest() {
  local list_output="${1}"
  local component="${2}"

  # sdkmanager --list has sections:
  # "Available Updates:" and "Available Packages:"
  # Lines look like: "  build-tools;37.0.0 | 37.0.0 | Android SDK Build-Tools 37"
  # We want the highest version available

  local versions=()
  local _re_component
  _re_component="${component};([0-9][^[:space:]|]*)"
  while IFS= read -r line; do
    # Match lines containing component name followed by ;version
    if [[ "${line}" =~ ${_re_component} ]]; then
      local ver="${BASH_REMATCH[1]}"
      # Clean up version
      ver="${ver%%|*}"
      ver="${ver//[[:space:]]/}"
      [[ -n "${ver}" ]] && versions+=("${ver}")
    fi
  done <<< "${list_output}"

  if [[ ${#versions[@]} -eq 0 ]]; then
    return 0
  fi

  # Return highest version
  printf '%s\n' "${versions[@]}" | sort -V | tail -1
}
