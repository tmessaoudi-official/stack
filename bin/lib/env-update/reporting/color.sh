#!/bin/bash
# color.sh — ANSI color gating + helpers for env-update output.
#
# Exports:   _gs_eu2_color_init  _gs_eu2_cnum  and the _GS_EU2_C_* color globals
# Sources:   (none)
# Deps:      bash 4.3+
# Env:       NO_COLOR, TERM, _GS_EU2_COLOR_FORCE, _GS_EU2_CFG[format]
#
# Gate mirrors reporting/tally.sh: color is enabled only when NO_COLOR is unset,
# TERM != dumb, output format is not json, and stdout is a TTY (bypass the TTY
# check with _GS_EU2_COLOR_FORCE=1 for deterministic testing). When disabled,
# every _GS_EU2_C_* global is the empty string, so colored format strings and
# %s-arg tags collapse to byte-identical monochrome output.

# shellcheck disable=SC2034  # _GS_EU2_C_* are consumed by core/drift.sh, core/apply.sh, main.sh
[[ -n "${_GS_EU2_REPORTING_COLOR_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_REPORTING_COLOR_SH_LOADED=1

# Source-time defaults — empty so `set -u` never trips even if _gs_eu2_color_init
# has not run (e.g. a signal function invoked directly by a unit test).
_GS_EU2_C_R=""
_GS_EU2_C_DIM=""
_GS_EU2_C_GREEN=""
_GS_EU2_C_YELLOW=""
_GS_EU2_C_ERR=""
_GS_EU2_C_MAGENTA=""
_GS_EU2_C_CYAN=""
_GS_EU2_C_DIMCYAN=""

# _gs_eu2_color_init — decide whether color is on and populate the _GS_EU2_C_* globals.
# Args:    none
# Reads:   NO_COLOR, TERM, _GS_EU2_COLOR_FORCE, _GS_EU2_CFG[format]
# Sets:    _GS_EU2_C_* globals (real ESC bytes when on, empty when off)
# Returns: 0 always
_gs_eu2_color_init() {
  # Reset to off (empty) first so a second call can toggle back off.
  _GS_EU2_C_R="" _GS_EU2_C_DIM="" _GS_EU2_C_GREEN="" _GS_EU2_C_YELLOW=""
  _GS_EU2_C_ERR="" _GS_EU2_C_MAGENTA="" _GS_EU2_C_CYAN="" _GS_EU2_C_DIMCYAN=""

  # Hard gates (always off) — mirror tally.sh precedence.
  [[ -n "${NO_COLOR:-}" ]] && return 0
  [[ "${TERM:-}" == "dumb" ]] && return 0
  [[ "${_GS_EU2_CFG[format]:-text}" == "json" ]] && return 0

  # TTY gate — bypass with _GS_EU2_COLOR_FORCE=1 for tests.
  if [[ "${_GS_EU2_COLOR_FORCE:-0}" != "1" ]]; then
    [[ ! -t 1 ]] && return 0
  fi

  # Color ON — real ESC bytes (work in printf format strings AND %s args).
  _GS_EU2_C_R=$'\033[0m'
  _GS_EU2_C_DIM=$'\033[2m'
  _GS_EU2_C_GREEN=$'\033[0;32m'
  _GS_EU2_C_YELLOW=$'\033[0;33m'
  _GS_EU2_C_ERR=$'\033[1;31m'
  _GS_EU2_C_MAGENTA=$'\033[0;35m'
  _GS_EU2_C_CYAN=$'\033[0;36m'
  _GS_EU2_C_DIMCYAN=$'\033[2;36m'
  return 0
}

# _gs_eu2_cnum — colorize a summary count: category color when > 0, plain when 0.
# Args:    $1 count (integer)  $2 color (ESC prefix or empty)
# Prints:  "${color}${n}${R}" when n>0 and color set; otherwise the bare number.
# Returns: 0 always
_gs_eu2_cnum() {
  local _n="${1}" _c="${2}"
  if [[ "${_n}" -gt 0 && -n "${_c}" ]]; then
    printf '%s%s%s' "${_c}" "${_n}" "${_GS_EU2_C_R}"
  else
    printf '%s' "${_n}"
  fi
  return 0
}
