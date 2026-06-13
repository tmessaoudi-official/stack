#!/bin/bash
# tally.sh — live running tally display subsystem for env-update check loop.
#
# Exports:   _gs_eu2_tally_init  _gs_eu2_tally_draw
#            _gs_eu2_tally_erase  _gs_eu2_tally_cleanup
# Sources:   config/defaults.sh
# Deps:      bash 4.3+, tput (for terminal width detection)
# Env:       _GS_EU2_TALLY_ACTIVE (1 when tally enabled for this run, 0 disabled)
#            _GS_EU2_TALLY_PREV_LINES (how many lines the last draw emitted)
#            _GS_EU2_TALLY_IDX, _GS_EU2_TALLY_COUNT, _GS_EU2_TALLY_VARNAME (per-draw state)
#            _GS_EU2_TALLY_N_* counters (per-draw decision tallies)
#            _GS_EU2_TALLY_FORCE=1 (test hook: bypass TTY gate for tally)
#
# Gate: tally != off  AND  stderr is TTY  AND  TERM != dumb  AND  NO_COLOR unset
#   AND ( tally == full  OR  cols >= 130 )

[[ -n "${_GS_EU2_REPORTING_TALLY_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_REPORTING_TALLY_SH_LOADED=1

# ── Tally helpers ────────────────────────────────────────────────────────────
# Live running tally displayed on stderr during the check loop.
# Gate: tally != off  AND  stderr is TTY  AND  TERM != dumb  AND  NO_COLOR unset
#   AND ( tally == full  OR  cols >= 130 )
# _GS_EU2_TALLY_FORCE=1 bypasses the TTY check (test hook).
#
# Module-level state (set by _gs_eu2_tally_init and the check loop):
_GS_EU2_TALLY_ACTIVE=0      # 1 when tally is enabled for this run
_GS_EU2_TALLY_PREV_LINES=0  # how many lines the last draw emitted
# Per-draw state written by the check loop before each _gs_eu2_tally_draw call:
_GS_EU2_TALLY_IDX=0         # 0-based current record index
_GS_EU2_TALLY_COUNT=0       # total record count
_GS_EU2_TALLY_VARNAME=""    # env_var name being fetched
_GS_EU2_TALLY_N_AUTO=0
_GS_EU2_TALLY_N_HOLD=0
_GS_EU2_TALLY_N_SKIP=0
_GS_EU2_TALLY_N_ERROR=0
_GS_EU2_TALLY_N_MANUAL=0
_GS_EU2_TALLY_N_SHA=0
_GS_EU2_TALLY_N_LOCK=0
_GS_EU2_TALLY_N_FROZEN=0
_GS_EU2_TALLY_N_FALLBACK=0
_GS_EU2_TALLY_N_WATCH=0
_GS_EU2_TALLY_N_DRIFT=0
_GS_EU2_TALLY_N_DRIFT_FIXABLE=0
_GS_EU2_TALLY_N_DOWNGRADE=0
_GS_EU2_TALLY_N_DOWNGRADE_FORCE=0
_GS_EU2_TALLY_N_HIDDEN=0
_GS_EU2_TALLY_N_SHA_ANNO=0
_GS_EU2_TALLY_N_REPLACE_DRIFT=0
_GS_EU2_TALLY_N_REPLACE_CASCADE=0
_GS_EU2_TALLY_N_RESOLVED=0

# _gs_eu2_tally_init — evaluate all display gates and set _GS_EU2_TALLY_ACTIVE.
#
# Args:    none
# Reads:   _GS_EU2_CFG[tally], NO_COLOR, TERM, COLUMNS, _GS_EU2_TALLY_FORCE
# Sets:    _GS_EU2_TALLY_ACTIVE (1 = tally enabled for this run, 0 = disabled)
#          _GS_EU2_TALLY_PREV_LINES (reset to 0)
# Prints:  nothing
# Returns: 0 always
# Side fx: none
_gs_eu2_tally_init() {
  _GS_EU2_TALLY_ACTIVE=0
  _GS_EU2_TALLY_PREV_LINES=0
  local _t_mode="${_GS_EU2_CFG[tally]:-auto}"
  [[ "${_t_mode}" == "off" ]] && return 0
  # NO_COLOR gate — machine-level opt-out; even --tally=full must respect it
  [[ -n "${NO_COLOR:-}" ]] && return 0
  # TERM gate
  [[ "${TERM:-}" == "dumb" ]] && return 0
  # TTY gate — bypass with _GS_EU2_TALLY_FORCE=1
  if [[ "${_GS_EU2_TALLY_FORCE:-0}" != "1" ]]; then
    [[ ! -t 2 ]] && return 0
  fi
  # Width gate: full bypasses width check; auto requires cols >= 130
  if [[ "${_t_mode}" == "auto" ]]; then
    local _cols
    _cols="${COLUMNS:-0}"
    if [[ "${_cols}" -lt 130 ]]; then
      _cols="$(tput cols 2>/dev/null || printf '0')"
    fi
    [[ "${_cols}" -lt 130 ]] && return 0
  fi
  _GS_EU2_TALLY_ACTIVE=1
}

# _gs_eu2_tally_draw — erase the previous tally block and redraw with current state.
#
# Args:    none (all state is read from _GS_EU2_TALLY_* module-level vars)
# Reads:   _GS_EU2_TALLY_ACTIVE, _GS_EU2_TALLY_PREV_LINES, _GS_EU2_TALLY_IDX,
#          _GS_EU2_TALLY_COUNT, _GS_EU2_TALLY_VARNAME, all _GS_EU2_TALLY_N_* counters
# Sets:    _GS_EU2_TALLY_PREV_LINES (number of lines just drawn)
# Prints:  multi-line tally block to stderr using ANSI cursor-movement escapes
# Returns: 0 always (early exit when TALLY_ACTIVE != 1)
# Side fx: moves terminal cursor up and erases lines via ANSI escape sequences
#
# Caller protocol: update all _GS_EU2_TALLY_* state vars before each call;
# the erase-and-redraw cycle uses _GS_EU2_TALLY_PREV_LINES to know how many
# lines to move the cursor up before overwriting.
_gs_eu2_tally_draw() {
  [[ "${_GS_EU2_TALLY_ACTIVE}" != "1" ]] && return 0

  # Erase previous tally block: move cursor up (_prev_lines - 1) lines then
  # overwrite each line with \r\033[K (erase to end of line).
  if [[ "${_GS_EU2_TALLY_PREV_LINES}" -gt 0 ]]; then
    local _up=$(( _GS_EU2_TALLY_PREV_LINES - 1 ))
    if [[ "${_up}" -gt 0 ]]; then
      printf '\033[%dA' "${_up}" >&2
    fi
    local _el
    for (( _el = 0; _el < _GS_EU2_TALLY_PREV_LINES; _el++ )); do
      if [[ "${_el}" -gt 0 ]]; then
        printf '\033[1B' >&2  # move down one line
      fi
      printf '\r\033[K' >&2   # erase line
    done
    # Move cursor back to top of the block
    if [[ "${_GS_EU2_TALLY_PREV_LINES}" -gt 1 ]]; then
      printf '\033[%dA' "$(( _GS_EU2_TALLY_PREV_LINES - 1 ))" >&2
    fi
  fi

  local _lines=0
  local _fetching_num=$(( _GS_EU2_TALLY_IDX + 1 ))

  # Line A: progress position with variable name
  printf '\r\033[K  [%d/%d] fetching %-55s' "${_fetching_num}" "${_GS_EU2_TALLY_COUNT}" "${_GS_EU2_TALLY_VARNAME:0:55}" >&2
  (( _lines++ )) || true

  # Line B1: decision tallies (Summary: format) — always present
  local _checked_suf="${_fetching_num} checked"
  (( _GS_EU2_TALLY_N_HIDDEN > 0 )) && _checked_suf="${_fetching_num} checked, ${_GS_EU2_TALLY_N_HIDDEN} hidden"
  printf '\n\r\033[K  Summary: %d AUTO, %d SHA, %d HOLD, %d MANUAL, %d LOCK, %d SKIP, %d FROZEN, %d FALLBACK, %d ERROR  (%s)' \
    "${_GS_EU2_TALLY_N_AUTO}" "${_GS_EU2_TALLY_N_SHA}" "${_GS_EU2_TALLY_N_HOLD}" \
    "${_GS_EU2_TALLY_N_MANUAL}" "${_GS_EU2_TALLY_N_LOCK}" "${_GS_EU2_TALLY_N_SKIP}" \
    "${_GS_EU2_TALLY_N_FROZEN}" "${_GS_EU2_TALLY_N_FALLBACK}" "${_GS_EU2_TALLY_N_ERROR}" \
    "${_checked_suf}" >&2
  (( _lines++ )) || true

  # Line B2 (signals): WATCH, DRIFT, DOWNGRADE, REPLACE-DRIFT, +sha, +replace
  if (( _GS_EU2_TALLY_N_WATCH > 0 || _GS_EU2_TALLY_N_DRIFT > 0 || \
        _GS_EU2_TALLY_N_DOWNGRADE > 0 || _GS_EU2_TALLY_N_DOWNGRADE_FORCE > 0 || \
        _GS_EU2_TALLY_N_SHA_ANNO > 0 || _GS_EU2_TALLY_N_REPLACE_DRIFT > 0 || \
        _GS_EU2_TALLY_N_REPLACE_CASCADE > 0 )); then
    printf '\n\r\033[K  ↳ %d WATCH · %d DRIFT (%d fixable) · %d DOWNGRADE · %d FORCE-DOWNGRADE · %d REPLACE-DRIFT · %d +sha · %d +replace' \
      "${_GS_EU2_TALLY_N_WATCH}" "${_GS_EU2_TALLY_N_DRIFT}" "${_GS_EU2_TALLY_N_DRIFT_FIXABLE}" \
      "${_GS_EU2_TALLY_N_DOWNGRADE}" "${_GS_EU2_TALLY_N_DOWNGRADE_FORCE}" \
      "${_GS_EU2_TALLY_N_REPLACE_DRIFT}" "${_GS_EU2_TALLY_N_SHA_ANNO}" \
      "${_GS_EU2_TALLY_N_REPLACE_CASCADE}" >&2
    (( _lines++ )) || true
  fi

  # Decision B1 (Option B): last line printed WITHOUT trailing \n — cursor stays on it
  _GS_EU2_TALLY_PREV_LINES="${_lines}"
}

# _gs_eu2_tally_erase — wipe the tally block entirely from the terminal.
#
# Args:    none
# Reads:   _GS_EU2_TALLY_ACTIVE, _GS_EU2_TALLY_PREV_LINES
# Sets:    _GS_EU2_TALLY_PREV_LINES (reset to 0)
# Prints:  ANSI erase sequences to stderr; leaves cursor at column 0 on the
#          first line of where the tally was
# Returns: 0 always
# Side fx: modifies terminal cursor position; must be called before any output
#          that should not appear below the tally (e.g. final summary)
_gs_eu2_tally_erase() {
  [[ "${_GS_EU2_TALLY_ACTIVE}" != "1" ]] && return 0
  [[ "${_GS_EU2_TALLY_PREV_LINES}" -eq 0 ]] && return 0
  local _up=$(( _GS_EU2_TALLY_PREV_LINES - 1 ))
  if [[ "${_up}" -gt 0 ]]; then
    printf '\033[%dA' "${_up}" >&2
  fi
  local _el
  for (( _el = 0; _el < _GS_EU2_TALLY_PREV_LINES; _el++ )); do
    if [[ "${_el}" -gt 0 ]]; then
      printf '\033[1B' >&2
    fi
    printf '\r\033[K' >&2
  done
  if [[ "${_GS_EU2_TALLY_PREV_LINES}" -gt 1 ]]; then
    printf '\033[%dA' "$(( _GS_EU2_TALLY_PREV_LINES - 1 ))" >&2
  fi
  printf '\r' >&2
  _GS_EU2_TALLY_PREV_LINES=0
}

# _gs_eu2_tally_cleanup — INT/ERR trap handler: erase tally then reset trap.
#
# Args:    none
# Reads:   _GS_EU2_TALLY_ACTIVE, _GS_EU2_TALLY_PREV_LINES (via _gs_eu2_tally_erase)
# Sets:    trap state (resets INT and ERR to default)
# Prints:  ANSI erase sequences to stderr (via _gs_eu2_tally_erase)
# Returns: 0 always
# Side fx: clears the INT and ERR traps so the outer ERR trap in bin/env-update.sh
#          can fire normally on subsequent errors after the check loop exits
_gs_eu2_tally_cleanup() {
  _gs_eu2_tally_erase
  trap - INT ERR
}
