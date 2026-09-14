#!/bin/bash
# channel.sh — stable/rc/beta/unstable channel selection and tag filtering.
#
# Exports:   _gs_eu2_version_matches_channel  _gs_eu2_filter_versions_by_channel
#            _gs_eu2_channel_select_best  _gs_eu2_channel_nth_newest
#            _gs_eu2_channel_count_stable
# Sources:   core/semver.sh
# Deps:      bash 4.3+ (associative array-free; portable)
# Env:       none
#
# Channel values (from @todo annotation (channel:VALUE)):
#   ""/"stable"  — return highest stable (non-prerelease) version
#   "unstable"   — return highest prerelease (or stable if stable surpassed it)
#   "nightly"    — return highest tag containing "nightly" literally
#   "rc","beta",… — return highest tag matching the qualifier; fall back to stable

[[ -n "${_GS_EU2_CHANNEL_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_CHANNEL_SH_LOADED=1

# shellcheck source=./semver.sh
source "$(dirname "${BASH_SOURCE[0]}")/semver.sh"

# _gs_eu2_version_matches_channel — test whether a version tag matches a channel qualifier.
#
# Args:    $1 version — version string to test
#          $2 channel — channel qualifier ("unstable" delegates to _gs_eu2_is_prerelease;
#                       other values are matched case-insensitively with word-boundary regex)
# Prints:  nothing
# Returns: 0 if the version matches; 1 if not
#
# Pattern: D3 — trailing anchor ([0-9]|$) prevents "rcx" matching "rc" while
# allowing rc1, rc2, rc.1, rc-1 forms.
_gs_eu2_version_matches_channel() {
  local _ver="${1,,}" _chan="${2}"
  [[ "${_chan}" == "unstable" ]] && { _gs_eu2_is_prerelease "${1}"; return; }
  # Split comma-separated channel qualifiers without mutating IFS (fragile on error paths).
  # Replace commas with newlines, then read into an array via process substitution.
  local _q_arr=()
  while IFS= read -r _q; do
    [[ -z "${_q}" ]] && continue
    _q="${_q,,}"
    # D3: Use ([0-9]|$) as trailing anchor — prevents "rcx" from matching "rc"
    # while still allowing rc1, rc2, rc.1, rc-1, etc.
    local _pat="(^|[-._[:digit:]])${_q}([0-9]|\$)"
    [[ "${_ver}" =~ ${_pat} ]] && return 0
  done <<<"${_chan//,/$'\n'}"
  return 1
}

# _gs_eu2_filter_versions_by_channel — keep only versions matching a channel qualifier.
#
# Args:    $1 versions — newline-separated list of version strings
#          $2 channel  — channel qualifier; empty → return all (pass-through)
# Prints:  filtered newline-separated list
# Returns: 0 always
_gs_eu2_filter_versions_by_channel() {
  local _vers="${1}" _chan="${2:-}"
  [[ -z "${_chan}" ]] && { printf '%s\n' "${_vers}"; return 0; }
  local _v
  while IFS= read -r _v; do
    [[ -z "${_v}" ]] && continue
    _gs_eu2_version_matches_channel "${_v}" "${_chan}" && printf '%s\n' "${_v}"
  done <<< "${_vers}"
}

# _gs_eu2_channel_count_stable — how many DISTINCT stable versions a list holds.
#
# Args:    $1 versions — newline-separated version strings
# Prints:  the count (0 when none) — used to word the "offset past the end" error
# Returns: 0 always
_gs_eu2_channel_count_stable() {
  local _all="${1}" _v
  local _stables=()
  while IFS= read -r _v; do
    [[ -z "${_v}" ]] && continue
    [[ "${_v}" =~ ^v?[0-9] ]] || continue
    _gs_eu2_is_prerelease "${_v}" && continue
    _stables+=("${_v}")
  done <<< "${_all}"
  if [[ ${#_stables[@]} -eq 0 ]]; then
    printf '0\n'
    return 0
  fi
  printf '%s\n' "${_stables[@]}" | _gs_eu2_version_sort -u | grep -c . || true
}

# _gs_eu2_channel_select_best — pick the best version from a list given a channel.
#
# Args:    $1 versions — newline-separated list of version strings
#          $2 channel  — channel qualifier (empty/"stable" → best stable only)
#          $3 offset   — (optional, default 0) the N-th newest DISTINCT version
#                        instead of the newest: 0 = latest, 1 = latest-1, …
#                        Honoured on the stable channel and the non-numeric
#                        fallback only — parse.sh refuses (offset:N>0) with any
#                        other (channel:…), so the prerelease branches never see it.
# Reads:   nothing
# Prints:  selected version string; nothing if list is empty, no match for channel,
#          or the offset reaches past the end of the list
# Returns: 0 always
#
# Sort strategy: tags are sorted with awk (strip v-prefix) + sort -V to avoid
# mixed v-prefix/no-prefix ordering bugs (v0.3.0 sorts after 1.0.0 in plain sort -V).
#
# Stable channel: never falls back to prerelease.
# Unstable: returns highest prerelease, but promotes to stable if stable has surpassed it.
# Nightly: only tags containing "nightly" literally.
# Other channels (rc, beta, …): highest tag matching qualifier; falls back to stable
#   if no match, but always promotes to stable if stable surpassed the channel match.
# _gs_eu2_channel_nth_newest — the N-th newest DISTINCT version of a list (row 41).
#
# Args:    $1 list — newline-separated version strings (already channel-filtered)
#          $2 n    — 0 = newest, 1 = the one below it, … (default 0)
# Prints:  the selected ORIGINAL string (v-prefix kept as written); nothing when
#          the list holds n or fewer distinct versions — past the end is "no
#          proposal", never "the oldest one", so a window that outruns upstream
#          surfaces as an error in the fetcher instead of a silent wrong pin
# Returns: 0 always
_gs_eu2_channel_nth_newest() {
  local _list="${1}" _n="${2:-0}"
  [[ -z "${_list}" ]] && return 0
  local _sorted _count
  # Ranked, v-stripped key (see _gs_eu2_version_keys); -u on the KEY makes 1.2.0 and
  # v1.2.0 one entry. The original strings come back as written.
  _sorted="$(printf '%s\n' "${_list}" | _gs_eu2_version_sort -u)"
  _count="$(printf '%s\n' "${_sorted}" | grep -c . || true)"
  [[ "${_count}" -le "${_n}" ]] && return 0
  printf '%s\n' "${_sorted}" | sed -n "$((_count - _n))p"
}

_gs_eu2_channel_select_best() {
  local _all="${1}" _chan="${2:-}" _off="${3:-0}"
  [[ -z "${_all}" ]] && return 0

  local _stables=() _pres=() _v
  while IFS= read -r _v; do
    [[ -z "${_v}" ]] && continue
    [[ "${_v}" =~ ^v?[0-9] ]] || continue
    if _gs_eu2_is_prerelease "${_v}"; then _pres+=("${_v}")
    else _stables+=("${_v}"); fi
  done <<< "${_all}"

  # _gs_eu2_version_sort strips the leading 'v' in its key (v0.3.0 would otherwise sort
  # after 1.0.0) AND ranks pre-release markers (RC-2 above beta-3, row 48), returning
  # the original tag strings.
  local _hs="" _hp=""
  [[ ${#_stables[@]} -gt 0 ]] && _hs="$(printf '%s\n' "${_stables[@]}" \
    | _gs_eu2_version_sort | tail -1)" || true
  [[ ${#_pres[@]}    -gt 0 ]] && _hp="$(printf '%s\n' "${_pres[@]}" \
    | _gs_eu2_version_sort | tail -1)" || true

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
      _gs_eu2_channel_nth_newest "$(printf '%s\n' "${_fb[@]}")" "${_off}"
    fi
    return 0
  fi

  # Default/stable channel: never fall back to prerelease — return nothing if no stable exists.
  # (offset:N) walks N distinct stable versions down from the newest; past the end → nothing.
  if [[ -z "${_chan}" || "${_chan}" == "stable" ]]; then
    if [[ "${_off}" -gt 0 ]]; then
      [[ ${#_stables[@]} -eq 0 ]] && return 0
      _gs_eu2_channel_nth_newest "$(printf '%s\n' "${_stables[@]}")" "${_off}"
      return 0
    fi
    [[ -z "${_hs}" ]] && return 0
    printf '%s\n' "${_hs}"
    return 0
  fi

  # Unstable: highest pre-release — but promote stable when it has surpassed the prerelease.
  # e.g. stable=3.1.1 vs hp=3.0.0-rc.4 → stable is newer → return stable (not a downgrade).
  # e.g. stable=1.7.1 vs hp=1.8.0-rc1  → hp is newer → return hp (genuine prerelease advance).
  if [[ "${_chan}" == "unstable" ]]; then
    if [[ -n "${_hp}" ]]; then
      if [[ -n "${_hs}" ]]; then
        local _cmp
        _cmp="$(_gs_eu2_semver_compare "${_hs}" "${_hp}")"
        [[ "${_cmp}" == "newer" ]] && { printf '%s\n' "${_hs}"; return 0; }
      fi
      printf '%s\n' "${_hp}"
      return 0
    fi
    [[ -n "${_hs}" ]] && printf '%s\n' "${_hs}"
    return 0
  fi

  # Nightly: highest tag containing "nightly" literally.
  # Falls back to any prerelease if no nightly tag found (consistent with channel:rc behavior).
  # Stable-promotion: if stable has surpassed the nightly/prerelease, return stable instead.
  if [[ "${_chan}" == "nightly" ]]; then
    local _nightlies=()
    while IFS= read -r _v; do
      [[ -z "${_v}" ]] && continue
      [[ "${_v,,}" == *"nightly"* ]] && _nightlies+=("${_v}")
    done <<< "${_all}"
    local _hn=""
    [[ ${#_nightlies[@]} -gt 0 ]] && _hn="$(printf '%s\n' "${_nightlies[@]}" \
      | _gs_eu2_version_sort | tail -1)" || true
    # Fall back to any prerelease if no nightly tag found (consistent with channel:rc behavior)
    [[ -z "${_hn}" && -n "${_hp}" ]] && _hn="${_hp}"
    if [[ -n "${_hn}" ]]; then
      # Stable-promotion: if stable has surpassed nightly/prerelease, return stable
      if [[ -n "${_hs}" ]]; then
        local _cmp; _cmp="$(_gs_eu2_semver_compare "${_hs}" "${_hn}")"
        [[ "${_cmp}" == "newer" ]] && { printf '%s\n' "${_hs}"; return 0; }
      fi
      printf '%s\n' "${_hn}"
    elif [[ -n "${_hs}" ]]; then
      printf '%s\n' "${_hs}"
    fi
    return 0
  fi

  # Specific channel (rc, beta, etc.)
  local _filtered
  _filtered="$(_gs_eu2_filter_versions_by_channel "${_all}" "${_chan}")"
  local _cm=""
  [[ -n "${_filtered}" ]] && _cm="$(printf '%s\n' "${_filtered}" \
    | _gs_eu2_version_sort | tail -1)" || true
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
