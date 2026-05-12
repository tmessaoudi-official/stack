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
    # D3: Use ([0-9]|$) as trailing anchor — prevents "rcx" from matching "rc"
    # while still allowing rc1, rc2, rc.1, rc-1, etc.
    local _pat="(^|[-._[:digit:]])${_q}([0-9]|\$)"
    [[ "${_ver}" =~ ${_pat} ]] && { IFS="${_IFS}"; return 0; }
  done
  IFS="${_IFS}"
  return 1
}

# Filter a newline-separated version list by channel
_gs_eu2_filter_versions_by_channel() {
  local _vers="${1}" _chan="${2:-}"
  [[ -z "${_chan}" ]] && { printf '%s\n' "${_vers}"; return 0; }
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
    [[ "${_v}" =~ ^v?[0-9] ]] || continue
    if _gs_eu2_is_prerelease "${_v}"; then _pres+=("${_v}")
    else _stables+=("${_v}"); fi
  done <<< "${_all}"

  local _hs="" _hp=""
  [[ ${#_stables[@]} -gt 0 ]] && _hs="$(printf '%s\n' "${_stables[@]}" | sort -V | tail -1)" || true
  [[ ${#_pres[@]}    -gt 0 ]] && _hp="$(printf '%s\n' "${_pres[@]}"    | sort -V | tail -1)" || true

  # Non-numeric fallback: handle letter-starting tags (e.g. ubuntu codename "resolute-20260413").
  # When no numeric/v-prefixed tags survive the loop, sort all non-unversioned tags with sort -V.
  if [[ ${#_stables[@]} -eq 0 && ${#_pres[@]} -eq 0 ]]; then
    local _fb=()
    while IFS= read -r _v; do
      [[ -z "${_v}" ]] && continue
      _gs_eu2_is_unversioned "${_v}" && continue
      _fb+=("${_v}")
    done <<< "${_all}"
    if [[ ${#_fb[@]} -gt 0 ]]; then
      printf '%s\n' "$(printf '%s\n' "${_fb[@]}" | sort -V | tail -1)"
    fi
    return 0
  fi

  # Default/stable channel: never fall back to prerelease — return nothing if no stable exists
  if [[ -z "${_chan}" || "${_chan}" == "stable" ]]; then
    [[ -z "${_hs}" ]] && return 0
    printf '%s\n' "${_hs}"
    return 0
  fi

  # Unstable: highest pre-release
  if [[ "${_chan}" == "unstable" ]]; then
    [[ -n "${_hp}" ]] && { printf '%s\n' "${_hp}"; return 0; }
    [[ -n "${_hs}" ]] && printf '%s\n' "${_hs}"
    return 0
  fi

  # Nightly: only return a version whose tag literally contains "nightly".
  # If none found → return nothing so the caller (url.sh) falls through to
  # the Tier-4 nightly directory listing.
  if [[ "${_chan}" == "nightly" ]]; then
    local _nightlies=()
    while IFS= read -r _v; do
      [[ -z "${_v}" ]] && continue
      [[ "${_v,,}" == *"nightly"* ]] && _nightlies+=("${_v}")
    done <<< "${_all}"
    [[ ${#_nightlies[@]} -gt 0 ]] && \
      printf '%s\n' "$(printf '%s\n' "${_nightlies[@]}" | sort -V | tail -1)"
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
