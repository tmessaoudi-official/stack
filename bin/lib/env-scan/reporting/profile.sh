#!/bin/bash
# profile.sh — execution profiling for env-scan phases (--profile flag)
#
# Exports:   _gs_es_profile_init  _gs_es_profile_start  _gs_es_profile_end
#            _gs_es_profile_report  _gs_es_now_ms  _gs_es_rss_kb
#            _gs_es_fmt_duration  _gs_es_fmt_mem
# Sources:   none
# Deps:      bash 4.3+; EPOCHREALTIME (bash 5.0+) or date +%s%3N as fallback
# Env:       none
#
# Usage pattern:
#   _gs_es_profile_init          # once at start (before Phase 1)
#   _gs_es_profile_start         # before each phase
#   _gs_es_profile_end "Name"    # after each phase
#   _gs_es_profile_report        # at end when --profile=true (prints to stderr)
#
# Note: mirrors env-update/reporting/profile.sh (same implementation, _GS_ES_ prefix).

# Include guard
[[ -n "${_GS_ES_PROFILE_SH_LOADED:-}" ]] && return 0
readonly _GS_ES_PROFILE_SH_LOADED=1

# ── State variables (global) ──────────────────────────────────────────────────
declare -ag _GS_ES_PROFILE_PHASES=()
declare -ag _GS_ES_PROFILE_DURATIONS_MS=()
declare -ag _GS_ES_PROFILE_MEM_DELTAS_KB=()
_GS_ES_PROFILE_PHASE_START_MS=0
_GS_ES_PROFILE_PHASE_START_KB=0
_GS_ES_PROFILE_TOTAL_START_MS=0
_GS_ES_PROFILE_PEAK_KB=0

