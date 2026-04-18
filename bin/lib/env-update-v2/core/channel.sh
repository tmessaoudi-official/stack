#!/bin/bash
# channel.sh — stable/rc/beta/unstable tag selection (ported from v1)

[[ -n "${_GS_EU2_CHANNEL_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_CHANNEL_SH_LOADED=1

# shellcheck source=./semver.sh
source "$(dirname "${BASH_SOURCE[0]}")/semver.sh"

# Returns 0 if version matches channel qualifier (case-insensitive word-boundary match)
_gs_eu2_version_matches_channel() {
  local _ver="${1,,}" _chan="${2}"
  [[ "${_chan}" == "unstable" ]] && { _gs_eu2_is_prerelease "${1}"; return; }
  local _q _IFS="${IFS}"; IFS=','
  for _q in ${_chan}; do
    _q="${_q,,}"
    local _pat="(^|[-._[:digit:]])${_q}([[:digit:]._-]|\$)"
    [[ "${_ver}" =~ ${_pat} ]] && { IFS="${_IFS}"; return 0; }
  done
  IFS="${_IFS}"
  return 1
}

# Filter a newline-separated version list by channel
_gs_eu2_filter_versions_by_channel() {
  local _vers="${1}" _chan="${2:-}"
  [[ -z "${_chan}" || "${_chan}" == "nightly" ]] && { printf '%s\n' "${_vers}"; return 0; }
  local _v
  while IFS= read -r _v; do
    [[ -z "${_v}" ]] && continue
    _gs_eu2_version_matches_channel "${_v}" "${_chan}" && printf '%s\n' "${_v}"
  done <<< "${_vers}"
}

# Select the best version from a newline-separated list given a channel.
# Echoes the selected version; returns 0 always.
# $1 = newline-separated version list, $2 = channel (empty → stable)
_gs_eu2_channel_select_best() {
  local _all="${1}" _chan="${2:-}"
  [[ -z "${_all}" ]] && return 0

  local _stables=() _pres=() _v
  while IFS= read -r _v; do
    [[ -z "${_v}" ]] && continue
    [[ "${_v}" =~ ^[0-9] ]] || continue
    if _gs_eu2_is_prerelease "${_v}"; then _pres+=("${_v}")
    else _stables+=("${_v}"); fi
  done <<< "${_all}"

  local _hs="" _hp=""
  [[ ${#_stables[@]} -gt 0 ]] && _hs="$(printf '%s\n' "${_stables[@]}" | sort -V | tail -1)" || true
  [[ ${#_pres[@]}    -gt 0 ]] && _hp="$(printf '%s\n' "${_pres[@]}"    | sort -V | tail -1)" || true

  # Default/stable channel
  if [[ -z "${_chan}" || "${_chan}" == "stable" ]]; then
    local _p="${_hs:-${_hp}}"
    [[ -z "${_p}" ]] && return 0
    printf '%s\n' "${_p}"
    return 0
  fi

  # Unstable: highest pre-release
  if [[ "${_chan}" == "unstable" ]]; then
    [[ -n "${_hp}" ]] && { printf '%s\n' "${_hp}"; return 0; }
    [[ -n "${_hs}" ]] && printf '%s\n' "${_hs}"
    return 0
  fi

  # Specific channel (rc, beta, etc.)
  local _filtered
  _filtered="$(_gs_eu2_filter_versions_by_channel "${_all}" "${_chan}")"
  local _cm=""
  [[ -n "${_filtered}" ]] && _cm="$(printf '%s\n' "${_filtered}" | grep -v '^$' | sort -V | tail -1)" || true
  [[ -z "${_cm}" && -n "${_hp}" ]] && _cm="${_hp}"

  if [[ -z "${_cm}" ]]; then
    [[ -n "${_hs}" ]] && printf '%s\n' "${_hs}"
    return 0
  fi

  # Promotion: if stable has surpassed the channel match
  if [[ -n "${_hs}" ]]; then
    local _cmp; _cmp="$(_gs_eu2_semver_compare "${_hs}" "${_cm}")"
    [[ "${_cmp}" == "newer" ]] && { printf '%s\n' "${_hs}"; return 0; }
  fi

  printf '%s\n' "${_cm}"
}
