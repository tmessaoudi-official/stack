#!/bin/bash
# iou = install-or-upgrade

set -xeE
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

set -xeE -o pipefail

_rust_fatal() {
  printf 'FATAL: %s\n' "$1" >&2
  exit 1
}

# The RUST gate, and the wipe it drives, moved here from rust-start.sh (pin-audit tranche 3
# step 20, rulings 2026-09-26 11:17 and 11:43, policy B; startup-prologue.test.sh §72).
# rust-start.sh wiped RUSTUP_HOME + CARGO_HOME on a RUST change BEFORE this script fetched
# rustup-init, so an unpublished or broken pin left no rust at all. Now rustup-init is
# downloaded and checked first; only then are the homes wiped. A failed check leaves both
# homes, the cargo-installed tools and every marker as they were. The toolchain itself is
# downloaded by rustup after the wipe; rustup checks each component against the channel
# manifest's sha256 [read: src/dist/download.rs at 1.29.1], and the rustc it yields must
# report the pin before the rust marker is written.
_rust_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust" "${GLOBAL_STACK_RUST_VERSION}" "rust")"
_rust_wipe=0
if [ "${_rust_gate}" != "skip" ] || [ "true" = "${GLOBAL_STACK_RELOAD_RUST:-false}" ]; then
  _rust_wipe=1
fi

# rustup itself (pin-audit pass 2, §58). The marker alone is not trusted: before pass 2 it
# was written from the PIN before anything installed, so on an existing install it records
# intent. The installed binary is compared too (none = not installed); a present binary
# whose --version fails is a real error and aborts here, loud. A RUST wipe takes rustup
# with it, so it always reinstalls rustup too.
_rustup_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust-init" "${GLOBAL_STACK_RUSTUP_INIT_VERSION}" "rust-init")"
_rustup_have=none
if [ -x "${CARGO_HOME}/bin/rustup" ]; then
  _rustup_have="$(rustup --version | awk 'NR == 1 { print $2 }')"
fi

