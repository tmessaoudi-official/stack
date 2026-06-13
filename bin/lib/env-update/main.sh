#!/bin/bash
# main.sh — top-level orchestrator for env-update: wires all library modules,
#           defines the tally display subsystem, the check loop, and _gs_eu2_main.
#
# Exports:   _gs_eu2_main  _gs_eu2_dispatch_fetcher
#            _gs_eu2_tally_init  _gs_eu2_tally_draw  _gs_eu2_tally_erase
#            _gs_eu2_tally_cleanup  _gs_eu2_run_check
#            _gs_eu2_check_prescan_width  _gs_eu2_classify_record
#            _gs_eu2_compute_reason_label  _gs_eu2_compute_change_string
#            _gs_eu2_should_hide_record  _gs_eu2_print_check_summary
# Sources:   all sub-libraries under config/, core/, fetchers/, http/, reporting/
# Deps:      bash 4.3+, tput (for terminal width detection)
# Env:       _GS_EU2_CFG (associative array), _GS_EU2_TALLY_* (module-level state),
#            _GS_EU2_TALLY_FORCE=1 (test hook: bypass TTY gate for tally)
#            _GS_EU2_APPLY_GATE_FORCE_TTY=true (test hook: treat stdin as TTY in confirm_apply)
#            _GS_EU2_ENV_SCAN_PATH (test hook: override env-scan.sh path for --scan)
#            _GS_EU2_MAX_VAR_LEN (set by _gs_eu2_check_prescan_width, read by run_check)
set -eEuo pipefail

[[ -n "${_GS_EU2_MAIN_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_MAIN_SH_LOADED=1

# shellcheck source=./config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/config/defaults.sh"
# shellcheck source=./core/args.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/args.sh"
# shellcheck source=./core/records.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/records.sh"
# shellcheck source=./core/parse.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/parse.sh"
# shellcheck source=./core/cache.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/cache.sh"
# shellcheck source=./core/decide.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/decide.sh"
# shellcheck source=./fetchers/github.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/github.sh"
# shellcheck source=./fetchers/codeberg.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/codeberg.sh"
# shellcheck source=./fetchers/dockerhub.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/dockerhub.sh"
# shellcheck source=./fetchers/quay.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/quay.sh"
# shellcheck source=./fetchers/npm.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/npm.sh"
# shellcheck source=./fetchers/pypi.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/pypi.sh"
# shellcheck source=./fetchers/rubygems.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/rubygems.sh"
# shellcheck source=./fetchers/sdkman.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/sdkman.sh"
# shellcheck source=./fetchers/sdkmanager.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/sdkmanager.sh"
# shellcheck source=./fetchers/pecl.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/pecl.sh"
# shellcheck source=./fetchers/url.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/url.sh"
# shellcheck source=./fetchers/ghcr.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/ghcr.sh"
# shellcheck source=./reporting/help.sh
source "$(dirname "${BASH_SOURCE[0]}")/reporting/help.sh"
# shellcheck source=./reporting/reference.sh
source "$(dirname "${BASH_SOURCE[0]}")/reporting/reference.sh"
# shellcheck source=./reporting/dump.sh
source "$(dirname "${BASH_SOURCE[0]}")/reporting/dump.sh"
# shellcheck source=./reporting/summary.sh
source "$(dirname "${BASH_SOURCE[0]}")/reporting/summary.sh"
# shellcheck source=./reporting/profile.sh
source "$(dirname "${BASH_SOURCE[0]}")/reporting/profile.sh"
# shellcheck source=./core/apply.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/apply.sh"
# shellcheck source=./core/parallel.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/parallel.sh"
# shellcheck source=./core/passes.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/passes.sh"

# _gs_eu2_dispatch_fetcher — route a record to its type-specific fetcher function.
#
# Args:    $1 record_index — 0-based index into the parallel record arrays
# Reads:   record field "type" (set by parse.sh from @todo annotation)
# Sets:    record fields "decision", "proposed_version", "error_message" (via fetcher)
# Prints:  nothing
# Returns: 0 always (unknown types set decision=SKIP rather than returning non-zero)
# Side fx: may write to cache directory (TTL-based HTTP response caching)
#
# Note: this DRY helper (I2) replaces three identical 12-fetcher case blocks
# that previously appeared separately in run_check, unstable-info second-pass,
# and stable-info second-pass.
# Note: dispatch is dynamic — calls _gs_eu2_fetch_<type> when the function exists.
#       Adding a new fetcher requires only: (1) new fetcher file, (2) one source line.
#       No case label needed. Unknown types fall through to decision=SKIP.
_gs_eu2_dispatch_fetcher() {
  local _df_i="${1}"
  local _df_type
  _df_type="$(_gs_eu2_record_get "${_df_i}" type)"
  local _df_fn="_gs_eu2_fetch_${_df_type}"
  if declare -F "${_df_fn}" >/dev/null 2>&1; then
    "${_df_fn}" "${_df_i}"
  else
    _gs_eu2_record_set "${_df_i}" decision      "SKIP"
    _gs_eu2_record_set "${_df_i}" error_message "unknown fetcher type '${_df_type}' — check annotation syntax"
  fi
}

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

# _gs_eu2_check_prescan_width — pre-scan all env_var names to compute the widest name.
#
# Args:    $1 count — total number of records
# Reads:   _GS_EU2_REC_<N>_env_var flat vars for N in [0, count)
# Sets:    _GS_EU2_MAX_VAR_LEN (module-level) to the widest env_var length (min 40)
# Prints:  nothing
# Returns: 0 always
# Side fx: none
#
# Used by: _gs_eu2_run_check to align the → arrow in output columns.
_GS_EU2_MAX_VAR_LEN=40

_gs_eu2_check_prescan_width() {
  local _pw_count="${1}"
  local _pw_max=40
  local _pw_vl _pw_j _pw_vname _pw_tmpval
  for (( _pw_j = 0; _pw_j < _pw_count; _pw_j++ )); do
    _pw_vname="_GS_EU2_REC_${_pw_j}_env_var"
    _pw_tmpval="${!_pw_vname:-}"
    _pw_vl="${#_pw_tmpval}"
    (( _pw_vl > _pw_max )) && _pw_max="${_pw_vl}"
  done
  _GS_EU2_MAX_VAR_LEN="${_pw_max}"
}

# _gs_eu2_classify_record — apply decision classifier and all annotation-based overrides.
#
# Args:    $1 record_index — 0-based index into the parallel record arrays
# Reads:   _GS_EU2_CFG[force_auto], _GS_EU2_CFG[unstable]; record fields: decision,
#          proposed_version, current_version, override, manual, major_hint,
#          major_hint_min, tag_channel_prefix, using_fallback_major,
#          skip_reason, lock_reason, annotation_sha, proposed_sha
# Sets:    record field "decision" (final classified value)
#          record field "error_message" (skip/lock annotations)
# Prints:  nothing
# Returns: 0 always
# Side fx: none
#
# Phases:
#   1. classify_decision: refines AUTO → HOLD/MANUAL/SKIP/AUTO based on version delta
#   2. force_auto upgrade: HOLD → AUTO when --force-auto active
#   3. lock gate: (lock:REASON) overrides any non-ERROR decision (except skip-gate SKIP)
#   4. SHA classification: SKIP → SHA when annotation sha lags proposed sha
#   5. Floating/prerelease skip annotations: adds error_message to explain up-to-date SKIP
_gs_eu2_classify_record() {
  local _cr_i="${1}"
  local _cr_cur _cr_prop _cr_override _cr_manual _cr_major _cr_major_min _cr_fetcher_decision
  _cr_cur="$(_gs_eu2_record_get "${_cr_i}" current_version)"
  _cr_prop="$(_gs_eu2_record_get "${_cr_i}" proposed_version)"
  _cr_override="$(_gs_eu2_record_get "${_cr_i}" override)"
  _cr_manual="$(_gs_eu2_record_get "${_cr_i}" manual)"
  _cr_major="$(_gs_eu2_record_get "${_cr_i}" major_hint)"
  _cr_major_min="$(_gs_eu2_record_get "${_cr_i}" major_hint_min)"
  _cr_fetcher_decision="$(_gs_eu2_record_get "${_cr_i}" decision)"

  # Phase 1: classify_decision — refines AUTO decisions
  if [[ "${_cr_fetcher_decision}" == "AUTO" || -z "${_cr_fetcher_decision}" ]]; then
    local _cr_classified
    # --force-auto: bypass (manual) and (override) annotation flags by passing "" so
    # classify_decision never sees them.  The HOLD gate is handled after classification.
    local _cr_eff_override="${_cr_override}" _cr_eff_manual="${_cr_manual}"
    if [[ "${_GS_EU2_CFG[force_auto]:-false}" == "true" ]]; then
      _cr_eff_override="" _cr_eff_manual=""
    fi
    # (tag-channel-prefix): pre-strip the channel prefix from _cur and _prop so that
    # decide.sh's internal sort -V downgrade check compares pure semver strings.
    # The round-trip prefix is display/storage-only; classify_decision must not see it.
    local _cr_cur_cls="${_cr_cur}" _cr_prop_cls="${_cr_prop}"
    local _cr_tcp_cls
    _cr_tcp_cls="$(_gs_eu2_record_get "${_cr_i}" tag_channel_prefix)"
    if [[ -n "${_cr_tcp_cls}" ]]; then
      _cr_cur_cls="${_cr_cur_cls#v}"; _cr_cur_cls="${_cr_cur_cls#"${_cr_tcp_cls}"}"
      _cr_prop_cls="${_cr_prop_cls#v}"; _cr_prop_cls="${_cr_prop_cls#"${_cr_tcp_cls}"}"
    fi
    # Range annotation: when the fetcher fell back to the LOW major, pass major_hint_min
    # to classify_decision so the HOLD guard accepts the fallback version.
    local _cr_using_fallback _cr_major_cls="${_cr_major}"
    _cr_using_fallback="$(_gs_eu2_record_get "${_cr_i}" using_fallback_major)"
    if [[ "${_cr_using_fallback}" == "true" && -n "${_cr_major_min}" ]]; then
      _cr_major_cls="${_cr_major_min}"
    fi
    local _cr_record_channel
    _cr_record_channel="$(_gs_eu2_record_get "${_cr_i}" channel)"
    local _cr_gate=""
    [[ "${_cr_eff_override}" == "true" || "${_cr_eff_manual}" == "true" ]] && _cr_gate="true"
    _cr_classified="$(_gs_eu2_classify_decision "${_cr_cur_cls}" "${_cr_prop_cls}" "${_cr_gate}" "${_cr_major_cls}" "${_GS_EU2_CFG[unstable]:-}" "${_GS_EU2_CFG[stable]:-}" "${_cr_record_channel}")"
    # Phase 2: --force-hold: HOLD → AUTO only (MANUAL/OVERRIDE flags NOT cleared; unaffected)
    if [[ "${_GS_EU2_CFG[force_hold]:-false}" == "true" && "${_cr_classified}" == "HOLD" ]]; then
      _cr_classified="AUTO"
    fi
    # Phase 2b: --force-auto upgrade: HOLD → AUTO (MANUAL/OVERRIDE already cleared above)
    if [[ "${_GS_EU2_CFG[force_auto]:-false}" == "true" && "${_cr_classified}" == "HOLD" ]]; then
      _cr_classified="AUTO"
    fi
    _gs_eu2_record_set "${_cr_i}" decision "${_cr_classified}"
  fi

  # Phase 3: lock gate — (lock:REASON) overrides AUTO/HOLD/MANUAL/SKIP(classifier) to LOCK.
  # Fires AFTER force-auto upgrade. Does NOT override ERROR or skip-gate SKIP.
  local _cr_skip_reason _cr_lock_reason
  _cr_skip_reason="$(_gs_eu2_record_get "${_cr_i}" skip_reason)"
  _cr_lock_reason="$(_gs_eu2_record_get "${_cr_i}" lock_reason)"
  if [[ -n "${_cr_lock_reason}" && \
        "$(_gs_eu2_record_get "${_cr_i}" decision)" != "ERROR" && \
        -z "${_cr_skip_reason}" ]]; then
    _gs_eu2_record_set "${_cr_i}" decision "LOCK"
    _gs_eu2_record_set "${_cr_i}" error_message "${_cr_lock_reason}"
  fi

  # Phase 4: SHA classification — SKIP → SHA when annotation sha lags proposed sha.
  local _cr_ann_sha _cr_prop_sha _cr_sha_classified
  _cr_ann_sha="$(_gs_eu2_record_get "${_cr_i}" annotation_sha)"
  _cr_prop_sha="$(_gs_eu2_record_get "${_cr_i}" proposed_sha)"
  _cr_sha_classified="$(_gs_eu2_classify_sha_decision "${_cr_ann_sha}" "${_cr_prop_sha}")"
  if [[ "${_cr_sha_classified}" == "SHA" && \
        "$(_gs_eu2_record_get "${_cr_i}" decision)" == "SKIP" ]]; then
    _gs_eu2_record_set "${_cr_i}" decision "SHA"
  fi

  # Phase 5: floating/prerelease skip annotations — add error_message to explain up-to-date SKIP.
  # Guard: skip-gated records already have error_message set; do not overwrite.
  if [[ -z "${_cr_skip_reason}" && \
        "$(_gs_eu2_record_get "${_cr_i}" decision)" == "SKIP" && \
        "${_cr_prop}" != "${_cr_cur}" ]] && \
     _gs_eu2_is_unversioned "${_cr_cur}"; then
    _gs_eu2_record_set "${_cr_i}" error_message \
      "floating reference (${_cr_cur}) — pin manually to adopt proposed version"
  fi

  # Annotate SKIP when proposed is prerelease but current is stable.
  if [[ -z "${_cr_skip_reason}" && \
        "$(_gs_eu2_record_get "${_cr_i}" decision)" == "SKIP" && \
        -z "$(_gs_eu2_record_get "${_cr_i}" error_message)" && \
        -n "${_cr_prop}" && "${_cr_prop}" != "${_cr_cur}" ]] && \
     _gs_eu2_is_prerelease "${_cr_prop}" && ! _gs_eu2_is_prerelease "${_cr_cur}"; then
    _gs_eu2_record_set "${_cr_i}" error_message \
      "proposed is prerelease — pin manually when stable ships"
  fi
}

# _gs_eu2_compute_reason_label — compute the reason suffix for non-AUTO decisions.
#
# Args:    $1 record_index — 0-based index into the parallel record arrays
#          $2 decision     — current decision string (HOLD/MANUAL/LOCK/SKIP/etc.)
#          $3 current_ver  — current_version field value
#          $4 proposed_ver — proposed_version field value
#          $5 major_hint   — major_hint field value (may be empty)
#          $6 lock_reason  — lock_reason field value (may be empty)
# Reads:   nothing beyond args
# Prints:  reason string (e.g. "  ← major pin (26.x available)") or "" (empty)
# Returns: 0 always
# Side fx: none
_gs_eu2_compute_reason_label() {
  local _rl_i="${1}"
  local _rl_decision="${2}"
  local _rl_cur="${3}"
  local _rl_prop="${4}"
  local _rl_major="${5}"
  local _rl_lock_reason="${6}"
  local _rl_reason=""

  case "${_rl_decision}" in
    HOLD)
      if [[ -n "${_rl_prop}" ]]; then
        local _rl_delta _rl_cur_maj _rl_prop_maj
        _rl_delta="$(_gs_eu2_semver_delta "${_rl_cur}" "${_rl_prop}")"
        _rl_cur_maj="${_rl_cur#v}"; _rl_cur_maj="${_rl_cur_maj%%.*}"
        _rl_prop_maj="${_rl_prop#v}"; _rl_prop_maj="${_rl_prop_maj%%.*}"
        # Strip path-like prefix from major labels (e.g. "tags/2" → "2")
        _rl_cur_maj="${_rl_cur_maj##*[^0-9]}"
        _rl_prop_maj="${_rl_prop_maj##*[^0-9]}"
        if [[ -n "${_rl_major}" ]]; then
          _rl_reason="  ← major pin (${_rl_prop_maj}.x available)"
        elif [[ "${_rl_delta}" == "major" ]]; then
          _rl_reason="  ← major bump (${_rl_cur_maj}→${_rl_prop_maj})"
        fi
      fi
      ;;
    MANUAL)
      _rl_reason="  ← manual flag"
      ;;
    LOCK)
      _rl_reason="  ← locked: ${_rl_lock_reason}"
      ;;
  esac

  printf '%s' "${_rl_reason}"
}

