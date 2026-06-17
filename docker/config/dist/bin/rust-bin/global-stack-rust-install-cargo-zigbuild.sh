#!/bin/bash

set -xeE -o pipefail

# cargo-zigbuild + the rustup std targets it cross-compiles to: the toolchain behind Phorge's
# `phorge build --target/--all` (cross-OS standalone executables). zig itself is provided by the
# zig service; rust-iou restores only the host toolchain, so a tools/-wipe reload would otherwise
# drop the cross driver and the per-target std libs. crates.io publishes a `v`-less version, so the
# tag's `v` prefix is stripped at install time (`--version "${VAR#v}"`).
if [[ -n "${GLOBAL_STACK_CARGO_ZIGBUILD_VERSION}" ]]; then
    if [[ "" = "$(command -v cargo-zigbuild)" ]]; then
        cargo install cargo-zigbuild --version "${GLOBAL_STACK_CARGO_ZIGBUILD_VERSION#v}" --locked
    fi
    # `rustup target add` is idempotent (a fast no-op when already present), so it runs on every
    # start to self-heal a partial reload. These four targets match src/bundle/cross.rs in phorge.
    rustup target add \
        x86_64-unknown-linux-musl \
        aarch64-unknown-linux-gnu \
        aarch64-unknown-linux-musl \
        x86_64-pc-windows-gnu
fi
