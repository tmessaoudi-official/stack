#!/bin/bash

set -xeE -o pipefail

if [[ -n "${GLOBAL_STACK_CARGO_OUTDATED_VERSION}" && "" = "$(command -v cargo-outdated)" ]]; then
    cargo install --git https://github.com/kbknapp/cargo-outdated --tag ${GLOBAL_STACK_CARGO_OUTDATED_VERSION} --bin cargo-outdated
fi