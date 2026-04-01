#!/bin/bash
# Cache read/write with TTL support.
# Cache directory: /tmp/global-stack-check-updates-cache/
# Cache key is derived from the type:identifier string (URL-safe filename).

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_CU_CACHE_LOADED:-}" ]] && return 0
readonly _CU_CACHE_LOADED=1

CU_CACHE_DIR="${CU_CACHE_DIR:-/tmp/global-stack-check-updates-cache}"
CU_CACHE_TTL="${CU_CACHE_TTL:-3600}"

# Ensure cache directory exists
_cache_init() {
  mkdir -p "${CU_CACHE_DIR}"
}

# Convert a cache key to a safe filename
# Usage: _cache_key_to_file "dockerhub:axllent/mailpit" → echoes file path
_cache_key_to_file() {
  local key="${1}"
  # Replace / : @ with _ to get a safe filename
  local safe
  safe="${key//[:\/@ ]/_}"
  echo "${CU_CACHE_DIR}/${safe}.cache"
}

# Read cached value if it exists and is within TTL
# Usage: _cache_read "dockerhub:axllent/mailpit"
# Returns 0 and echoes cached content if valid, returns 1 if miss/expired
_cache_read() {
  local key="${1}"
  local cache_file
  cache_file="$(_cache_key_to_file "${key}")"

  if [[ ! -f "${cache_file}" ]]; then
    _log_debug "Cache MISS: ${key}"
    return 1
  fi

  local now
  now="$(date +%s)"
  local mtime
  mtime="$(stat -c %Y "${cache_file}" 2>/dev/null || stat -f %m "${cache_file}" 2>/dev/null || echo 0)"
  local age=$(( now - mtime ))

  if [[ ${age} -gt ${CU_CACHE_TTL} ]]; then
    _log_debug "Cache EXPIRED (age=${age}s): ${key}"
    return 1
  fi

  _log_debug "Cache HIT (age=${age}s): ${key}"
  cat "${cache_file}"
  return 0
}

# Write a value to the cache
# Usage: _cache_write "dockerhub:axllent/mailpit" "v1.30.0"
_cache_write() {
  local key="${1}"
  local value="${2}"
  local cache_file
  cache_file="$(_cache_key_to_file "${key}")"
  _cache_init
  printf '%s' "${value}" > "${cache_file}"
  _log_debug "Cache WRITE: ${key} = ${value}"
}

# Invalidate a specific cache entry
# Usage: _cache_invalidate "dockerhub:axllent/mailpit"
_cache_invalidate() {
  local key="${1}"
  local cache_file
  cache_file="$(_cache_key_to_file "${key}")"
  rm -f "${cache_file}"
}

# Clear all cache entries
_cache_clear_all() {
  rm -rf "${CU_CACHE_DIR}"
  _log_debug "Cache cleared"
}
