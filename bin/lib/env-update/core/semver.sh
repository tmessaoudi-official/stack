#!/bin/bash
# semver.sh — version comparison + pre-release detection helpers

[[ -n "${_GS_EU2_SEMVER_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_SEMVER_SH_LOADED=1

# shellcheck source=./../config/prerelease_markers.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/prerelease_markers.sh"

# Returns 0 if version looks like a pre-release
_gs_eu2_is_prerelease() {
  local _v="${1,,}"
  [[ "${_v}" =~ (${_GS_EU2_PRERELEASE_REGEX}) ]]
}

# Returns 0 if version is unversioned (nightly/latest/edge/next/master)
_gs_eu2_is_unversioned() {
  local _v="${1,,}"
  [[ "${_v}" =~ ^(nightly|latest|edge|master|next|head|main)$ ]]
}

# Compare two version strings. Echoes: older | newer | equal
# Handles v-prefix and SemVer pre-release ordering (1.0.0-rc1 < 1.0.0)
_gs_eu2_semver_compare() {
  local _a="${1#v}" _b="${2#v}"
  [[ "${_a}" == "${_b}" ]] && { echo "equal"; return 0; }

  local _a_base="${_a}" _b_base="${_b}"
  local _a_pre=false _b_pre=false
  if [[ "${_a}" =~ ^([0-9]+(\.[0-9]+)*)-([a-zA-Z]) ]]; then
    _a_base="${BASH_REMATCH[1]}"; _a_pre=true
  fi
  if [[ "${_b}" =~ ^([0-9]+(\.[0-9]+)*)-([a-zA-Z]) ]]; then
    _b_base="${BASH_REMATCH[1]}"; _b_pre=true
  fi
  if [[ "${_a_base}" == "${_b_base}" ]]; then
    if [[ "${_a_pre}" == "true" && "${_b_pre}" == "false" ]]; then
      echo "older"; return 0
    elif [[ "${_a_pre}" == "false" && "${_b_pre}" == "true" ]]; then
      echo "newer"; return 0
    fi
  fi

  local _first
  _first="$(printf '%s\n%s\n' "${_a}" "${_b}" | sort -V | head -1)"
  if [[ "${_first}" == "${_a}" ]]; then echo "older"; else echo "newer"; fi
}

# Returns delta type between two versions: major | minor | patch | unknown
_gs_eu2_semver_delta() {
  local _a="${1#v}" _b="${2#v}"
  [[ -z "${_a}" || -z "${_b}" ]] && { echo "unknown"; return; }

  # Codename-date style (e.g. ubuntu "resolute-20260108" → "resolute-20260413"):
  # both strings start with an alpha char → extract prefix up to first hyphen.
  # Same prefix (same codename) → patch.  Different prefix → major.
  if [[ "${_a}" =~ ^[^0-9] && "${_b}" =~ ^[^0-9] ]]; then
    local _ap="${_a%%-*}" _bp="${_b%%-*}"
    [[ "${_ap}" == "${_bp}" ]] && { echo "patch"; return; }
    echo "major"; return
  fi

  # Date-SHA style used by pecl-git: YYYYMMDD-<sha8>  or full 40-char SHA.
  # Either operand matching means we are in commit-tracking mode — treat all
  # changes as patch so decide.sh emits AUTO instead of HOLD.
  local _date_sha_re='^[0-9]{8}-[0-9a-f]{8}$'
  local _sha40_re='^[0-9a-f]{40}$'
  if [[ "${_a}" =~ ${_date_sha_re} || "${_b}" =~ ${_date_sha_re} \
     || "${_a}" =~ ${_sha40_re}    || "${_b}" =~ ${_sha40_re} ]]; then
    echo "patch"; return
  fi

  # Normalize underscore separators (e.g. Ruby's 3_4_9 style) to dots
  _a="${_a//_/.}" _b="${_b//_/.}"

  local _am="${_a%%.*}" _bm="${_b%%.*}"
  [[ "${_am}" != "${_bm}" ]] && { echo "major"; return; }
  local _ar="${_a#*.}" _br="${_b#*.}"
  [[ "${_ar%%.*}" != "${_br%%.*}" ]] && { echo "minor"; return; }
  echo "patch"
}