if [ "${_rust_wipe}" = 1 ] || [ "${_rustup_gate}" != "skip" ] || [ "${_rustup_have}" != "${GLOBAL_STACK_RUSTUP_INIT_VERSION}" ]; then
  echo -e "\nFetching rustup-init ${GLOBAL_STACK_RUSTUP_INIT_VERSION} (rust gate: ${_rust_gate}, rustup gate: ${_rustup_gate}, installed: ${_rustup_have})"
  # The pinned rustup-init BINARY, from the archive the upstream rustup-init.sh itself
  # downloads from (RUSTUP_UPDATE_ROOT/archive/<version>/<target>/rustup-init), and its
  # published .sha256, whose single line reads `<hex> *./rustup-init` [measured 1.29.1].
  # The installer script is gone: it only fetched this same binary, unchecked.
  _ri_dl="$(mktemp -d)"
  _ri_url="https://static.rust-lang.org/rustup/archive/${GLOBAL_STACK_RUSTUP_INIT_VERSION}/x86_64-unknown-linux-gnu/rustup-init"
  if ! curl --connect-timeout 30 --max-time 300 -fsSL -o "${_ri_dl}/rustup-init" "${_ri_url}" \
    || ! curl --connect-timeout 30 --max-time 60 -fsSL -o "${_ri_dl}/rustup-init.sha256" "${_ri_url}.sha256"; then
    _rust_fatal "rustup-init ${GLOBAL_STACK_RUSTUP_INIT_VERSION} could not be downloaded - rust left as it was"
  fi
  if ! _ri_want="$(awk '($2 == "*./rustup-init" || $2 == "rustup-init") && length($1) == 64 { print $1 }' "${_ri_dl}/rustup-init.sha256")" \
    || [[ "$(grep -c . <<<"${_ri_want}")" != 1 ]]; then
    _rust_fatal "rustup-init ${GLOBAL_STACK_RUSTUP_INIT_VERSION}: its .sha256 lists no single checksum for rustup-init - rust left as it was"
  fi
  if ! printf '%s  %s\n' "${_ri_want}" "${_ri_dl}/rustup-init" | sha256sum -c --quiet - >/dev/null 2>&1; then
    _rust_fatal "rustup-init ${GLOBAL_STACK_RUSTUP_INIT_VERSION} does not match its published SHA-256 - rust left as it was"
  fi
  chmod 0755 "${_ri_dl}/rustup-init"
  # `rustup-init 1.29.1 (d95a37b6a 2026-08-13)`: the space after the version is what
  # stops 1.29.10 from passing for 1.29.1.
  if ! _ri_says="$("${_ri_dl}/rustup-init" --version 2>&1)" \
    || [[ "${_ri_says%%$'\n'*}" != "rustup-init ${GLOBAL_STACK_RUSTUP_INIT_VERSION} "* ]]; then
    _rust_fatal "rustup-init ${GLOBAL_STACK_RUSTUP_INIT_VERSION}: the downloaded binary reports \"${_ri_says%%$'\n'*}\" - rust left as it was"
  fi

  # Checked: from here on a RUST change wipes the homes and reinstalls clean.
  if [ "${_rust_wipe}" = 1 ]; then
    echo -e "\nWiping rust for ${GLOBAL_STACK_RUST_VERSION} (gate: ${_rust_gate}, RELOAD_RUST: ${GLOBAL_STACK_RELOAD_RUST:-false})"
    rm -rf "${RUSTUP_HOME}" "${CARGO_HOME}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rust" \
      "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust-init"
    mkdir -p "${RUSTUP_HOME}" "${CARGO_HOME}"
  fi

  # Re-running rustup-init over an existing install replaces rustup in EITHER direction and
  # keeps installed toolchains [measured 2026-09-24 through the installer script, which ran
  # this same binary with these same arguments]. The marker is written from the INSTALLED
  # rustup, only after it matches the pin.
  "${_ri_dl}/rustup-init" -y --profile default --default-toolchain none
  _rustup_installed="$(rustup --version | awk 'NR == 1 { print $2 }')"
  if [ "${_rustup_installed}" != "${GLOBAL_STACK_RUSTUP_INIT_VERSION}" ]; then
    _rust_fatal "rustup-init ${GLOBAL_STACK_RUSTUP_INIT_VERSION} installed rustup ${_rustup_installed}"
  fi
  printf '%s\n' "${_rustup_installed}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust-init"
  rm -rf "${_ri_dl}"
fi

# Every boot, before any toolchain command: with auto-self-update left at its default,
# `rustup toolchain install` self-updates rustup to latest [measured 2026-09-24:
# 1.28.2 -> 1.29.1, "info: downloading self-update"], i.e. past the pin with nothing
# in .env changed. The setting lives in ${RUSTUP_HOME}/settings.toml; setting it is
# local and idempotent, and covers installs made before this line existed.
rustup set auto-self-update disable

# Re-read after the wipe: a wiped marker means install. 2>/dev/null only drops a second
# copy of the WARN the first rust gate above already printed.
if [ "$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust" "${GLOBAL_STACK_RUST_VERSION}" "rust" 2>/dev/null)" != "skip" ]; then
  echo -e "\nInstalling rust ${GLOBAL_STACK_RUST_VERSION}"

  rustup toolchain install "${GLOBAL_STACK_RUST_VERSION}" --profile default
  rustup default "${GLOBAL_STACK_RUST_VERSION}"

  # The rustup proxy by its path, never PATH's rustc. `rustc 1.98.1 (<hash> <date>)`.
  if ! _rc_says="$("${CARGO_HOME}/bin/rustc" --version 2>&1)" \
    || [[ "${_rc_says%%$'\n'*}" != "rustc ${GLOBAL_STACK_RUST_VERSION} "* ]]; then
    _rust_fatal "rust ${GLOBAL_STACK_RUST_VERSION}: the installed rustc reports \"${_rc_says%%$'\n'*}\""
  fi
  printf '%s\n' "${GLOBAL_STACK_RUST_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust"
fi

# source "${CARGO_HOME}/env" && rustup update ${RUST_LATEST_VERSION}
