#!/bin/bash

set -xeE -o pipefail

# Row 18 — see global-stack-rust-install-cargo-nextest.sh for why the gate helper
# is sourced here rather than the prologue.
source global-stack-base-version-gate.sh

_mergiraf_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust.mergiraf" "${GLOBAL_STACK_MERGIRAF_VERSION}" "rust.mergiraf")"
if [[ -n "${GLOBAL_STACK_MERGIRAF_VERSION}" ]] &&
   { [[ "${_mergiraf_gate}" != "skip" ]] || [[ "" = "$(command -v mergiraf)" ]]; }; then
    sudo rm -rf /tmp/mergiraf
    sudo mkdir /tmp/mergiraf
    sudo chmod -R a+rwx /tmp/mergiraf
    sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}:${GLOBAL_STACK_DOCKER_GROUP_ID}" /tmp/mergiraf
    git clone --progress --verbose --branch ${GLOBAL_STACK_MERGIRAF_VERSION} https://codeberg.org/mergiraf/mergiraf.git /tmp/mergiraf
    cd /tmp/mergiraf
    _mergiraf_force=""
    [[ "${_mergiraf_gate}" = "reinstall" ]] && _mergiraf_force="--force"
    # shellcheck disable=SC2086  # deliberate word-split: empty means "no flag"
    cargo install --path /tmp/mergiraf --locked ${_mergiraf_force}
    cd ${GLOBAL_STACK_DOCKER_ROOT_PATH}
    rm -rf /tmp/mergiraf
    printf '%s\n' "${GLOBAL_STACK_MERGIRAF_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust.mergiraf"
fi
