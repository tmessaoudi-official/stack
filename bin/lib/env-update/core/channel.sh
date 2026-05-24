#!/bin/bash
# channel.sh — stable/rc/beta/unstable channel selection and tag filtering.
#
# Exports:   _gs_eu2_version_matches_channel  _gs_eu2_filter_versions_by_channel
#            _gs_eu2_channel_select_best
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

# _gs_eu2_channel_select_best — pick the best version from a list given a channel.
#
# Args:    $1 versions — newline-separated list of version strings
#          $2 channel  — channel qualifier (empty/"stable" → best stable only)
# Reads:   nothing
# Prints:  selected version string; nothing if list is empty or no match for channel
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

  # sort -V misorders mixed v-prefix/no-prefix inputs (v0.3.0 sorts after 1.0.0 because
  # 'v' > '1' in ASCII, while semantically 0.3.0 < 1.0.0).  Strip the leading 'v' before
  # sorting (key col 1), then recover the original tag string from col 2.
  local _hs="" _hp=""
  [[ ${#_stables[@]} -gt 0 ]] && _hs="$(printf '%s\n' "${_stables[@]}" \
    | awk '{n=$0; sub(/^v/,"",n); printf "%s\t%s\n",n,$0}' \
    | sort -V -k1,1 | tail -1 | cut -f2-)" || true
  [[ ${#_pres[@]}    -gt 0 ]] && _hp="$(printf '%s\n' "${_pres[@]}" \
    | awk '{n=$0; sub(/^v/,"",n); printf "%s\t%s\n",n,$0}' \
    | sort -V -k1,1 | tail -1 | cut -f2-)" || true

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
      printf '%s\n' "$(printf '%s\n' "${_nightlies[@]}" \
        | awk '{n=$0; sub(/^v/,"",n); printf "%s\t%s\n",n,$0}' \
        | sort -V -k1,1 | tail -1 | cut -f2-)"
    return 0
  fi

  # Specific channel (rc, beta, etc.)
  local _filtered
  _filtered="$(_gs_eu2_filter_versions_by_channel "${_all}" "${_chan}")"
  local _cm=""
  [[ -n "${_filtered}" ]] && _cm="$(printf '%s\n' "${_filtered}" | grep -v '^$' \
    | awk '{n=$0; sub(/^v/,"",n); printf "%s\t%s\n",n,$0}' \
    | sort -V -k1,1 | tail -1 | cut -f2-)" || true
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
