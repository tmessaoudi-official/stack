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
      >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH:-/tmp}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && \
      printf 'line: %s\ncommand: %s\n' "${2:-?}" "${3:-?}" \
      > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS:-/tmp}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP

# Dry-run seam: GS_STARTUP_DRY_RUN=1 exits before any install work.
# Usage: GS_STARTUP_DRY_RUN=1 bash global-stack-nvm-start.sh
if [[ "${GS_STARTUP_DRY_RUN:-0}" == "1" ]]; then
  printf '[DRY RUN] %s: prologue loaded, skipping install.\n' \
    "${GLOBAL_STACK_ERROR_TOKEN:-$(basename "${BASH_SOURCE[1]:-unknown}")}" >&2
  exit 0
fi