# _gs_eu2_compute_change_string — compute the inline change/status string for the main output line.
#
# Args:    $1 record_index — 0-based index into the parallel record arrays
#          $2 decision     — current decision string
#          $3 current_ver  — current_version field value
#          $4 proposed_ver — proposed_version field value
#          $5 err_msg      — error_message field value (may be empty)
#          $6 manual       — manual flag value ("true" or "")
#          $7 override     — override flag value ("true" or "")
#          $8 reason_label — pre-computed reason label from _gs_eu2_compute_reason_label
# Reads:   record field "skip_reason" (for downgrade SKIP check), "tag_channel_prefix",
#          "annotation_sha", "proposed_sha"
# Prints:  change string (e.g. "  1.2.0 → 1.3.0  ← major bump") or status text
# Returns: 0 always
# Side fx: none
_gs_eu2_compute_change_string() {
  local _cs_i="${1}"
  local _cs_decision="${2}"
  local _cs_cur="${3}"
  local _cs_prop="${4}"
  local _cs_err="${5}"
  local _cs_manual="${6}"
  local _cs_override="${7}"
  local _cs_reason="${8}"
  local _cs_change=""

  if [[ "${_cs_decision}" == "SHA" ]]; then
    local _cs_sha_new _cs_sha_ann
    _cs_sha_new="$(_gs_eu2_record_get "${_cs_i}" proposed_sha)"
    _cs_sha_ann="$(_gs_eu2_record_get "${_cs_i}" annotation_sha)"
    _cs_change="  sha:${_cs_sha_ann:0:8} → sha:${_cs_sha_new:0:8}"
  elif [[ "${_cs_decision}" == "SKIP" && -n "${_cs_err}" ]]; then
    _cs_change="  (${_cs_err})"
  elif [[ "${_cs_decision}" == "SKIP" && -z "${_cs_err}" && -n "${_cs_prop}" && "${_cs_prop}" != "${_cs_cur}" ]]; then
    # Detect downgrade: proposed non-empty, differs from current, no error yet.
    # If a downgrade is detected, set _cs_err and display it as "(would downgrade: ...)".
    # If no downgrade, display the version arrow ("cur → prop") via the prop!=cur branch.
    local _cs_tcp_disp
    _cs_tcp_disp="$(_gs_eu2_record_get "${_cs_i}" tag_channel_prefix)"
    local _cs_cur_cmp="${_cs_cur#v}" _cs_prop_cmp="${_cs_prop#v}"
    [[ -n "${_cs_tcp_disp}" ]] && _cs_cur_cmp="${_cs_cur_cmp#"${_cs_tcp_disp}"}"
    [[ -n "${_cs_tcp_disp}" ]] && _cs_prop_cmp="${_cs_prop_cmp#"${_cs_tcp_disp}"}"
    local _cs_cv_norm _cs_pv_norm _cs_oldest
    _cs_cv_norm="$(perl -pe 's/(\d{8})[0-9a-fA-F]+$/$1/' <<< "${_cs_cur_cmp}")"
    _cs_pv_norm="$(perl -pe 's/(\d{8})[0-9a-fA-F]+$/$1/' <<< "${_cs_prop_cmp}")"
    _cs_oldest="$(printf '%s\n%s\n' "${_cs_cv_norm}" "${_cs_pv_norm}" | sort -V | head -1)"
    if [[ "${_cs_oldest}" == "${_cs_pv_norm}" && "${_cs_oldest}" != "${_cs_cv_norm}" ]]; then
      local _cs_channel
      _cs_channel="$(_gs_eu2_record_get "${_cs_i}" channel)"
      _cs_err="would downgrade: current ${_cs_cur_cmp} → ${_cs_channel:-proposed} ${_cs_prop_cmp}"
      _cs_change="  (${_cs_err})"
    else
      # No downgrade — show version arrow (mirrors the generic prop!=cur branch below)
      _cs_change="  ${_cs_cur} → ${_cs_prop}${_cs_reason}"
    fi
  elif [[ "${_cs_decision}" == "ERROR" && -n "${_cs_err}" ]]; then
    # ERROR with an explicit message: show the error, not the version arrow.
    # This covers float+(watch-major) and other annotation errors where the
    # fetcher may have found a proposed version but the record is still invalid.
    _cs_change="  (${_cs_err})"
  elif [[ -n "${_cs_prop}" && "${_cs_prop}" != "${_cs_cur}" ]]; then
    _cs_change="  ${_cs_cur} → ${_cs_prop}${_cs_reason}"
  elif [[ -n "${_cs_err}" ]]; then
    _cs_change="  (${_cs_err})"
  elif [[ "${_cs_decision}" == "SKIP" ]]; then
    if [[ "${_cs_manual}" == "true" ]]; then
      _cs_change="  (up to date — manual)"
    elif [[ "${_cs_override}" == "true" ]]; then
      _cs_change="  (up to date — override)"
    else
      _cs_change="  (up to date)"
    fi
  elif [[ -n "${_cs_reason}" ]]; then
    _cs_change="${_cs_reason}"
  fi

  printf '%s' "${_cs_change}"
}

