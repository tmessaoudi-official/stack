#!/bin/bash

set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

HOURS="$((${1} / 3600))"
MINUTES="$(((${1} % 3600) / 60))"
SECONDS="$(((${1} % 3600) % 60))"
echo -e "\n$(date '+%d-%m-%Y %H:%M:%S') - ${HOURS} hours and ${MINUTES} minutes and ${SECONDS} seconds elapsed."
echo -e "\nInstallation complete -- seems like it went well !"

if [ "${3:-update}" = "create" ]; then
  echo -e "$(date '+%d-%m-%Y %H:%M:%S'): $(echo "${2}") - ${HOURS} hours and ${MINUTES} minutes and ${SECONDS} seconds elapsed." > "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
  chmod o+w "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
else
  echo -e "$(date '+%d-%m-%Y %H:%M:%S'): $(echo "${2}") - ${HOURS} hours and ${MINUTES} minutes and ${SECONDS} seconds elapsed." >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
fi
