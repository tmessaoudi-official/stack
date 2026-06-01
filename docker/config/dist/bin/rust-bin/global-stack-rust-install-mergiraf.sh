#!/bin/bash

set -xeE -o pipefail

if [[ -n "${GLOBAL_STACK_MERGIRAF_VERSION}" && "" = "$(command -v mergiraf)" ]]; then
    sudo mkdir /tmp/mergiraf
    sudo chmod -R a+rwx /tmp/mergiraf
    sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}:${GLOBAL_STACK_DOCKER_GROUP_ID}" /tmp/mergiraf
    git clone --progress --verbose --branch ${GLOBAL_STACK_MERGIRAF_VERSION} https://codeberg.org/mergiraf/mergiraf.git /tmp/mergiraf
    cd /tmp/mergiraf
    cargo install --path /tmp/mergiraf --locked
    cd ${GLOBAL_STACK_DOCKER_ROOT_PATH}
    rm -rf /tmp/mergiraf
fi