#!/bin/bash

set -xeE -o pipefail

# Row 18 — see global-stack-rust-install-cargo-nextest.sh for why the gate helper
# is sourced here rather than the prologue.
source global-stack-base-version-gate.sh

_outdated_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust.cargo-outdated" "${GLOBAL_STACK_CARGO_OUTDATED_VERSION}" "rust.cargo-outdated")"
if [[ -n "${GLOBAL_STACK_CARGO_OUTDATED_VERSION}" ]] &&
   { [[ "${_outdated_gate}" != "skip" ]] || [[ "" = "$(command -v cargo-outdated)" ]]; }; then
    _outdated_force=""
    [[ "${_outdated_gate}" = "reinstall" ]] && _outdated_force="--force"
    # shellcheck disable=SC2086  # deliberate word-split: empty means "no flag"
    cargo install --git https://github.com/kbknapp/cargo-outdated --tag ${GLOBAL_STACK_CARGO_OUTDATED_VERSION} --bin cargo-outdated ${_outdated_force}
    printf '%s\n' "${GLOBAL_STACK_CARGO_OUTDATED_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust.cargo-outdated"
fi
