#!/bin/bash
# profile.sh — execution profiling for env-update phases

# Include guard
[[ -n "${_GS_EU2_PROFILE_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_PROFILE_SH_LOADED=1

# ── State variables (global) ──────────────────────────────────────────────────
declare -ag _GS_EU2_PROFILE_PHASES=()
declare -ag _GS_EU2_PROFILE_DURATIONS_MS=()
declare -ag _GS_EU2_PROFILE_MEM_DELTAS_KB=()
_GS_EU2_PROFILE_PHASE_START_MS=0
_GS_EU2_PROFILE_PHASE_START_KB=0
_GS_EU2_PROFILE_TOTAL_START_MS=0
_GS_EU2_PROFILE_PEAK_KB=0

# ── Helper: millisecond timestamp (no subprocess when bash >= 5.0) ────────────
# Note: EPOCHREALTIME uses a locale-dependent decimal separator (. or ,)
# We strip non-digit characters after the integer seconds part to be portable.
_gs_eu2_now_ms() {
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

# ── Helper: current RSS in KB (reads /proc/self/status; returns 0 if unavailable) ──
_gs_eu2_rss_kb() {
  awk '/^VmRSS:/{print $2; exit}' /proc/self/status 2>/dev/null || echo 0
}

# ── _gs_eu2_profile_init: called once at the start of _gs_eu2_main ────────────────
_gs_eu2_profile_init() {
  _GS_EU2_PROFILE_TOTAL_START_MS=$(_gs_eu2_now_ms)
  _GS_EU2_PROFILE_PEAK_KB=$(_gs_eu2_rss_kb)
}

# ── _gs_eu2_profile_start: called before a phase begins ──────────────────────
_gs_eu2_profile_start() {
  _GS_EU2_PROFILE_PHASE_START_MS=$(_gs_eu2_now_ms)
  _GS_EU2_PROFILE_PHASE_START_KB=$(_gs_eu2_rss_kb)
}

# ── _gs_eu2_profile_end "Phase Name": called after a phase completes ──────────
_gs_eu2_profile_end() {
  local _name="$1"
  local _end_ms _end_kb
  _end_ms=$(_gs_eu2_now_ms)
  _end_kb=$(_gs_eu2_rss_kb)
  local _dur=$(( _end_ms - _GS_EU2_PROFILE_PHASE_START_MS ))
  local _delta=$(( _end_kb - _GS_EU2_PROFILE_PHASE_START_KB ))
  _GS_EU2_PROFILE_PHASES+=("${_name}")
  _GS_EU2_PROFILE_DURATIONS_MS+=("${_dur}")
  _GS_EU2_PROFILE_MEM_DELTAS_KB+=("${_delta}")
  if [[ ${_end_kb} -gt ${_GS_EU2_PROFILE_PEAK_KB} ]]; then _GS_EU2_PROFILE_PEAK_KB=${_end_kb}; fi
}

# ── Format helpers ────────────────────────────────────────────────────────────

# Right-align duration in 9 chars: "  123 ms" or "  1.23  s"
_gs_eu2_fmt_duration() {
  local ms="$1"
  if (( ms < 1000 )); then
    printf "%6d ms" "${ms}"
  else
    local s=$(( ms / 1000 ))
    local frac=$(( (ms % 1000) / 10 ))
    printf "%4d.%02d  s" "${s}" "${frac}"
  fi
}

# Format memory delta in KB as e.g. "+1.2 MB" or "−1.2 MB"
# Near-zero (abs < 100 KB) always shows as "+0.0 MB"
_gs_eu2_fmt_mem() {
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

# ── _gs_eu2_profile_report: print the pretty summary table ────────────────────
_gs_eu2_profile_report() {
  # ANSI codes — only when stderr is a tty (profile output goes to stderr)
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
  _now_ms=$(_gs_eu2_now_ms)
  _total_ms=$(( _now_ms - _GS_EU2_PROFILE_TOTAL_START_MS ))

  # Box dimensions: inner width = 62 chars
  local _border_inner="──────────────────────────────────────────────────────────────"
  local _header_line="─ Profile ────────────────────────────────────────────────────"

  printf "\n" >&2
  printf "  ${DIM}┌${_header_line}┐${R}\n" >&2
  printf "  ${DIM}│${R}  %-32s %9s   %10s     ${DIM}│${R}\n" "Phase" "Duration" "Memory" >&2
  printf "  ${DIM}├${_border_inner}┤${R}\n" >&2

  local _i
  for _i in "${!_GS_EU2_PROFILE_PHASES[@]}"; do
    local _name="${_GS_EU2_PROFILE_PHASES[${_i}]}"
    local _ms="${_GS_EU2_PROFILE_DURATIONS_MS[${_i}]}"
    local _kb="${_GS_EU2_PROFILE_MEM_DELTAS_KB[${_i}]}"

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
    _dur_str=$(_gs_eu2_fmt_duration "${_ms}")
    local _mem_str
    _mem_str=$(_gs_eu2_fmt_mem "${_kb}")

    printf "  ${DIM}│${R}  %-32s ${_dur_color}%9s${R}   ${_mem_color}%10s${R}     ${DIM}│${R}\n" \
      "${_name}" "${_dur_str}" "${_mem_str}" >&2
  done

  printf "  ${DIM}├${_border_inner}┤${R}\n" >&2

  # Total row
  local _total_dur_str
  _total_dur_str=$(_gs_eu2_fmt_duration "${_total_ms}")
  local _peak_mb_int=$(( _GS_EU2_PROFILE_PEAK_KB / 1024 ))
  local _peak_mb_frac=$(( (_GS_EU2_PROFILE_PEAK_KB % 1024) * 10 / 1024 ))
  local _peak_str
  _peak_str=$(printf "Peak: %d.%d MB" "${_peak_mb_int}" "${_peak_mb_frac}")

  printf "  ${DIM}│${R}  ${BOLD}%-32s %9s   %12s${R}   ${DIM}│${R}\n" \
    "Total" "${_total_dur_str}" "${_peak_str}" >&2

  printf "  ${DIM}└${_border_inner}┘${R}\n" >&2
  printf "\n" >&2
}
