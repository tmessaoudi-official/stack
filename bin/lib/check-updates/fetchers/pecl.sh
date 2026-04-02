#!/bin/bash
# PECL REST API fetcher.
# PECL uses an XML-based REST API at https://pecl.php.net/rest/

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_CU_PECL_SH_LOADED:-}" ]] && return 0
readonly _GS_CU_PECL_SH_LOADED=1

# Fetch latest stable version of a PECL extension
# Usage: _gs_cu_pecl_fetch_latest "imagick" "3.8.1"
_gs_cu_pecl_fetch_latest() {
  local identifier="${1}"    # extension name, e.g. "imagick"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"

  local cache_key="pecl:${identifier}"

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

  # PECL REST API: https://pecl.php.net/rest/r/<extension>/allreleases.xml
  local url="https://pecl.php.net/rest/r/${identifier}/allreleases.xml"
  local response
  if ! response="$(curl --silent --fail --max-time 10 --retry 2 "${url}" 2>/dev/null)"; then
    return 1
  fi

  # Parse XML with grep/sed (xmllint may not be available on host)
  local proposed
  proposed="$(_gs_cu_pecl_parse_latest_stable "${response}")"

  if [[ -n "${proposed}" ]]; then
    _gs_cu_cache_write "${cache_key}" "${proposed}"
    echo "${proposed}"
  fi
}

# Parse PECL allreleases XML and return highest stable version
_gs_cu_pecl_parse_latest_stable() {
  local xml="${1}"

  # Extract version/stability pairs
  # XML format: <v>X.Y.Z</v><s>stable|beta|alpha|...</s>
  local versions=()

  # Simple line-by-line extraction using grep
  local pair
  while IFS= read -r pair; do
    local ver="${pair%%:*}"
    local stab="${pair##*:}"
    if [[ "${stab,,}" == "stable" ]]; then
      versions+=("${ver}")
    fi
  done < <(
    printf '%s' "${xml}" | \
      grep -oE '<v>[^<]+</v><s>[^<]+</s>' | \
      sed 's|<v>\([^<]*\)</v><s>\([^<]*\)</s>|\1:\2|g' \
      2>/dev/null || true
  )

  if [[ ${#versions[@]} -eq 0 ]]; then
    # No stable — try beta
    while IFS= read -r pair; do
      local ver="${pair%%:*}"
      local stab="${pair##*:}"
      if [[ "${stab,,}" =~ (beta|alpha) ]]; then
        versions+=("${ver}")
      fi
    done < <(
      printf '%s' "${xml}" | \
        grep -oE '<v>[^<]+</v><s>[^<]+</s>' | \
        sed 's|<v>\([^<]*\)</v><s>\([^<]*\)</s>|\1:\2|g' \
        2>/dev/null || true
    )
  fi

  if [[ ${#versions[@]} -eq 0 ]]; then
    return 0
  fi

  # Sort and return highest
  local highest
  highest="$(printf '%s\n' "${versions[@]}" | sort -V | tail -1)"
  echo "${highest}"
}
