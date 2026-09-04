#!/bin/bash
set -euo pipefail

# Row 21 — see global-stack-base-install-go.sh for why the gate helper is sourced
# here rather than the prologue.
source global-stack-base-version-gate.sh

_zig_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/base.zig" "${GLOBAL_STACK_ZIG_VERSION}" "base.zig")"
if [[ -n "${GLOBAL_STACK_ZIG_VERSION}" ]] &&
   { [[ "${_zig_gate}" != "skip" ]] || [[ "" = "$(command -v zig)" ]]; }; then
    mkdir -p "${GLOBAL_STACK_ZIGPATH}"/
    curl --connect-timeout 30 --max-time 300 -fsSLO "https://ziglang.org/download/${GLOBAL_STACK_ZIG_VERSION}/zig-x86_64-linux-${GLOBAL_STACK_ZIG_VERSION}.tar.xz"
    sudo tar -C "${GLOBAL_STACK_ZIGPATH}"/ --strip-component=1 -xf zig-x86_64-linux-${GLOBAL_STACK_ZIG_VERSION}.tar.xz
    sudo mkdir -p "${GLOBAL_STACK_ZIGPATH}"/
    sudo chmod -R a+rwx "${GLOBAL_STACK_ZIGPATH}"/
    sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}:${GLOBAL_STACK_DOCKER_GROUP_ID}" "${GLOBAL_STACK_ZIGPATH}"/
    rm -rf zig-x86_64-linux-${GLOBAL_STACK_ZIG_VERSION}.tar.xz
    printf '%s\n' "${GLOBAL_STACK_ZIG_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/base.zig"
fi
