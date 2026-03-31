#!/bin/bash
set -euo pipefail

if [[ -n "${GLOBAL_STACK_HURL_VERSION}" && "" = "$(command -v hurl)" ]]; then
    sudo mkdir -p "${GLOBAL_STACK_HURLPATH}"
    sudo chmod -R a+rwx "${GLOBAL_STACK_HURLPATH}"
    sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}:${GLOBAL_STACK_DOCKER_GROUP_ID}" "${GLOBAL_STACK_HURLPATH}"

    archive="hurl-${GLOBAL_STACK_HURL_VERSION}-x86_64-unknown-linux-gnu.tar.gz"
    wget "https://github.com/Orange-OpenSource/hurl/releases/download/${GLOBAL_STACK_HURL_VERSION}/${archive}"
    tar -C "${GLOBAL_STACK_HURLPATH}" --strip-components=1 -xzf "${archive}"

    rm -rf "${archive}"
fi