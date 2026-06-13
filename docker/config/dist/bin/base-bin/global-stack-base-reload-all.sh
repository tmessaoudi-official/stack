#!/bin/bash

sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base" "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"

set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

GLOBAL_STACK_CURRENT_VERSION=$([[ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/version" ]] && cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/version" || echo "null")
if [ "${GLOBAL_STACK_VERSION}" != "${GLOBAL_STACK_CURRENT_VERSION}" ] || [ "${GLOBAL_STACK_RELOAD_ALL}" = "true" ]; then
    echo -e "\nReloading all"
    find "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/" -type d -exec sudo rm -rf {} \;
    find "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/" -type f -exec sudo rm -rf {} \;
    sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/*"
    touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/.gitkeep"
fi