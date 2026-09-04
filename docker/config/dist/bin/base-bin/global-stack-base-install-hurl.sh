#!/bin/bash
set -euo pipefail

# Row 21 — see global-stack-base-install-go.sh for why the gate helper is sourced
# here rather than the prologue.
source global-stack-base-version-gate.sh

_hurl_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/base.hurl" "${GLOBAL_STACK_HURL_VERSION}" "base.hurl")"
if [[ -n "${GLOBAL_STACK_HURL_VERSION}" ]] &&
   { [[ "${_hurl_gate}" != "skip" ]] || [[ "" = "$(command -v hurl)" ]]; }; then
    sudo mkdir -p "${GLOBAL_STACK_HURLPATH}"
    sudo chmod -R a+rwx "${GLOBAL_STACK_HURLPATH}"
    sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}:${GLOBAL_STACK_DOCKER_GROUP_ID}" "${GLOBAL_STACK_HURLPATH}"

    archive="hurl-${GLOBAL_STACK_HURL_VERSION}-x86_64-unknown-linux-gnu.tar.gz"
    curl --connect-timeout 30 --max-time 300 -fsSLO "https://github.com/Orange-OpenSource/hurl/releases/download/${GLOBAL_STACK_HURL_VERSION}/${archive}"
    tar -C "${GLOBAL_STACK_HURLPATH}" --strip-components=1 -xzf "${archive}"

    rm -rf "${archive}"
    printf '%s\n' "${GLOBAL_STACK_HURL_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/base.hurl"
fi