# _gs_eu2_should_hide_record — evaluate whether a record should be suppressed under --changes-only.
#
# Args:    $1 record_index — 0-based index into the parallel record arrays
#          $2 decision     — current decision string
#          $3 err_msg      — error_message field value (may be empty)
#          $4 skip_reason  — skip_reason field value (may be empty — distinguishes FROZEN vs SKIP)
#          $5 major_hint   — major_hint field value (for FALLBACK signal)
#          $6 cur          — current_version value
# Reads:   _GS_EU2_CFG[changes_only], _GS_EU2_CFG[unstable], _GS_EU2_CFG[stable],
#          _GS_EU2_CFG[env_file]; record fields for signal detection
# Prints:  nothing
# Returns: 0 (hide the record) | 1 (show the record)
# Side fx: reads env file for replace-drift detection
#
# A record is hidden only when: decision=SKIP, error_message empty, no skip_reason,
# AND none of: FALLBACK signal, WATCH signal, UNSTABLE/STABLE info sub-lines, DRIFT, REPLACE-DRIFT.
_gs_eu2_should_hide_record() {
  local _sh_i="${1}"
  local _sh_decision="${2}"
  local _sh_err="${3}"
  local _sh_skip_reason="${4}"
  local _sh_major="${5}"
  local _sh_cur="${6}"

  # Gate: only evaluate when --changes-only is active and the record is a plain up-to-date SKIP
  if [[ "${_GS_EU2_CFG[changes_only]:-false}" != "true" \
        || "${_sh_decision}" != "SKIP" \
        || -n "${_sh_err}" \
        || -n "${_sh_skip_reason}" ]]; then
    return 1  # show
  fi

  # Tentatively hide; check each signal that would prevent hiding
  # [FALLBACK] signal: range annotation fell back to LOW major
  local _sh_fallback
  _sh_fallback="$(_gs_eu2_record_get "${_sh_i}" using_fallback_major)"
  if [[ "${_sh_fallback}" == "true" && -n "${_sh_major}" ]]; then
    return 1  # show
  fi

  # [WATCH] signal: new runtime generation detected
  local _sh_wm_depth
  _sh_wm_depth="$(_gs_eu2_record_get "${_sh_i}" watch_major_depth)"
  if [[ -n "${_sh_wm_depth}" ]]; then
    local _sh_wm_lat
    _sh_wm_lat="$(_gs_eu2_record_get "${_sh_i}" latest_unconstrained)"
    [[ -z "${_sh_wm_lat}" ]] && _sh_wm_lat="$(_gs_eu2_record_get "${_sh_i}" proposed_version)"
    if [[ -n "${_sh_wm_lat}" && -n "${_sh_cur}" ]]; then
      local _sh_wm_cpfx _sh_wm_lpfx
      _sh_wm_cpfx="$(_gs_eu2_version_prefix "${_sh_cur}" "${_sh_wm_depth}")"
      _sh_wm_lpfx="$(_gs_eu2_version_prefix "${_sh_wm_lat}" "${_sh_wm_depth}")"
      if [[ -n "${_sh_wm_cpfx}" && -n "${_sh_wm_lpfx}" \
            && "${_sh_wm_cpfx}" != "${_sh_wm_lpfx}" ]]; then
        local _sh_wm_hi
        _sh_wm_hi="$(printf '%s\n%s\n' "${_sh_wm_cpfx}" "${_sh_wm_lpfx}" | sort -V | tail -1)"
        [[ "${_sh_wm_hi}" == "${_sh_wm_lpfx}" ]] && return 1  # show
      fi
    fi
  fi

  # [UNSTABLE] info sub-line signal
  if [[ "${_GS_EU2_CFG[unstable]:-}" == "info" && "${_GS_EU2_CFG[stable]:-}" != "full" ]]; then
    local _sh_unstable
    _sh_unstable="$(_gs_eu2_record_get "${_sh_i}" unstable_proposed)"
    [[ -n "${_sh_unstable}" && "${_sh_unstable}" != "${_sh_cur}" ]] && return 1  # show
  fi

  # [STABLE] info sub-line signal
  if [[ "${_GS_EU2_CFG[stable]:-}" == "info" ]]; then
    local _sh_stable
    _sh_stable="$(_gs_eu2_record_get "${_sh_i}" stable_proposed)"
    [[ -n "${_sh_stable}" && "${_sh_stable}" != "${_sh_cur}" ]] && return 1  # show
  fi

  # [DRIFT] signal: VAR= differs from annotation version or SHA
  local _sh_actual _sh_ann_ver _sh_use_sha _sh_ann_sha
  _sh_actual="$(_gs_eu2_record_get "${_sh_i}" actual_var_value)"
  _sh_ann_ver="$(_gs_eu2_record_get "${_sh_i}" current_version)"
  _sh_use_sha="$(_gs_eu2_record_get "${_sh_i}" use_sha)"
  _sh_ann_sha="$(_gs_eu2_record_get "${_sh_i}" annotation_sha)"
  if [[ "${_sh_use_sha}" == "true" ]]; then
    [[ -n "${_sh_actual}" && -n "${_sh_ann_sha}" \
       && "${_sh_actual}" != "${_sh_ann_sha}" ]] && return 1  # show
  else
    if [[ -z "${_sh_actual}" && -n "${_sh_ann_ver}" ]]; then
      return 1  # show
    elif [[ -n "${_sh_actual}" && -n "${_sh_ann_ver}" \
            && "${_sh_actual}" != "${_sh_ann_ver}" ]]; then
      return 1  # show
    fi
  fi

  # [REPLACE-DRIFT] signal: any replace target whose actual value differs from expand_template(cur)
  local _sh_rep_tgts _sh_rep_tmpls
  _sh_rep_tgts="$(_gs_eu2_record_get "${_sh_i}" replace_targets)"
  _sh_rep_tmpls="$(_gs_eu2_record_get "${_sh_i}" replace_templates)"
  if [[ -n "${_sh_rep_tgts}" ]]; then
    local _sh_old_ifs="${IFS}"
    IFS=$'\x1f'
    local _sh_rt_arr _sh_rm_arr
    read -ra _sh_rt_arr <<< "${_sh_rep_tgts}"
    read -ra _sh_rm_arr <<< "${_sh_rep_tmpls}"
    IFS="${_sh_old_ifs}"
    local _sh_ri
    for (( _sh_ri = 0; _sh_ri < ${#_sh_rt_arr[@]}; _sh_ri++ )); do
      local _sh_rt="${_sh_rt_arr[${_sh_ri}]}"
      local _sh_rm="${_sh_rm_arr[${_sh_ri}]:-}"
      local _sh_tgt_actual _sh_exp_cur
      _sh_tgt_actual="$(grep -m1 "^${_sh_rt}=" "${_GS_EU2_CFG[env_file]}" 2>/dev/null \
        | cut -d= -f2-)"
      _sh_exp_cur="$(_gs_eu2_expand_replace_template "${_sh_rm}" "${_sh_ann_ver:-}")"
      if [[ "${_sh_tgt_actual}" != "${_sh_exp_cur}" ]]; then
        return 1  # show
      fi
    done
  fi

  return 0  # hide
}

# _gs_eu2_print_check_summary — print the post-loop separator + summary line + secondary signals.
#
# Args:    $1  n_auto            $2  n_hold         $3  n_skip
#          $4  n_error           $5  n_manual        $6  n_sha
#          $7  n_lock            $8  n_frozen        $9  n_fallback
#          $10 n_watch           $11 n_drift         $12 n_drift_fixable
#          $13 n_downgrade       $14 n_downgrade_force $15 n_hidden
#          $16 n_sha_anno        $17 n_replace_drift  $18 n_replace_cascade
#          $19 n_resolved        $20 n_warn_depends_on
# Reads:   _GS_EU2_CFG[no_drift]
# Prints:  separator line + summary line + optional secondary signals sub-line to stdout
# Returns: 0 always
# Side fx: none
_gs_eu2_print_check_summary() {
  local _ps_n_auto="${1}"
  local _ps_n_hold="${2}"
  local _ps_n_skip="${3}"
  local _ps_n_error="${4}"
  local _ps_n_manual="${5}"
  local _ps_n_sha="${6}"
  local _ps_n_lock="${7}"
  local _ps_n_frozen="${8}"
  local _ps_n_fallback="${9}"
  local _ps_n_watch="${10}"
  local _ps_n_drift="${11}"
  local _ps_n_drift_fixable="${12}"
  local _ps_n_downgrade="${13}"
  local _ps_n_downgrade_force="${14}"
  local _ps_n_hidden="${15}"
  local _ps_n_sha_anno="${16}"
  local _ps_n_replace_drift="${17}"
  local _ps_n_replace_cascade="${18}"
  local _ps_n_resolved="${19}"
  local _ps_n_warn_depends_on="${20}"

  local _ps_total=$(( _ps_n_auto + _ps_n_hold + _ps_n_skip + _ps_n_error + _ps_n_manual + _ps_n_sha + _ps_n_lock + _ps_n_frozen ))
  printf '%-80s\n' "──────────────────────────────────────────────────────────────────────────────"
  local _ps_checked_suffix="${_ps_total} checked"
  (( _ps_n_hidden > 0 )) && _ps_checked_suffix="${_ps_total} checked, ${_ps_n_hidden} hidden"
  # RESOLVE column: shown only when at least one RESOLVED record exists
  local _ps_resolve_col=""
  (( _ps_n_resolved > 0 )) && _ps_resolve_col=" ${_ps_n_resolved} RESOLVE,"
  printf '  Summary: %d AUTO,%s %d SHA, %d HOLD, %d MANUAL, %d LOCK, %d SKIP, %d FROZEN, %d FALLBACK, %d ERROR  (%s)\n' \
    "${_ps_n_auto}" "${_ps_resolve_col}" "${_ps_n_sha}" "${_ps_n_hold}" "${_ps_n_manual}" "${_ps_n_lock}" "${_ps_n_skip}" "${_ps_n_frozen}" "${_ps_n_fallback}" "${_ps_n_error}" "${_ps_checked_suffix}"

  # Secondary signals sub-line: WATCH, DRIFT (with fixable count), DOWNGRADE, REPLACE-DRIFT, +sha, +replace.
  # DRIFT, DOWNGRADE, REPLACE-DRIFT, and +replace suppressed when --no-drift is active.
  # +sha follows WATCH (unconditional — not suppressed by --no-drift).
  # Entire line omitted when all relevant signals are zero.
  local _ps_sec_watch="${_ps_n_watch}"
  local _ps_sec_drift=0 _ps_sec_fixable=0 _ps_sec_down=0 _ps_sec_down_force=0
  local _ps_sec_sha_anno="${_ps_n_sha_anno}"
  local _ps_sec_replace_drift=0 _ps_sec_replace_cascade=0
  local _ps_sec_resolved="${_ps_n_resolved}"
  if [[ "${_GS_EU2_CFG[no_drift]:-false}" != "true" ]]; then
    _ps_sec_drift="${_ps_n_drift}"
    _ps_sec_fixable="${_ps_n_drift_fixable}"
    _ps_sec_down="${_ps_n_downgrade}"
    _ps_sec_down_force="${_ps_n_downgrade_force}"
    _ps_sec_replace_drift="${_ps_n_replace_drift}"
    _ps_sec_replace_cascade="${_ps_n_replace_cascade}"
  fi
  if (( _ps_sec_watch > 0 || _ps_sec_drift > 0 || _ps_sec_down > 0 || _ps_sec_down_force > 0 || _ps_sec_sha_anno > 0 || _ps_sec_replace_drift > 0 || _ps_sec_replace_cascade > 0 || _ps_sec_resolved > 0 || _ps_n_warn_depends_on > 0 )); then
    printf '    ↳ %d WATCH · %d DRIFT (%d fixable) · %d DOWNGRADE · %d FORCE-DOWNGRADE · %d REPLACE-DRIFT · %d +sha · %d +replace' \
      "${_ps_sec_watch}" "${_ps_sec_drift}" "${_ps_sec_fixable}" "${_ps_sec_down}" "${_ps_sec_down_force}" "${_ps_sec_replace_drift}" "${_ps_sec_sha_anno}" "${_ps_sec_replace_cascade}"
    (( _ps_sec_resolved > 0 )) && printf ' · +resolve %d' "${_ps_sec_resolved}"
    (( _ps_n_warn_depends_on > 0 )) && printf ' · %d depends-on-warn' "${_ps_n_warn_depends_on}"
    printf '\n'
  fi
}

# ── Signal sub-functions ──────────────────────────────────────────────────────
# Each _gs_eu2_signal_* function handles one class of sub-line output for a
# single record.  They are called as plain function calls (not subshells) so
# they can increment the _n_* counters that live in the parent loop scope via
# dynamic scoping — no `local` re-declaration of counter variables here.
# All sub-functions end with `return 0` to prevent set -e / ERR-trap from
# firing when an internal [[ … ]] test evaluates to false.

# _gs_eu2_signal_primary_line — print the main decision line + optional note sub-line.
# Args: _tag _max_var_len _env_var _change _note
_gs_eu2_signal_primary_line() {
  local _tag="${1}" _max_var_len="${2}" _env_var="${3}" _change="${4}" _note="${5}"
  printf "%s  %-${_max_var_len}s%s\n" "${_tag}" "${_env_var}" "${_change}"
  [[ -n "${_note}" && "${_GS_EU2_CFG[no_notes]:-false}" != "true" ]] && \
    printf '%10s↳ %s\n' "" "${_note}"
  return 0
}

# _gs_eu2_signal_fallback — [FALLBACK] sub-line when major range fell back to LOW major.
# Args: _i _major _major_min
_gs_eu2_signal_fallback() {
  local _i="${1}" _major="${2}" _major_min="${3}"
  local _using_fallback_disp
  _using_fallback_disp="$(_gs_eu2_record_get "${_i}" using_fallback_major)"
  if [[ "${_using_fallback_disp}" == "true" && -n "${_major_min}" ]]; then
    printf '%10s↳ [FALLBACK] major=%s not yet in registry — using fallback major=%s\n' \
      "" "${_major}" "${_major_min}"
    (( ++_n_fallback )) || true
  fi
  return 0
}

# _gs_eu2_signal_pin_miss — [PIN-MISS] sub-line when major-pin produced zero results.
# Args: _i _decision _major _skip_err_disp
_gs_eu2_signal_pin_miss() {
  local _i="${1}" _decision="${2}" _major="${3}" _skip_err_disp="${4}"
  if [[ "${_decision}" == "SKIP" && -n "${_major}" && -n "${_skip_err_disp}" ]]; then
    local _pin_uc
    _pin_uc="$(_gs_eu2_record_get "${_i}" latest_unconstrained)"
    if [[ -n "${_pin_uc}" ]]; then
      printf '%10s↳ [PIN-MISS] major=%s not yet in registry — globally latest: %s\n' \
        "" "${_major}" "${_pin_uc}"
    fi
  fi
  return 0
}

# _gs_eu2_signal_watch — [WATCH] sub-line when a new runtime generation is available.
# Args: _i _decision _cur _prop
_gs_eu2_signal_watch() {
  local _i="${1}" _decision="${2}" _cur="${3}" _prop="${4}"
  if [[ "${_decision}" != "ERROR" ]]; then
    local _wm_depth_r
    _wm_depth_r="$(_gs_eu2_record_get "${_i}" watch_major_depth)"
    if [[ -n "${_wm_depth_r}" ]]; then
      local _wm_latest
      _wm_latest="$(_gs_eu2_record_get "${_i}" latest_unconstrained)"
      [[ -z "${_wm_latest}" ]] && _wm_latest="${_prop}"
      if [[ -n "${_wm_latest}" && -n "${_cur}" ]]; then
        local _wm_cur_pfx _wm_lat_pfx
        _wm_cur_pfx="$(_gs_eu2_version_prefix "${_cur}" "${_wm_depth_r}")"
        _wm_lat_pfx="$(_gs_eu2_version_prefix "${_wm_latest}" "${_wm_depth_r}")"
        if [[ -n "${_wm_cur_pfx}" && -n "${_wm_lat_pfx}" && \
              "${_wm_cur_pfx}" != "${_wm_lat_pfx}" ]]; then
          local _wm_higher
          _wm_higher="$(printf '%s\n%s\n' "${_wm_cur_pfx}" "${_wm_lat_pfx}" | sort -V | tail -1)"
          if [[ "${_wm_higher}" == "${_wm_lat_pfx}" ]]; then
            printf '%10s↳ [WATCH] New generation available: %s (depth %s: %s → %s)\n' \
              "" "${_wm_latest}" "${_wm_depth_r}" "${_wm_cur_pfx}" "${_wm_lat_pfx}"
            (( ++_n_watch )) || true
          fi
        fi
      fi
    fi
  fi
  return 0
}

# _gs_eu2_signal_sha — SHA sub-line display + +sha counter logic.
# Args: _i _decision
_gs_eu2_signal_sha() {
  local _i="${1}" _decision="${2}"
  # SHA sub-line: show short SHA (8 chars) + date for AUTO, SHA, and MANUAL decisions
  if [[ "${_decision}" == "AUTO" || "${_decision}" == "SHA" || "${_decision}" == "MANUAL" ]]; then
    local _disp_prop_sha _disp_ann_sha _disp_sha_date
    _disp_prop_sha="$(_gs_eu2_record_get "${_i}" proposed_sha)"
    _disp_ann_sha="$(_gs_eu2_record_get "${_i}" annotation_sha)"
    _disp_sha_date="$(_gs_eu2_record_get "${_i}" proposed_sha_date)"
    if [[ -n "${_disp_prop_sha}" && "${_disp_prop_sha}" != "${_disp_ann_sha}" ]]; then
      local _sha_sub="sha: ${_disp_prop_sha:0:8}"
      [[ -n "${_disp_sha_date}" ]] && _sha_sub+=" (${_disp_sha_date})"
      [[ -n "${_disp_ann_sha}" ]] && _sha_sub+="  ← was ${_disp_ann_sha:0:8}"
      printf '%10s↳ %s\n' "" "${_sha_sub}"
    fi
  fi
  # +sha counter: AUTO or MANUAL decisions that also carry a sha annotation update.
  # Pure SHA decisions (decision=SHA) are already in the primary SHA counter — excluded here.
  if [[ "${_decision}" == "AUTO" || "${_decision}" == "MANUAL" ]]; then
    local _sha_anno_prop _sha_anno_ann
    _sha_anno_prop="$(_gs_eu2_record_get "${_i}" proposed_sha)"
    _sha_anno_ann="$(_gs_eu2_record_get "${_i}" annotation_sha)"
    if [[ -n "${_sha_anno_prop}" && "${_sha_anno_prop}" != "${_sha_anno_ann}" ]]; then
      (( ++_n_sha_anno )) || true
    fi
  fi
  return 0
}

# _gs_eu2_signal_unstable — [UNSTABLE] info sub-line.
# Args: _i _cur
_gs_eu2_signal_unstable() {
  local _i="${1}" _cur="${2}"
  if [[ "${_GS_EU2_CFG[unstable]:-}" == "info" && "${_GS_EU2_CFG[stable]:-}" != "full" ]]; then
    local _unstable_disp
    _unstable_disp="$(_gs_eu2_record_get "${_i}" unstable_proposed)"
    if [[ -n "${_unstable_disp}" && "${_unstable_disp}" != "${_cur}" ]]; then
      printf '%10s↳ [UNSTABLE] unstable: %s\n' "" "${_unstable_disp}"
    fi
  fi
  return 0
}

# _gs_eu2_signal_stable — [STABLE] info sub-line.
# Args: _i _cur
_gs_eu2_signal_stable() {
  local _i="${1}" _cur="${2}"
  if [[ "${_GS_EU2_CFG[stable]:-}" == "info" ]]; then
    local _stable_disp
    _stable_disp="$(_gs_eu2_record_get "${_i}" stable_proposed)"
    if [[ -n "${_stable_disp}" && "${_stable_disp}" != "${_cur}" ]]; then
      printf '%10s↳ [STABLE] stable: %s\n' "" "${_stable_disp}"
    fi
  fi
  return 0
}

# _gs_eu2_signal_depends_on — [WARN] depends-on safety warning sub-line.
# Args: _i
_gs_eu2_signal_depends_on() {
  local _i="${1}"
  local _depends_on
  _depends_on="$(_gs_eu2_record_get "${_i}" depends_on)"
  if [[ -n "${_depends_on}" ]]; then
    printf '%10s↳ [WARN] (depends-on:%s) not enforced — dependency ordering\n' \
      "" "${_depends_on}"
    printf '%10s         unimplemented; verify %s manually before --apply\n' \
      "" "${_depends_on%%:*}"
    (( ++_n_warn_depends_on )) || true
  fi
  return 0
}

# _gs_eu2_signal_drift — [DRIFT] sub-line + post-drift counter updates.
# Covers: use-sha case (case 3), empty-var case (case 1), differ case (case 2).
# Also increments _n_drift, _n_drift_fixable, _n_downgrade, _n_downgrade_force.
# Args: _i _decision _cur _prop _skip_reason
# shellcheck disable=SC2154
_gs_eu2_signal_drift() {
  local _i="${1}" _decision="${2}" _cur="${3}" _prop="${4}" _skip_reason="${5}"
  # RESOLVED: drift comparison is meaningless for floating aliases — skip entire block.
  if [[ "${_GS_EU2_CFG[no_drift]:-false}" != "true" && "${_decision}" != "RESOLVED" ]]; then
    local _drift_actual _drift_ann_ver _drift_ann_sha _drift_use_sha
    _drift_actual="$(_gs_eu2_record_get "${_i}" actual_var_value)"
    _drift_ann_ver="$(_gs_eu2_record_get "${_i}" current_version)"
    _drift_ann_sha="$(_gs_eu2_record_get "${_i}" annotation_sha)"
    _drift_use_sha="$(_gs_eu2_record_get "${_i}" use_sha)"
    if [[ "${_drift_use_sha}" == "true" ]]; then
      # Case 3: use-sha record — compare VAR= value vs. annotation sha
      if [[ -n "${_drift_actual}" && -n "${_drift_ann_sha}" \
            && "${_drift_actual}" != "${_drift_ann_sha}" ]]; then
        if [[ "${_decision}" == "LOCK" ]]; then
          printf '%10s↳ [DRIFT] var SHA (%s) differs from annotation sha:(%s) — locked; update annotation or revert VAR= manually\n' \
            "" "${_drift_actual:0:8}" "${_drift_ann_sha:0:8}"
        elif [[ -n "${_skip_reason}" ]]; then
          printf '%10s↳ [DRIFT] var SHA (%s) differs from annotation sha:(%s) — frozen by skip flag; update annotation or revert VAR= manually\n' \
            "" "${_drift_actual:0:8}" "${_drift_ann_sha:0:8}"
        elif [[ "${_decision}" == "SKIP" ]]; then
          printf '%10s↳ [DRIFT] var SHA (%s) differs from annotation sha:(%s) — update annotation or revert VAR= manually (--apply skips up-to-date records)\n' \
            "" "${_drift_actual:0:8}" "${_drift_ann_sha:0:8}"
        elif [[ "${_decision}" == "HOLD" || "${_decision}" == "MANUAL" ]]; then
          printf '%10s↳ [DRIFT] var SHA (%s) differs from annotation sha:(%s) — --force-auto --apply to resolve\n' \
            "" "${_drift_actual:0:8}" "${_drift_ann_sha:0:8}"
        elif [[ "${_decision}" == "ERROR" ]]; then
          printf '%10s↳ [DRIFT] var SHA (%s) differs from annotation sha:(%s) — fetch failed; fix error then re-run\n' \
            "" "${_drift_actual:0:8}" "${_drift_ann_sha:0:8}"
        else
          # AUTO or SHA: --apply can resolve
          printf '%10s↳ [DRIFT] var SHA (%s) differs from annotation sha:(%s) — re-run --apply to resolve\n' \
            "" "${_drift_actual:0:8}" "${_drift_ann_sha:0:8}"
        fi
        _drift_fired=true
      fi
    else
      if [[ -z "${_drift_actual}" && -n "${_drift_ann_ver}" ]]; then
        # Case 1: empty var — decision-aware enable-warning
        if [[ "${_decision}" == "LOCK" ]]; then
          printf '%10s↳ [DRIFT] var is empty — annotation locked at %s; feature disabled (set VAR= manually to re-enable — lock blocks --apply and --force-auto)\n' \
            "" "${_drift_ann_ver}"
          _drift_fired=true
        elif [[ -n "${_skip_reason}" ]]; then
          : # skip-gate blocks apply; empty var is intentional — no drift message
        elif [[ "${_decision}" == "HOLD" ]]; then
          printf '%10s↳ [DRIFT] var is empty — annotation tracks %s (feature disabled? --force-auto --apply will write it to enable)\n' \
            "" "${_drift_ann_ver}"
          _drift_fired=true
        elif [[ "${_decision}" == "MANUAL" ]]; then
          printf '%10s↳ [DRIFT] var is empty — annotation tracks %s (feature disabled? --force-auto --apply will write it to enable)\n' \
            "" "${_drift_ann_ver}"
          _drift_fired=true
        elif [[ "${_decision}" == "AUTO" ]]; then
          printf '%10s↳ [DRIFT] var is empty — annotation tracks %s (feature disabled? --apply will write %s to enable it)\n' \
            "" "${_drift_ann_ver}" "${_prop:-${_drift_ann_ver}}"
          _drift_fired=true
        elif [[ "${_decision}" == "SHA" ]]; then
          printf '%10s↳ [DRIFT] var is empty — annotation tracks %s (feature disabled? set VAR= manually to enable)\n' \
            "" "${_drift_ann_ver}"
          _drift_fired=true
        else
          # SKIP (up-to-date, not skip-gate) or ERROR: informational only
          printf '%10s↳ [DRIFT] var is empty — annotation tracks %s (feature disabled?)\n' \
            "" "${_drift_ann_ver}"
          _drift_fired=true
        fi
      elif [[ -n "${_drift_actual}" && -n "${_drift_ann_ver}" \
              && "${_drift_actual}" != "${_drift_ann_ver}" ]]; then
        # Case 2: both non-empty but differ — direction-aware + decision-aware message
        local _drift_dir_msg=""
        if [[ "${_drift_actual}" =~ ^v?[0-9][0-9.]*$ && \
              "${_drift_ann_ver}" =~ ^v?[0-9][0-9.]*$ ]]; then
          local _drift_oldest
          _drift_oldest="$(printf '%s\n%s\n' "${_drift_actual}" "${_drift_ann_ver}" | sort -V | head -1)"
          if [[ "${_drift_oldest}" == "${_drift_actual}" && "${_drift_actual}" != "${_drift_ann_ver}" ]]; then
            _drift_dir_msg=" — re-run --apply or update annotation"
          else
            _drift_dir_msg=" — VAR is ahead of annotation (downgrade risk: run --apply only if intentional)"
            _drift_dir_downgrade=true
          fi
        fi
        # Decision-aware message (B2-B11)
        if [[ "${_decision}" == "LOCK" ]]; then
          printf '%10s↳ [DRIFT] annotation says %s but VAR=%s — locked; update annotation manually to resolve\n' \
            "" "${_drift_ann_ver}" "${_drift_actual}"
          _drift_fired=true
        elif [[ -n "${_skip_reason}" ]]; then
          printf '%10s↳ [DRIFT] annotation says %s but VAR=%s — frozen by skip flag; update annotation manually to resolve\n' \
            "" "${_drift_ann_ver}" "${_drift_actual}"
          _drift_fired=true
        elif [[ "${_decision}" == "HOLD" ]]; then
          if [[ "${_drift_dir_downgrade}" == "true" ]]; then
            printf '%10s↳ [DRIFT] annotation says %s but VAR=%s%s\n' \
              "" "${_drift_ann_ver}" "${_drift_actual}" "${_drift_dir_msg}"
          else
            printf '%10s↳ [DRIFT] annotation says %s but VAR=%s — --force-auto --apply to resolve\n' \
              "" "${_drift_ann_ver}" "${_drift_actual}"
          fi
          _drift_fired=true
        elif [[ "${_decision}" == "MANUAL" ]]; then
          if [[ "${_drift_dir_downgrade}" == "true" ]]; then
            printf '%10s↳ [DRIFT] annotation says %s but VAR=%s%s\n' \
              "" "${_drift_ann_ver}" "${_drift_actual}" "${_drift_dir_msg}"
          else
            printf '%10s↳ [DRIFT] annotation says %s but VAR=%s — --force-auto --apply to resolve\n' \
              "" "${_drift_ann_ver}" "${_drift_actual}"
          fi
          _drift_fired=true
        elif [[ "${_decision}" == "ERROR" ]]; then
          printf '%10s↳ [DRIFT] annotation says %s but VAR=%s%s — fetch failed; fix error then re-run\n' \
            "" "${_drift_ann_ver}" "${_drift_actual}" "${_drift_dir_msg:-}"
          _drift_fired=true
        elif [[ "${_decision}" == "SKIP" && -z "${_skip_reason}" ]]; then
          printf '%10s↳ [DRIFT] annotation says %s but VAR=%s%s — update annotation or revert VAR= manually (--apply skips up-to-date records)\n' \
            "" "${_drift_ann_ver}" "${_drift_actual}" "${_drift_dir_msg:-}"
          _drift_fired=true
        else
          # AUTO, SHA — neutral fallback when non-semver (no _drift_dir_msg)
          printf '%10s↳ [DRIFT] annotation says %s but VAR=%s%s\n' \
            "" "${_drift_ann_ver}" "${_drift_actual}" "${_drift_dir_msg:- — re-run --apply or update annotation}"
          _drift_fired=true
        fi
      fi
    fi
  fi
  # Post-drift counter updates (outside the no_drift guard — _drift_fired is false when suppressed)
  if [[ "${_drift_fired}" == "true" ]]; then
    (( ++_n_drift )) || true
    if [[ "${_drift_dir_downgrade}" == "true" ]]; then
      # Count downgrade only when --apply CAN write VAR=
      # LOCK/FROZEN/SKIP/ERROR drift is informational — downgrade not actionable by --apply
      if [[ "${_decision}" != "LOCK" && -z "${_skip_reason}" \
            && "${_decision}" != "SKIP" && "${_decision}" != "ERROR" ]]; then
        if [[ "${_decision}" == "MANUAL" || "${_decision}" == "HOLD" ]]; then
          (( ++_n_downgrade_force )) || true
        else
          (( ++_n_downgrade )) || true
        fi
      fi
    elif [[ "${_decision}" == "AUTO" || "${_decision}" == "HOLD" \
            || "${_decision}" == "MANUAL" || "${_decision}" == "SHA" ]]; then
      (( ++_n_drift_fixable )) || true
    fi
  fi
  return 0
}

# _gs_eu2_signal_replace_drift — [REPLACE-DRIFT] sub-line for (replace:TARGET=template) records.
# Args: _i _decision _cur _prop _skip_reason
_gs_eu2_signal_replace_drift() {
  local _i="${1}" _decision="${2}" _cur="${3}" _prop="${4}" _skip_reason="${5}"
  if [[ "${_GS_EU2_CFG[no_drift]:-false}" != "true" && "${_decision}" != "ERROR" ]]; then
    local _rd_rep_tgts _rd_rep_tmpls
    _rd_rep_tgts="$(_gs_eu2_record_get "${_i}" replace_targets)"
    _rd_rep_tmpls="$(_gs_eu2_record_get "${_i}" replace_templates)"
    if [[ -n "${_rd_rep_tgts}" ]]; then
      local _rd_old_ifs="${IFS}"
      IFS=$'\x1f'
      local _rd_rt_arr _rd_rm_arr
      read -ra _rd_rt_arr <<< "${_rd_rep_tgts}"
      read -ra _rd_rm_arr <<< "${_rd_rep_tmpls}"
      IFS="${_rd_old_ifs}"
      local _rd_ri
      for (( _rd_ri = 0; _rd_ri < ${#_rd_rt_arr[@]}; _rd_ri++ )); do
        local _rd_rt="${_rd_rt_arr[${_rd_ri}]}"
        local _rd_rm="${_rd_rm_arr[${_rd_ri}]:-}"
        local _rd_tgt_actual _rd_exp_cur _rd_exp_prop
        _rd_tgt_actual="$(grep -m1 "^${_rd_rt}=" "${_GS_EU2_CFG[env_file]}" 2>/dev/null \
          | cut -d= -f2-)"
        _rd_exp_cur="$(_gs_eu2_expand_replace_template "${_rd_rm}" "${_cur:-}")"
        _rd_exp_prop="$(_gs_eu2_expand_replace_template "${_rd_rm}" "${_prop:-}")"
        local _rd_stale_now=false _rd_update_pending=false
        [[ "${_rd_tgt_actual}" != "${_rd_exp_cur}" ]] && _rd_stale_now=true
        [[ "${_rd_exp_cur}" != "${_rd_exp_prop}" ]] && _rd_update_pending=true

        if [[ "${_decision}" == "AUTO" || "${_decision}" == "SHA" ]]; then
          if [[ "${_rd_stale_now}" == "true" || "${_rd_update_pending}" == "true" ]]; then
            if [[ "${_rd_stale_now}" == "true" ]]; then
              printf '%10s↳ (replace) %-47s  %s → %s  [REPLACE-DRIFT]\n' \
                "" "${_rd_rt}" "${_rd_tgt_actual}" "${_rd_exp_prop}"
            else
              printf '%10s↳ (replace) %-47s  %s → %s\n' \
                "" "${_rd_rt}" "${_rd_tgt_actual}" "${_rd_exp_prop}"
            fi
          fi
        elif [[ "${_decision}" == "SKIP" && -z "${_skip_reason}" && "${_rd_stale_now}" == "true" ]]; then
          printf '%10s↳ [REPLACE-DRIFT] %s  actual=%s ≠ expected=%s — run --apply to fix\n' \
            "" "${_rd_rt}" "${_rd_tgt_actual}" "${_rd_exp_cur}"
        elif [[ ( "${_decision}" == "HOLD" || "${_decision}" == "MANUAL" ) \
                && "${_rd_stale_now}" == "true" ]]; then
          printf '%10s↳ [REPLACE-DRIFT] %s  actual=%s ≠ expected=%s — run --force-auto --apply to fix\n' \
            "" "${_rd_rt}" "${_rd_tgt_actual}" "${_rd_exp_cur}"
        elif [[ ( "${_decision}" == "HOLD" || "${_decision}" == "MANUAL" ) \
                && "${_rd_stale_now}" == "false" && "${_rd_update_pending}" == "true" ]]; then
          printf '%10s↳ (replace) %-47s  → %s  (with --force-auto --apply)\n' \
            "" "${_rd_rt}" "${_rd_exp_prop}"
        elif [[ -n "${_skip_reason}" && "${_rd_stale_now}" == "true" ]]; then
          printf '%10s↳ [REPLACE-DRIFT] %s  actual=%s ≠ expected=%s — informational only (frozen)\n' \
            "" "${_rd_rt}" "${_rd_tgt_actual}" "${_rd_exp_cur}"
        elif [[ "${_decision}" == "LOCK" && "${_rd_stale_now}" == "true" ]]; then
          printf '%10s↳ [REPLACE-DRIFT] %s  actual=%s ≠ expected=%s — informational only (locked)\n' \
            "" "${_rd_rt}" "${_rd_tgt_actual}" "${_rd_exp_cur}"
        fi

        # Per-record counters (at most once per record)
        if [[ "${_rd_stale_now}" == "true" && "${_record_replace_drift_counted}" == "false" ]]; then
          (( ++_n_replace_drift )) || true
          _record_replace_drift_counted=true
        fi
        if [[ "${_record_replace_cascade_counted}" == "false" \
              && ( "${_rd_stale_now}" == "true" || "${_rd_update_pending}" == "true" ) \
              && ( "${_decision}" == "AUTO" || "${_decision}" == "SHA" ) ]]; then
          (( ++_n_replace_cascade )) || true
          _record_replace_cascade_counted=true
        fi
      done
    fi
  fi
  return 0
}

# _gs_eu2_run_check — main check loop: fetch, classify, and stream results for all records.
#
# Args:    none
# Reads:   _GS_EU2_CFG (env_file, filter, unstable, stable, changes_only, no_drift,
#          no_notes, no_fail, format, tally, force_auto), all record arrays
# Sets:    record fields (decision, proposed_version, error_message, unstable_proposed,
#          stable_proposed) for each record; _GS_EU2_CACHE_TTL
# Prints:  per-record status lines ([AUTO], [HOLD], etc.) + sub-lines to stdout;
#          progress indicator / live tally to stderr
# Returns: 0 when no ERROR decisions; 1 when at least one ERROR decision exists
#          (caller in _gs_eu2_main captures with || _check_rc=$?)
# Side fx: fetches from external registries (unless cache hits); may write cache files;
#          arms/disarms INT+ERR traps around the loop for tally cleanup
_gs_eu2_run_check() {
  local _count _i
  _count="$(_gs_eu2_record_count)"

  # Propagate cache settings from CFG to env vars consumed by cache.sh
  _GS_EU2_CACHE_TTL="${_GS_EU2_CFG[cache_ttl]:-3600}"

  local _n_auto=0 _n_hold=0 _n_skip=0 _n_error=0 _n_manual=0 _n_sha=0 _n_lock=0 _n_frozen=0
  local _n_fallback=0 _n_watch=0 _n_drift=0 _n_drift_fixable=0 _n_downgrade=0 _n_downgrade_force=0 _n_hidden=0 _n_sha_anno=0 _n_replace_drift=0 _n_replace_cascade=0 _n_resolved=0 _n_warn_depends_on=0

  # Initialize and arm live tally (TTY-only, gate checked inside)
  _gs_eu2_tally_init
  trap '_gs_eu2_tally_cleanup' INT ERR

  # Dynamic column width: pre-scan all env_var names so the → arrow aligns
  # across every record in this run, regardless of variable name length.
  _gs_eu2_check_prescan_width "${_count}"
  local _max_var_len="${_GS_EU2_MAX_VAR_LEN}"

  # ── Parallel fan-out ─────────────────────────────────────────────────────
  # When --jobs > 1 and profile is off: spawn _count background workers (capped
  # at --jobs concurrent), each running _gs_eu2_fetch_one_worker into a per-index
  # result file.  The collect loop below then sources these files instead of
  # dispatching fetchers directly.
  # --profile forces serial mode: per-record timing arrays cannot propagate from
  # subshells back to the parent.
  local _par_mode="false"
  local _par_tmpdir=""
  local _par_jobs
  _par_jobs="${_GS_EU2_CFG[jobs]:-8}"
  declare -A _par_pids=()

  if (( _par_jobs > 1 )) && [[ "${_GS_EU2_CFG[profile]:-false}" != "true" ]]; then
    _par_mode="true"
    _par_tmpdir="$(mktemp -d)"
    # Extend INT trap: kill all background workers and clean up tmpdir.
    # shellcheck disable=SC2064
    trap "kill \$(printf '%s ' \"\${_par_pids[@]:-}\") 2>/dev/null || true; rm -rf '${_par_tmpdir}' 2>/dev/null || true; _gs_eu2_tally_cleanup" INT

    printf '\r  fetching %d records (%d parallel workers)...' "${_count}" "${_par_jobs}" >&2

    local _par_active=0
    for (( _i = 0; _i < _count; _i++ )); do
      if (( _par_active >= _par_jobs )); then
        wait -n 2>/dev/null || true
        (( _par_active-- )) || true
      fi
      ( _gs_eu2_fetch_one_worker "${_i}" "${_par_tmpdir}" ) &
      _par_pids[${_i}]=$!
      (( _par_active++ )) || true
    done
    # Wait for all remaining workers; || true prevents set -e propagation on
    # non-zero worker exit codes (worker failures are handled via missing result file).
    for (( _i = 0; _i < _count; _i++ )); do
      wait "${_par_pids[${_i}]:-}" 2>/dev/null || true
    done

    # Clear the fan-out progress line so collect output begins cleanly.
    printf '\r%*s\r' "$(( _max_var_len + 40 ))" "" >&2
  fi

  for (( _i = 0; _i < _count; _i++ )); do
    local _env_var
    _env_var="$(_gs_eu2_record_get "${_i}" env_var)"

    # Progress indicator: live tally when tally is active; fallback single-line \r when not.
    # In parallel collect mode (fetching already done) the tally still draws correctly —
    # the "fetching VARNAME..." hint is cosmetically stale but harmless; counters are accurate.
    if [[ "${_GS_EU2_TALLY_ACTIVE}" == "1" ]]; then
      _GS_EU2_TALLY_IDX="${_i}"
      _GS_EU2_TALLY_COUNT="${_count}"
      _GS_EU2_TALLY_VARNAME="${_env_var}"
      _GS_EU2_TALLY_N_AUTO="${_n_auto}"
      _GS_EU2_TALLY_N_HOLD="${_n_hold}"
      _GS_EU2_TALLY_N_SKIP="${_n_skip}"
      _GS_EU2_TALLY_N_ERROR="${_n_error}"
      _GS_EU2_TALLY_N_MANUAL="${_n_manual}"
      _GS_EU2_TALLY_N_SHA="${_n_sha}"
      _GS_EU2_TALLY_N_LOCK="${_n_lock}"
      _GS_EU2_TALLY_N_FROZEN="${_n_frozen}"
      _GS_EU2_TALLY_N_FALLBACK="${_n_fallback}"
      _GS_EU2_TALLY_N_WATCH="${_n_watch}"
      _GS_EU2_TALLY_N_DRIFT="${_n_drift}"
      _GS_EU2_TALLY_N_DRIFT_FIXABLE="${_n_drift_fixable}"
      _GS_EU2_TALLY_N_DOWNGRADE="${_n_downgrade}"
      _GS_EU2_TALLY_N_DOWNGRADE_FORCE="${_n_downgrade_force}"
      _GS_EU2_TALLY_N_HIDDEN="${_n_hidden}"
      _GS_EU2_TALLY_N_SHA_ANNO="${_n_sha_anno}"
      _GS_EU2_TALLY_N_REPLACE_DRIFT="${_n_replace_drift}"
      _GS_EU2_TALLY_N_REPLACE_CASCADE="${_n_replace_cascade}"
      _GS_EU2_TALLY_N_RESOLVED="${_n_resolved}"
      _gs_eu2_tally_draw
    else
      printf '\r  [%d/%d] fetching %-55s' \
        "$(( _i + 1 ))" "${_count}" "${_env_var:0:55}" >&2
    fi

    # ── Fetch or load: skip gate + dispatch + second passes ─────────────────
    # Parallel mode: results are already in the tmpdir from the fan-out phase;
    # source the per-index file to load them into the parent's record variables.
    # Serial mode: run skip gate + dispatch + second passes inline as before.
    if [[ "${_par_mode}" == "true" ]]; then
      if [[ -f "${_par_tmpdir}/${_i}.env" ]]; then
        # shellcheck disable=SC1090
        source "${_par_tmpdir}/${_i}.env"
      else
        _gs_eu2_record_set "${_i}" decision      "ERROR"
        _gs_eu2_record_set "${_i}" error_message "worker process died unexpectedly"
      fi
    else
    # Skip gate: (skip:REASON) annotation forces SKIP before any fetch.
    # Sets decision + error_message on the record; display code below handles output.
    local _skip_reason
    _skip_reason="$(_gs_eu2_record_get "${_i}" skip_reason)"
    if [[ -n "${_skip_reason}" ]]; then
      _gs_eu2_record_set "${_i}" decision      "SKIP"
      _gs_eu2_record_set "${_i}" error_message "skip flag: ${_skip_reason}"
    fi

    # Skip gate fires: bypass all fetcher dispatch and second-pass blocks.
    # The record already has decision=SKIP and error_message set; display code below handles output.
    if [[ -z "${_skip_reason}" ]]; then
      # I2: dispatch via helper — all 12 fetcher types handled in _gs_eu2_dispatch_fetcher
      _gs_eu2_dispatch_fetcher "${_i}"

    # Second passes: unstable=info and stable=info.
    # Delegated to shared helper in core/passes.sh.
    _gs_eu2_run_second_passes "${_i}"
    fi  # end: if [[ -z "${_skip_reason}" ]] (skip gate — bypass all fetcher dispatch)
    fi  # end: serial mode fetch

    # Always read skip_reason after fetch/load so display code below can use it in both modes.
    # In serial mode it was set inside the else block; in parallel mode it wasn't — read it now.
    local _skip_reason
    _skip_reason="$(_gs_eu2_record_get "${_i}" skip_reason)"

    # ── Classify: decision classifier + lock gate + SHA + skip annotations ──
    # _gs_eu2_classify_record refines the fetcher's AUTO decision and applies all
    # annotation-based overrides (force_auto, lock gate, SHA upgrade, skip annotations).
    # After this call the record's "decision" field is final.
    _gs_eu2_classify_record "${_i}"

    # Read fields needed for display — classification is complete at this point.
    local _cur _prop _override _manual _major _major_min _note _lock_reason
    _cur="$(_gs_eu2_record_get "${_i}" current_version)"
    _prop="$(_gs_eu2_record_get "${_i}" proposed_version)"
    _override="$(_gs_eu2_record_get "${_i}" override)"
    _manual="$(_gs_eu2_record_get "${_i}" manual)"
    _major="$(_gs_eu2_record_get "${_i}" major_hint)"
    _major_min="$(_gs_eu2_record_get "${_i}" major_hint_min)"
    _note="$(_gs_eu2_record_get "${_i}" note)"
    _lock_reason="$(_gs_eu2_record_get "${_i}" lock_reason)"

    # Stream this record immediately — don't buffer until all fetches complete
    local _decision _err _tag _change _reason
    _decision="$(_gs_eu2_record_get "${_i}" decision)"
    _err="$(_gs_eu2_record_get "${_i}" error_message)"

    # Float + (watch-major) guard: detect BEFORE display so the primary decision
    # line shows [ERROR], not [RESOLVE] or [AUTO]. When current is a floating alias
    # (latest/stable/lts/…), _gs_eu2_version_prefix returns empty and watch-major
    # depth comparison is undefined. Override decision to ERROR at check time.
    if [[ "${_decision}" != "ERROR" ]]; then
      local _pre_wm_depth
      _pre_wm_depth="$(_gs_eu2_record_get "${_i}" watch_major_depth)"
      if [[ -n "${_pre_wm_depth}" ]] && _gs_eu2_is_unversioned "${_cur}"; then
        local _wm_err_msg="(watch-major) with floating current version '${_cur}' is undefined — pin the current version first"
        _gs_eu2_record_set "${_i}" error_message "${_wm_err_msg}"
        _gs_eu2_record_set "${_i}" decision "ERROR"
        _decision="ERROR"
        _err="${_wm_err_msg}"
      fi
    fi

    case "${_decision}" in
      AUTO)   _tag="[AUTO   ]"; (( ++_n_auto ))   || true ;;
      HOLD)   _tag="[HOLD   ]"; (( ++_n_hold ))   || true ;;
      SKIP)
        # skip-gate SKIP (skip:REASON annotation): display as [FROZEN], separate counter
        if [[ -n "${_skip_reason}" ]]; then
          _tag="[FROZEN ]"; (( ++_n_frozen )) || true
        else
          _tag="[SKIP   ]"; (( ++_n_skip ))  || true
        fi
        ;;
      ERROR)  _tag="[ERROR  ]"; (( ++_n_error ))  || true ;;
      MANUAL) _tag="[MANUAL ]"; (( ++_n_manual )) || true ;;
      SHA)    _tag="[SHA    ]"; (( ++_n_sha ))    || true ;;
      LOCK)     _tag="[LOCK   ]"; (( ++_n_lock ))     || true ;;
      RESOLVED) _tag="[RESOLVE]"; (( ++_n_resolved )) || true ;;
      *)        _tag="[SKIP   ]"; (( ++_n_skip ))     || true ;;
    esac

    # ── Reason label + change string ─────────────────────────────────────────
    # _gs_eu2_compute_reason_label: HOLD/MANUAL/LOCK reason suffix (e.g. "← major pin")
    # _gs_eu2_compute_change_string: full inline change text (e.g. "1.2.0 → 1.3.0 ← major pin")
    local _reason _change
    _reason="$(_gs_eu2_compute_reason_label "${_i}" "${_decision}" "${_cur}" "${_prop}" "${_major}" "${_lock_reason}")"
    _change="$(_gs_eu2_compute_change_string "${_i}" "${_decision}" "${_cur}" "${_prop}" "${_err}" "${_manual}" "${_override}" "${_reason}")"

    # ── Changes-only hide gate ────────────────────────────────────────────────
    # _gs_eu2_should_hide_record returns 0 (hide) when --changes-only is active and the
    # record is a purely up-to-date SKIP with no signals (WATCH/FALLBACK/DRIFT/etc.).
    # The _n_hidden counter and the `continue` statement remain here — the predicate
    # function cannot `continue` in the caller's loop.
    if _gs_eu2_should_hide_record "${_i}" "${_decision}" "${_err}" "${_skip_reason}" "${_major}" "${_cur}"; then
      (( ++_n_hidden )) || true
      if [[ "${_GS_EU2_TALLY_ACTIVE}" != "1" ]]; then
        printf '\r%*s\r' "$(( _max_var_len + 20 ))" "" >&2
      fi
      continue
    fi

    # Clear the progress line then emit the primary result line + all sub-lines.
    # Width: tag(8) + 2 spaces + var field + some margin for change text
    if [[ "${_GS_EU2_TALLY_ACTIVE}" == "1" ]]; then
      _gs_eu2_tally_erase
    else
      printf '\r%*s\r' "$(( _max_var_len + 20 ))" "" >&2
    fi

    # Primary decision line + optional note sub-line
    _gs_eu2_signal_primary_line "${_tag}" "${_max_var_len}" "${_env_var}" "${_change}" "${_note}"

    # [FALLBACK] sub-line
    _gs_eu2_signal_fallback "${_i}" "${_major}" "${_major_min}"

    # [PIN-MISS] sub-line
    local _skip_err_disp
    _skip_err_disp="$(_gs_eu2_record_get "${_i}" error_message)"
    _gs_eu2_signal_pin_miss "${_i}" "${_decision}" "${_major}" "${_skip_err_disp}"

    # [WATCH] sub-line (Float + watch-major guard handled above before the case block)
    _gs_eu2_signal_watch "${_i}" "${_decision}" "${_cur}" "${_prop}"

    # SHA sub-line + +sha counter
    _gs_eu2_signal_sha "${_i}" "${_decision}"

    # [UNSTABLE] info sub-line
    _gs_eu2_signal_unstable "${_i}" "${_cur}"

    # [STABLE] info sub-line
    _gs_eu2_signal_stable "${_i}" "${_cur}"

    # [WARN] depends-on safety warning
    _gs_eu2_signal_depends_on "${_i}"

    # [DRIFT] sub-line + post-drift counter updates
    # _drift_fired and _drift_dir_downgrade are set by the sub-function via dynamic scope
    local _drift_fired=false _drift_dir_downgrade=false
    _gs_eu2_signal_drift "${_i}" "${_decision}" "${_cur}" "${_prop}" "${_skip_reason}"

    # [REPLACE-DRIFT] sub-line + per-record replace counters
    # _record_replace_drift_counted and _record_replace_cascade_counted set via dynamic scope
    local _record_replace_drift_counted=false
    local _record_replace_cascade_counted=false
    _gs_eu2_signal_replace_drift "${_i}" "${_decision}" "${_cur}" "${_prop}" "${_skip_reason}"
  done

  # Clean up parallel tmpdir (no-op in serial mode where _par_tmpdir is empty)
  [[ -n "${_par_tmpdir:-}" ]] && rm -rf "${_par_tmpdir}" 2>/dev/null || true

  # Disarm tally traps and erase live tally block before printing static summary
  trap - INT ERR
  _gs_eu2_tally_erase

  # ── Summary ───────────────────────────────────────────────────────────────
  _gs_eu2_print_check_summary \
    "${_n_auto}" "${_n_hold}" "${_n_skip}" "${_n_error}" \
    "${_n_manual}" "${_n_sha}" "${_n_lock}" "${_n_frozen}" \
    "${_n_fallback}" "${_n_watch}" "${_n_drift}" "${_n_drift_fixable}" \
    "${_n_downgrade}" "${_n_downgrade_force}" "${_n_hidden}" \
    "${_n_sha_anno}" "${_n_replace_drift}" "${_n_replace_cascade}" \
    "${_n_resolved}" "${_n_warn_depends_on}"

  # Exit non-zero when any ERROR decisions were recorded — callers can detect fetch failures.
  (( _n_error > 0 )) && return 1 || return 0
}

