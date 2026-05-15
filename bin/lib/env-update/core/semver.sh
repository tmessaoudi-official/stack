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

# Extract first N dot-separated numeric segments from a version string.
# Strips build metadata (+...) and non-numeric suffixes (-LTS, -alpine, etc.)
# so "25.0.1+9-LTS" at depth 1 returns "25", and "8.5.2" at depth 2 returns "8.5".
# Returns empty string if the version cannot be parsed.
# Extract the variant tag suffix from a version string for (watch-major) unconstrained fetch.
# Returns the trailing "-SUFFIX" when the version has a non-numeric dash suffix (e.g. -zulu,
# -alpine3.21, -fpm).  Returns empty when no dash suffix or when only build metadata (+...).
# Examples:
#   "25.0.1-zulu"         → "-zulu"
#   "8.5.2-alpine3.21"   → "-alpine3.21"
#   "25.0.1+9-LTS"       → "" (build metadata, not a tag suffix)
#   "22.15.0"             → ""
_gs_eu2_version_tag_suffix() {
  local _v="${1}"
  # Strip build metadata (everything from +) — build metadata never appears in tag names
  local _no_meta="${_v%%+*}"
  # Extract the leading semver numeric portion: digits, dots, optionally v-prefix
  local _numeric_part
  _numeric_part="$(printf '%s' "${_no_meta}" | grep -oE '^v?[0-9]+(\.[0-9]+)*')"
  if [[ -z "${_numeric_part}" ]]; then
    printf ''
    return
  fi
  # Remainder after numeric part — only return if it starts with -
  local _remainder="${_no_meta#"${_numeric_part}"}"
  if [[ "${_remainder}" == -* ]]; then
    printf '%s' "${_remainder}"
  fi
}

_gs_eu2_version_prefix() {
  local _version="${1}" _depth="${2:-1}"
  # Strip build metadata (everything after +)
  local _clean="${_version%%+*}"
  # Strip leading v-prefix (e.g. v24.14.0 → 24.14.0) so the first segment
  # passes the ^[0-9]+$ check even when the raw tag carries a v.
  _clean="${_clean#v}"
  # Strip pre-release / tag suffix starting with a dash followed by a non-digit
  # e.g. -LTS, -alpine, -rc1 → removed; -20260108 (date) → kept as it IS numeric
  _clean="$(printf '%s' "${_clean}" | sed 's/-[^0-9].*//')"
  # Extract the first _depth dot-separated numeric segments
  local _out="" _seg _remaining="${_clean}" _i=0
  while (( _i < _depth )); do
    _seg="${_remaining%%.*}"
    [[ "${_seg}" =~ ^[0-9]+$ ]] || break
    [[ -n "${_out}" ]] && _out+="."
    _out+="${_seg}"
    (( ++_i )) || true
    if [[ "${_remaining}" == *"."* ]]; then
      _remaining="${_remaining#*.}"
    else
      break
    fi
  done
  # Only output if we got the requested depth
  if (( _i == _depth )); then
    printf '%s' "${_out}"
  fi
}

# Returns delta type between two versions: major | minor | patch | unknown
_gs_eu2_semver_delta() {
  local _a="${1#v}" _b="${2#v}"
  [[ -z "${_a}" || -z "${_b}" ]] && { echo "unknown"; return; }

  # Strip path-like prefix (e.g. "tags/2.4.66" → "2.4.66", "refs/heads/v3" stays).
  # Matches <word>/<digit-led-version> — git refs style like "tags/", "branches/".
  [[ "${_a}" =~ ^[^0-9/][^/]*/([0-9].*)$ ]] && _a="${BASH_REMATCH[1]}"
  [[ "${_b}" =~ ^[^0-9/][^/]*/([0-9].*)$ ]] && _b="${BASH_REMATCH[1]}"

  # Codename-date style (e.g. ubuntu "resolute-20260108" → "resolute-20260413"):
  # both strings start with an alpha char → extract prefix up to first hyphen.
  # Same prefix (same codename) → patch.  Different prefix → major.
  if [[ "${_a}" =~ ^[^0-9] && "${_b}" =~ ^[^0-9] ]]; then
    local _ap="${_a%%-*}" _bp="${_b%%-*}"
    [[ "${_ap}" == "${_bp}" ]] && { echo "patch"; return; }
    echo "major"; return
  fi

  # Date-SHA style used by SHA-tracking annotations: YYYYMMDD-<sha8>  or full 40-char SHA.
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

  # Date-version guard: if both major components are 6+ digit pure numerics
  # (YYYYMMDD, YYYYMM, or similar monotonic date stamps), treat any forward
  # increment as "patch" — these are not semantic major versions.
  # By the time we reach semver_delta, decide.sh has already verified _b >= _a
  # via sort -V, so if both components are date-stamps we know it is a forward
  # increment and "patch" is correct.
  if [[ "${_am}" =~ ^[0-9]{6,}$ && "${_bm}" =~ ^[0-9]{6,}$ ]]; then
    echo "patch"; return
  fi

  [[ "${_am}" != "${_bm}" ]] && { echo "major"; return; }
  local _ar="${_a#*.}" _br="${_b#*.}"
  [[ "${_ar%%.*}" != "${_br%%.*}" ]] && { echo "minor"; return; }
  echo "patch"
}
