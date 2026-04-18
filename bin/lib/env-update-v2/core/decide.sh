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

  # Override or manual flags → MANUAL always
  if [[ "${_override}" == "true" || "${_manual}" == "true" ]]; then
    echo "MANUAL"; return 0
  fi

  # Same version → up to date, SKIP
  if [[ "${_cur}" == "${_prop}" ]]; then
    echo "SKIP"; return 0
  fi

  # Determine semver delta
  local _delta
  _delta="$(_gs_eu2_semver_delta "${_cur}" "${_prop}")"

  # Major jump without major_hint pin → HOLD for review
  if [[ "${_delta}" == "major" && -z "${_major_hint}" ]]; then
    echo "HOLD"; return 0
  fi

  # Major jump with pin but proposed escapes the pin → HOLD
  if [[ -n "${_major_hint}" && ! "${_prop}" =~ ^${_major_hint}[.^-] ]]; then
    echo "HOLD"; return 0
  fi

  echo "AUTO"
}