# _gs_eu2_count_apply_candidates — count records that would be written by --apply.
#
# Args:    none (reads record state set by _gs_eu2_run_check)
# Reads:   all record decision, current_version, proposed_version, annotation_sha,
#          proposed_sha, skip_reason, use_sha fields; _GS_EU2_CFG[apply_resolve]
# Prints:  integer N to stdout
# Returns: 0 always
# Side fx: none
#
# Uses the same predicates as _gs_eu2_apply_updates (apply.sh) so the count
# displayed in the confirmation prompt equals the number of writes that follow.
# AUTO: writes when prop != cur (and prop is non-empty).
# SHA:  writes annotation sha (and optionally VAR=) when sha tokens differ.
# LOCK: writes annotation when prop != cur and current is not unversioned.
# RESOLVED: writes when --apply-resolve active and prop != cur.
_gs_eu2_count_apply_candidates() {
  local _n=0
  local _cac_count _cac_i _cac_decision _cac_cur _cac_prop _cac_ann_sha _cac_new_sha
  _cac_count="$(_gs_eu2_record_count)"
  for (( _cac_i = 0; _cac_i < _cac_count; _cac_i++ )); do
    _cac_decision="$(_gs_eu2_record_get "${_cac_i}" decision)"
    case "${_cac_decision}" in
      AUTO)
        _cac_cur="$(_gs_eu2_record_get "${_cac_i}" current_version)"
        _cac_prop="$(_gs_eu2_record_get "${_cac_i}" proposed_version)"
        [[ -n "${_cac_prop}" && "${_cac_prop}" != "${_cac_cur}" ]] && (( _n++ )) || true
        ;;
      SHA)
        (( _n++ )) || true
        ;;
      LOCK)
        _cac_cur="$(_gs_eu2_record_get "${_cac_i}" current_version)"
        _cac_prop="$(_gs_eu2_record_get "${_cac_i}" proposed_version)"
        if [[ -n "${_cac_prop}" && "${_cac_prop}" != "${_cac_cur}" ]] && \
           ! _gs_eu2_is_unversioned "${_cac_cur}"; then
          (( _n++ )) || true
        fi
        ;;
      RESOLVED)
        if [[ "${_GS_EU2_CFG[apply_resolve]:-false}" == "true" ]]; then
          _cac_cur="$(_gs_eu2_record_get "${_cac_i}" current_version)"
          _cac_prop="$(_gs_eu2_record_get "${_cac_i}" proposed_version)"
          [[ -n "${_cac_prop}" && "${_cac_prop}" != "${_cac_cur}" ]] && (( _n++ )) || true
        fi
        ;;
    esac
  done
  printf '%d' "${_n}"
}

