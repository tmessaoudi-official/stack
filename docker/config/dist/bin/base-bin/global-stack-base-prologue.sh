#!/bin/bash
# Shared startup prologue: stackCatch ERR handler + trap registration.
# Sourced at the top of all global-stack-*-start.sh scripts (Category 1 + Category 2).
#
# Caller convention:
#   set -xeE -o pipefail   (or set -xeEu -o pipefail for base scripts)
#   shopt -s extdebug
#   IFS=$'\n\t'
#   source global-stack-base-prologue.sh
#
# Scripts NOT covered (they keep their own stackCatch — deliberate 141 exemption):
#   caddy-bin/*, httpd-bin/*, nginx-bin/*, android-bin/global-stack-android-setup*.sh
# Those scripts MAY source global-stack-base-version-gate.sh on its own to reach the
# version gate without taking this prologue's error handling (row 15, 2026-09-04).
# None does yet — rows 18-21 of MASTER.plan.md are what make them use it.
# Those handlers used to exempt exit code 1 as well. That was removed (2026-08-29):
# code 1 is the most common failure in their own chain, and exempting it produced
# total silence rather than a tolerated error — dropping it changes no control flow,
# since `set -e` already aborts wherever the ERR trap fires. They now carry the same
# _STACK_CAUGHT re-entry guard used below, which the `-ne 1` arm had been serving by
# accident: without it, the handler's own `exit 1` re-enters through the EXIT trap
# and overwrites the error token with the trap's line number.
#
# Dry-run seam:
#   GS_STARTUP_DRY_RUN=1 bash global-stack-nvm-start.sh   # exits before any install work
#
# Arg order: stackCatch EXIT_CODE LINE_NUMBER BASH_COMMAND BASH_SOURCE [SIGNAL]
# Trap:      trap 'stackCatch "${?}" "${LINENO}" "${BASH_COMMAND}" "${BASH_SOURCE[0]}"' ERR
#
# On failure the report contains:
#   * failing file / line / command / exit code   (BASH_SOURCE[0] expanded IN the trap
#     string, so it names the CALLER's file, not this prologue)
#   * script chain — every *-start.sh that led here, across process boundaries
#   * source backtrace — in-process file:line:function frames
#   * process tree — OS ancestry, catches links that never sourced this prologue
#
# Optional environment:
#   GLOBAL_STACK_DOCKER_TOOLS_PATH         append log dir      (default /tmp)
#   GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS  per-token error dir (default /tmp)
#   GLOBAL_STACK_ERROR_TOKEN               enables the per-token error file
#   GLOBAL_INTERNAL_STACK_TRACE_STDERR              1 = mirror report to stderr (default 1)
#   GLOBAL_INTERNAL_STACK_TRACE_ARGS                1 = include function args (default 0, extdebug)
#   GLOBAL_INTERNAL_STACK_EXIT_PASSTHROUGH          1 = exit with real code (default 1; 0 = always 1)

if [[ -z "${BASH_VERSION:-}" ]]; then
  printf 'global-stack-base-prologue.sh: bash is required\n' >&2
  return 1 2>/dev/null || exit 1
fi

: "${GLOBAL_STACK_DOCKER_TOOLS_PATH:=/tmp}"
: "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS:=/tmp}"
: "${GLOBAL_INTERNAL_STACK_TRACE_STDERR:=1}"
: "${GLOBAL_INTERNAL_STACK_TRACE_ARGS:=0}"
: "${GLOBAL_INTERNAL_STACK_EXIT_PASSTHROUGH:=1}"

declare -a _STACK_REPORT=()

# --------------------------------------------------------------------------
# trace helpers — only ever called from stackCatch, after `set +eux`
# --------------------------------------------------------------------------

_stack_say() { _STACK_REPORT+=("$*"); }

# Absolute path when the target exists, otherwise verbatim (so a $0 of "bash"
# does not become a bogus /cwd/bash).
_stack_abspath() {
  local p="${1:-}" r=""
  [[ -n "${p}" ]] || { printf '?'; return 0; }
  if [[ -e "${p}" ]]; then
    r="$(readlink -f -- "${p}" 2>/dev/null)" || r=""
  fi
  [[ -n "${r}" ]] || r="${p}"
  printf '%s' "${r}"
}

