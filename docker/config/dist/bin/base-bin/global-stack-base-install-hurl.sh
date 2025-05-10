#!/bin/bash

if [[ -n "${GLOBAL_STACK_HURL_VERSION}" && "" = "$(command -v hurl)" ]]; then
    sudo mkdir -p ${HURLPATH}
    sudo chmod -R a+rwx ${HURLPATH}
    sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}:${GLOBAL_STACK_DOCKER_GROUP_ID}" ${HURLPATH}

    wget https://github.com/Orange-OpenSource/hurl/releases/download/${GLOBAL_STACK_HURL_VERSION}/hurl-${GLOBAL_STACK_HURL_VERSION}-x86_64-unknown-linux-gnu.tar.gz
    tar -C ${HURLPATH} --strip-component=1 -xzf hurl-${GLOBAL_STACK_HURL_VERSION}-x86_64-unknown-linux-gnu.tar.gz

    rm -rf hurl-${GLOBAL_STACK_HURL_VERSION}-x86_64-unknown-linux-gnu.tar.gz
fi