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
# Scripts NOT covered (they keep their own stackCatch — deliberate 141/1 exemption):
#   caddy-bin/*, httpd-bin/*, nginx-bin/*, android-bin/global-stack-android-setup*.sh
#
# Dry-run seam:
#   GS_STARTUP_DRY_RUN=1 bash global-stack-nvm-start.sh   # exits before any install work
#
# Arg order: stackCatch EXIT_CODE LINE_NUMBER BASH_COMMAND
# Trap:      trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP

stackCatch() {
  if [[ "${1:-0}" != "0" ]]; then
    echo "Error detected !!"
    printf '%s: Error - ** line: %s ** ** command: %s **\n' \
      "$(date '+%d-%m-%Y %H:%M:%S')" "${2:-?}" "${3:-?}" \
      >>"${GLOBAL_STACK_DOCKER_TOOLS_PATH:-/tmp}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] \
      && printf 'line: %s\ncommand: %s\n' "${2:-?}" "${3:-?}" \
        >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS:-/tmp}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP

# gs_version_gate <marker_path> <expected_value> [label]
#
# Content-compare gate for tools/versions/<marker> files. Emits ONE decision word
# on STDOUT — install | skip | reinstall — and, only on a real mismatch (marker
# exists but its content differs from <expected_value>), a loud WARN on STDERR.
#
#   install    marker absent            → first install, silent
#   skip       marker == expected       → up to date, silent
#   reinstall  marker != expected       → version changed, WARN + caller reinstalls
#
# ERR-trap safe by contract: this runs sourced into `set -eE` with the stackCatch
# ERR trap armed. Every path ends in `return 0` and the only comparison that can
# be false lives inside `if`, so the gate NEVER returns non-zero for a normal
# decision — a non-zero return would fire stackCatch, write tools/errors/<token>,
# and mask the container as permanently unhealthy behind the 24h start_period.
# Callers capture the decision (e.g. `dec="$(gs_version_gate ...)"`); the WARN
# goes to STDERR so it is never swallowed by the command substitution.
gs_version_gate() {
  local _gvg_marker="${1:-}" _gvg_expected="${2:-}" _gvg_label="${3:-${1:-marker}}"
  local _gvg_current

  if [[ ! -f "${_gvg_marker}" ]]; then
    printf 'install\n'
    return 0
  fi

  _gvg_current="$(cat "${_gvg_marker}" 2>/dev/null || true)"
  if [[ "${_gvg_current}" == "${_gvg_expected}" ]]; then
    printf 'skip\n'
    return 0
  fi

  printf 'WARN: %s version changed (marker=%s expected=%s) — reinstalling\n' \
    "${_gvg_label}" "${_gvg_current}" "${_gvg_expected}" >&2
  printf 'reinstall\n'
  return 0
}

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
if [[ "${GS_STARTUP_DRY_RUN:-0}" == "1" ]]; then
  printf '[DRY RUN] %s: prologue loaded, skipping install.\n' \
    "${GLOBAL_STACK_ERROR_TOKEN:-$(basename "${BASH_SOURCE[1]:-unknown}")}" >&2
  exit 0
fi
