#!/bin/bash
set -euo pipefail

# Row 21 — see global-stack-base-install-go.sh for why the gate helper is sourced
# here rather than the prologue.
source global-stack-base-version-gate.sh

# Pin-audit tranche 2 step 14a — same shape as install-go.sh (startup-prologue.test.sh
# §63): the archive is checked against the SHA-256 in ziglang.org's index.json and for
# its zig binary BEFORE the old tree is removed, then the tree is wiped and unpacked
# fresh, and the marker follows a version check. It used to extract over the old tree.
_zig_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/base.zig" "${GLOBAL_STACK_ZIG_VERSION}" "base.zig")"
if [[ -n "${GLOBAL_STACK_ZIG_VERSION}" ]] &&
   { [[ "${_zig_gate}" != "skip" ]] || [[ "" = "$(command -v zig)" ]]; }; then
    _zig_top="zig-x86_64-linux-${GLOBAL_STACK_ZIG_VERSION}"
    archive="${_zig_top}.tar.xz"
    _zig_dl="$(mktemp -d)"
    trap 'rm -rf "${_zig_dl}"' EXIT
    curl --connect-timeout 30 --max-time 300 -fsSL -o "${_zig_dl}/${archive}" "https://ziglang.org/download/${GLOBAL_STACK_ZIG_VERSION}/${archive}"
    _zig_sha="$(curl --connect-timeout 30 --max-time 60 -fsSL https://ziglang.org/download/index.json \
        | jq -r --arg v "${GLOBAL_STACK_ZIG_VERSION}" '.[$v]["x86_64-linux"].shasum // empty')"
    if ! printf '%s  %s\n' "${_zig_sha}" "${_zig_dl}/${archive}" | sha256sum -c --quiet - >/dev/null 2>&1; then
        printf 'FATAL: %s does not match the SHA-256 in index.json - zig left as it was\n' "${archive}" >&2
        exit 1
    fi
    # grep reads the whole listing (no -q): an early exit would SIGPIPE tar under pipefail.
    if ! tar -tJf "${_zig_dl}/${archive}" | grep -x "${_zig_top}/zig" >/dev/null; then
        printf 'FATAL: %s holds no %s/zig - zig left as it was\n' "${archive}" "${_zig_top}" >&2
        exit 1
    fi

    # Checked: from here on the old tree goes.
    sudo rm -rf "${GLOBAL_STACK_ZIGPATH}"
    sudo mkdir -p "${GLOBAL_STACK_ZIGPATH}"
    sudo tar -C "${GLOBAL_STACK_ZIGPATH}"/ --strip-components=1 -xJf "${_zig_dl}/${archive}"
    sudo chmod -R a+rwx "${GLOBAL_STACK_ZIGPATH}"/
    sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}:${GLOBAL_STACK_DOCKER_GROUP_ID}" "${GLOBAL_STACK_ZIGPATH}"/

    _zig_got="$("${GLOBAL_STACK_ZIGPATH}/zig" version)"
    if [[ "${_zig_got}" != "${GLOBAL_STACK_ZIG_VERSION}" ]]; then
        printf 'FATAL: installed zig reports "%s", pin is %s - marker not written\n' "${_zig_got}" "${GLOBAL_STACK_ZIG_VERSION}" >&2
        exit 1
    fi
    printf '%s\n' "${GLOBAL_STACK_ZIG_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/base.zig"
fi
