#!/bin/bash
set -euo pipefail

# Row 21. Invoked as a bare command by global-stack-base-start.sh, so this is its
# own process and inherits nothing — it sources the version gate alone (never the
# full prologue, which would install an ERR trap this script does not expect).
source global-stack-base-version-gate.sh

# Pin-audit tranche 2 step 14a (rulings 2026-09-25 09:58 and 10:07; pinned by
# startup-prologue.test.sh §63). A reinstall used to extract the new archive OVER the
# old tree, so every file only the old version shipped survived, in either direction,
# and nothing checked the download. Now the archive lands in a temp dir and is checked
# against go's published SHA-256 and for go/bin/go BEFORE anything is removed; only
# then is GOROOT wiped and unpacked fresh, and the marker follows a version check.
#
# GOPATH (go/home) lives inside GOROOT. It is renamed to the sibling go.gopath-aside
# for the wipe and renamed back after the permission pass, so the module cache and the
# `go install`ed binaries survive a bump with their modes untouched. The EXIT trap puts
# it back on any failure. A leftover aside (a run killed mid-reinstall) is restored
# here when GOPATH is absent or an EMPTY dir — the shape the next boot really meets,
# since base-start.sh runs create-directories.sh, which mkdirs GOPATH, before this
# script — and is FATAL only when GOPATH has content. The aside is never deleted.
_go_aside="${GOROOT}.gopath-aside"
_go_nested=0
case "${GOPATH}" in "${GOROOT}"/*) _go_nested=1 ;; esac
_go_restore_gopath() {
    if [[ -e "${_go_aside}" && ! -e "${GOPATH}" ]]; then
        sudo mkdir -p "$(dirname "${GOPATH}")"
        sudo mv -T "${_go_aside}" "${GOPATH}"
    fi
    return 0
}
if [[ -e "${_go_aside}" ]]; then
    # Emptiness is tested first: a bare `rmdir` on a non-empty dir would abort under
    # `set -e` before the FATAL below could say why.
    if [[ -d "${GOPATH}" && -z "$(ls -A "${GOPATH}")" ]]; then
        sudo rmdir "${GOPATH}"
    fi
    if [[ -e "${GOPATH}" ]]; then
        printf 'FATAL: both %s and %s exist - a go reinstall was interrupted; merge them by hand\n' \
            "${_go_aside}" "${GOPATH}" >&2
        exit 1
    fi
    _go_restore_gopath
fi

# Was exist-only: a GLOBAL_STACK_GO_VERSION bump did nothing, because the guard
# only asked whether go was absent or was the distro's /usr/bin/go. That check is
# KEPT as a floor — it is what makes a fresh container install go at all.
_go_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/base.go" "${GLOBAL_STACK_GO_VERSION}" "base.go")"
if [[ -n "${GLOBAL_STACK_GO_VERSION}" ]] &&
   { [[ "${_go_gate}" != "skip" ]] ||
     [[ "/usr/bin/go" = "$(command -v go)" || "" = "$(command -v go)" ]]; }; then
    archive="go${GLOBAL_STACK_GO_VERSION}.linux-amd64.tar.gz"
    _go_dl="$(mktemp -d)"
    trap 'rm -rf "${_go_dl}"; _go_restore_gopath' EXIT
    curl --connect-timeout 30 --max-time 300 -fsSL -o "${_go_dl}/${archive}" "https://go.dev/dl/${archive}"
    # Inside an `if`: a bare failing capture exited on curl's code with nothing naming it.
    if ! _go_sha="$(curl --connect-timeout 30 --max-time 60 -fsSL "https://dl.google.com/go/${archive}.sha256")"; then
        printf 'FATAL: cannot fetch the published SHA-256 of %s - go left as it was\n' "${archive}" >&2
        exit 1
    fi
    if ! printf '%s  %s\n' "${_go_sha}" "${_go_dl}/${archive}" | sha256sum -c --quiet - >/dev/null 2>&1; then
        printf 'FATAL: %s does not match its published SHA-256 - go left as it was\n' "${archive}" >&2
        exit 1
    fi
    # grep reads the whole listing (no -q): an early exit would SIGPIPE tar under pipefail.
    if ! tar -tzf "${_go_dl}/${archive}" | grep -x 'go/bin/go' >/dev/null; then
        printf 'FATAL: %s holds no go/bin/go - go left as it was\n' "${archive}" >&2
        exit 1
    fi

    # Checked: from here on the old tree goes.
    if [[ "${_go_nested}" == 1 && -e "${GOPATH}" ]]; then
        sudo mv -T "${GOPATH}" "${_go_aside}"
    fi
    sudo rm -rf "${GOROOT}"
    sudo mkdir -p "${GOROOT}"
    sudo tar -C "${GOROOT}"/ --strip-components=1 -xzf "${_go_dl}/${archive}"
    if [[ ! -e "${_go_aside}" ]]; then
        sudo mkdir -p "${GOPATH}"
    fi
    sudo chmod -R a+rwx "${GOROOT}"/
    sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}:${GLOBAL_STACK_DOCKER_GROUP_ID}" "${GOROOT}"/
    _go_restore_gopath

    _go_got="$("${GOROOT}/bin/go" version)"
    if [[ "${_go_got}" != "go version go${GLOBAL_STACK_GO_VERSION} "* ]]; then
        printf 'FATAL: installed go reports "%s", pin is %s - marker not written\n' "${_go_got}" "${GLOBAL_STACK_GO_VERSION}" >&2
        exit 1
    fi
    # Marker last: under `set -e` any failure above aborts before this line, so a
    # failed download cannot leave a satisfied marker behind.
    printf '%s\n' "${GLOBAL_STACK_GO_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/base.go"
fi
