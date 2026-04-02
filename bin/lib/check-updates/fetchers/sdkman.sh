#!/bin/bash
# SDKMAN REST API fetcher.
# Fetches available versions for SDKMAN candidates.
# Supports major version constraint via sdkman:<candidate>:<major> format.

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_CU_SDKMAN_SH_LOADED:-}" ]] && return 0
readonly _GS_CU_SDKMAN_SH_LOADED=1

readonly _GS_CU_SDKMAN_API_BASE="https://api.sdkman.io/2"

# Fetch latest version of an SDKMAN candidate, optionally constrained to a major version
# Usage: _gs_cu_sdkman_fetch_latest "gradle:8" "8.14"    → latest 8.x
# Usage: _gs_cu_sdkman_fetch_latest "gradle" "9.4.0"     → latest overall
_gs_cu_sdkman_fetch_latest() {
  local identifier="${1}"    # "candidate" or "candidate:major"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"

  # Parse identifier to extract candidate and optional major constraint
  local candidate=""
  local major_constraint=""

  if [[ "${identifier}" =~ ^([^:]+):([0-9]+)$ ]]; then
    candidate="${BASH_REMATCH[1]}"
    major_constraint="${BASH_REMATCH[2]}"
  else
    candidate="${identifier}"
    # Infer major from current version
    major_constraint="${current_version%%.*}"
  fi

  local cache_key="sdkman:${identifier}"

  if [[ "${no_cache}" != "true" ]]; then
    local cached
    if cached="$(_gs_cu_cache_read "${cache_key}" 2>/dev/null)"; then
      echo "${cached}"
      return 0
    fi
  fi

  if [[ "${offline}" == "true" ]]; then
    return 1
  fi

  # SDKMAN API: list versions for candidate
  local url="${_GS_CU_SDKMAN_API_BASE}/candidates/${candidate}/list?current=${current_version}&pageSize=40"
  local response
  if ! response="$(curl --silent --fail --max-time 15 --retry 2 "${url}" 2>/dev/null)"; then
    # Try alternative endpoint
    url="${_GS_CU_SDKMAN_API_BASE}/candidates/${candidate}/default"
    if ! response="$(curl --silent --fail --max-time 15 --retry 2 "${url}" 2>/dev/null)"; then
      return 1
    fi
    # Response is just the default version string
    local default_ver="${response}"
    default_ver="${default_ver//[[:space:]]/}"
    if [[ -n "${default_ver}" && -n "${major_constraint}" ]]; then
      if [[ "${default_ver}" == "${major_constraint}."* ]]; then
        _gs_cu_cache_write "${cache_key}" "${default_ver}"
        echo "${default_ver}"
      fi
    elif [[ -n "${default_ver}" ]]; then
      _gs_cu_cache_write "${cache_key}" "${default_ver}"
      echo "${default_ver}"
    fi
    return 0
  fi

  # Parse version list response — it's a text list of versions
  local proposed
  proposed="$(_gs_cu_sdkman_select_best_version "${response}" "${major_constraint}")"

  if [[ -n "${proposed}" ]]; then
    _gs_cu_cache_write "${cache_key}" "${proposed}"
    echo "${proposed}"
  fi
}

# Select best version from SDKMAN list response
# SDKMAN list output is a formatted table; extract version numbers
_gs_cu_sdkman_select_best_version() {
  local response="${1}"
  local major_constraint="${2}"

  # Extract version-like tokens from the response
  local versions=()
  while IFS= read -r ver; do
    [[ -z "${ver}" ]] && continue
    # Apply major constraint filter if specified
    if [[ -n "${major_constraint}" ]]; then
      [[ "${ver}" == "${major_constraint}."* ]] || continue
    fi
    versions+=("${ver}")
  done < <(
    printf '%s' "${response}" | \
      grep -oE '[0-9]+\.[0-9]+[.0-9]*(-[a-zA-Z0-9_]+)?' | \
      grep -v '^[[:space:]]*$' | \
      sort -V | \
      uniq \
      2>/dev/null || true
  )

  if [[ ${#versions[@]} -eq 0 ]]; then
    return 0
  fi

  # Return highest (already sorted)
  echo "${versions[${#versions[@]}-1]}"
}
