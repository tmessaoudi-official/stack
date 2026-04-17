#!/bin/bash
# PyPI JSON API fetcher.
# Strategy: try pip CLI via pyenv first, fall back to PyPI JSON API.

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_EU_PYPI_SH_LOADED:-}" ]] && return 0
readonly _GS_EU_PYPI_SH_LOADED=1

# CLI fetch: uses `pip index versions --pre` to get all versions including prereleases.
# Usage: _gs_eu_pypi_fetch_cli identifier current_version offline no_cache channel
_gs_eu_pypi_fetch_cli() {
  local identifier="${1}"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"
  local channel="${5:-}"

  # Skip if offline
  [[ "${offline}" == "true" ]] && return 1

  # Use pip index versions --pre to get all versions including prereleases
  local pip_output
  pip_output="$(pip index versions --pre "${identifier}" 2>/dev/null)" || return 1
  [[ -z "${pip_output}" ]] && return 1

  # Parse: "PACKAGE (X.Y.Z, X.Y.Z-1, ...)"
  local versions_str
  versions_str="$(printf '%s' "${pip_output}" | grep -oP '\(.*?\)' | tr -d '()' | tr ',' '\n' | tr -d ' ')" || return 1
  [[ -z "${versions_str}" ]] && return 1

  _gs_eu_channel_select_best "${versions_str}" "${channel}"
}

# API fetch: uses PyPI JSON API.
# Usage: _gs_eu_pypi_fetch_api identifier current_version offline no_cache channel
_gs_eu_pypi_fetch_api() {
  local identifier="${1}"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"
  local channel="${5:-}"

  if [[ "${offline}" == "true" ]]; then
    return 1
  fi

  local url="https://pypi.org/pypi/${identifier}/json"
  local response
  if ! response="$(curl --silent --location --fail --max-time 10 --retry 2 \
    -H "Accept: application/json" \
    "${url}" 2>/dev/null)"; then
    _gs_eu_set_fetch_error "pypi: network error fetching '${identifier}'"
    return 1
  fi

  local proposed

  local all_versions
  all_versions="$(printf '%s' "${response}" | jq -r '[.releases | keys[]] | .[]' 2>/dev/null || true)"
  proposed="$(_gs_eu_channel_select_best "${all_versions}" "${channel}")"

  if [[ -n "${proposed}" ]]; then
    echo "${proposed}"
  fi
}

# Fetch latest version of a PyPI package.
# Tries CLI (pip index) first via _gs_eu_cli_with_fallback, falls back to PyPI JSON API.
# Usage: _gs_eu_pypi_fetch_latest identifier current_version offline no_cache channel env_var
_gs_eu_pypi_fetch_latest() {
  local identifier="${1}"    # package name (case-sensitive as per PyPI)
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"
  local channel="${5:-}"        # channel qualifier (rc, beta, alpha, unstable, ...)
  local env_var="${6:-}"        # .env variable name for runtime derivation

  local cache_key="pypi:${identifier}:${channel}"

  if [[ "${no_cache}" != "true" ]]; then
    local cached
    if cached="$(_gs_eu_cache_read "${cache_key}" 2>/dev/null)"; then
      echo "${cached}"
      return 0
    fi
  fi

  local proposed
  proposed="$(_gs_eu_cli_with_fallback \
    "_gs_eu_pypi_fetch_cli" \
    "_gs_eu_pypi_fetch_api" \
    "${env_var}" \
    "${identifier}" "${current_version}" "${offline}" "${no_cache}" "${channel}")"

  if [[ -n "${proposed}" ]]; then
    _gs_eu_cache_write "${cache_key}" "${proposed}"
    echo "${proposed}"
  fi
}
