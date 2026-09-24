#!/bin/bash
# iou = install-or-upgrade

set -xeE
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

# RUST_LATEST_VERSION=$(curl --silent https://api.github.com/repos/rust-lang/rust/releases/latest | jq .name -r | sed 's/Rust //')
RUST_LATEST_VERSION=${GLOBAL_STACK_RUST_VERSION}
RUST_CURRENT_VERSION=$([[ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust" ]] && cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust" || echo "null")

set -xeE -o pipefail

# rustup itself (pin-audit pass 2, startup-prologue.test.sh §58). The installer is
# pinned through its OWN documented knob, RUSTUP_VERSION (both the 1.28.2 and the
# 1.29.1 rustup-init.sh read it) — never by sed-patching the downloaded script: at
# 1.29.1 upstream reshaped the URL line, the sed matched nothing, rustup floated to
# latest and the marker, written from the pin before anything installed, said
# otherwise. Re-running the installer over an existing install replaces rustup in
# EITHER direction and keeps installed toolchains [measured 2026-09-24, scratch
# homes: 1.29.1 -> 1.28.2 -> 1.29.1, rustc 1.98.1 still active]. The marker is
# written from the INSTALLED binary, only after it matches the pin.
# The marker alone is not trusted: before this change it was written from the PIN
# before anything installed, so on an existing install it records intent. The
# installed binary is compared too (none = not installed); a present binary whose
# --version fails is a real error and aborts here, loud.
_rustup_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust-init" "${GLOBAL_STACK_RUSTUP_INIT_VERSION}" "rust-init")"
_rustup_have=none
if [ -x "${CARGO_HOME}/bin/rustup" ]; then
  _rustup_have="$(rustup --version | awk 'NR == 1 { print $2 }')"
fi
if [ "${_rustup_gate}" != "skip" ] || [ "${_rustup_have}" != "${GLOBAL_STACK_RUSTUP_INIT_VERSION}" ]; then
  echo -e "\nInstalling rustup ${GLOBAL_STACK_RUSTUP_INIT_VERSION} (gate: ${_rustup_gate}, installed: ${_rustup_have})"

  rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/rustup.installer.sh"
  curl --connect-timeout 30 --max-time 300 -fsSL -o "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/rustup.installer.sh" "https://raw.githubusercontent.com/rust-lang/rustup/${GLOBAL_STACK_RUSTUP_INIT_VERSION}/rustup-init.sh"
  chmod a+x "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/rustup.installer.sh"

  RUSTUP_VERSION="${GLOBAL_STACK_RUSTUP_INIT_VERSION}" rustup.installer.sh -y --profile default --default-toolchain none

  _rustup_installed="$(rustup --version | awk 'NR == 1 { print $2 }')"
  if [ "${_rustup_installed}" != "${GLOBAL_STACK_RUSTUP_INIT_VERSION}" ]; then
    printf 'FATAL: rustup-init %s installed rustup %s; the RUSTUP_VERSION knob was not honoured\n' "${GLOBAL_STACK_RUSTUP_INIT_VERSION}" "${_rustup_installed}" >&2
    exit 1
  fi
  printf '%s\n' "${_rustup_installed}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust-init"
fi

# Every boot, before any toolchain command: with auto-self-update left at its default,
# `rustup toolchain install` self-updates rustup to latest [measured 2026-09-24:
# 1.28.2 -> 1.29.1, "info: downloading self-update"], i.e. past the pin with nothing
# in .env changed. The setting lives in ${RUSTUP_HOME}/settings.toml; setting it is
# local and idempotent, and covers installs made before this line existed.
rustup set auto-self-update disable

if [ "${RUST_CURRENT_VERSION}" != "${RUST_LATEST_VERSION}" ]; then
  echo -e "\nInstalling/Updating rust from ${RUST_CURRENT_VERSION} to ${RUST_LATEST_VERSION}"

  rustup toolchain install "${RUST_LATEST_VERSION}" --profile default
  rustup default "${RUST_LATEST_VERSION}"

  echo "${RUST_LATEST_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust"
fi

# source "${CARGO_HOME}/env" && rustup update ${RUST_LATEST_VERSION}