# Args of snapshot frame <n>. Requires `shopt -s extdebug` (the caller convention).
# BASH_ARGV is a flat stack, newest frame first, each frame's args reversed.
_stack_frame_args() {
  local frame="${1:-0}" i base=0 n out=""
  [[ "${GLOBAL_INTERNAL_STACK_TRACE_ARGS}" == "1" ]] || return 0
  n="${_sc_argc[frame]}"
  [[ -n "${n}" ]] && (( n > 0 )) || return 0
  for (( i = 0; i < frame; i++ )); do base=$(( base + ${_sc_argc[i]:-0} )); done
  for (( i = base + n - 1; i >= base; i-- )); do out+=" ${_sc_argv[i]}"; done
  printf '  args:%s' "${out}"
}

# Cross-process chain, appended at source time by every script that loads us.
_stack_chain_trace() {
  local entry line
  local -a chain=()
  IFS='|' read -r -a chain <<<"${GLOBAL_INTERNAL_STACK_SCRIPT_CHAIN:-}"
  if (( ${#chain[@]} == 0 )); then
    _stack_say "    (empty)"
    return 0
  fi
  for entry in "${chain[@]}"; do
    [[ -n "${entry}" ]] || continue
    printf -v line '    [pid %s] %s' "${entry##*#}" "${entry%#*}"
    _stack_say "${line}"
  done
}

# OS ancestry — catches links that never sourced this prologue (curl | bash,
# Makefile recipes, Docker ENTRYPOINT, su/sh -c wrappers). Linux only.
_stack_process_trace() {
  local pid="${1:-$$}" depth=0 ppid cmd line
  if [[ ! -d /proc ]]; then
    _stack_say "    (unavailable: no /proc)"
    return 0
  fi
  while [[ "${pid}" =~ ^[0-9]+$ ]] && (( pid > 1 && depth < 20 )); do
    [[ -r "/proc/${pid}/cmdline" ]] || break
    cmd="$(tr '\0' ' ' <"/proc/${pid}/cmdline" 2>/dev/null)"
    cmd="${cmd% }"
    [[ -n "${cmd}" ]] || cmd="$(cat "/proc/${pid}/comm" 2>/dev/null)"
    printf -v line '    [pid %s] %s' "${pid}" "${cmd}"
    _stack_say "${line}"
    # PPid from status, NOT field 4 of stat — a process named "my (weird) sh"
    # breaks field splitting on stat.
    ppid="$(awk '/^PPid:/{print $2; exit}' "/proc/${pid}/status" 2>/dev/null)"
    [[ -n "${ppid}" ]] || break
    pid="${ppid}"
    depth=$(( depth + 1 ))
  done
}

# --------------------------------------------------------------------------
# handler
# --------------------------------------------------------------------------

stackCatch() {
  local code="${1:-0}" line="${2:-?}" cmd="${3:-?}" src="${4:-?}" sig="${5:-}"

  [[ "${code}" == "0" ]]        && return 0   # success (incl. the dry-run exit 0)
  [[ -n "${_STACK_CAUGHT:-}" ]] && return 0   # ERR already reported; EXIT is a re-entry
  _STACK_CAUGHT=1

  # -e: never let logging mask the real error.  -u: robustness over strictness in a
  # handler.  -x: the caller runs with `set -x`; without this every trace frame
  # emits a dozen xtrace lines and buries the report.
  set +eux

  [[ "${code}" =~ ^[0-9]+$ ]] || code=1

  # Snapshot the call stack BEFORE calling any helper (each call pushes a frame).
  # Index 0 is stackCatch itself, so real frames start at 1.
  local -a _sc_src=("${BASH_SOURCE[@]}") _sc_fn=("${FUNCNAME[@]}") \
           _sc_ln=("${BASH_LINENO[@]}") _sc_argc=("${BASH_ARGC[@]}") \
           _sc_argv=("${BASH_ARGV[@]}")

  local ts header logdir errdir i frame args
  ts="$(date '+%d-%m-%Y %H:%M:%S' 2>/dev/null)" || ts='?'
  src="$(_stack_abspath "${src}")"

  _STACK_REPORT=()
  _stack_say "Error detected !!"

  # Original prefix preserved verbatim; file/exit/signal appended so existing
  # greps on '** line:' / '** command:' keep matching.
  printf -v header \
    '%s: Error - ** line: %s ** ** command: %s ** ** file: %s ** ** exit: %s **%s' \
    "${ts}" "${line}" "${cmd}" "${src}" "${code}" "${sig:+ ** signal: ${sig} **}"
  _stack_say "${header}"

  _stack_say "  script chain:"
  _stack_chain_trace

  _stack_say "  source backtrace:"
  if (( ${#_sc_src[@]} <= 1 )); then
    _stack_say "    (top level, no function frames)"
  else
    for (( i = 1; i < ${#_sc_src[@]}; i++ )); do
      args="$(_stack_frame_args "${i}")"
      printf -v frame '    %s:%s in %s()%s' \
        "${_sc_src[i]}" "${_sc_ln[i-1]}" "${_sc_fn[i]:-main}" "${args}"
      _stack_say "${frame}"
    done
  fi

  _stack_say "  process tree:"
  _stack_process_trace

  logdir="${GLOBAL_STACK_DOCKER_TOOLS_PATH:-/tmp}"
  mkdir -p -- "${logdir}" 2>/dev/null || logdir=/tmp
  printf '%s\n' "${_STACK_REPORT[@]}" >>"${logdir}/elapsed" 2>/dev/null || true

  if [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]]; then
    errdir="${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS:-/tmp}"
    mkdir -p -- "${errdir}" 2>/dev/null || errdir=/tmp
    # First two lines keep the original 'line:' / 'command:' shape.
    {
      printf 'line: %s\ncommand: %s\nfile: %s\nexit: %s\n' \
        "${line}" "${cmd}" "${src}" "${code}"
      printf '%s\n' "${_STACK_REPORT[@]:2}"
    } >"${errdir}/${GLOBAL_STACK_ERROR_TOKEN}" 2>/dev/null || true
  fi

  [[ "${GLOBAL_INTERNAL_STACK_TRACE_STDERR}" == "1" ]] \
    && printf '%s\n' "${_STACK_REPORT[@]}" >&2

  if [[ "${GLOBAL_INTERNAL_STACK_EXIT_PASSTHROUGH}" == "1" ]]; then
    exit "${code}"
  fi
  exit 1
}

# Deliberate non-zero exit that must NOT be reported as a crash.
#   stackExit 2   # e.g. usage error
stackExit() {
  _STACK_CAUGHT=1
  exit "${1:-0}"
}

# --------------------------------------------------------------------------
# chain registration — runs at source time, once per process
# --------------------------------------------------------------------------

_stack_register_chain() {
  local entry
  entry="$(_stack_abspath "${0}")#$$"
  # The chain already ends with our PID if this process registered before.
  if [[ "${GLOBAL_INTERNAL_STACK_SCRIPT_CHAIN:-}" != *"#$$" ]]; then
    GLOBAL_INTERNAL_STACK_SCRIPT_CHAIN="${GLOBAL_INTERNAL_STACK_SCRIPT_CHAIN:+${GLOBAL_INTERNAL_STACK_SCRIPT_CHAIN}|}${entry}"
  fi
  export GLOBAL_INTERNAL_STACK_SCRIPT_CHAIN
}
_stack_register_chain

# --------------------------------------------------------------------------
# traps
# --------------------------------------------------------------------------

# Mandatory: without errtrace the ERR trap is NOT inherited by functions,
# subshells or command substitutions. Callers already set -E; re-asserted here
# so the prologue is correct even if sourced into a laxer script.
set -E

# BASH_SOURCE[0] is expanded in the TRAP STRING, i.e. in the frame where the
# failure happened — inside stackCatch it would always be this prologue.
trap 'stackCatch "${?}" "${LINENO}" "${BASH_COMMAND}" "${BASH_SOURCE[0]}"' ERR
trap 'stackCatch "${?}" "${LINENO}" "${BASH_COMMAND}" "${BASH_SOURCE[0]}"' EXIT
trap 'stackCatch 129 "${LINENO}" "${BASH_COMMAND}" "${BASH_SOURCE[0]}" SIGHUP'  SIGHUP
trap 'stackCatch 141 "${LINENO}" "${BASH_COMMAND}" "${BASH_SOURCE[0]}" SIGPIPE' SIGPIPE
# Uncomment if these should also be reported (SIGTERM = `docker stop`, expected
# shutdown for a long-running entrypoint — reporting it would be a false alarm):
# trap 'stackCatch 130 "${LINENO}" "${BASH_COMMAND}" "${BASH_SOURCE[0]}" SIGINT'  SIGINT
# trap 'stackCatch 143 "${LINENO}" "${BASH_COMMAND}" "${BASH_SOURCE[0]}" SIGTERM' SIGTERM

# The version gate lives in its own file so the prologue-EXEMPT scripts (caddy,
# httpd, nginx, android-setup — see the header above) can source the gate ALONE,
# without swapping their own stackCatch for this one. Sourced by sibling path
# rather than by PATH: bash resolves a PATH lookup to a full path, so
# BASH_SOURCE[0] names this file's directory whether the prologue was found on
# PATH or sourced directly, and the helper sits beside it in both the repo tree
# (base-bin/) and the container (/usr/local/bin, flat-copied by
# global-stack-base-sync-bin-n-exec.sh). All existing call sites are unchanged.
# Exempt scripts use: source global-stack-base-version-gate.sh
# shellcheck source=docker/config/dist/bin/base-bin/global-stack-base-version-gate.sh
source "${BASH_SOURCE[0]%/*}/global-stack-base-version-gate.sh"

# gs_install_retry_purge <cache_dir> <command...>
#
# Run <command>; if it fails, `rm -rf <cache_dir>` and run it once more. Guards a
# runtime installer that reuses a persistent download cache and cannot self-heal a
# corrupt/partial artifact — e.g. nvm on a nightly download interrupted under
# concurrent-rebuild load: it reuses the poisoned tarball every boot and dies on an
# empty expected checksum, looping forever behind the 24h start_period.
#
# ERR-trap safe by contract (sourced into `set -eE` with the stackCatch trap armed):
# the FIRST attempt runs inside `if`, so a recoverable failure does NOT fire the trap;
# the retry is the function's final command, so a SECOND failure propagates (real
# error → caller's trap writes tools/errors/<token>, as before this guard existed).
# <cache_dir> empty → no purge (still retries). The purge is `rm -rf` only on failure.
#
# The backtrace now names this frame explicitly, so a report showing
# `gs_install_retry_purge()` means the purge+retry ALSO failed.
gs_install_retry_purge() {
  local _girp_cache="${1:-}"
  shift
  if "$@"; then
    return 0
  fi
  printf 'WARN: install failed — purging download cache (%s) and retrying once\n' \
    "${_girp_cache:-<none>}" >&2
  if [[ -n "${_girp_cache}" ]]; then
    rm -rf "${_girp_cache}"
  fi
  "$@"
}

# Dry-run seam: GS_STARTUP_DRY_RUN=1 exits before any install work.
# Usage: GS_STARTUP_DRY_RUN=1 bash global-stack-nvm-start.sh
# `stackExit 0` rather than `exit 0` so the EXIT trap can never mis-file this
# as a crash, whatever $? happened to be beforehand.
if [[ "${GS_STARTUP_DRY_RUN:-0}" == "1" ]]; then
  printf '[DRY RUN] %s: prologue loaded, skipping install.\n' \
    "${GLOBAL_STACK_ERROR_TOKEN:-$(basename "${BASH_SOURCE[1]:-unknown}")}" >&2
  stackExit 0
fi