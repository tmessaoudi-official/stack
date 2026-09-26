#!/bin/bash

set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

echo -e "\nInstalling tools"

# Pin-audit tranche 3 step 19 (ruling 2026-09-26 11:17; pinned by startup-prologue.test.sh
# §71). deno ran a downloaded install.sh in the cwd, which is compose's working_dir, the
# developer's /stack/projects; bun was `curl https://bun.sh/install | bash`. Both removed
# the old binary and its marker BEFORE fetching, so a failed download lost a working tool,
# and neither download was checked. Now each pinned release zip lands in a temp dir and
# is checked: its own line in the published checksum file (an unlisted asset is refused),
# the zip holds the binary, and the binary's own --version prints the pin. Only then does
# `install` replace the old binary, and the marker is written last. Every failure is a
# named FATAL that leaves the old binary and marker as they were.
# Dropped with the installers (they touched the container's home, never tools/): their
# ~/.bashrc edits, deno's shell setup and `bun completions`. The bunx link that
# `bun completions` used to make is made here instead.
_nt_dl="$(mktemp -d)"
cd "${_nt_dl}"

_nt_fatal() {
    printf 'FATAL: %s\n' "$1" >&2
    exit 1
}

# _nt_fetch <tool> <release url> <asset> <checksum file>
_nt_fetch() {
    local d="${_nt_dl}/$1" want
    mkdir -p "${d}"
    if ! curl --connect-timeout 30 --max-time 300 -fsSL -o "${d}/$3" "$2/$3" \
        || ! curl --connect-timeout 30 --max-time 60 -fsSL -o "${d}/$4" "$2/$4"; then
        _nt_fatal "$1: $2/$3 could not be downloaded - $1 left as it was"
    fi
    if ! want="$(awk -v n="$3" '$2 == n && length($1) == 64 { print $1 }' "${d}/$4")" \
        || [[ "$(grep -c . <<<"${want}")" != 1 ]]; then
        _nt_fatal "$1: $4 lists no single checksum for $3 - $1 left as it was"
    fi
    if ! printf '%s  %s\n' "${want}" "${d}/$3" | sha256sum -c --quiet - >/dev/null 2>&1; then
        _nt_fatal "$1: $3 does not match its published SHA-256 - $1 left as it was"
    fi
}

# _nt_unzip <tool> <asset> <member>: extracts the member into ${_nt_dl}/<tool>/x/
_nt_unzip() {
    local d="${_nt_dl}/$1"
    # grep reads the whole listing (no -q): an early exit would SIGPIPE unzip under pipefail.
    if ! unzip -Z1 "${d}/$2" 2>/dev/null | grep -xF "$3" >/dev/null; then
        _nt_fatal "$1: $2 is not a zip holding $3 - $1 left as it was"
    fi
    unzip -q -o "${d}/$2" "$3" -d "${d}/x"
}

DENO_JS="${DENO_INSTALL}/bin/deno"
# Content-compare gate (row 16). The `-f` check is a FLOOR: a marker can outlive its
# artifact (a hand-cleaned tools/ tree), and `make down` clears successes/ but not versions/.
_deno_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm.deno" "${GLOBAL_STACK_DENO_VERSION}" "nvm.deno")"
if [ "${_deno_gate}" = "skip" ] && [ -f "${DENO_JS}" ]; then
    echo "**** ${DENO_JS} already installed (${GLOBAL_STACK_DENO_VERSION})."
else
    echo "**** Installing ${DENO_JS}"
    _nt_fetch deno "https://github.com/denoland/deno/releases/download/${GLOBAL_STACK_DENO_VERSION}" \
        deno-x86_64-unknown-linux-gnu.zip deno-x86_64-unknown-linux-gnu.zip.sha256sum
    _nt_unzip deno deno-x86_64-unknown-linux-gnu.zip deno
    # The first line is `deno <version> (stable, ...)`: the space after the version is
    # what stops 2.9.70 from passing for 2.9.7.
    if ! _nt_says="$("${_nt_dl}/deno/x/deno" --version 2>&1)" \
        || [[ "${_nt_says%%$'\n'*}" != "deno ${GLOBAL_STACK_DENO_VERSION#v} "* ]]; then
        _nt_fatal "deno ${GLOBAL_STACK_DENO_VERSION}: the downloaded binary reports \"${_nt_says%%$'\n'*}\" - deno left as it was"
    fi
    mkdir -p "${DENO_INSTALL}/bin"
    install -m 0755 "${_nt_dl}/deno/x/deno" "${DENO_JS}"
    printf '%s\n' "${GLOBAL_STACK_DENO_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm.deno"
fi
# deno upgrade

# if [ ! -f "${DENO_INSTALL_ROOT}/bin/aleph" ]; then
#   deno install --global --allow-import --allow-read --allow-write --allow-net --force --name aleph https://deno.land/x/aleph@${GLOBAL_STACK_DENO_ALEPH_VERSION}/init.ts
# fi

# if [ ! -f "${DENO_INSTALL_ROOT}/bin/mandarine" ]; then
#   deno install --global --allow-import --allow-read --allow-write --allow-run --force --name mandarine https://deno.land/x/mandarinets@${GLOBAL_STACK_DENO_MANDARINETS_VERSION}/cli.ts
# fi

BUN_JS="${BUN_INSTALL}/bin/bun"
# Same gate as deno above; same floor for the marker-outlives-artifact case.
_bun_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm.bun" "${GLOBAL_STACK_BUN_VERSION}" "nvm.bun")"
if [ "${_bun_gate}" = "skip" ] && [ -f "${BUN_JS}" ]; then
    echo "**** ${BUN_JS} already installed (${GLOBAL_STACK_BUN_VERSION})."
else
    echo "**** Installing ${BUN_JS}"
    _nt_fetch bun "https://github.com/oven-sh/bun/releases/download/${GLOBAL_STACK_BUN_VERSION}" \
        bun-linux-x64.zip SHASUMS256.txt
    _nt_unzip bun bun-linux-x64.zip bun-linux-x64/bun
    if ! _nt_says="$("${_nt_dl}/bun/x/bun-linux-x64/bun" --version 2>&1)" \
        || [[ "${_nt_says}" != "${GLOBAL_STACK_BUN_VERSION#bun-v}" ]]; then
        _nt_fatal "bun ${GLOBAL_STACK_BUN_VERSION}: the downloaded binary reports \"${_nt_says}\" - bun left as it was"
    fi
    mkdir -p "${BUN_INSTALL}/bin"
    install -m 0755 "${_nt_dl}/bun/x/bun-linux-x64/bun" "${BUN_JS}"
    ln -sfn "${BUN_JS}" "${BUN_INSTALL}/bin/bunx"
    printf '%s\n' "${GLOBAL_STACK_BUN_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm.bun"
fi

cd /
rm -rf "${_nt_dl}"
