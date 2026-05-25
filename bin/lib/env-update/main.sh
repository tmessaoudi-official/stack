#!/bin/bash
# main.sh — top-level orchestrator for env-update: wires all library modules,
#           defines the tally display subsystem, the check loop, and _gs_eu2_main.
#
# Exports:   _gs_eu2_main  _gs_eu2_dispatch_fetcher
#            _gs_eu2_tally_init  _gs_eu2_tally_draw  _gs_eu2_tally_erase
#            _gs_eu2_tally_cleanup  _gs_eu2_run_check
# Sources:   all sub-libraries under config/, core/, fetchers/, http/, reporting/
# Deps:      bash 4.3+, tput (for terminal width detection)
# Env:       _GS_EU2_CFG (associative array), _GS_EU2_TALLY_* (module-level state),
#            _GS_EU2_TALLY_FORCE=1 (test hook: bypass TTY gate for tally)
#            _GS_EU2_ENV_SCAN_PATH (test hook: override env-scan.sh path for --scan)
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

# _gs_eu2_dispatch_fetcher — route a record to its type-specific fetcher function.
#
# Args:    $1 record_index — 0-based index into the parallel record arrays
# Reads:   record field "type" (set by parse.sh from @todo annotation)
# Sets:    record fields "decision", "proposed_version", "error_message" (via fetcher)
# Prints:  nothing
# Returns: 0 always (unknown types set decision=SKIP rather than returning non-zero)
# Side fx: may write to cache directory (TTL-based HTTP response caching)
#
# Note: this DRY helper (I2) replaces three identical 11-fetcher case blocks
# that previously appeared separately in run_check, unstable-info second-pass,
# and stable-info second-pass.
_gs_eu2_dispatch_fetcher() {
  local _df_i="${1}"
  local _df_type
  _df_type="$(_gs_eu2_record_get "${_df_i}" type)"
  case "${_df_type}" in
    codeberg)   _gs_eu2_fetch_codeberg   "${_df_i}" ;;
    dockerhub)  _gs_eu2_fetch_dockerhub  "${_df_i}" ;;
    github)     _gs_eu2_fetch_github     "${_df_i}" ;;
    quay)       _gs_eu2_fetch_quay       "${_df_i}" ;;
    npm)        _gs_eu2_fetch_npm        "${_df_i}" ;;
    pypi)       _gs_eu2_fetch_pypi       "${_df_i}" ;;
    rubygems)   _gs_eu2_fetch_rubygems   "${_df_i}" ;;
    sdkman)     _gs_eu2_fetch_sdkman     "${_df_i}" ;;
    sdkmanager) _gs_eu2_fetch_sdkmanager "${_df_i}" ;;
    pecl)       _gs_eu2_fetch_pecl       "${_df_i}" ;;
    url)        _gs_eu2_fetch_url        "${_df_i}" ;;
    *)
      _gs_eu2_record_set "${_df_i}" decision      "SKIP"
      _gs_eu2_record_set "${_df_i}" error_message "unknown fetcher type '${_df_type}' — check annotation syntax"
      ;;
  esac
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
  local _max_var_len=40
  local _vl _j _vname _tmpval
  for (( _j = 0; _j < _count; _j++ )); do
    _vname="_GS_EU2_REC_${_j}_env_var"
    _tmpval="${!_vname:-}"
    _vl="${#_tmpval}"
    (( _vl > _max_var_len )) && _max_var_len="${_vl}"
  done

  for (( _i = 0; _i < _count; _i++ )); do
    local _env_var
    _env_var="$(_gs_eu2_record_get "${_i}" env_var)"

    # Progress indicator: live tally when tally is active; fallback single-line \r when not
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
      # I2: dispatch via helper — all 11 fetcher types handled in _gs_eu2_dispatch_fetcher
      _gs_eu2_dispatch_fetcher "${_i}"

    # --unstable=info second-pass: temporarily swap channel→unstable, re-run the
    # same fetcher (cache hit — no extra HTTP), capture proposed as unstable_proposed,
    # then restore proposed_version and decision to pre-pass values.
    # Only runs when: unstable=info, record channel is not already unstable,
    # and the fetcher type supports channel selection (github/dockerhub/quay/npm/…).
    # Suppressed when --stable=full is active (args.sh already enforces mutual exclusivity,
    # but this belt-and-suspenders guard protects against direct library calls).
    # stable=info is compatible — both second-pass blocks can run independently.
    if [[ "${_GS_EU2_CFG[unstable]:-}" == "info" && "${_GS_EU2_CFG[stable]:-}" != "full" ]]; then
      local _info_chan
      _info_chan="$(_gs_eu2_record_get "${_i}" channel)"
      if [[ "${_info_chan}" != "unstable" ]]; then
        # Save state (all fields that fetchers may overwrite during the second pass)
        local _saved_prop _saved_decision _saved_chan _saved_err
        _saved_prop="$(_gs_eu2_record_get "${_i}" proposed_version)"
        _saved_decision="$(_gs_eu2_record_get "${_i}" decision)"
        _saved_err="$(_gs_eu2_record_get "${_i}" error_message)"
        _saved_chan="${_info_chan}"
        # Temporarily set channel=unstable and re-run fetcher
        _gs_eu2_record_set "${_i}" channel "unstable"
        _gs_eu2_record_set "${_i}" proposed_version ""
        _gs_eu2_record_set "${_i}" decision ""
        _gs_eu2_record_set "${_i}" error_message ""
        # I2: dispatch via helper
        _gs_eu2_dispatch_fetcher "${_i}"
        local _unstable_ver
        _unstable_ver="$(_gs_eu2_record_get "${_i}" proposed_version)"
        # Restore original state (including error_message to avoid info-pass errors bleeding through)
        _gs_eu2_record_set "${_i}" channel "${_saved_chan}"
        _gs_eu2_record_set "${_i}" proposed_version "${_saved_prop}"
        _gs_eu2_record_set "${_i}" decision "${_saved_decision}"
        _gs_eu2_record_set "${_i}" error_message "${_saved_err}"
        # Store unstable_proposed only if it's a prerelease, different from stable proposed,
        # AND genuinely newer than the stable proposed (not a backward step like stable=3.1.1
        # returning hp=3.0.0-rc.4 — that would be a downgrade, not an advance).
        if [[ -n "${_unstable_ver}" && "${_unstable_ver}" != "${_saved_prop}" ]] && \
           _gs_eu2_is_prerelease "${_unstable_ver}"; then
          local _ui_store="true"
          if [[ -n "${_saved_prop}" ]]; then
            local _ui_cmp
            _ui_cmp="$(_gs_eu2_semver_compare "${_saved_prop}" "${_unstable_ver}")"
            # "older" means stable is older than unstable — i.e. unstable is genuinely newer
            [[ "${_ui_cmp}" != "older" ]] && _ui_store="false"
          fi
          [[ "${_ui_store}" == "true" ]] && \
            _gs_eu2_record_set "${_i}" unstable_proposed "${_unstable_ver}"
        fi
      fi
    fi

    # --stable=info second-pass: temporarily swap channel→stable, re-run the
    # same fetcher (cache hit — no extra HTTP), capture proposed as stable_proposed,
    # then restore proposed_version and decision to pre-pass values.
    # Only runs when: stable=info, record channel is not already stable/empty
    # (a stable channel would make the second pass identical to the main fetch).
    if [[ "${_GS_EU2_CFG[stable]:-}" == "info" ]]; then
      local _si_chan
      _si_chan="$(_gs_eu2_record_get "${_i}" channel)"
      if [[ -n "${_si_chan}" && "${_si_chan}" != "stable" ]]; then
        local _si_saved_prop _si_saved_decision _si_saved_chan _si_saved_err
        _si_saved_prop="$(_gs_eu2_record_get "${_i}" proposed_version)"
        _si_saved_decision="$(_gs_eu2_record_get "${_i}" decision)"
        _si_saved_err="$(_gs_eu2_record_get "${_i}" error_message)"
        _si_saved_chan="${_si_chan}"
        _gs_eu2_record_set "${_i}" channel "stable"
        _gs_eu2_record_set "${_i}" proposed_version ""
        _gs_eu2_record_set "${_i}" decision ""
        _gs_eu2_record_set "${_i}" error_message ""
        # I2: dispatch via helper
        _gs_eu2_dispatch_fetcher "${_i}"
        local _stable_ver
        _stable_ver="$(_gs_eu2_record_get "${_i}" proposed_version)"
        _gs_eu2_record_set "${_i}" channel "${_si_saved_chan}"
        _gs_eu2_record_set "${_i}" proposed_version "${_si_saved_prop}"
        _gs_eu2_record_set "${_i}" decision "${_si_saved_decision}"
        _gs_eu2_record_set "${_i}" error_message "${_si_saved_err}"
        # Store stable_proposed only if it's non-empty, not a prerelease,
        # and different from the main proposed (suppress when identical).
        if [[ -n "${_stable_ver}" && "${_stable_ver}" != "${_si_saved_prop}" ]] && \
           ! _gs_eu2_is_prerelease "${_stable_ver}"; then
          _gs_eu2_record_set "${_i}" stable_proposed "${_stable_ver}"
        fi
      fi
    fi
    fi  # end: if [[ -z "${_skip_reason}" ]] (skip gate — bypass all fetcher dispatch)

    # Apply decision classifier (refines any AUTO decision the fetcher set)
    local _cur _prop _override _manual _major _major_min _note _fetcher_decision
    _cur="$(_gs_eu2_record_get "${_i}" current_version)"
    _prop="$(_gs_eu2_record_get "${_i}" proposed_version)"
    _override="$(_gs_eu2_record_get "${_i}" override)"
    _manual="$(_gs_eu2_record_get "${_i}" manual)"
    _major="$(_gs_eu2_record_get "${_i}" major_hint)"
    _major_min="$(_gs_eu2_record_get "${_i}" major_hint_min)"
    _note="$(_gs_eu2_record_get "${_i}" note)"
    _fetcher_decision="$(_gs_eu2_record_get "${_i}" decision)"

    if [[ "${_fetcher_decision}" == "AUTO" || -z "${_fetcher_decision}" ]]; then
      local _classified
      # --force-auto: bypass (manual) and (override) annotation flags by passing "" so
      # classify_decision never sees them.  The HOLD gate is handled after classification.
      local _eff_override="${_override}" _eff_manual="${_manual}"
      if [[ "${_GS_EU2_CFG[force_auto]:-false}" == "true" ]]; then
        _eff_override="" _eff_manual=""
      fi
      # (tag-channel-prefix): pre-strip the channel prefix from _cur and _prop so that
      # decide.sh's internal sort -V downgrade check compares pure semver strings.
      # The round-trip prefix is display/storage-only; classify_decision must not see it.
      local _cur_cls="${_cur}" _prop_cls="${_prop}"
      local _tcp_cls
      _tcp_cls="$(_gs_eu2_record_get "${_i}" tag_channel_prefix)"
      if [[ -n "${_tcp_cls}" ]]; then
        _cur_cls="${_cur_cls#v}"; _cur_cls="${_cur_cls#"${_tcp_cls}"}"
        _prop_cls="${_prop_cls#v}"; _prop_cls="${_prop_cls#"${_tcp_cls}"}"
      fi
      # Range annotation: when the fetcher fell back to the LOW major, pass major_hint_min
      # to classify_decision so the HOLD guard accepts the fallback version (e.g., 25.x
      # is valid against pin=25, not pin=26 which would HOLD).
      local _using_fallback _major_cls="${_major}"
      _using_fallback="$(_gs_eu2_record_get "${_i}" using_fallback_major)"
      if [[ "${_using_fallback}" == "true" && -n "${_major_min}" ]]; then
        _major_cls="${_major_min}"
      fi
      _classified="$(_gs_eu2_classify_decision "${_cur_cls}" "${_prop_cls}" "${_eff_override}" "${_eff_manual}" "${_major_cls}" "${_GS_EU2_CFG[unstable]:-}")"
      # --force-auto: upgrade HOLD to AUTO (bypasses major-bump guard / major_hint pin guard)
      if [[ "${_GS_EU2_CFG[force_auto]:-false}" == "true" && "${_classified}" == "HOLD" ]]; then
        _classified="AUTO"
      fi
      _gs_eu2_record_set "${_i}" decision "${_classified}"
    fi

    # Lock gate: (lock:REASON) overrides AUTO/HOLD/MANUAL/SKIP(classifier) to LOCK.
    # Fires AFTER force-auto (HOLD→AUTO upgrade) — lock is immune to --force-auto.
    # Does NOT override ERROR (fetch failures must surface).
    # Does NOT override SKIP from the skip gate (when _skip_reason is set) —
    # only overrides SKIP from the classifier (current==proposed with no skip flag).
    local _lock_reason
    _lock_reason="$(_gs_eu2_record_get "${_i}" lock_reason)"
    if [[ -n "${_lock_reason}" && \
          "$(_gs_eu2_record_get "${_i}" decision)" != "ERROR" && \
          -z "${_skip_reason}" ]]; then
      _gs_eu2_record_set "${_i}" decision "LOCK"
      _gs_eu2_record_set "${_i}" error_message "${_lock_reason}"
    fi

    # SHA classification: independent of version decision.
    # When a repo is tracking HEAD (git:owner/repo flag), the annotation SHA may
    # lag behind even when the version is current.  Upgrade the decision to SHA
    # so the apply step can rewrite the annotation without touching VAR=.
    local _ann_sha _prop_sha _sha_classified
    _ann_sha="$(_gs_eu2_record_get "${_i}" annotation_sha)"
    _prop_sha="$(_gs_eu2_record_get "${_i}" proposed_sha)"
    _sha_classified="$(_gs_eu2_classify_sha_decision "${_ann_sha}" "${_prop_sha}")"
    if [[ "${_sha_classified}" == "SHA" && \
          "$(_gs_eu2_record_get "${_i}" decision)" == "SKIP" ]]; then
      _gs_eu2_record_set "${_i}" decision "SHA"
    fi

    # Annotate SKIP on a floating-reference current with a human-readable reason.
    # Guard: skip-gated records already have error_message set by the skip gate above;
    # do not overwrite it (for skip-gated records _prop is empty, so _prop != _cur is
    # vacuously true and would fire incorrectly without this guard).
    if [[ -z "${_skip_reason}" && \
          "$(_gs_eu2_record_get "${_i}" decision)" == "SKIP" && \
          "${_prop}" != "${_cur}" ]] && \
       _gs_eu2_is_unversioned "${_cur}"; then
      _gs_eu2_record_set "${_i}" error_message \
        "floating reference (${_cur}) — pin manually to adopt proposed version"
    fi

    # Annotate SKIP when proposed is prerelease but current is stable.
    # Guard: skip-gated records already have error_message set; -z check below would
    # prevent overwrite anyway, but the explicit _skip_reason guard is consistent and
    # avoids calling _gs_eu2_is_prerelease with an empty _prop (which fetcher never set).
    if [[ -z "${_skip_reason}" && \
          "$(_gs_eu2_record_get "${_i}" decision)" == "SKIP" && \
          -z "$(_gs_eu2_record_get "${_i}" error_message)" && \
          -n "${_prop}" && "${_prop}" != "${_cur}" ]] && \
       _gs_eu2_is_prerelease "${_prop}" && ! _gs_eu2_is_prerelease "${_cur}"; then
      _gs_eu2_record_set "${_i}" error_message \
        "proposed is prerelease — pin manually when stable ships"
    fi

    # Stream this record immediately — don't buffer until all fetches complete
    local _decision _err _tag _change _reason
    _decision="$(_gs_eu2_record_get "${_i}" decision)"
    _err="$(_gs_eu2_record_get "${_i}" error_message)"

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

    # Compute reason label for non-AUTO decisions
    _reason=""
    case "${_decision}" in
      HOLD)
        if [[ -n "${_prop}" ]]; then
          local _delta _cur_maj _prop_maj
          _delta="$(_gs_eu2_semver_delta "${_cur}" "${_prop}")"
          _cur_maj="${_cur#v}"; _cur_maj="${_cur_maj%%.*}"
          _prop_maj="${_prop#v}"; _prop_maj="${_prop_maj%%.*}"
          # Strip path-like prefix from major labels (e.g. "tags/2" → "2")
          _cur_maj="${_cur_maj##*[^0-9]}"
          _prop_maj="${_prop_maj##*[^0-9]}"
          if [[ -n "${_major}" ]]; then
            # Proposed escapes major_hint pin
            _reason="  ← major pin (${_prop_maj}.x available)"
          elif [[ "${_delta}" == "major" ]]; then
            # Unpinned major bump
            _reason="  ← major bump (${_cur_maj}→${_prop_maj})"
          fi
        fi
        ;;
      MANUAL)
        _reason="  ← manual flag"
        ;;
      LOCK)
        _reason="  ← locked: ${_lock_reason}"
        ;;
      SKIP)
        # Detect downgrade: proposed non-empty, differs from current, no error yet
        if [[ -z "${_err}" && -n "${_prop}" && "${_prop}" != "${_cur}" ]]; then
          local _tcp_disp
          _tcp_disp="$(_gs_eu2_record_get "${_i}" tag_channel_prefix)"
          local _cur_cmp="${_cur#v}" _prop_cmp="${_prop#v}"
          [[ -n "${_tcp_disp}" ]] && _cur_cmp="${_cur_cmp#"${_tcp_disp}"}"
          [[ -n "${_tcp_disp}" ]] && _prop_cmp="${_prop_cmp#"${_tcp_disp}"}"
          local _cv_norm _pv_norm _oldest
          _cv_norm="$(perl -pe 's/(\d{8})[0-9a-fA-F]+$/$1/' <<< "${_cur_cmp}")"
          _pv_norm="$(perl -pe 's/(\d{8})[0-9a-fA-F]+$/$1/' <<< "${_prop_cmp}")"
          _oldest="$(printf '%s\n%s\n' "${_cv_norm}" "${_pv_norm}" | sort -V | head -1)"
          if [[ "${_oldest}" == "${_pv_norm}" && "${_oldest}" != "${_cv_norm}" ]]; then
            local _channel
            _channel="$(_gs_eu2_record_get "${_i}" channel)"
            _err="would downgrade: current ${_cur_cmp} → ${_channel:-proposed} ${_prop_cmp}"
          fi
        fi
        ;;
    esac

    _change=""
    if [[ "${_decision}" == "SHA" ]]; then
      local _sha_disp_new _sha_disp_ann
      _sha_disp_new="$(_gs_eu2_record_get "${_i}" proposed_sha)"
      _sha_disp_ann="$(_gs_eu2_record_get "${_i}" annotation_sha)"
      _change="  sha:${_sha_disp_ann:0:8} → sha:${_sha_disp_new:0:8}"
    elif [[ "${_decision}" == "SKIP" && -n "${_err}" ]]; then
      _change="  (${_err})"
    elif [[ -n "${_prop}" && "${_prop}" != "${_cur}" ]]; then
      _change="  ${_cur} → ${_prop}${_reason}"
    elif [[ -n "${_err}" ]]; then
      _change="  (${_err})"
    elif [[ "${_decision}" == "SKIP" ]]; then
      if [[ "${_manual}" == "true" ]]; then
        _change="  (up to date — manual)"
      elif [[ "${_override}" == "true" ]]; then
        _change="  (up to date — override)"
      else
        _change="  (up to date)"
      fi
    elif [[ -n "${_reason}" ]]; then
      _change="${_reason}"
    fi

    # --changes-only hide gate: suppress purely up-to-date records from output.
    # A record is hidden only when ALL of the following hold:
    #   • decision=SKIP, error_message empty (genuine up-to-date — not FROZEN/skip-gate)
    #   • no [DRIFT] condition (checked from record fields, independent of --no-drift display)
    #   • no [WATCH] signal
    #   • no [FALLBACK] signal
    #   • no [UNSTABLE]/[STABLE] info sub-lines
    # (note:TEXT) is the only sub-line that does NOT prevent hiding — it is metadata.
    # Signals are pre-computed from record fields so the gate is atomic: either the
    # full record (main line + all sub-lines) prints or nothing does.
    local _should_hide=false
    if [[ "${_GS_EU2_CFG[changes_only]:-false}" == "true" \
          && "${_decision}" == "SKIP" && -z "${_err}" && -z "${_skip_reason}" ]]; then
      _should_hide=true
      # [FALLBACK] signal: range annotation fell back to LOW major
      local _co_fallback
      _co_fallback="$(_gs_eu2_record_get "${_i}" using_fallback_major)"
      [[ "${_co_fallback}" == "true" && -n "${_major_min}" ]] && _should_hide=false
      # [WATCH] signal: new runtime generation detected
      if [[ "${_should_hide}" == "true" ]]; then
        local _co_wm_depth
        _co_wm_depth="$(_gs_eu2_record_get "${_i}" watch_major_depth)"
        if [[ -n "${_co_wm_depth}" ]]; then
          local _co_wm_lat
          _co_wm_lat="$(_gs_eu2_record_get "${_i}" latest_unconstrained)"
          [[ -z "${_co_wm_lat}" ]] && _co_wm_lat="${_prop}"
          if [[ -n "${_co_wm_lat}" && -n "${_cur}" ]]; then
            local _co_wm_cpfx _co_wm_lpfx
            _co_wm_cpfx="$(_gs_eu2_version_prefix "${_cur}" "${_co_wm_depth}")"
            _co_wm_lpfx="$(_gs_eu2_version_prefix "${_co_wm_lat}" "${_co_wm_depth}")"
            if [[ -n "${_co_wm_cpfx}" && -n "${_co_wm_lpfx}" \
                  && "${_co_wm_cpfx}" != "${_co_wm_lpfx}" ]]; then
              local _co_wm_hi
              _co_wm_hi="$(printf '%s\n%s\n' "${_co_wm_cpfx}" "${_co_wm_lpfx}" | sort -V | tail -1)"
              [[ "${_co_wm_hi}" == "${_co_wm_lpfx}" ]] && _should_hide=false
            fi
          fi
        fi
      fi
      # [UNSTABLE] info sub-line signal: mirror the exact display condition (including stable!=full guard)
      if [[ "${_should_hide}" == "true" && "${_GS_EU2_CFG[unstable]:-}" == "info" \
            && "${_GS_EU2_CFG[stable]:-}" != "full" ]]; then
        local _co_unstable
        _co_unstable="$(_gs_eu2_record_get "${_i}" unstable_proposed)"
        [[ -n "${_co_unstable}" && "${_co_unstable}" != "${_cur}" ]] && _should_hide=false
      fi
      # [STABLE] info sub-line signal
      if [[ "${_should_hide}" == "true" && "${_GS_EU2_CFG[stable]:-}" == "info" ]]; then
        local _co_stable
        _co_stable="$(_gs_eu2_record_get "${_i}" stable_proposed)"
        [[ -n "${_co_stable}" && "${_co_stable}" != "${_cur}" ]] && _should_hide=false
      fi
      # [DRIFT] signal: checked independently of --no-drift (drift exists even when display suppressed)
      if [[ "${_should_hide}" == "true" ]]; then
        local _co_actual _co_ann_ver _co_use_sha _co_ann_sha
        _co_actual="$(_gs_eu2_record_get "${_i}" actual_var_value)"
        _co_ann_ver="$(_gs_eu2_record_get "${_i}" current_version)"
        _co_use_sha="$(_gs_eu2_record_get "${_i}" use_sha)"
        _co_ann_sha="$(_gs_eu2_record_get "${_i}" annotation_sha)"
        if [[ "${_co_use_sha}" == "true" ]]; then
          [[ -n "${_co_actual}" && -n "${_co_ann_sha}" \
             && "${_co_actual}" != "${_co_ann_sha}" ]] && _should_hide=false
        else
          if [[ -z "${_co_actual}" && -n "${_co_ann_ver}" ]]; then
            _should_hide=false
          elif [[ -n "${_co_actual}" && -n "${_co_ann_ver}" \
                  && "${_co_actual}" != "${_co_ann_ver}" ]]; then
            _should_hide=false
          fi
        fi
      fi
      # [REPLACE-DRIFT] signal: any replace target whose actual value differs from
      # expand_template(cur) is a drift condition — reveal SKIP records that would otherwise hide.
      # Checked independently of --no-drift (same pattern as [DRIFT] gate above).
      if [[ "${_should_hide}" == "true" ]]; then
        local _co_rep_tgts _co_rep_tmpls
        _co_rep_tgts="$(_gs_eu2_record_get "${_i}" replace_targets)"
        _co_rep_tmpls="$(_gs_eu2_record_get "${_i}" replace_templates)"
        if [[ -n "${_co_rep_tgts}" ]]; then
          local _co_old_ifs="${IFS}"
          IFS=$'\x1f'
          local _co_rt_arr _co_rm_arr
          read -ra _co_rt_arr <<< "${_co_rep_tgts}"
          read -ra _co_rm_arr <<< "${_co_rep_tmpls}"
          IFS="${_co_old_ifs}"
          local _co_ri
          for (( _co_ri = 0; _co_ri < ${#_co_rt_arr[@]}; _co_ri++ )); do
            local _co_rt="${_co_rt_arr[${_co_ri}]}"
            local _co_rm="${_co_rm_arr[${_co_ri}]:-}"
            local _co_tgt_actual _co_exp_cur
            _co_tgt_actual="$(grep -m1 "^${_co_rt}=" "${_GS_EU2_CFG[env_file]}" 2>/dev/null \
              | cut -d= -f2-)"
            _co_exp_cur="$(_gs_eu2_expand_replace_template "${_co_rm}" "${_cur:-}")"
            if [[ "${_co_tgt_actual}" != "${_co_exp_cur}" ]]; then
              _should_hide=false
              break
            fi
          done
        fi
      fi
    fi
    if [[ "${_should_hide}" == "true" ]]; then
      (( ++_n_hidden )) || true
      if [[ "${_GS_EU2_TALLY_ACTIVE}" != "1" ]]; then
        printf '\r%*s\r' "$(( _max_var_len + 20 ))" "" >&2
      fi
      continue
    fi

    # Clear the progress line then print the result
    # Width: tag(8) + 2 spaces + var field + some margin for change text
    if [[ "${_GS_EU2_TALLY_ACTIVE}" == "1" ]]; then
      _gs_eu2_tally_erase
    else
      printf '\r%*s\r' "$(( _max_var_len + 20 ))" "" >&2
    fi
    printf "%s  %-${_max_var_len}s%s\n" "${_tag}" "${_env_var}" "${_change}"
    [[ -n "${_note}" && "${_GS_EU2_CFG[no_notes]:-false}" != "true" ]] && \
      printf '%10s↳ %s\n' "" "${_note}"

    # [FALLBACK] sub-line: emitted when a range annotation (LOW-HIGH) fell back to
    # the LOW major because HIGH had no versions yet. NOT suppressed by --no-notes.
    # Guard: only when using_fallback_major is set by the fetcher.
    local _using_fallback_disp
    _using_fallback_disp="$(_gs_eu2_record_get "${_i}" using_fallback_major)"
    if [[ "${_using_fallback_disp}" == "true" && -n "${_major_min}" ]]; then
      printf '%10s↳ [FALLBACK] major=%s not yet in registry — using fallback major=%s\n' \
        "" "${_major}" "${_major_min}"
      (( ++_n_fallback )) || true
    fi

    # major-pin no-match sub-line: when a major_hint filter produced zero results (decision=SKIP)
    # and latest_unconstrained is known, show it so the user knows what exists without the pin.
    # Guard: only when major_hint is set AND error_message is non-empty (fetcher SKIP from
    # "no versions matched" — not from same-version up-to-date SKIP where error_message is empty).
    # NOT suppressed by --no-notes.
    local _skip_err_disp
    _skip_err_disp="$(_gs_eu2_record_get "${_i}" error_message)"
    if [[ "${_decision}" == "SKIP" && -n "${_major}" && -n "${_skip_err_disp}" ]]; then
      local _pin_uc
      _pin_uc="$(_gs_eu2_record_get "${_i}" latest_unconstrained)"
      if [[ -n "${_pin_uc}" ]]; then
        printf '%10s↳ [PIN-MISS] major=%s not yet in registry — globally latest: %s\n' \
          "" "${_major}" "${_pin_uc}"
      fi
    fi

    # (watch-major) sub-line: emit when a new runtime generation is available.
    # Uses latest_unconstrained (set by fetchers from the pre-major-pin tag set),
    # falling back to proposed_version for fetcher types with no major-pin concept.
    # Suppressed when: decision is ERROR/SKIP-unversioned, or no depth set.
    # NOT suppressed by --no-notes — WATCH is a signal, not a note.
    if [[ "${_decision}" != "ERROR" ]]; then
      local _wm_depth_r
      _wm_depth_r="$(_gs_eu2_record_get "${_i}" watch_major_depth)"
      if [[ -n "${_wm_depth_r}" ]]; then
        local _wm_latest
        _wm_latest="$(_gs_eu2_record_get "${_i}" latest_unconstrained)"
        # Fall back to proposed_version for fetchers without major-pin filtering
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
    # Counted independently of display — uses record fields directly so MANUAL would
    # count if it ever carries a proposed_sha diff (forward-compatible).
    # Pure SHA decisions (decision=SHA) are already reflected in the primary SHA counter
    # and are intentionally excluded here.
    if [[ "${_decision}" == "AUTO" || "${_decision}" == "MANUAL" ]]; then
      local _sha_anno_prop _sha_anno_ann
      _sha_anno_prop="$(_gs_eu2_record_get "${_i}" proposed_sha)"
      _sha_anno_ann="$(_gs_eu2_record_get "${_i}" annotation_sha)"
      if [[ -n "${_sha_anno_prop}" && "${_sha_anno_prop}" != "${_sha_anno_ann}" ]]; then
        (( ++_n_sha_anno )) || true
      fi
    fi

    # --unstable=info sub-line: show what the unstable version would be (informational only).
    # Only shown when: unstable=info mode, unstable_proposed is set, and it differs from
    # both the stable proposed_version and the current version.
    # Suppressed when --stable=full is active (mutual exclusivity enforced in args.sh).
    # stable=info is compatible — both sub-lines may appear (unstable first, stable second).
    if [[ "${_GS_EU2_CFG[unstable]:-}" == "info" && "${_GS_EU2_CFG[stable]:-}" != "full" ]]; then
      local _unstable_disp
      _unstable_disp="$(_gs_eu2_record_get "${_i}" unstable_proposed)"
      if [[ -n "${_unstable_disp}" && "${_unstable_disp}" != "${_cur}" ]]; then
        printf '%10s↳ [UNSTABLE] unstable: %s\n' "" "${_unstable_disp}"
      fi
    fi

    # --stable=info sub-line: show what the stable version would be (informational only).
    # Only shown when: stable=info mode, stable_proposed is set, and it differs from current.
    if [[ "${_GS_EU2_CFG[stable]:-}" == "info" ]]; then
      local _stable_disp
      _stable_disp="$(_gs_eu2_record_get "${_i}" stable_proposed)"
      if [[ -n "${_stable_disp}" && "${_stable_disp}" != "${_cur}" ]]; then
        printf '%10s↳ [STABLE] stable: %s\n' "" "${_stable_disp}"
      fi
    fi

    # (depends-on) safety warning: when a record carries a depends_on annotation, emit a
    # [WARN] sub-line reminding the user that dependency ordering is not enforced at runtime.
    # NOT suppressed by --no-notes (this is a safety signal, not cosmetic output).
    local _depends_on
    _depends_on="$(_gs_eu2_record_get "${_i}" depends_on)"
    if [[ -n "${_depends_on}" ]]; then
      printf '%10s↳ [WARN] (depends-on:%s) not enforced — dependency ordering\n' \
        "" "${_depends_on}"
      printf '%10s         unimplemented; verify %s manually before --apply\n' \
        "" "${_depends_on%%:*}"
      (( ++_n_warn_depends_on )) || true
    fi

    # [DRIFT] sub-line: emitted when the actual VAR= value in the env file differs from
    # what the annotation records as the current version (or SHA for use-sha records).
    # Decision-aware: the message adapts to the current decision so the user knows exactly
    # what action (if any) will resolve the drift.
    # - LOCK/FROZEN (skip-gate): drift is informational only — lock and skip gate block --apply.
    # - HOLD: drift noted; --force-auto --apply required to resolve.
    # - MANUAL: drift noted; manual flag blocks --apply; --force-auto --apply to override.
    # - AUTO/SHA: re-run --apply to resolve.
    # - SKIP (up-to-date, not skip-gate): re-run --apply or update annotation.
    # - ERROR: drift noted but cannot auto-resolve (fetch failed).
    # Empty VAR + skip-gate or empty VAR + LOCK: suppressed — skipped/locked vars are never
    #   auto-written; the empty state is intentional (feature disabled by design).
    # Empty VAR + other decisions: enable-warning — --apply will write the fetched version.
    # NOT suppressed by --no-notes. ONLY suppressed by --no-drift.
    local _drift_fired=false _drift_dir_downgrade=false
    # RESOLVED: annotation holds a floating alias (latest/stable/lts/…), not a semver baseline.
    # Drift comparison is meaningless — skip the whole block to avoid false [DRIFT] sub-lines.
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
          # Decision-aware: LOCK/FROZEN/SKIP cannot be written by --apply; others can.
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
          # LOCK: immune to --apply and --force-auto — never auto-written; suppress drift noise
          if [[ "${_decision}" == "LOCK" ]]; then
            printf '%10s↳ [DRIFT] var is empty — annotation locked at %s; feature disabled (set VAR= manually to re-enable — lock blocks --apply and --force-auto)\n' \
              "" "${_drift_ann_ver}"
            _drift_fired=true
          # FROZEN (skip-gate SKIP): skip gate also blocks --apply — suppress drift noise
          elif [[ -n "${_skip_reason}" ]]; then
            : # skip-gate blocks apply; empty var is intentional — no drift message
          # HOLD: both apply and force-auto apply can eventually resolve this
          elif [[ "${_decision}" == "HOLD" ]]; then
            printf '%10s↳ [DRIFT] var is empty — annotation tracks %s (feature disabled? --force-auto --apply will write it to enable)\n' \
              "" "${_drift_ann_ver}"
            _drift_fired=true
          # MANUAL: --force-auto --apply required; manual flag blocks plain --apply
          elif [[ "${_decision}" == "MANUAL" ]]; then
            printf '%10s↳ [DRIFT] var is empty — annotation tracks %s (feature disabled? --force-auto --apply will write it to enable)\n' \
              "" "${_drift_ann_ver}"
            _drift_fired=true
          # AUTO: --apply will write the proposed version to VAR= and enable the feature
          elif [[ "${_decision}" == "AUTO" ]]; then
            printf '%10s↳ [DRIFT] var is empty — annotation tracks %s (feature disabled? --apply will write %s to enable it)\n' \
              "" "${_drift_ann_ver}" "${_prop:-${_drift_ann_ver}}"
            _drift_fired=true
          # SHA: --apply updates annotation sha only; VAR= must be set manually to enable
          elif [[ "${_decision}" == "SHA" ]]; then
            printf '%10s↳ [DRIFT] var is empty — annotation tracks %s (feature disabled? set VAR= manually to enable)\n' \
              "" "${_drift_ann_ver}"
            _drift_fired=true
          # SKIP (up-to-date, not skip-gate) or ERROR: informational only
          else
            printf '%10s↳ [DRIFT] var is empty — annotation tracks %s (feature disabled?)\n' \
              "" "${_drift_ann_ver}"
            _drift_fired=true
          fi
        elif [[ -n "${_drift_actual}" && -n "${_drift_ann_ver}" \
                && "${_drift_actual}" != "${_drift_ann_ver}" ]]; then
          # Case 2: both non-empty but differ — direction-aware + decision-aware message
          # Direction detection: only for clean semver values (vX.Y.Z or X.Y.Z form).
          # Non-semver (e.g. 18.3-alpine3.23, 2.5.0-rc1, main) use the neutral fallback.
          local _drift_dir_msg=""
          if [[ "${_drift_actual}" =~ ^v?[0-9][0-9.]*$ && \
                "${_drift_ann_ver}" =~ ^v?[0-9][0-9.]*$ ]]; then
            local _drift_oldest
            _drift_oldest="$(printf '%s\n%s\n' "${_drift_actual}" "${_drift_ann_ver}" | sort -V | head -1)"
            if [[ "${_drift_oldest}" == "${_drift_actual}" && "${_drift_actual}" != "${_drift_ann_ver}" ]]; then
              # VAR is BEHIND annotation (normal drift: annotation advanced, apply not run)
              _drift_dir_msg=" — re-run --apply or update annotation"
            else
              # VAR is AHEAD of annotation (downgrade risk: VAR newer than annotation)
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
            # B2/B7: downgrade → direction-only (would worsen it); VAR behind → --force-auto action
            if [[ "${_drift_dir_downgrade}" == "true" ]]; then
              printf '%10s↳ [DRIFT] annotation says %s but VAR=%s%s\n' \
                "" "${_drift_ann_ver}" "${_drift_actual}" "${_drift_dir_msg}"
            else
              printf '%10s↳ [DRIFT] annotation says %s but VAR=%s — --force-auto --apply to resolve\n' \
                "" "${_drift_ann_ver}" "${_drift_actual}"
            fi
            _drift_fired=true
          elif [[ "${_decision}" == "MANUAL" ]]; then
            # B3/B8: downgrade → direction-only; VAR behind → --force-auto action
            if [[ "${_drift_dir_downgrade}" == "true" ]]; then
              printf '%10s↳ [DRIFT] annotation says %s but VAR=%s%s\n' \
                "" "${_drift_ann_ver}" "${_drift_actual}" "${_drift_dir_msg}"
            else
              printf '%10s↳ [DRIFT] annotation says %s but VAR=%s — --force-auto --apply to resolve\n' \
                "" "${_drift_ann_ver}" "${_drift_actual}"
            fi
            _drift_fired=true
          elif [[ "${_decision}" == "ERROR" ]]; then
            # B9: include direction message when VAR is ahead of annotation
            printf '%10s↳ [DRIFT] annotation says %s but VAR=%s%s — fetch failed; fix error then re-run\n' \
              "" "${_drift_ann_ver}" "${_drift_actual}" "${_drift_dir_msg:-}"
            _drift_fired=true
          elif [[ "${_decision}" == "SKIP" && -z "${_skip_reason}" ]]; then
            # B4/B10: up-to-date SKIP — --apply will not write; include direction for downgrade awareness
            printf '%10s↳ [DRIFT] annotation says %s but VAR=%s%s — update annotation or revert VAR= manually (--apply skips up-to-date records)\n' \
              "" "${_drift_ann_ver}" "${_drift_actual}" "${_drift_dir_msg:-}"
            _drift_fired=true
          else
            # B11: AUTO, SHA — neutral fallback when non-semver (no _drift_dir_msg)
            printf '%10s↳ [DRIFT] annotation says %s but VAR=%s%s\n' \
              "" "${_drift_ann_ver}" "${_drift_actual}" "${_drift_dir_msg:- — re-run --apply or update annotation}"
            _drift_fired=true
          fi
        fi
      fi
    fi

    # [REPLACE-DRIFT] sub-line: for records with (replace:TARGET=template) annotations, compare
    # each target's actual value against expand_template(cur) and expand_template(prop).
    # - stale_now  : target_actual ≠ exp_cur  → target is already wrong relative to current primary
    # - update_pending : exp_cur ≠ exp_prop → proposed version would change the expanded value
    # Decision-aware display, per-record counter (first stale target fires the counter).
    # NOT suppressed by --no-notes. ONLY suppressed by --no-drift (consistent with [DRIFT]).
    local _record_replace_drift_counted=false
    local _record_replace_cascade_counted=false
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
            # AUTO/SHA: show the replace sub-line only when there is actual work to do.
            # Suppress when stale_now=false AND update_pending=false (target already correct,
            # version bump doesn't change the expanded value — pure no-op).
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
            # SKIP + stale: target already wrong; plain --apply can fix replace-only drift
            printf '%10s↳ [REPLACE-DRIFT] %s  actual=%s ≠ expected=%s — run --apply to fix\n' \
              "" "${_rd_rt}" "${_rd_tgt_actual}" "${_rd_exp_cur}"
          elif [[ ( "${_decision}" == "HOLD" || "${_decision}" == "MANUAL" ) \
                  && "${_rd_stale_now}" == "true" ]]; then
            # HOLD/MANUAL + stale: --force-auto --apply required
            printf '%10s↳ [REPLACE-DRIFT] %s  actual=%s ≠ expected=%s — run --force-auto --apply to fix\n' \
              "" "${_rd_rt}" "${_rd_tgt_actual}" "${_rd_exp_cur}"
          elif [[ ( "${_decision}" == "HOLD" || "${_decision}" == "MANUAL" ) \
                  && "${_rd_stale_now}" == "false" && "${_rd_update_pending}" == "true" ]]; then
            # HOLD/MANUAL + not stale but update pending: informational (force-auto will apply)
            printf '%10s↳ (replace) %-47s  → %s  (with --force-auto --apply)\n' \
              "" "${_rd_rt}" "${_rd_exp_prop}"
          elif [[ -n "${_skip_reason}" && "${_rd_stale_now}" == "true" ]]; then
            # FROZEN (skip-gate) + stale: informational only — skip gate blocks apply
            printf '%10s↳ [REPLACE-DRIFT] %s  actual=%s ≠ expected=%s — informational only (frozen)\n' \
              "" "${_rd_rt}" "${_rd_tgt_actual}" "${_rd_exp_cur}"
          elif [[ "${_decision}" == "LOCK" && "${_rd_stale_now}" == "true" ]]; then
            # LOCK + stale: informational only — lock blocks apply
            printf '%10s↳ [REPLACE-DRIFT] %s  actual=%s ≠ expected=%s — informational only (locked)\n' \
              "" "${_rd_rt}" "${_rd_tgt_actual}" "${_rd_exp_cur}"
          fi

          # Per-record counter: each counter increments at most once per record.
          # Two independent flags ensure multi-target records are counted correctly even when
          # the first target triggers cascade (update_pending) but a later target is stale.
          # _n_replace_drift  : stale targets (replace value wrong relative to current primary)
          # _n_replace_cascade: AUTO/SHA decisions where a replace write will occur on --apply
          #                     (stale_now OR update_pending — both result in a write)
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

    # Post-drift counter updates (outside the no_drift guard — drift_fired is false when suppressed)
    if [[ "${_drift_fired}" == "true" ]]; then
      (( ++_n_drift )) || true
      if [[ "${_drift_dir_downgrade}" == "true" ]]; then
        # B5/B6: count downgrade only when --apply CAN write VAR=
        # LOCK/FROZEN/SKIP/ERROR drift is informational — downgrade not actionable by --apply
        if [[ "${_decision}" != "LOCK" && -z "${_skip_reason}" \
              && "${_decision}" != "SKIP" && "${_decision}" != "ERROR" ]]; then
          # MANUAL/HOLD: only actionable with --force-auto --apply
          if [[ "${_decision}" == "MANUAL" || "${_decision}" == "HOLD" ]]; then
            (( ++_n_downgrade_force )) || true
          else
            # AUTO/SHA: actionable by plain --apply
            (( ++_n_downgrade )) || true
          fi
        fi
      elif [[ "${_decision}" == "AUTO" || "${_decision}" == "HOLD" \
              || "${_decision}" == "MANUAL" || "${_decision}" == "SHA" ]]; then
        (( ++_n_drift_fixable )) || true
      fi
    fi
  done

  # Disarm tally traps and erase live tally block before printing static summary
  trap - INT ERR
  _gs_eu2_tally_erase

  local _total=$(( _n_auto + _n_hold + _n_skip + _n_error + _n_manual + _n_sha + _n_lock + _n_frozen ))
  printf '%-80s\n' "──────────────────────────────────────────────────────────────────────────────"
  local _checked_suffix="${_total} checked"
  (( _n_hidden > 0 )) && _checked_suffix="${_total} checked, ${_n_hidden} hidden"
  # RESOLVE column: shown only when at least one RESOLVED record exists (consistent with FALLBACK behaviour)
  local _resolve_col=""
  (( _n_resolved > 0 )) && _resolve_col=" ${_n_resolved} RESOLVE,"
  printf '  Summary: %d AUTO,%s %d SHA, %d HOLD, %d MANUAL, %d LOCK, %d SKIP, %d FROZEN, %d FALLBACK, %d ERROR  (%s)\n' \
    "${_n_auto}" "${_resolve_col}" "${_n_sha}" "${_n_hold}" "${_n_manual}" "${_n_lock}" "${_n_skip}" "${_n_frozen}" "${_n_fallback}" "${_n_error}" "${_checked_suffix}"

  # Secondary signals sub-line: WATCH, DRIFT (with fixable count), DOWNGRADE, REPLACE-DRIFT, +sha, +replace.
  # DRIFT, DOWNGRADE, REPLACE-DRIFT, and +replace suppressed when --no-drift is active.
  # +sha follows WATCH (unconditional — not suppressed by --no-drift).
  # Entire line omitted when all relevant signals are zero.
  local _sec_watch="${_n_watch}"
  local _sec_drift=0 _sec_fixable=0 _sec_down=0 _sec_down_force=0 _sec_sha_anno="${_n_sha_anno}" _sec_replace_drift=0 _sec_replace_cascade=0
  local _sec_resolved="${_n_resolved}"
  if [[ "${_GS_EU2_CFG[no_drift]:-false}" != "true" ]]; then
    _sec_drift="${_n_drift}"
    _sec_fixable="${_n_drift_fixable}"
    _sec_down="${_n_downgrade}"
    _sec_down_force="${_n_downgrade_force}"
    _sec_replace_drift="${_n_replace_drift}"
    _sec_replace_cascade="${_n_replace_cascade}"
  fi
  if (( _sec_watch > 0 || _sec_drift > 0 || _sec_down > 0 || _sec_down_force > 0 || _sec_sha_anno > 0 || _sec_replace_drift > 0 || _sec_replace_cascade > 0 || _sec_resolved > 0 || _n_warn_depends_on > 0 )); then
    printf '    ↳ %d WATCH · %d DRIFT (%d fixable) · %d DOWNGRADE · %d FORCE-DOWNGRADE · %d REPLACE-DRIFT · %d +sha · %d +replace' \
      "${_sec_watch}" "${_sec_drift}" "${_sec_fixable}" "${_sec_down}" "${_sec_down_force}" "${_sec_replace_drift}" "${_sec_sha_anno}" "${_sec_replace_cascade}"
    (( _sec_resolved > 0 )) && printf ' · +resolve %d' "${_sec_resolved}"
    (( _n_warn_depends_on > 0 )) && printf ' · %d depends-on-warn' "${_n_warn_depends_on}"
    printf '\n'
  fi

  # Exit non-zero when any ERROR decisions were recorded — callers can detect fetch failures.
  (( _n_error > 0 )) && return 1 || return 0
}

# _gs_eu2_main — top-level entry point: parse args, validate, orchestrate check/dump/apply.
#
# Args:    "$@" — all CLI arguments forwarded from bin/env-update.sh
# Reads:   _GS_EU2_CFG (all fields, populated by _gs_eu2_parse_args)
# Sets:    _GS_EU2_CFG[check]="true" when --apply is set (apply implies check)
# Prints:  mode banners + check/dump/apply output to stdout; warnings to stderr
# Returns: 0 on success; 1 on usage error or when ERROR decisions present
#          (propagated via the || exit $? pattern in bin/env-update.sh)
# Side fx: may write .env backup files; may invoke env-scan.sh (--scan);
#          writes last-dry-run-ts marker after a successful dry-run check
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

  # Safety guard: --apply (without --dry-run) requires a recent --dry-run in the same session.
  # This prevents the 2026-04-23 incident class (running --apply cold without previewing changes).
  # Marker file: ${_GS_EU2_CACHE_DIR}/last-dry-run-ts (written after every successful --dry-run check)
  if [[ "${_GS_EU2_CFG[apply]}" == "true" && "${_GS_EU2_CFG[dry_run]}" != "true" ]]; then
    local _dry_run_marker="${_GS_EU2_CACHE_DIR:-/tmp/global-stack-env-update-cache}/last-dry-run-ts"
    local _guard_ok=false
    if [[ -f "${_dry_run_marker}" ]]; then
      local _now _mtime _age
      _now="$(date +%s)"
      _mtime="$(stat -c %Y "${_dry_run_marker}" 2>/dev/null \
        || stat -f %m "${_dry_run_marker}" 2>/dev/null \
        || printf '0')"
      _age=$(( _now - _mtime ))
      (( _age < 1800 )) && _guard_ok=true
    fi
    if [[ "${_guard_ok}" != "true" ]]; then
      printf '[WARN] --apply requires a recent --dry-run (within 30 min). Run with --dry-run first.\n' >&2
      exit 1
    fi
  fi

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
  local _stable_overrides=0
  if [[ "${_GS_EU2_CFG[stable]:-}" == "full" ]]; then
    local _sc _scount
    _scount="$(_gs_eu2_record_count)"
    for (( _sc = 0; _sc < _scount; _sc++ )); do
      local _existing_sc_channel
      _existing_sc_channel="$(_gs_eu2_record_get "${_sc}" channel)"
      if [[ -n "${_existing_sc_channel}" && "${_existing_sc_channel}" != "stable" ]]; then
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
    printf 'WARNING: --scan has no effect without --apply — env-scan runs only after the env file is rewritten\n' >&2
  fi

  if [[ "true" == "${_GS_EU2_CFG[dump]}" ]]; then
    _gs_eu2_dump_records "${_GS_EU2_CFG[format]}"
  elif [[ "true" == "${_GS_EU2_CFG[check]}" ]]; then
    local _check_rc=0
    _gs_eu2_profile_start
    _gs_eu2_run_check || _check_rc=$?
    _gs_eu2_profile_end "Fetch + classify"

    # After a successful dry-run check, write the timestamp marker so a subsequent
    # --apply knows a recent preview was done (incident prevention: 2026-04-23).
    if [[ "${_GS_EU2_CFG[dry_run]}" == "true" ]]; then
      local _dry_run_marker="${_GS_EU2_CACHE_DIR:-/tmp/global-stack-env-update-cache}/last-dry-run-ts"
      mkdir -p "$(dirname "${_dry_run_marker}")"
      date +%s > "${_dry_run_marker}"
    fi

    if [[ "${_GS_EU2_CFG[apply]}" == "true" ]]; then
      printf '\n'
      if [[ "${_GS_EU2_CFG[dry_run]}" == "true" ]]; then
        printf 'Apply preview (--dry-run):\n'
        _gs_eu2_profile_start
        _gs_eu2_apply_updates "${_env_file}" "true"
        _gs_eu2_profile_end "Apply"
      else
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
      fi
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