# _gs_eu2_confirm_apply — interactive confirmation gate for --apply writes.
#
# Args:    $1 n_candidates — number of changes that will be written (for display)
# Reads:   _GS_EU2_CFG[yes] — when "true", skip prompt and proceed immediately
# Prints:  prompt to stderr (TTY path); error message to stderr (non-TTY / rejected)
# Returns: 0 (proceed) | exits 1 (user declined or non-TTY without --yes)
# Side fx: reads one line from stdin when on a TTY
#
# Gate logic:
#   --yes=true         → proceed immediately (scripting / Claude use)
#   stdin not a TTY    → exit 1 with clear error (require --yes for non-interactive use)
#   TTY, user enters y/Y → proceed (return 0)
#   TTY, any other input → exit 1
_gs_eu2_confirm_apply() {
  local _n_cand="${1:-0}"
  if [[ "${_GS_EU2_CFG[yes]:-false}" == "true" ]]; then
    return 0
  fi
  if [[ ! -t 0 && "${_GS_EU2_APPLY_GATE_FORCE_TTY:-false}" != "true" ]]; then
    printf 'env-update: --apply requires --yes in non-interactive mode (no TTY detected).\n' >&2
    printf '  Run with --yes to bypass this gate, or use --dry-run to preview without writing.\n' >&2
    exit 1
  fi
  # TTY path: ask the user
  local _reply
  printf '\nApply %d change(s)? [y/N]: ' "${_n_cand}" >&2
  read -r _reply || _reply=""
  if [[ "${_reply}" =~ ^[Yy]$ ]]; then
    return 0
  fi
  printf 'Aborted.\n' >&2
  exit 1
}

