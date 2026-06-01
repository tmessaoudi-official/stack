#!/bin/bash
set -euo pipefail

cd "${GLOBAL_STACK_DOCKER_TOOLS_PATH}"

if [[ ! -d "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/awscli" ]]; then
    mkdir -p "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/awscli"

    sudo chmod -R a+rwx "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/awscli"
    sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}:${GLOBAL_STACK_DOCKER_GROUP_ID}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/awscli"

    cd "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/awscli"

    curl --connect-timeout 30 --max-time 300 "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

    unzip awscliv2.zip

    ./aws/install --install-dir "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/awscli/" --bin-dir "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/"

    rm -rf awscliv2.zip aws/
fi