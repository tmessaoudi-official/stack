#!/bin/bash
# decide.sh — classify a proposed version update into AUTO/HOLD/MANUAL/SKIP/ERROR

[[ -n "${_GS_EU2_DECIDE_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_DECIDE_SH_LOADED=1

# shellcheck source=./semver.sh
source "$(dirname "${BASH_SOURCE[0]}")/semver.sh"

# Classify a version update.
# Args:
#   $1 current      — current version string
#   $2 proposed     — proposed version string
#   $3 override     — "true" → always MANUAL
#   $4 manual       — "true" → always MANUAL
#   $5 major_hint   — if set, proposed must stay within this major
# Echoes: AUTO | HOLD | MANUAL | SKIP
_gs_eu2_classify_decision() {
  local _cur="${1}" _prop="${2}" _override="${3:-}" _manual="${4:-}" _major_hint="${5:-}"

  # No proposed version → skip
  [[ -z "${_prop}" ]] && { echo "SKIP"; return 0; }

  # Unversioned current (nightly/latest/edge/…): version comparison is meaningless.
  # The proposed value is informational only; a pin change requires deliberate action.
  if _gs_eu2_is_unversioned "${_cur}"; then echo "SKIP"; return 0; fi

  # Same version → nothing to do; SKIP even for manual/override vars.
  # manual/override means "don't auto-apply changes", not "always surface as MANUAL".
  if [[ "${_cur}" == "${_prop}" ]]; then
    echo "SKIP"; return 0
  fi

  # Override or manual flags → MANUAL (only reached when there IS a version change)
  if [[ "${_override}" == "true" || "${_manual}" == "true" ]]; then
    echo "MANUAL"; return 0
  fi

  # Prerelease guard: don't auto-propose a prerelease when current is stable.
  # Handles both dash-separated (6.3.0-rc1) and no-dash (6.3.0RC1) formats.
  if _gs_eu2_is_prerelease "${_prop}" && ! _gs_eu2_is_prerelease "${_cur}"; then
    echo "SKIP"; return 0
  fi

  # Downgrade protection: if proposed sorts before current via sort -V, skip
  # Use sort -V directly (not semver_compare) to avoid misclassifying platform
  # suffixes like -alpine3.23 as pre-release markers.
  local _cv="${_cur#v}" _pv="${_prop#v}"
  if [[ "${_cv}" != "${_pv}" ]]; then
    local _oldest
    _oldest="$(printf '%s\n%s\n' "${_cv}" "${_pv}" | sort -V | head -1)"
    if [[ "${_oldest}" == "${_pv}" ]]; then
      echo "SKIP"; return 0
    fi
  fi

  # Determine semver delta
  local _delta
  _delta="$(_gs_eu2_semver_delta "${_cur}" "${_prop}")"

  # Major jump without major_hint pin → HOLD for review
  if [[ "${_delta}" == "major" && -z "${_major_hint}" ]]; then
    echo "HOLD"; return 0
  fi

  # C3: Major jump with pin but proposed escapes the pin → HOLD
  # Use ([.^_-]|$) anchor to prevent "18" matching "180.x"; _ for Ruby-style tags.
  if [[ -n "${_major_hint}" && ! "${_prop}" =~ ^${_major_hint}([.^_-]|$) ]]; then
    echo "HOLD"; return 0
  fi

  echo "AUTO"
}
