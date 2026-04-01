#!/bin/bash
# npm registry API fetcher.
# Also handles npm --global outdated for all Node versions.

set -eEuo pipefail

# Fetch latest version of an npm package from the registry
# Usage: _npm_fetch_latest "@angular/cli" "21.2.2"
_npm_fetch_latest() {
  local identifier="${1}"    # "package-name" or "@scope/package"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"

  local cache_key="npm:${identifier}"

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

  # URL-encode the package name (@ → %40, / → %2F)
  local encoded_pkg="${identifier//@/%40}"
  encoded_pkg="${encoded_pkg//\//%2F}"

  local url="https://registry.npmjs.org/${encoded_pkg}"
  local response
  if ! response="$(curl --silent --fail --max-time 10 --retry 2 \
    -H "Accept: application/json" \
    "${url}" 2>/dev/null)"; then
    return 1
  fi

  local is_pre=false
  if [[ "${current_version,,}" =~ (alpha|beta|rc[0-9]*|preview) ]]; then
    is_pre=true
  fi

  local proposed
  if [[ "${is_pre}" == "false" ]]; then
    # Get the "latest" dist-tag
    proposed="$(printf '%s' "${response}" | jq -r '.["dist-tags"].latest // empty' 2>/dev/null || echo "")"
  else
    # Get highest version number from all versions
    proposed="$(printf '%s' "${response}" | jq -r \
      '[.versions | keys[]] | sort | last // empty' \
      2>/dev/null || echo "")"
  fi

  if [[ -n "${proposed}" ]]; then
    _cache_write "${cache_key}" "${proposed}"
    echo "${proposed}"
  fi
}

# Check npm --global outdated for a specific Node version using nvm
# Usage: _npm_global_outdated_for_node "22.22.1" "GLOBAL_STACK_NODE22_VERSION"
# Returns: JSON object mapping package_name → latest_version
_npm_global_outdated_for_node() {
  local node_version="${1}"
  local node_var="${2}"

  # NVM_DIR must be set — try tools path
  local nvm_dir="${GLOBAL_STACK_NVM_DIR:-${GLOBAL_STACK_DOCKER_TOOLS_PATH:-/stack/tools}/nvm}"

  if [[ ! -f "${nvm_dir}/nvm.sh" ]]; then
    _log_debug "nvm.sh not found at ${nvm_dir}/nvm.sh — skipping npm global outdated for ${node_version}"
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
_npm_global_outdated_all() {
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

    _log_debug "Running npm --global outdated for node ${nv} (${label})"
    local result
    result="$(_npm_global_outdated_for_node "${nv}" "${label}")"
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
