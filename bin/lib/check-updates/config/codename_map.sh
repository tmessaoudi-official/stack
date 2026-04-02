#!/bin/bash
# Ubuntu release codename lookup table.
# Ordered oldest → newest (as of 2026).
# Key = codename, Value = version number (YY.MM)
# shellcheck disable=SC2034  # Variables are used by sourcing scripts

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_CU_CODENAME_MAP_SH_LOADED:-}" ]] && return 0
readonly _GS_CU_CODENAME_MAP_SH_LOADED=1

# Ordered list of known Ubuntu codenames (oldest first)
readonly _GS_CU_CODENAME_UBUNTU_ORDERED=(
  "focal"
  "jammy"
  "kinetic"
  "lunar"
  "mantic"
  "noble"
  "oracular"
  "plucky"
  "questing"
  "resolute"
)

# Associative map: codename → version
declare -A _GS_CU_CODENAME_TO_VERSION
_GS_CU_CODENAME_TO_VERSION=(
  [focal]="20.04"
  [jammy]="22.04"
  [kinetic]="22.10"
  [lunar]="23.04"
  [mantic]="23.10"
  [noble]="24.04"
  [oracular]="24.10"
  [plucky]="25.04"
  [questing]="25.10"
  [resolute]="26.04"
)

# Returns the numeric index of a codename in _GS_CU_CODENAME_UBUNTU_ORDERED
# Usage: _gs_cu_codename_index "noble" → echoes index or -1 if not found
_gs_cu_codename_index() {
  local name="${1}"
  local i=0
  for cn in "${_GS_CU_CODENAME_UBUNTU_ORDERED[@]}"; do
    if [[ "${cn}" == "${name}" ]]; then
      echo "${i}"
      return 0
    fi
    (( i++ )) || true
  done
  echo "-1"
}

# Returns 1 if codename_a is older than codename_b, 0 otherwise
# Usage: _gs_cu_codename_is_older "noble" "resolute"
_gs_cu_codename_is_older() {
  local a="${1}"
  local b="${2}"
  local idx_a idx_b
  idx_a="$(_gs_cu_codename_index "${a}")"
  idx_b="$(_gs_cu_codename_index "${b}")"
  if [[ "${idx_a}" -eq -1 || "${idx_b}" -eq -1 ]]; then
    return 1
  fi
  [[ "${idx_a}" -lt "${idx_b}" ]]
}

# Extract codename from a version string (first alphabetical word found)
# e.g. "8.2.6-rc0-noble" → "noble", "resolute-20260108" → "resolute"
_gs_cu_extract_codename_from_version() {
  local version="${1}"
  local cn
  for cn in "${_GS_CU_CODENAME_UBUNTU_ORDERED[@]}"; do
    if [[ "${version}" == *"${cn}"* ]]; then
      echo "${cn}"
      return 0
    fi
  done
  echo ""
}
