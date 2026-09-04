#!/bin/bash

set -xeE -o pipefail

# Row 18 — see global-stack-rust-install-cargo-nextest.sh for why the gate helper
# is sourced here rather than the prologue.
source global-stack-base-version-gate.sh

_jujutsu_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust.jujutsu" "${GLOBAL_STACK_JUJUTSU_VERSION}" "rust.jujutsu")"
if [[ -n "${GLOBAL_STACK_JUJUTSU_VERSION}" ]] &&
   { [[ "${_jujutsu_gate}" != "skip" ]] || [[ "" = "$(command -v jj)" ]]; }; then
    _jujutsu_force=""
    [[ "${_jujutsu_gate}" = "reinstall" ]] && _jujutsu_force="--force"
    # shellcheck disable=SC2086  # deliberate word-split: empty means "no flag"
    cargo install --git https://github.com/jj-vcs/jj.git --tag ${GLOBAL_STACK_JUJUTSU_VERSION} --locked --bin jj jj-cli ${_jujutsu_force}
    printf '%s\n' "${GLOBAL_STACK_JUJUTSU_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust.jujutsu"
fi
