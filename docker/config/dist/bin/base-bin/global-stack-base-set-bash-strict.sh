#!/bin/bash
# NOTE: Despite the name, this script is NOT a strict-mode setter.
# It is an ERR-trap / EXIT-trap handler invoked as:
#   trap 'global-stack-base-set-bash-strict.sh $?' EXIT ERR
# It receives the exit code as $1 and writes the error token on failure.
#
# Strict mode for container startup scripts is set inline at the top of each
# *-start.sh:  set -xeE -o pipefail  (debug trace, no -u)
# Strict mode for lib scripts uses:  set -eEuo pipefail  (no debug trace, with -u)
set -euo pipefail

if [ "${1}" != "0" ]; then
  # error handling goes here
  echo "Error detected !!"
  echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - global-stack-base-set-bash-strict.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
  [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && printf 'exit: %s\n' "${1:-unknown}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
  exit 1
fi