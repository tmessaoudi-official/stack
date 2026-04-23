#!/bin/bash
set -euo pipefail

if [[ -n "${GLOBAL_STACK_ZIG_VERSION}" && "" = "$(command -v zig)" ]]; then
    mkdir -p "${GLOBAL_STACK_ZIGPATH}"/
    curl -fsSLO "https://ziglang.org/download/${GLOBAL_STACK_ZIG_VERSION}/zig-x86_64-linux-${GLOBAL_STACK_ZIG_VERSION}.tar.xz"
    sudo tar -C "${GLOBAL_STACK_ZIGPATH}"/ --strip-component=1 -xf zig-x86_64-linux-${GLOBAL_STACK_ZIG_VERSION}.tar.xz
    sudo mkdir -p "${GLOBAL_STACK_ZIGPATH}"/
    sudo chmod -R a+rwx "${GLOBAL_STACK_ZIGPATH}"/
    sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}:${GLOBAL_STACK_DOCKER_GROUP_ID}" "${GLOBAL_STACK_ZIGPATH}"/
    rm -rf zig-x86_64-linux-${GLOBAL_STACK_ZIG_VERSION}.tar.xz
fi