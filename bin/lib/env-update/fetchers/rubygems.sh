#!/bin/bash
# RubyGems.org API fetcher.
# Fetches latest stable or pre-release version for a RubyGems package.
# Usage type: rubygems:PACKAGE

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_EU_RUBYGEMS_SH_LOADED:-}" ]] && return 0
readonly _GS_EU_RUBYGEMS_SH_LOADED=1

# CLI fetch: uses `gem search` to get all versions.
# Usage: _gs_eu_rubygems_fetch_cli identifier current_version offline no_cache channel
_gs_eu_rubygems_fetch_cli() {
  local identifier="${1}"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"
  local channel="${5:-}"

  # Skip if offline
  [[ "${offline}" == "true" ]] && return 1

  # Use gem search to get versions
  local gem_output
  gem_output="$(gem search "^${identifier}$" --versions --all 2>/dev/null)" || return 1
  [[ -z "${gem_output}" ]] && return 1

  # gem search output: "gemname (1.0.0, 0.9.0, ...)"
  local versions_str
  versions_str="$(printf '%s' "${gem_output}" | grep -E "^${identifier} " | grep -oP '\(.*?\)' | tr -d '()' | tr ',' '\n' | tr -d ' ')" || return 1
  [[ -z "${versions_str}" ]] && return 1

  # For pre-release: also try gem search --pre
  if [[ -n "${channel}" && "${channel}" != "stable" ]]; then
    local pre_output
    pre_output="$(gem search "^${identifier}$" --versions --all --pre 2>/dev/null)" || true
    local pre_versions
    pre_versions="$(printf '%s' "${pre_output}" | grep -E "^${identifier} " | grep -oP '\(.*?\)' | tr -d '()' | tr ',' '\n' | tr -d ' ')" || true
    versions_str="${versions_str}"$'\n'"${pre_versions}"
  fi

  _gs_eu_channel_select_best "${versions_str}" "${channel}"
}

# API fetch: uses RubyGems.org JSON API.
# Usage: _gs_eu_rubygems_fetch_api identifier current_version offline no_cache channel
_gs_eu_rubygems_fetch_api() {
  local identifier="${1}"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"
  local channel="${5:-}"

  if [[ "${offline}" == "true" ]]; then
    return 1
  fi

  # ------------------------------------------------------------------
  # Fetch stable latest via /api/v1/gems/:name.json
  # ------------------------------------------------------------------
  local api_url="https://rubygems.org/api/v1/gems/${identifier}.json"
  local tmp_file
  tmp_file="$(mktemp)"
  local http_code
  http_code="$(curl --silent --location --max-time 15 --retry 2 \
    -H "Accept: application/json" \
    -o "${tmp_file}" \
    -w "%{http_code}" \
    "${api_url}" 2>/dev/null || echo "0")"
  local response
  response="$(cat "${tmp_file}" 2>/dev/null || true)"
  rm -f "${tmp_file}"

  if [[ "${http_code}" == "404" ]]; then
    _gs_eu_set_fetch_error "rubygems: gem '${identifier}' not found (HTTP 404)"
    return 1
  elif [[ "${http_code}" == "0" || "${http_code:0:1}" != "2" ]]; then
    _gs_eu_set_fetch_error "rubygems: HTTP ${http_code} for '${identifier}'"
    return 1
  fi

  # /gems/:name.json returns the latest stable version
  local stable_proposed
  stable_proposed="$(printf '%s' "${response}" | jq -r '.version // empty' 2>/dev/null || true)"

  if [[ -z "${stable_proposed}" || "${stable_proposed}" == "null" ]]; then
    _gs_eu_set_fetch_error "rubygems: could not extract version for '${identifier}'"
    return 1
  fi

  # ------------------------------------------------------------------
  # Fetch all versions via /api/v1/versions/:name.json for channel/pre-release support
  # ------------------------------------------------------------------
  local all_versions_json=""
  local ver_tmp
  ver_tmp="$(mktemp)"
  local ver_http
  ver_http="$(curl --silent --location --max-time 15 --retry 2 \
    -H "Accept: application/json" \
    -o "${ver_tmp}" \
    -w "%{http_code}" \
    "https://rubygems.org/api/v1/versions/${identifier}.json" 2>/dev/null || echo "0")"
  all_versions_json="$(cat "${ver_tmp}" 2>/dev/null || true)"
  rm -f "${ver_tmp}"

  if [[ "${ver_http:0:1}" != "2" ]]; then
    # Versions endpoint failed — fall through using only stable_proposed
    all_versions_json=""
  fi

  local proposed

  local versions_body="${all_versions_json}"
  local all_versions
  if [[ -n "${versions_body}" ]]; then
    all_versions="$(printf '%s' "${versions_body}" | jq -r '.[].number' 2>/dev/null || true)"
  else
    # Fall back to stable_proposed only if versions endpoint failed
    all_versions="${stable_proposed}"
  fi
  proposed="$(_gs_eu_channel_select_best "${all_versions}" "${channel}")"

  if [[ -n "${proposed}" ]]; then
    echo "${proposed}"
  fi
}

# Fetch latest version of a RubyGems package.
# Tries CLI (gem search) first via _gs_eu_cli_with_fallback, falls back to RubyGems API.
# Usage: _gs_eu_rubygems_fetch_latest gem ver offline no_cache channel env_var
# Returns: echoed version string or empty on failure
_gs_eu_rubygems_fetch_latest() {
  local identifier="${1}"    # gem name
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"
  local channel="${5:-}"        # channel qualifier (rc, beta, alpha, unstable, ...)
  local env_var="${6:-}"        # .env variable name for runtime derivation

  local cache_key="rubygems:${identifier}:${channel}"

  if [[ "${no_cache}" != "true" ]]; then
    local cached
    if cached="$(_gs_eu_cache_read "${cache_key}" 2>/dev/null)"; then
      echo "${cached}"
      return 0
    fi
  fi

  local proposed
  proposed="$(_gs_eu_cli_with_fallback \
    "_gs_eu_rubygems_fetch_cli" \
    "_gs_eu_rubygems_fetch_api" \
    "${env_var}" \
    "${identifier}" "${current_version}" "${offline}" "${no_cache}" "${channel}")"

  if [[ -n "${proposed}" ]]; then
    _gs_eu_cache_write "${cache_key}" "${proposed}"
    echo "${proposed}"
  fi
}
