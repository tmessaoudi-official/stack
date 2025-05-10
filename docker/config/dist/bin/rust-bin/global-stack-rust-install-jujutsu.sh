#!/bin/bash

if [[ -n "${GLOBAL_STACK_JUJUTSU_VERSION}" && "" = "$(command -v jj)" ]]; then
    cargo install --git https://github.com/jj-vcs/jj.git --tag ${GLOBAL_STACK_JUJUTSU_VERSION} --features vendored-openssl --locked --bin jj jj-cli
fi