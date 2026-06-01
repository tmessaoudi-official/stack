#!/bin/bash
set -euo pipefail

if [[ -n "${GLOBAL_STACK_GO_VERSION}" && ( "/usr/bin/go" = "$(command -v go)" || "" = "$(command -v go)" ) ]]; then
    archive="go${GLOBAL_STACK_GO_VERSION}.linux-amd64.tar.gz"
    mkdir -p "${GOROOT}"/
    curl --connect-timeout 30 --max-time 300 -fsSLO "https://go.dev/dl/${archive}"
    sudo tar -C "${GOROOT}"/ --strip-components=1 -xzf "${archive}"
    sudo mkdir -p "${GOPATH}"
    sudo chmod -R a+rwx "${GOROOT}"/
    sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}:${GLOBAL_STACK_DOCKER_GROUP_ID}" "${GOROOT}"/
    rm -rf "${archive}"
fi