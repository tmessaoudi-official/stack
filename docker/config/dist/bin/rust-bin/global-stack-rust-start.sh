#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

SECONDS=0

rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rust"
rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

sleep 1

global-stack-base-wait-for.sh \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

PATH="${RUSTUP_HOME}/bin:${RUSTUP_HOME}/toolchains/stable-x86_64-unknown-linux-gnu/bin:${CARGO_HOME}/bin:${PATH}"
export PATH

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${RUSTUP_HOME}/bin:${RUSTUP_HOME}/toolchains/stable-x86_64-unknown-linux-gnu/bin:${CARGO_HOME}/bin:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

mkdir -p "${RUSTUP_HOME}" "${CARGO_HOME}"

# iou runs on EVERY boot: it carries its own equality gates (rustup-init and the
# toolchain), is network-free when both are current, and is the only place a
# GLOBAL_STACK_RUSTUP_INIT_VERSION bump — up or down — can land (pin-audit pass 2, §58).
# It also owns the RUST gate and the wipe of both homes (tranche 3 step 20, §72): the
# wipe used to sit here, BEFORE rustup-init was fetched, so a failed fetch left no rust.
# A RUST change or RELOAD still wipes both homes, after the check: a clean reinstall.
global-stack-rust-iou.sh

source "${CARGO_HOME}/env"

global-stack-base-init-mkcert.sh
global-stack-rust-install-jujutsu.sh
global-stack-rust-install-mergiraf.sh
global-stack-rust-install-cargo-zigbuild.sh
global-stack-rust-install-cargo-outdated.sh
global-stack-rust-install-cargo-nextest.sh
global-stack-base-prepare-shell.sh
echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION="${SECONDS}"
global-stack-base-print-success.sh "${DURATION}" "rust"

echo -e "\nWriting success"
: > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rust"

if [ "${GLOBAL_STACK_RELOAD_RUST:-false}" = "true" ]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_RUST is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi

sleep infinity
