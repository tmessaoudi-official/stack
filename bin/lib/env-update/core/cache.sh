#!/bin/bash
# cache.sh — TTL-based flat-file cache for fetched versions.
#
# Exports:   _gs_eu2_cache_read  _gs_eu2_cache_write
#            _gs_eu2_cache_invalidate  _gs_eu2_cache_clear_all
#            _gs_eu2_cache_key_to_file  _gs_eu2_cache_try_load
# Sources:   config/defaults.sh
# Deps:      date, stat (GNU or BSD), mktemp, mv
# Env:       _GS_EU2_CACHE_DIR (default: /tmp/global-stack-env-update-cache)
#            _GS_EU2_CACHE_TTL (default: 3600 seconds; set by main.sh from _GS_EU2_CFG)
#
# Cache key → filename: special chars (:, /, @, space) replaced with _ to produce
# a safe flat-file prefix; an 8-char md5 hash of the full key is appended so that
# keys differing only in sanitized characters map to distinct files.  Atomic writes
# (tmp+mv) prevent partial reads from concurrent fetches hitting the same key.
# Dry-run mode skips cache writes (C4).

[[ -n "${_GS_EU2_CACHE_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_CACHE_SH_LOADED=1

# shellcheck source=./../config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/defaults.sh"

_GS_EU2_CACHE_DIR="${_GS_EU2_CACHE_DIR:-/tmp/global-stack-env-update-cache}"
_GS_EU2_CACHE_TTL="${_GS_EU2_CACHE_TTL:-3600}"

# _gs_eu2_cache_key_to_file — map a cache key to its on-disk filename.
#
# Args:    $1 key — cache key (e.g. "github:owner/repo:stable")
# Prints:  absolute path to the cache file (file may or may not exist)
# Returns: 0 always
# Note:    A short md5 hash is appended to the sanitized prefix so that keys
#          differing only in sanitized characters map to distinct files.
_gs_eu2_cache_key_to_file() {
  local _key="${1}"
  local _safe="${_key//[:\/@ ]/_}"
  local _hash
  _hash="$(printf '%s' "${_key}" | md5sum | cut -c1-8)"
  printf '%s/%s_%s.cache' "${_GS_EU2_CACHE_DIR}" "${_safe}" "${_hash}"
}

# _gs_eu2_cache_read — return cached value if fresh, else signal miss.
#
# Args:    $1 key — cache key
# Reads:   _GS_EU2_CACHE_TTL, cache file mtime
# Prints:  cached value string (may be empty if cached as empty)
# Returns: 0 on cache hit (value is fresh); 1 on miss or error (file absent,
#          expired, or disappeared between stat and read)
_gs_eu2_cache_read() {
  local _key="${1}"
  # TTL=0 is an alias for --no-cache: bypass reads entirely (write-through still active)
  [[ "${_GS_EU2_CACHE_TTL}" -eq 0 ]] && return 1
  local _f
  _f="$(_gs_eu2_cache_key_to_file "${_key}")"
  local _now _mtime _age
  _now="$(date +%s)"
  _mtime="$(stat -c %Y "${_f}" 2>/dev/null || stat -f %m "${_f}" 2>/dev/null || echo 0)"
  # stat returns 0 when file is absent — treat age as infinite (stale)
  [[ "${_mtime}" == "0" ]] && return 1
  _age=$(( _now - _mtime ))
  (( _age <= _GS_EU2_CACHE_TTL )) || return 1
  # Atomic read: cat fails if file disappeared between stat and here — caller sees empty/error
  local _content
  _content="$(cat "${_f}" 2>/dev/null)" || return 1
  printf '%s' "${_content}"
  return 0
}

# _gs_eu2_cache_write — atomically write a value to the cache.
#
# Args:    $1 key   — cache key
#          $2 value — value to store (may be empty string)
# Reads:   _GS_EU2_CFG[dry_run]
# Prints:  nothing
# Returns: 0 on success; 1 on failure (mktemp or write error)
# Side fx: creates _GS_EU2_CACHE_DIR if needed; writes tmp file then renames atomically
_gs_eu2_cache_write() {
  # C4: Skip cache writes in dry-run mode — dry runs must not pollute the cache
  if [[ "${_GS_EU2_CFG[dry_run]:-false}" == "true" ]]; then
    return 0
  fi
  local _key="${1}" _value="${2}"
  local _f _ftmp
  _f="$(_gs_eu2_cache_key_to_file "${_key}")"
  mkdir -p "${_GS_EU2_CACHE_DIR}"
  # Atomic write: write to a temp file in the same directory, then rename.
  # Prevents partial reads when a concurrent fetch writes the same cache key.
  _ftmp="$(mktemp "${_GS_EU2_CACHE_DIR}/.cache.XXXXXXXX")"
  if printf '%s' "${_value}" > "${_ftmp}" && mv "${_ftmp}" "${_f}"; then
    return 0
  fi
  rm -f "${_ftmp}" || true
  return 1
}

# _gs_eu2_cache_invalidate — delete the cache file for a single key.
#
# Args:    $1 key — cache key to invalidate
# Returns: 0 always
_gs_eu2_cache_invalidate() {
  local _key="${1}"
  rm -f "$(_gs_eu2_cache_key_to_file "${_key}")"
}

# _gs_eu2_cache_clear_all — delete the entire cache directory.
#
# Args:    none
# Returns: 0 always
# Side fx: removes _GS_EU2_CACHE_DIR and all its contents
_gs_eu2_cache_clear_all() {
  rm -rf "${_GS_EU2_CACHE_DIR}"
}

# _gs_eu2_cache_try_load — probe cache, populate record if hit, signal miss.
#
# Args:    $1 idx           — record index
#          $2 cache_key     — cache key to look up
#          $3 major_hint    — (optional) desired major hint string
#          $4 major_hint_min — (optional) fallback major hint string
# Reads:   _GS_EU2_CFG[no_cache], cache file
# Sets:    record field proposed_version (on hit); using_fallback_major "true" (on fallback)
# Returns: 0 on cache hit (record populated, caller should return 0)
#          1 on cache miss or no_cache=true
_gs_eu2_cache_try_load() {
  local _idx="${1}" _cache_key="${2}" _mh="${3:-}" _mh_min="${4:-}"
  [[ "${_GS_EU2_CFG[no_cache]:-false}" == "true" ]] && return 1
  local _cached
  _cached="$(_gs_eu2_cache_read "${_cache_key}")" || return 1
  [[ -n "${_cached}" ]] || return 1
  if [[ -n "${_mh_min}" \
        && "${_cached}" =~ ^v?"${_mh_min}"([.^_-]|$) \
        && ! "${_cached}" =~ ^v?"${_mh}"([.^_-]|$) ]]; then
    _gs_eu2_record_set "${_idx}" using_fallback_major "true"
  fi
  _gs_eu2_record_set "${_idx}" proposed_version "${_cached}"
  return 0
}
