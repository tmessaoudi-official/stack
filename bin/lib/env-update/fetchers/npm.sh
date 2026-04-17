#!/bin/bash
# npm registry API fetcher.
# Also handles npm --global outdated for all Node versions.

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_EU_NPM_SH_LOADED:-}" ]] && return 0
readonly _GS_EU_NPM_SH_LOADED=1

# CLI fetch: uses `npm view <pkg> versions --json` to get all versions
# Usage: _gs_eu_npm_fetch_cli identifier current_version offline no_cache channel
_gs_eu_npm_fetch_cli() {
  local identifier="${1}"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"
  local channel="${5:-}"

  # Skip if offline
  [[ "${offline}" == "true" ]] && return 1

  # For stable mode, use dist-tags.latest — npm's canonical "latest stable" as declared
  # by the package maintainer. This correctly excludes deprecated sentinels like 9999.0.0.
  if [[ -z "${channel}" || "${channel}" == "stable" ]]; then
    local dist_tags_latest
    dist_tags_latest="$(npm view "${identifier}" dist-tags.latest 2>/dev/null)" || return 1
    if [[ -n "${dist_tags_latest}" ]]; then
      echo "${dist_tags_latest}"
      return 0
    fi
  fi

  # For channel modes (rc, beta, etc.) or when dist-tags.latest is unavailable,
  # fall back to full version list + channel selector
  local pkg_versions
  pkg_versions="$(npm view "${identifier}" versions --json 2>/dev/null)" || return 1
  [[ -z "${pkg_versions}" ]] && return 1

  local all_versions
  all_versions="$(printf '%s' "${pkg_versions}" | jq -r '.[]' 2>/dev/null)" || return 1
  [[ -z "${all_versions}" ]] && return 1

  _gs_eu_channel_select_best "${all_versions}" "${channel}"
}

# API fetch: uses npm registry JSON API
# Usage: _gs_eu_npm_fetch_api identifier current_version offline no_cache channel
_gs_eu_npm_fetch_api() {
  local identifier="${1}"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"
  local channel="${5:-}"

  if [[ "${offline}" == "true" ]]; then
    return 1
  fi

  # URL-encode the package name (@ → %40, / → %2F)
  local encoded_pkg="${identifier//@/%40}"
  encoded_pkg="${encoded_pkg//\//%2F}"

  local url="https://registry.npmjs.org/${encoded_pkg}"
  local response
  if ! response="$(curl --silent --location --fail --max-time 10 --retry 2 \
    -H "Accept: application/json" \
    "${url}" 2>/dev/null)"; then
    _gs_eu_set_fetch_error "npm: network error fetching '${identifier}'"
    return 1
  fi

  local proposed

  # Get all non-deprecated version keys from registry.
  # Packages like @nrwl/cli use 9999.0.0 as a deprecated sentinel — filter these out.
  local all_versions
  all_versions="$(printf '%s' "${response}" | jq -r \
    '[.versions | to_entries[] | select(.value.deprecated | not) | .key] | .[]' \
    2>/dev/null || true)"
  proposed="$(_gs_eu_channel_select_best "${all_versions}" "${channel}")"

  if [[ -n "${proposed}" ]]; then
    echo "${proposed}"
  fi
}

# Fetch latest version of an npm package.
# Tries CLI (npm view) first via _gs_eu_cli_with_fallback, falls back to registry API.
# Usage: _gs_eu_npm_fetch_latest identifier current_version offline no_cache channel env_var
_gs_eu_npm_fetch_latest() {
  local identifier="${1}"    # "package-name" or "@scope/package"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"
  local channel="${5:-}"        # channel qualifier (rc, beta, alpha, unstable, ...)
  local env_var="${6:-}"        # .env variable name for runtime derivation

  local cache_key="npm:${identifier}:${channel}"

  if [[ "${no_cache}" != "true" ]]; then
    local cached
    if cached="$(_gs_eu_cache_read "${cache_key}" 2>/dev/null)"; then
      echo "${cached}"
      return 0
    fi
  fi

  local proposed
  proposed="$(_gs_eu_cli_with_fallback \
    "_gs_eu_npm_fetch_cli" \
    "_gs_eu_npm_fetch_api" \
    "${env_var}" \
    "${identifier}" "${current_version}" "${offline}" "${no_cache}" "${channel}")"

  if [[ -n "${proposed}" ]]; then
    _gs_eu_cache_write "${cache_key}" "${proposed}"
    echo "${proposed}"
  fi
}

# Check npm --global outdated for a specific Node version using nvm
# Usage: _gs_eu_npm_global_outdated_for_node "22.22.1" "GLOBAL_STACK_NODE22_VERSION"
# Returns: JSON object mapping package_name → latest_version
_gs_eu_npm_global_outdated_for_node() {
  local node_version="${1}"
  local node_var="${2}"

  # NVM_DIR must be set — try tools path
  local nvm_dir="${GLOBAL_STACK_NVM_DIR:-${GLOBAL_STACK_DOCKER_TOOLS_PATH:-/stack/tools}/nvm}"

  if [[ ! -f "${nvm_dir}/nvm.sh" ]]; then
    _gs_eu_log_debug "nvm.sh not found at ${nvm_dir}/nvm.sh — skipping npm global outdated for ${node_version}"
    echo "{}"
    return 0
  fi

  # We need a subshell to source nvm without polluting current environment
  local outdated_json
  outdated_json="$(
    # shellcheck source=/dev/null
    export NVM_DIR="${nvm_dir}"
    source "${nvm_dir}/nvm.sh" --no-use 2>/dev/null || true

    if ! nvm use "${node_version}" > /dev/null 2>&1; then
      echo "{}"
      exit 0
    fi

    npm --global outdated --json 2>/dev/null || echo "{}"
  )" || true

  # npm --global outdated --json returns non-zero when there are outdated packages
  # Output format: { "package": { "current": "x", "wanted": "y", "latest": "z" } }
  printf '%s' "${outdated_json}"
}

# Run npm global outdated for all node versions and return merged results
# Returns: echoes tab-separated "package_name\tlatest_version" pairs
_gs_eu_npm_global_outdated_all() {
  local offline="${1:-false}"
  [[ "${offline}" == "true" ]] && return 0

  local node_vars=(
    "${GLOBAL_STACK_NODE22_VERSION:-}:NODE22"
    "${GLOBAL_STACK_NODE24_VERSION:-}:NODE24"
    "${GLOBAL_STACK_NODEEDGE_VERSION:-}:NODEEDGE"
  )

  local combined="{}"

  local entry
  for entry in "${node_vars[@]}"; do
    local nv="${entry%%:*}"
    local label="${entry##*:}"
    [[ -z "${nv}" ]] && continue

    _gs_eu_log_debug "Running npm --global outdated for node ${nv} (${label})"
    local result
    result="$(_gs_eu_npm_global_outdated_for_node "${nv}" "${label}")"
    if [[ -n "${result}" && "${result}" != "{}" ]]; then
      # Merge: combined = combined + result (latest key wins)
      combined="$(printf '%s\n%s\n' "${combined}" "${result}" | \
        jq -rs 'reduce .[] as $item ({}; . * $item)' 2>/dev/null || echo "{}")"
    fi
  done

  # Output: one line per outdated package: "package\tlatest"
  printf '%s' "${combined}" | jq -r \
    'to_entries[] | "\(.key)\t\(.value.latest // empty)"' 2>/dev/null || true
}
