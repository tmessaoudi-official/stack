#!/bin/bash

set -xeE -o pipefail

if [[ -n "${GLOBAL_STACK_JUJUTSU_VERSION}" && "" = "$(command -v jj)" ]]; then
    cargo install --git https://github.com/jj-vcs/jj.git --tag ${GLOBAL_STACK_JUJUTSU_VERSION} --locked --bin jj jj-cli
fi