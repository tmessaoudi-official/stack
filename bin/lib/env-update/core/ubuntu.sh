#!/bin/bash
# ubuntu.sh — Ubuntu LTS codename helpers for the url-probe mechanism.
#
# Exports:   _gs_eu2_ubuntu_codename_list
#            _gs_eu2_ubuntu_codename_to_version
#            _gs_eu2_ubuntu_version_to_codename
#            _gs_eu2_ubuntu_codename_index
# Sources:   none
# Deps:      none (pure bash)
# Env:       _GS_EU2_UBUNTU_CODENAMES (readonly array)
#            _GS_EU2_UBUNTU_VERSIONS  (readonly parallel array)
#
# Provides ordered codename list and bidirectional codename/version lookup.
# Ported from v1's bin/lib/env-update/config/codename_map.sh but adapted
# to v2 naming conventions and without associative-array globals
# (associative arrays in subshells require re-declaration; use parallel arrays).

[[ -n "${_GS_EU2_UBUNTU_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_UBUNTU_SH_LOADED=1

# Ordered Ubuntu codename list (oldest → newest).
# Source of truth: https://wiki.ubuntu.com/Releases
# Last updated: 2026-04.
readonly _GS_EU2_UBUNTU_CODENAMES=(
  xenial
  bionic
  focal
  jammy
  kinetic
  lunar
  mantic
  noble
  oracular
  plucky
  questing
  resolute
)

# Corresponding version numbers (parallel array, same index as _GS_EU2_UBUNTU_CODENAMES).
readonly _GS_EU2_UBUNTU_VERSIONS=(
  "16.04"
  "18.04"
  "20.04"
  "22.04"
  "22.10"
  "23.04"
  "23.10"
  "24.04"
  "24.10"
  "25.04"
  "25.10"
  "26.04"
)

# _gs_eu2_ubuntu_codename_list — output all known codenames, oldest → newest.
#
# Args:    none
# Prints:  one codename per line
# Returns: 0 always
_gs_eu2_ubuntu_codename_list() {
  local _cn
  for _cn in "${_GS_EU2_UBUNTU_CODENAMES[@]}"; do
    printf '%s\n' "${_cn}"
  done
}

# _gs_eu2_ubuntu_codename_to_version — map a codename to its version number.
#
# Args:    $1 codename — Ubuntu codename (e.g. "noble", "jammy")
# Prints:  version string (e.g. "24.04"); empty for unknown codenames
# Returns: 0 always
_gs_eu2_ubuntu_codename_to_version() {
  local _cn="${1}"
  local _i
  for (( _i = 0; _i < ${#_GS_EU2_UBUNTU_CODENAMES[@]}; _i++ )); do
    if [[ "${_GS_EU2_UBUNTU_CODENAMES[${_i}]}" == "${_cn}" ]]; then
      printf '%s' "${_GS_EU2_UBUNTU_VERSIONS[${_i}]}"
      return 0
    fi
  done
}

# _gs_eu2_ubuntu_version_to_codename — map a version number to its codename.
#
# Args:    $1 version — Ubuntu version number (e.g. "24.04", "22.04")
# Prints:  codename (e.g. "noble"); empty for unknown versions
# Returns: 0 always
_gs_eu2_ubuntu_version_to_codename() {
  local _ver="${1}"
  local _i
  for (( _i = 0; _i < ${#_GS_EU2_UBUNTU_VERSIONS[@]}; _i++ )); do
    if [[ "${_GS_EU2_UBUNTU_VERSIONS[${_i}]}" == "${_ver}" ]]; then
      printf '%s' "${_GS_EU2_UBUNTU_CODENAMES[${_i}]}"
      return 0
    fi
  done
}

# _gs_eu2_ubuntu_codename_index — return the 0-based position of a codename.
#
# Args:    $1 codename — Ubuntu codename
# Prints:  0-based index in _GS_EU2_UBUNTU_CODENAMES; "-1" if not found
# Returns: 0 always
# Note:    used by url.sh to advance to the next/previous codename in url-probe
_gs_eu2_ubuntu_codename_index() {
  local _cn="${1}"
  local _i
  for (( _i = 0; _i < ${#_GS_EU2_UBUNTU_CODENAMES[@]}; _i++ )); do
    if [[ "${_GS_EU2_UBUNTU_CODENAMES[${_i}]}" == "${_cn}" ]]; then
      printf '%s' "${_i}"
      return 0
    fi
  done
  printf '%s' "-1"
}
