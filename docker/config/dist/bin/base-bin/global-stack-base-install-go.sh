#!/bin/bash

if [[ -n "${GLOBAL_STACK_GO_VERSION}" && ( "/usr/bin/go" = "$(command -v go)" || "" = "$(command -v go)" ) ]]; then
    mkdir -p "${GOROOT}"/
    wget https://go.dev/dl/go${GLOBAL_STACK_GO_VERSION}.linux-amd64.tar.gz
    sudo tar -C "${GOROOT}"/ --strip-component=1 -xzf go${GLOBAL_STACK_GO_VERSION}.linux-amd64.tar.gz
    sudo mkdir -p "${GOPATH}"
    sudo chmod -R a+rwx "${GOROOT}"/
    sudo chown -R "${GLOBAL_STACK_BASE_USERNAME}:${GLOBAL_STACK_BASE_GROUP}" "${GOROOT}"/
    rm -rf go${GLOBAL_STACK_GO_VERSION}.linux-amd64.tar.gz
fi