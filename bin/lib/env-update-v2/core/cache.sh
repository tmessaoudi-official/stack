#!/bin/bash
# cache.sh — TTL-based flat-file cache for fetched versions

[[ -n "${_GS_EU2_CACHE_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_CACHE_SH_LOADED=1

# shellcheck source=./../config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/defaults.sh"

_GS_EU2_CACHE_DIR="${_GS_EU2_CACHE_DIR:-/tmp/global-stack-env-update-v2-cache}"
_GS_EU2_CACHE_TTL="${_GS_EU2_CACHE_TTL:-3600}"

_gs_eu2_cache_key_to_file() {
  local _key="${1}"
  local _safe="${_key//[:\/@ ]/_}"
  printf '%s/%s.cache' "${_GS_EU2_CACHE_DIR}" "${_safe}"
}

_gs_eu2_cache_read() {
  local _key="${1}"
  local _f
  _f="$(_gs_eu2_cache_key_to_file "${_key}")"
  [[ -f "${_f}" ]] || return 1
  local _now _mtime _age
  _now="$(date +%s)"
  _mtime="$(stat -c %Y "${_f}" 2>/dev/null || stat -f %m "${_f}" 2>/dev/null || echo 0)"
  _age=$(( _now - _mtime ))
  (( _age <= _GS_EU2_CACHE_TTL )) || return 1
  cat "${_f}"
  return 0
}

_gs_eu2_cache_write() {
  # C4: Skip cache writes in dry-run mode — dry runs must not pollute the cache
  if [[ "${_GS_EU2_CFG[dry_run]:-false}" == "true" ]]; then
    return 0
  fi
  local _key="${1}" _value="${2}"
  local _f
  _f="$(_gs_eu2_cache_key_to_file "${_key}")"
  mkdir -p "${_GS_EU2_CACHE_DIR}"
  printf '%s' "${_value}" > "${_f}"
}

_gs_eu2_cache_invalidate() {
  local _key="${1}"
  rm -f "$(_gs_eu2_cache_key_to_file "${_key}")"
}

_gs_eu2_cache_clear_all() {
  rm -rf "${_GS_EU2_CACHE_DIR}"
}
