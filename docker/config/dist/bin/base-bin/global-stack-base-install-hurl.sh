#!/bin/bash
set -euo pipefail

# Row 21 — see global-stack-base-install-go.sh for why the gate helper is sourced
# here rather than the prologue.
source global-stack-base-version-gate.sh

# Pin-audit tranche 2 step 14c (ruling 2026-09-25 09:58; startup-prologue.test.sh §65).
# hurl's only Linux x86_64 build links libxml2.so.2, which Ubuntu 26.04 no longer ships
# (libxml2.so.16), so the tarball this used to download could never run — in 00base or on
# the host. The 00base image now compiles the pinned release (Dockerfile stage
# `hurl-build`) into ${GLOBAL_STACK_HURL_BUILD_PATH}/bin; this copies it into tools/hurl,
# where the host PATH finds it. Nothing is downloaded at boot.
#
# An installed hurl that cannot run is a reinstall trigger on its own: the tools/hurl the
# old download left behind is exactly that, with a marker equal to the pin.
_hurl_bin="${GLOBAL_STACK_HURLPATH}/bin"
_hurl_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/base.hurl" "${GLOBAL_STACK_HURL_VERSION}" "base.hurl")"
if [[ -n "${GLOBAL_STACK_HURL_VERSION}" ]] &&
   { [[ "${_hurl_gate}" != "skip" ]] || ! "${_hurl_bin}/hurl" --version >/dev/null 2>&1; }; then
    # The build path is image ENV; an image built before step 14c has none, hence the
    # `:-`. Such an image cannot supply hurl at all, and hurl is a developer tool nothing
    # in the stack depends on, so this WARNs and leaves tools/hurl as it is rather than
    # failing the whole 00base boot (ruling 2026-09-25 11:47); the rebuild repairs it.
    # The pin reaches the container only through the same build, so a REBUILT image and
    # its pin always agree — the mismatch below stays FATAL.
    _hurl_src="${GLOBAL_STACK_HURL_BUILD_PATH:-}/bin"
    if [[ ! -x "${_hurl_src}/hurl" || ! -x "${_hurl_src}/hurlfmt" ]]; then
        printf 'WARN: this 00base image carries no compiled hurl (GLOBAL_STACK_HURL_BUILD_PATH=%s) - rebuild 00base; tools/hurl left as it is\n' \
            "${GLOBAL_STACK_HURL_BUILD_PATH:-<unset: image built before step 14c>}" >&2
        exit 0
    fi
    _hurl_got="$("${_hurl_src}/hurl" --version)"
    if [[ "${_hurl_got}" != "hurl ${GLOBAL_STACK_HURL_VERSION} "* ]]; then
        printf 'FATAL: the image compiled "%s", pin is %s - rebuild 00base (the image predates the pin)\n' \
            "${_hurl_got%%$'\n'*}" "${GLOBAL_STACK_HURL_VERSION}" >&2
        exit 1
    fi

    # Checked: from here on the old tree goes.
    sudo rm -rf "${GLOBAL_STACK_HURLPATH}"
    sudo mkdir -p "${_hurl_bin}"
    sudo install -m 0755 "${_hurl_src}/hurl" "${_hurl_src}/hurlfmt" "${_hurl_bin}/"
    sudo chmod -R a+rwx "${GLOBAL_STACK_HURLPATH}"
    sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}:${GLOBAL_STACK_DOCKER_GROUP_ID}" "${GLOBAL_STACK_HURLPATH}"

    _hurl_got="$("${_hurl_bin}/hurl" --version)"
    if [[ "${_hurl_got}" != "hurl ${GLOBAL_STACK_HURL_VERSION} "* ]]; then
        printf 'FATAL: installed hurl reports "%s", pin is %s - marker not written\n' "${_hurl_got%%$'\n'*}" "${GLOBAL_STACK_HURL_VERSION}" >&2
        exit 1
    fi
    printf '%s\n' "${GLOBAL_STACK_HURL_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/base.hurl"
fi
