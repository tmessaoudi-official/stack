#!/bin/bash

if [[ -n "${GLOBAL_STACK_GO_VERSION}" && "" = "$(command -v go)" ]]; then
    mkdir -p "${GLOBAL_STACK_DOCKER_TOOLS_PATH}"/go/
    wget https://go.dev/dl/go${GLOBAL_STACK_GO_VERSION}.linux-amd64.tar.gz
    sudo tar -C "${GLOBAL_STACK_DOCKER_TOOLS_PATH}"/go/ -xzf go${GLOBAL_STACK_GO_VERSION}.linux-amd64.tar.gz
    rm -rf go${GLOBAL_STACK_GO_VERSION}.linux-amd64.tar.gz
fi