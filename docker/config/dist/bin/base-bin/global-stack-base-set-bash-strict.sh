#!/bin/bash
set -euo pipefail

if [ "${1}" != "0" ]; then
  # error handling goes here
  echo "Error detected !!"
  echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - global-stack-base-set-bash-strict.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
  [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
  exit 1
fi