# _gs_eu2_main — top-level entry point: parse args, validate, orchestrate check/dump/apply.
#
# Args:    "$@" — all CLI arguments forwarded from bin/env-update.sh
# Reads:   _GS_EU2_CFG (all fields, populated by _gs_eu2_parse_args)
# Sets:    _GS_EU2_CFG[check]="true" when --apply is set (apply implies check)
# Prints:  mode banners + check/dump/apply output to stdout; warnings to stderr
# Returns: 0 on success; 1 on usage error or when ERROR decisions present
#          (propagated via the || exit $? pattern in bin/env-update.sh)
# Side fx: may write .env backup files; may invoke env-scan.sh (--scan)
_gs_eu2_main() {
  _gs_eu2_profile_init   # records total start time before we know --profile value
  _gs_eu2_profile_start
  _gs_eu2_parse_args "${@}"
  _gs_eu2_profile_end "Parse args"

  # --reference: print comprehensive reference and exit (before any env file access)
  if [[ "${_GS_EU2_CFG[reference]:-false}" == "true" ]]; then
    _gs_eu2_show_reference "${_GS_EU2_CFG[reference_section]:-all}"
    exit 0
  fi

  if [[ "${_GS_EU2_CFG[dump]}" == "true" && \
        ( "${_GS_EU2_CFG[check]}" == "true" || "${_GS_EU2_CFG[apply]}" == "true" ) ]]; then
    printf 'env-update: --dump is mutually exclusive with --check and --apply\n' >&2
    exit 1
  fi

  # --apply implies --check
  [[ "${_GS_EU2_CFG[apply]}" == "true" ]] && _GS_EU2_CFG[check]="true"

  local _env_file="${_GS_EU2_CFG[env_file]}"
  if [[ ! -f "${_env_file}" ]]; then
    printf 'env-update: env file not found: %s\n' "${_env_file}" >&2
    exit 1
  fi

  _gs_eu2_profile_start
  _gs_eu2_parse_env_file "${_env_file}" "${_GS_EU2_CFG[filter]}" "${_GS_EU2_CFG[exclude]}"
  _gs_eu2_profile_end "Parse env file"

  # --unstable full: inject channel=unstable on records that don't already have it.
  # This causes fetchers to return the highest prerelease as proposed_version, and
  # classify_decision will promote stable→prerelease to AUTO (prerelease guard bypassed).
  # Note: --unstable=info does NOT inject here — it does a separate second-pass fetch
  # after each record to populate unstable_proposed without touching the main decision.
  local _unstable_overrides=0
  if [[ "${_GS_EU2_CFG[unstable]:-}" == "full" ]]; then
    local _uc _ucount
    _ucount="$(_gs_eu2_record_count)"
    for (( _uc = 0; _uc < _ucount; _uc++ )); do
      local _existing_channel
      _existing_channel="$(_gs_eu2_record_get "${_uc}" channel)"
      if [[ -z "${_existing_channel}" || "${_existing_channel}" == "stable" ]]; then
        _gs_eu2_record_set "${_uc}" channel "unstable"
        (( _unstable_overrides++ )) || true
      fi
    done
  fi

  # --stable: force channel=stable on all records that have an explicit non-stable channel.
  # Overrides channel:rc, channel:beta, channel:alpha, channel:nightly, channel:unstable, etc.
  # Records already at channel="" or channel="stable" are untouched.
  # Emits a per-record warning when an annotated channel is suppressed (annotation intent overridden).
  local _stable_overrides=0
  if [[ "${_GS_EU2_CFG[stable]:-}" == "full" ]]; then
    local _sc _scount
    _scount="$(_gs_eu2_record_count)"
    for (( _sc = 0; _sc < _scount; _sc++ )); do
      local _existing_sc_channel
      _existing_sc_channel="$(_gs_eu2_record_get "${_sc}" channel)"
      if [[ -n "${_existing_sc_channel}" && "${_existing_sc_channel}" != "stable" ]]; then
        local _sc_varname
        _sc_varname="$(_gs_eu2_record_get "${_sc}" env_var)"
        printf '[STABLE MODE] WARNING: overriding (channel:%s) on %s — annotation intent suppressed by --stable=full\n' \
          "${_existing_sc_channel}" "${_sc_varname}" >&2
        _gs_eu2_record_set "${_sc}" channel "stable"
        (( _stable_overrides++ )) || true
      fi
    done
  fi

  # Mode banners always go to stderr — this ensures --format=json output is clean JSON on
  # stdout, parseable directly by jq. Tests that grep for banners use 2>&1 so they still work.
  if [[ "${_GS_EU2_CFG[dry_run]:-false}" == "true" ]]; then
    printf '[DRY-RUN MODE] no writes — cache, .env, and Dockerfile propagation suppressed\n' >&2
  fi
  if [[ "${_GS_EU2_CFG[unstable]:-}" == "full" ]]; then
    printf '[UNSTABLE MODE] channel forced unstable for %d record(s)\n' "${_unstable_overrides}" >&2
  fi
  if [[ "${_GS_EU2_CFG[stable]:-}" == "full" ]]; then
    printf '[STABLE MODE] channel forced stable for %d record(s)\n' "${_stable_overrides}" >&2
  fi
  if [[ "${_GS_EU2_CFG[force_auto]:-false}" == "true" ]]; then
    printf '[FORCE-AUTO MODE] (manual) and (override) gates bypassed\n' >&2
  fi
  if [[ "${_GS_EU2_CFG[force_hold]:-false}" == "true" ]]; then
    printf '[FORCE-HOLD MODE] HOLD decisions upgraded to AUTO (MANUAL/OVERRIDE unaffected)\n' >&2
  fi
  if [[ "${_GS_EU2_CFG[no_notes]:-false}" == "true" ]]; then
    local _nn_count _nn_i _nn_total
    _nn_total="$(_gs_eu2_record_count)"
    _nn_count=0
    for (( _nn_i = 0; _nn_i < _nn_total; _nn_i++ )); do
      local _nn_note
      _nn_note="$(_gs_eu2_record_get "${_nn_i}" note)"
      [[ -n "${_nn_note}" ]] && (( _nn_count++ )) || true
    done
    printf '[NO-NOTES MODE] note sub-lines suppressed for %d record(s)\n' "${_nn_count}" >&2
  fi
  if [[ "${_GS_EU2_CFG[no_cache]:-false}" == "true" ]]; then
    printf '[NO-CACHE MODE] cache bypassed — all fetches hit network\n' >&2
  fi
  if [[ "${_GS_EU2_CFG[with_tags]:-false}" == "true" ]]; then
    printf '[WITH-TAGS MODE] tags API merged for all github records\n' >&2
  fi
  if [[ -n "${_GS_EU2_CFG[filter]:-}" ]]; then
    printf '[FILTER MODE: %s]\n' "${_GS_EU2_CFG[filter]}" >&2
  fi
  if [[ -n "${_GS_EU2_CFG[exclude]:-}" ]]; then
    printf '[EXCLUDE MODE: %s]\n' "${_GS_EU2_CFG[exclude]}" >&2
  fi
  if [[ "${_GS_EU2_CFG[no_drift]:-false}" == "true" ]]; then
    printf '[NO-DRIFT MODE] drift sub-lines and drift/downgrade secondary counters suppressed\n' >&2
  fi
  if [[ "${_GS_EU2_CFG[changes_only]:-false}" == "true" ]]; then
    printf '[CHANGES-ONLY MODE] purely up-to-date SKIP records suppressed from output\n' >&2
  fi
  if [[ "${_GS_EU2_CFG[no_fail]:-false}" == "true" ]]; then
    printf '[NO-FAIL MODE] ERROR decisions will not abort — exit code forced to 0\n' >&2
  fi
  # Backup banners — only relevant when --apply is active and not --dry-run
  if [[ "${_GS_EU2_CFG[apply]:-false}" == "true" && "${_GS_EU2_CFG[dry_run]:-false}" != "true" ]]; then
    if [[ "${_GS_EU2_CFG[backup]:-true}" == "false" ]]; then
      printf '[NO-BACKUP MODE] backup skipped — env file will be modified without a backup\n' >&2
    fi
    if [[ "${_GS_EU2_CFG[backup_purge]:-false}" == "true" ]]; then
      printf '[BACKUP-PURGE MODE] existing backups will be deleted before creating new backup\n' >&2
    fi
  fi
  # --scan requires --apply to take effect: env-scan only runs after env file is written.
  if [[ "${_GS_EU2_CFG[scan]:-false}" == "true" && "${_GS_EU2_CFG[apply]:-false}" != "true" ]]; then
    printf 'FATAL: --scan requires --apply — env-scan only runs after the env file is rewritten\n' >&2
    printf '  did you mean: --apply --scan?\n' >&2
    exit 1
  fi

  if [[ "true" == "${_GS_EU2_CFG[dump]}" ]]; then
    _gs_eu2_dump_records "${_GS_EU2_CFG[format]}"
  elif [[ "true" == "${_GS_EU2_CFG[check]}" ]]; then
    local _check_rc=0
    _gs_eu2_profile_start
    _gs_eu2_run_check || _check_rc=$?
    _gs_eu2_profile_end "Fetch + classify"

    if [[ "${_GS_EU2_CFG[apply]}" == "true" ]]; then
      printf '\n'
      {
        # ── Confirmation gate ────────────────────────────────────────────────
        # Interactive: prompt on TTY; require --yes in non-interactive (no TTY) mode.
        local _n_cand
        _n_cand="$(_gs_eu2_count_apply_candidates)"
        _gs_eu2_confirm_apply "${_n_cand}"

        # ── Configurable backup (A2) ────────────────────────────────────────
        local _bk_suffix="${_GS_EU2_CFG[backup_suffix]:-.bak}"
        local _bk_keep="${_GS_EU2_CFG[backup_keep]:-10}"
        local _bk_purge="${_GS_EU2_CFG[backup_purge]:-false}"
        local _bk_enabled="${_GS_EU2_CFG[backup]:-true}"

        if [[ "${_bk_enabled}" == "true" ]]; then
          # Step 1: purge existing backups if requested
          if [[ "${_bk_purge}" == "true" ]]; then
            while IFS= read -r _old_bak; do
              [[ -f "${_old_bak}" ]] && rm -f "${_old_bak}"
            done < <(find "$(dirname "${_env_file}")" -maxdepth 1 \
              -name "$(basename "${_env_file}")${_bk_suffix}.*" -type f 2>/dev/null | sort)
          fi
          # Step 2: create new timestamped backup
          local _backup_ts
          _backup_ts="$(date +%Y%m%d-%H%M%S)-$$"
          local _backup="${_env_file}${_bk_suffix}.${_backup_ts}"
          if ! cp -a "${_env_file}" "${_backup}"; then
            printf 'env-update: backup failed (%s) — aborting apply to protect source file\n' "${_backup}" >&2
            return 1
          fi
          printf 'Backup: %s\n' "${_backup}" >&2
        fi

        _gs_eu2_profile_start
        _gs_eu2_apply_updates "${_env_file}" "false"
        _gs_eu2_profile_end "Apply"

        # Step 3: retention prune (keep N newest backups; 0 = unlimited)
        if [[ "${_bk_enabled}" == "true" && "${_bk_keep}" -gt 0 ]]; then
          local -a _all_baks=()
          mapfile -t _all_baks < <(find "$(dirname "${_env_file}")" -maxdepth 1 \
            -name "$(basename "${_env_file}")${_bk_suffix}.*" -type f 2>/dev/null | sort)
          local _bk_total="${#_all_baks[@]}"
          if [[ "${_bk_total}" -gt "${_bk_keep}" ]]; then
            local _bk_remove=$(( _bk_total - _bk_keep ))
            local _bk_i
            for (( _bk_i = 0; _bk_i < _bk_remove; _bk_i++ )); do
              rm -f "${_all_baks[${_bk_i}]}"
            done
          fi
        fi

        if [[ "${_GS_EU2_CFG[scan]}" == "true" ]]; then
          local _env_scan
          # _GS_EU2_ENV_SCAN_PATH overrides the default path (used in tests to inject a mock)
          if [[ -n "${_GS_EU2_ENV_SCAN_PATH:-}" ]]; then
            _env_scan="${_GS_EU2_ENV_SCAN_PATH}"
          else
            _env_scan="$(dirname "${BASH_SOURCE[0]}")/../../env-scan.sh"
          fi
          if [[ -x "${_env_scan}" ]]; then
            printf 'Running env-scan.sh to propagate changes...\n' >&2
            local _scan_flags=()
            # Always pass --yes: user already confirmed at env-update's gate above,
            # so env-scan's TTY prompt would be a double-prompt. Pre-authorize it.
            _scan_flags+=("--yes")
            [[ "${_GS_EU2_CFG[no_fail]:-false}" == "true" ]]        && _scan_flags+=("--no-fail")
            [[ "${_GS_EU2_CFG[backup]:-true}" == "false" ]]         && _scan_flags+=("--backup=false")
            [[ "${_GS_EU2_CFG[backup_purge]:-false}" == "true" ]]   && _scan_flags+=("--backup-purge=true")
            [[ -n "${_GS_EU2_CFG[backup_suffix]:-}" && "${_GS_EU2_CFG[backup_suffix]}" != ".bak" ]] \
              && _scan_flags+=("--backup-suffix=${_GS_EU2_CFG[backup_suffix]}")
            [[ -n "${_GS_EU2_CFG[backup_keep]:-}" && "${_GS_EU2_CFG[backup_keep]}" != "10" ]] \
              && _scan_flags+=("--backup-keep=${_GS_EU2_CFG[backup_keep]}")
            [[ "${_GS_EU2_CFG[profile]:-false}" == "true" ]] && _scan_flags+=("--profile=true")
            _gs_eu2_profile_start
            bash "${_env_scan}" "${_scan_flags[@]}" 2>&1 || printf 'WARNING: env-scan failed — .env updated but .env.local and Dockerfiles may be stale. Run bin/env-scan.sh manually.\n' >&2
            _gs_eu2_profile_end "env-scan"
          else
            printf 'WARNING: --scan requested but env-scan.sh not found at %s\n' "${_env_scan}" >&2
          fi
        else
          printf 'Tip: run bin/env-scan.sh to propagate to .env.local and Dockerfiles (or pass --scan)\n' >&2
        fi

        # Warn when --apply skipped RESOLVED records (require --apply-resolve to pin them)
        if [[ "${_GS_EU2_CFG[apply_resolve]:-false}" != "true" ]]; then
          local _n_resolved_skipped=0
          local _ri
          for (( _ri=0; _ri<"$(_gs_eu2_record_count)"; _ri++ )); do
            [[ "$(_gs_eu2_record_get "${_ri}" decision)" == "RESOLVED" ]] && (( ++_n_resolved_skipped )) || true
          done
          if [[ "${_n_resolved_skipped}" -gt 0 ]]; then
            printf '  ↳ %d RESOLVED record(s) skipped — use --apply --apply-resolve to pin floating references\n' \
              "${_n_resolved_skipped}" >&2
          fi
        fi
      }
    fi
    # --no-fail: suppress non-zero exit from ERROR fetch decisions.
    # Usage errors (args.sh exit 1), backup failures, and env-file errors are unaffected
    # because they return/exit before reaching this point.
    if [[ "${_check_rc}" -ne 0 && "${_GS_EU2_CFG[no_fail]:-false}" == "true" ]]; then
      _check_rc=0
    fi
    # ── Print profile report if requested ─────────────────────────────────────
    [[ "true" == "${_GS_EU2_CFG[profile]}" ]] && _gs_eu2_profile_report
    # Propagate non-zero return from _gs_eu2_run_check (errors present) without
    # triggering the ERR trap — the error was already reported in the output.
    return "${_check_rc}"
  else
    _gs_eu2_print_summary "${_env_file}"
  fi
}
