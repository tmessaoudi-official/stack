#!/bin/bash
# iou = install-or-upgrade

set -xeE
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

RUST_INIT_LATEST_VERSION=${GLOBAL_STACK_RUSTUP_INIT_VERSION}
RUST_INIT_CURRENT_VERSION=$([[ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust-init" ]] && cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust-init" || echo "null")

# RUST_LATEST_VERSION=$(curl --silent https://api.github.com/repos/rust-lang/rust/releases/latest | jq .name -r | sed 's/Rust //')
RUST_LATEST_VERSION=${GLOBAL_STACK_RUST_VERSION}
RUST_CURRENT_VERSION=$([[ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust" ]] && cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust" || echo "null")

set -xeE -o pipefail

if [ "${RUST_INIT_CURRENT_VERSION}" != "${RUST_INIT_LATEST_VERSION}" ]; then
  echo -e "\nInstalling/Updating rust-init from ${RUST_INIT_CURRENT_VERSION} to ${RUST_INIT_LATEST_VERSION}"

  rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/rustup.installer.sh"
  curl --connect-timeout 30 --max-time 300 -fsSL -o "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/rustup.installer.sh" "https://raw.githubusercontent.com/rust-lang/rustup/${RUST_INIT_LATEST_VERSION}/rustup-init.sh"
  chmod a+x "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/rustup.installer.sh"
  
  sed -i 's|local _url="${RUSTUP_UPDATE_ROOT}/dist/${_arch}/rustup-init${_ext}"|local _url="\$\{RUSTUP_UPDATE_ROOT\}/archive/${GLOBAL_STACK_RUSTUP_INIT_VERSION}/\$\{_arch\}/rustup-init\$\{_ext\}"|g' "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/rustup.installer.sh"
  
  echo "${RUST_INIT_LATEST_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust-init"
fi

if [ "${RUST_CURRENT_VERSION}" != "${RUST_LATEST_VERSION}" ]; then
  echo -e "\nInstalling/Updating rust from ${RUST_CURRENT_VERSION} to ${RUST_LATEST_VERSION}"
  
  rustup.installer.sh -y --profile default --default-toolchain ${RUST_LATEST_VERSION}

  echo "${RUST_LATEST_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust"
fi

# source "${CARGO_HOME}/env" && rustup update ${RUST_LATEST_VERSION}