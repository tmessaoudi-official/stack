#!/bin/bash

set -xeE -o pipefail

# Row 18. This script is invoked as a bare command by rust-start.sh, so it is its
# own process and inherits nothing — it must source the version gate itself. It
# takes ONLY the gate helper, never the full prologue, so it keeps whatever error
# handling rust-start.sh established for the chain.
source global-stack-base-version-gate.sh

_nextest_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust.cargo-nextest" "${GLOBAL_STACK_CARGO_NEXTEST_VERSION}" "rust.cargo-nextest")"
if [[ -n "${GLOBAL_STACK_CARGO_NEXTEST_VERSION}" ]] &&
   { [[ "${_nextest_gate}" != "skip" ]] || [[ "" = "$(command -v cargo-nextest)" ]]; }; then
    # --force on a reinstall: `cargo install` is only guaranteed to replace when
    # forced, so without it a version bump could no-op and the marker below would
    # then record a version that is not installed.
    _nextest_force=""
    [[ "${_nextest_gate}" = "reinstall" ]] && _nextest_force="--force"
    # shellcheck disable=SC2086  # deliberate word-split: empty means "no flag"
    cargo install --git https://github.com/nextest-rs/nextest cargo-nextest --tag "cargo-nextest-${GLOBAL_STACK_CARGO_NEXTEST_VERSION}" --locked --bin cargo-nextest ${_nextest_force}
    printf '%s\n' "${GLOBAL_STACK_CARGO_NEXTEST_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust.cargo-nextest"
fi
