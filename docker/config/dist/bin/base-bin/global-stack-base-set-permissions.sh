#!/bin/bash
set -euo pipefail

if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/permissions" ] || [ "${GLOBAL_STACK_RELOAD_ALL}" = "true" ] || [ "${GLOBAL_STACK_RELOAD_PERMISSIONS}" = "true" ]; then
    echo -e "\nSetting up stack permissions"
    # Only the shared tools volume is made a+rwx. ROOT_PATH (/stack) and WORKDIR (/stack/projects) are the
    # HOST projects bind mount: the recursive a+rwx that used to cover them made every project file 777 —
    # .env files world-writable, every file executable — on each start with a fresh tools volume
    # (review-remediation rows 17/18). The chown below is all the container user needs there.
    sudo chmod -R a+rwx "${GLOBAL_STACK_DOCKER_TOOLS_PATH}"
    sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}" "${GLOBAL_STACK_DOCKER_ROOT_PATH}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH}" "${GLOBAL_STACK_DOCKER_WORKDIR}"
fi
