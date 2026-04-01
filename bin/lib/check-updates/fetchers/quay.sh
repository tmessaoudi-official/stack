#!/bin/bash
# Quay.io API fetcher.
# Used for keycloak and other Quay-hosted images.

set -eEuo pipefail

# Fetch latest tag from Quay.io
# Usage: _quay_fetch_latest "keycloak/keycloak" "26.5.5-0"
_quay_fetch_latest() {
  local identifier="${1}"    # "org/image"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"

  local cache_key="quay:${identifier}"

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

  # Quay.io API v1
  local url="https://quay.io/api/v1/repository/${identifier}/tag/?limit=50&onlyActiveTags=true"
  local response
  if ! response="$(curl --silent --fail --max-time 10 --retry 2 \
    -H "Accept: application/json" \
    "${url}" 2>/dev/null)"; then
    return 1
  fi

  local proposed
  proposed="$(_quay_select_best_tag "${response}" "${current_version}")"

  if [[ -n "${proposed}" ]]; then
    _cache_write "${cache_key}" "${proposed}"
    echo "${proposed}"
  fi
}

# Select best tag from Quay.io API response
_quay_select_best_tag() {
  local response="${1}"
  local current_version="${2}"

  local is_pre=false
  if [[ "${current_version,,}" =~ (alpha|beta|rc[0-9]*|preview) ]]; then
    is_pre=true
  fi

  local proposed
  if [[ "${is_pre}" == "false" ]]; then
    # Only stable versions — filter out alpha/beta/rc/latest
    proposed="$(printf '%s' "${response}" | jq -r \
      '[.tags[].name | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+-[0-9]+$"))] | sort | last // empty' \
      2>/dev/null || echo "")"
    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0

    # Fallback: any semver-like tag
    proposed="$(printf '%s' "${response}" | jq -r \
      '[.tags[].name | select(test("^[0-9]+\\.[0-9]") and (test("alpha|beta|rc|latest|nightly") | not))] | sort | last // empty' \
      2>/dev/null || echo "")"
  else
    proposed="$(printf '%s' "${response}" | jq -r \
      '[.tags[].name | select(test("^[0-9]+\\.[0-9]") and (test("latest|nightly") | not))] | sort | last // empty' \
      2>/dev/null || echo "")"
  fi

  echo "${proposed}"
}
