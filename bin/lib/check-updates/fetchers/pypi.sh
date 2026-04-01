#!/bin/bash
# PyPI JSON API fetcher.

set -eEuo pipefail

# Fetch latest version of a PyPI package
# Usage: _pypi_fetch_latest "Django" "6.0.3"
_pypi_fetch_latest() {
  local identifier="${1}"    # package name (case-sensitive as per PyPI)
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"

  local cache_key="pypi:${identifier}"

  if [[ "${no_cache}" != "true" ]]; then
    local cached
    if cached="$(_cache_read "${cache_key}" 2>/dev/null)"; then
      echo "${cached}"
      return 0
    fi
  fi

  if [[ "${offline}" == "true" ]]; then
    return 1
  fi

  local url="https://pypi.org/pypi/${identifier}/json"
  local response
  if ! response="$(curl --silent --fail --max-time 10 --retry 2 \
    -H "Accept: application/json" \
    "${url}" 2>/dev/null)"; then
    return 1
  fi

  local is_pre=false
  if [[ "${current_version,,}" =~ (alpha|beta|rc[0-9]*|a[0-9]|b[0-9]|dev) ]]; then
    is_pre=true
  fi

  local proposed
  if [[ "${is_pre}" == "false" ]]; then
    # Latest stable
    proposed="$(printf '%s' "${response}" | jq -r '.info.version // empty' 2>/dev/null || echo "")"
  else
    # Latest any (including pre-release)
    proposed="$(printf '%s' "${response}" | jq -r \
      '[.releases | keys[]] | sort | last // empty' \
      2>/dev/null || echo "")"
  fi

  if [[ -n "${proposed}" ]]; then
    _cache_write "${cache_key}" "${proposed}"
    echo "${proposed}"
  fi
}