# _gs_es_now_ms — return current time in milliseconds.
#
# Prints:  integer millisecond timestamp
# Returns: 0 always
# Note:    uses EPOCHREALTIME (bash 5.0+, no subprocess); falls back to
#          `date +%s%3N` on older bash. EPOCHREALTIME decimal separator is
#          locale-dependent (. or ,) — digit stripping makes it portable.
_gs_es_now_ms() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        local _raw="${EPOCHREALTIME}"
        # Extract integer seconds: everything up to the first non-digit
        local _s="${_raw%%[^0-9]*}"
        # Extract fractional part: everything after the first non-digit char, then take first 6 digits
        local _frac_raw="${_raw#*[^0-9]}"
        # Normalise to exactly 6 digits (pad right with zeros if shorter)
        local _frac="${_frac_raw:0:6}"
        while (( ${#_frac} < 6 )); do _frac="${_frac}0"; done
        echo $(( _s * 1000 + 10#${_frac} / 1000 ))
    else
        date +%s%3N
    fi
}

# _gs_es_rss_kb — return current process RSS in KB.
#
# Prints:  integer KB (0 if /proc/self/status is unavailable)
# Returns: 0 always
_gs_es_rss_kb() {
    awk '/^VmRSS:/{print $2; exit}' /proc/self/status 2>/dev/null || echo 0
}

# _gs_es_profile_init — initialize profiling state at the start of a run.
#
# Args:    none
# Side fx: sets _GS_ES_PROFILE_TOTAL_START_MS and _GS_ES_PROFILE_PEAK_KB
_gs_es_profile_init() {
    _GS_ES_PROFILE_TOTAL_START_MS=$(_gs_es_now_ms)
    _GS_ES_PROFILE_PEAK_KB=$(_gs_es_rss_kb)
}

# _gs_es_profile_start — record start time and memory for the next phase.
#
# Args:    none
# Side fx: sets _GS_ES_PROFILE_PHASE_START_MS and _GS_ES_PROFILE_PHASE_START_KB
_gs_es_profile_start() {
    _GS_ES_PROFILE_PHASE_START_MS=$(_gs_es_now_ms)
    _GS_ES_PROFILE_PHASE_START_KB=$(_gs_es_rss_kb)
}

# _gs_es_profile_end — record elapsed time and memory delta for a completed phase.
#
# Args:    $1 name — human-readable phase name (e.g. "Parse args")
# Side fx: appends to _GS_ES_PROFILE_PHASES / _DURATIONS_MS / _MEM_DELTAS_KB arrays;
#          updates _GS_ES_PROFILE_PEAK_KB if current RSS exceeds previous peak
_gs_es_profile_end() {
    local _name="$1"
    local _end_ms _end_kb
    _end_ms=$(_gs_es_now_ms)
    _end_kb=$(_gs_es_rss_kb)
    local _dur=$(( _end_ms - _GS_ES_PROFILE_PHASE_START_MS ))
    local _delta=$(( _end_kb - _GS_ES_PROFILE_PHASE_START_KB ))
    _GS_ES_PROFILE_PHASES+=("${_name}")
    _GS_ES_PROFILE_DURATIONS_MS+=("${_dur}")
    _GS_ES_PROFILE_MEM_DELTAS_KB+=("${_delta}")
    if [[ ${_end_kb} -gt ${_GS_ES_PROFILE_PEAK_KB} ]]; then _GS_ES_PROFILE_PEAK_KB=${_end_kb}; fi
}

# ── Format helpers ────────────────────────────────────────────────────────────

# _gs_es_fmt_duration — format millisecond duration as a fixed-width string.
#
# Args:    $1 ms — integer millisecond count
# Prints:  "  NNN ms" (< 1000ms) or "  N.NN  s" (>= 1000ms), 9 chars wide
_gs_es_fmt_duration() {
    local ms="$1"
    if (( ms < 1000 )); then
        printf "%6d ms" "${ms}"
    else
        local s=$(( ms / 1000 ))
        local frac=$(( (ms % 1000) / 10 ))
        printf "%4d.%02d  s" "${s}" "${frac}"
    fi
}

# _gs_es_fmt_mem — format KB memory delta as a human-readable string.
#
# Args:    $1 kb — integer KB delta (positive = growth, negative = freed)
# Prints:  e.g. "+1.2 MB", "−0.5 MB", "+0.0 MB" (near-zero: abs < 100 KB → zero)
_gs_es_fmt_mem() {
    local kb="$1"
    local sign="+" minus_sign="−"
    local abs_kb=$(( kb < 0 ? -kb : kb ))
    # Treat tiny deltas as zero
    if (( abs_kb < 100 )); then
        printf "+0.0 MB"
        return
    fi
    local mb_int=$(( abs_kb / 1024 ))
    local mb_frac=$(( (abs_kb % 1024) * 10 / 1024 ))
    if [[ ${kb} -lt 0 ]]; then sign="${minus_sign}"; fi
    printf "%s%d.%d MB" "${sign}" "${mb_int}" "${mb_frac}"
}

# _gs_es_profile_report — print the phase timing table to stderr.
#
# Args:    none
# Prints:  box-drawn table with per-phase duration + memory delta + total (to stderr)
# Returns: 0 always
# Side fx: uses ANSI color codes when stderr is a terminal
_gs_es_profile_report() {
    # ANSI codes — only when stderr is a tty
    local R="" DIM="" BOLD="" GREEN="" YELLOW="" RED="" CYAN="" DIMCYAN=""
    if [[ -t 2 ]]; then
        R="\033[0m"
        DIM="\033[2m"
        BOLD="\033[1m"
        GREEN="\033[0;32m"
        YELLOW="\033[0;33m"
        RED="\033[0;31m"
        CYAN="\033[0;36m"
        DIMCYAN="\033[2;36m"
    fi

    local _total_ms=0
    local _now_ms
    _now_ms=$(_gs_es_now_ms)
    _total_ms=$(( _now_ms - _GS_ES_PROFILE_TOTAL_START_MS ))

    # Box dimensions: inner width = 62 chars
    local _border_inner="──────────────────────────────────────────────────────────────"
    local _header_line="─ Profile ────────────────────────────────────────────────────"

    printf "\n" >&2
    printf "  ${DIM}┌${_header_line}┐${R}\n" >&2
    printf "  ${DIM}│${R}  %-32s %9s   %10s     ${DIM}│${R}\n" "Phase" "Duration" "Memory" >&2
    printf "  ${DIM}├${_border_inner}┤${R}\n" >&2

    local _i
    for _i in "${!_GS_ES_PROFILE_PHASES[@]}"; do
        local _name="${_GS_ES_PROFILE_PHASES[${_i}]}"
        local _ms="${_GS_ES_PROFILE_DURATIONS_MS[${_i}]}"
        local _kb="${_GS_ES_PROFILE_MEM_DELTAS_KB[${_i}]}"

        # Duration color
        local _dur_color="${GREEN}"
        if (( _ms >= 200 && _ms < 1000 )); then _dur_color="${YELLOW}"; fi
        if (( _ms >= 1000 ));              then _dur_color="${RED}";    fi

        # Memory color
        local _abs_kb=$(( _kb < 0 ? -_kb : _kb ))
        local _mem_color="${DIM}"
        if (( _kb > 1024 ));               then _mem_color="${YELLOW}";  fi
        if (( _kb < 0 && _abs_kb >= 100 )); then _mem_color="${DIMCYAN}"; fi

        local _dur_str
        _dur_str=$(_gs_es_fmt_duration "${_ms}")
        local _mem_str
        _mem_str=$(_gs_es_fmt_mem "${_kb}")

        printf "  ${DIM}│${R}  %-32s ${_dur_color}%9s${R}   ${_mem_color}%10s${R}     ${DIM}│${R}\n" \
            "${_name}" "${_dur_str}" "${_mem_str}" >&2
    done

    printf "  ${DIM}├${_border_inner}┤${R}\n" >&2

    # Total row
    local _total_dur_str
    _total_dur_str=$(_gs_es_fmt_duration "${_total_ms}")
    local _peak_mb_int=$(( _GS_ES_PROFILE_PEAK_KB / 1024 ))
    local _peak_mb_frac=$(( (_GS_ES_PROFILE_PEAK_KB % 1024) * 10 / 1024 ))
    local _peak_str
    _peak_str=$(printf "Peak: %d.%d MB" "${_peak_mb_int}" "${_peak_mb_frac}")

    printf "  ${DIM}│${R}  ${BOLD}%-32s %9s   %12s${R}   ${DIM}│${R}\n" \
        "Total" "${_total_dur_str}" "${_peak_str}" >&2

    printf "  ${DIM}└${_border_inner}┘${R}\n" >&2
    printf "\n" >&2
}
