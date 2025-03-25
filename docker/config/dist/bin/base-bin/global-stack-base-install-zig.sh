#!/bin/bash

if [[ -n "${GLOBAL_STACK_ZIG_VERSION}" && "" = "$(command -v zig)" ]]; then
    mkdir -p "${ZIGPATH}"/
    wget https://ziglang.org/download/${GLOBAL_STACK_ZIG_VERSION}/zig-linux-x86_64-${GLOBAL_STACK_ZIG_VERSION}.tar.xz
    sudo tar -C "${ZIGPATH}"/ --strip-component=1 -xf zig-linux-x86_64-${GLOBAL_STACK_ZIG_VERSION}.tar.xz
    sudo mkdir -p "${ZIGPATH}"/
    sudo chmod -R a+rwx "${ZIGPATH}"/
    sudo chown -R "${GLOBAL_STACK_BASE_USERNAME}:${GLOBAL_STACK_BASE_GROUP}" "${ZIGPATH}"/
    rm -rf zig-linux-x86_64-${GLOBAL_STACK_ZIG_VERSION}.tar.xz
fi