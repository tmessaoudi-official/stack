#!/bin/bash

set -xeE -o pipefail

# Row 18 — see global-stack-rust-install-cargo-nextest.sh for why the gate helper
# is sourced here rather than the prologue.
source global-stack-base-version-gate.sh

# cargo-zigbuild + the rustup std targets it cross-compiles to: the toolchain behind Phorge's
# `phorge build --target/--all` (cross-OS standalone executables). zig itself is provided by the
# zig service; rust-iou restores only the host toolchain, so a tools/-wipe reload would otherwise
# drop the cross driver and the per-target std libs. crates.io publishes a `v`-less version, so the
# tag's `v` prefix is stripped at install time (`--version "${VAR#v}"`).
if [[ -n "${GLOBAL_STACK_CARGO_ZIGBUILD_VERSION}" ]]; then
    _zigbuild_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust.cargo-zigbuild" "${GLOBAL_STACK_CARGO_ZIGBUILD_VERSION}" "rust.cargo-zigbuild")"
    if [[ "${_zigbuild_gate}" != "skip" ]] || [[ "" = "$(command -v cargo-zigbuild)" ]]; then
        _zigbuild_force=""
        [[ "${_zigbuild_gate}" = "reinstall" ]] && _zigbuild_force="--force"
        # shellcheck disable=SC2086  # deliberate word-split: empty means "no flag"
        cargo install cargo-zigbuild --version "${GLOBAL_STACK_CARGO_ZIGBUILD_VERSION#v}" --locked ${_zigbuild_force}
        # The marker holds the RAW pin (with any `v`), not the stripped value passed
        # to cargo — the gate compares against the .env variable, so the two must be
        # the same string or every boot would look like a version change.
        printf '%s\n' "${GLOBAL_STACK_CARGO_ZIGBUILD_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust.cargo-zigbuild"
    fi
    # `rustup target add` is idempotent (a fast no-op when already present), so it runs on every
    # start to self-heal a partial reload — deliberately OUTSIDE the gate, which only decides
    # whether the cross driver itself is reinstalled. These four targets match src/bundle/cross.rs
    # in phorge.
    rustup target add \
        x86_64-unknown-linux-musl \
        aarch64-unknown-linux-gnu \
        aarch64-unknown-linux-musl \
        x86_64-pc-windows-gnu
fi
