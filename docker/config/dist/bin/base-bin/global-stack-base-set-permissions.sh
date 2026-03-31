#!/bin/bash
set -euo pipefail

if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/permissions" ] || [ "${GLOBAL_STACK_RELOAD_ALL}" = "true" ] || [ "${GLOBAL_STACK_RELOAD_PERMISSIONS}" = "true" ]; then
    echo -e "\nSetting up stack permissions"
    sudo chmod -R a+rwx "${GLOBAL_STACK_DOCKER_ROOT_PATH}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH}" "${GLOBAL_STACK_DOCKER_WORKDIR}"
    sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}" "${GLOBAL_STACK_DOCKER_ROOT_PATH}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH}" "${GLOBAL_STACK_DOCKER_WORKDIR}"
fi