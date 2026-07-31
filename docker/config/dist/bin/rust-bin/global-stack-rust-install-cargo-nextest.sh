#!/bin/bash

set -xeE -o pipefail

if [[ -n "${GLOBAL_STACK_CARGO_NEXTEST_VERSION}" && "" = "$(command -v cargo-nextest)" ]]; then
    cargo install --git https://github.com/nextest-rs/nextest --tag ${GLOBAL_STACK_CARGO_NEXTEST_VERSION} --locked --bin cargo-nextest
fi