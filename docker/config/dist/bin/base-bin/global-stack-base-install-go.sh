#!/bin/bash
set -euo pipefail

# Row 21. Invoked as a bare command by global-stack-base-start.sh, so this is its
# own process and inherits nothing — it sources the version gate alone (never the
# full prologue, which would install an ERR trap this script does not expect).
source global-stack-base-version-gate.sh

# Was exist-only: a GLOBAL_STACK_GO_VERSION bump did nothing, because the guard
# only asked whether go was absent or was the distro's /usr/bin/go. That check is
# KEPT as a floor — it is what makes a fresh container install go at all.
_go_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/base.go" "${GLOBAL_STACK_GO_VERSION}" "base.go")"
if [[ -n "${GLOBAL_STACK_GO_VERSION}" ]] &&
   { [[ "${_go_gate}" != "skip" ]] ||
     [[ "/usr/bin/go" = "$(command -v go)" || "" = "$(command -v go)" ]]; }; then
    archive="go${GLOBAL_STACK_GO_VERSION}.linux-amd64.tar.gz"
    mkdir -p "${GOROOT}"/
    curl --connect-timeout 30 --max-time 300 -fsSLO "https://go.dev/dl/${archive}"
    sudo tar -C "${GOROOT}"/ --strip-components=1 -xzf "${archive}"
    sudo mkdir -p "${GOPATH}"
    sudo chmod -R a+rwx "${GOROOT}"/
    sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}:${GLOBAL_STACK_DOCKER_GROUP_ID}" "${GOROOT}"/
    rm -rf "${archive}"
    # Marker last: under `set -e` any failure above aborts before this line, so a
    # failed download cannot leave a satisfied marker behind.
    printf '%s\n' "${GLOBAL_STACK_GO_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/base.go"
fi
