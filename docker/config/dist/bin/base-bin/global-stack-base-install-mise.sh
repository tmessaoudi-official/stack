#!/bin/bash
set -euo pipefail

# Row 21 — see global-stack-base-install-go.sh for why the gate helper is sourced
# here rather than the prologue.
source global-stack-base-version-gate.sh

# Was exist-only on ! -f "${MISE_INSTALL_PATH}", so a GLOBAL_STACK_MISE_VERSION
# bump did nothing. The file check is KEPT as a floor; the BASE_INSTALL_TOOLS
# opt-out is unchanged and still short-circuits everything.
#
# Pin-audit tranche 2 step 14b (ruling 2026-09-25 09:58; startup-prologue.test.sh §64).
# This used to wipe the data dirs and THEN pipe https://mise.run into sh, so a failed
# download left mise with no data, and a remote script ran unchecked. The pinned
# release binary and the release's SHASUMS256.txt now land in a temp dir and are
# checked first — checksum, then `--version` — and only then are the data dirs wiped
# and the binary installed. `--version` migrates whatever data dir it is given, so the
# pre-wipe check runs with every MISE_*_DIR pointed into the temp dir.
_mise_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/base.mise" "${GLOBAL_STACK_MISE_VERSION}" "base.mise")"
# Check if mise installation is required
if [[ -n "${GLOBAL_STACK_MISE_VERSION}" && "${GLOBAL_STACK_BASE_INSTALL_TOOLS}" == "true" ]] &&
   { [[ "${_mise_gate}" != "skip" ]] || [[ ! -f "${MISE_INSTALL_PATH}" ]]; }; then
    echo "Installing mise..."

    _mise_asset="mise-${GLOBAL_STACK_MISE_VERSION}-linux-x64"
    _mise_url="https://github.com/jdx/mise/releases/download/${GLOBAL_STACK_MISE_VERSION}"
    _mise_want="${GLOBAL_STACK_MISE_VERSION#v} "
    _mise_dl="$(mktemp -d)"
    trap 'rm -rf "${_mise_dl}"' EXIT
    curl --connect-timeout 30 --max-time 300 -fsSL -o "${_mise_dl}/${_mise_asset}" "${_mise_url}/${_mise_asset}"
    curl --connect-timeout 30 --max-time 60 -fsSL -o "${_mise_dl}/SHASUMS256.txt" "${_mise_url}/SHASUMS256.txt"
    # The release names its assets `./<asset>`, so the check runs inside the temp dir.
    if ! (cd "${_mise_dl}" && grep -xE "[0-9a-f]{64}  \./${_mise_asset}" SHASUMS256.txt | sha256sum -c --quiet - >/dev/null 2>&1); then
        printf 'FATAL: %s does not match the release SHA256SUMS - mise left as it was\n' "${_mise_asset}" >&2
        exit 1
    fi
    chmod 0755 "${_mise_dl}/${_mise_asset}"
    _mise_got="$(MISE_DATA_DIR="${_mise_dl}/d" MISE_STATE_DIR="${_mise_dl}/s" MISE_CONFIG_DIR="${_mise_dl}/c" \
        MISE_CACHE_DIR="${_mise_dl}/k" "${_mise_dl}/${_mise_asset}" --version 2>/dev/null)"
    if [[ "${_mise_got}" != "${_mise_want}"* ]]; then
        printf 'FATAL: downloaded mise reports "%s", pin is %s - mise left as it was\n' "${_mise_got}" "${GLOBAL_STACK_MISE_VERSION}" >&2
        exit 1
    fi

    # Checked: from here on the old install goes.
    # Remove and recreate required directories
    for dir in "${MISE_DATA_DIR}" "${MISE_STATE_DIR}" "${MISE_CONFIG_DIR}" "${MISE_CACHE_DIR}" "${MISE_DATA_DIR}/plugins"; do
        rm -rf "${dir}"
        mkdir -p "${dir}"
    done

    # Prepare mise environment configuration.
    # E-4: build the file content in a temp file then atomic-rename it onto the
    # shared volume so the host never sources a partially-written mise.shellrc
    # (rename is atomic on the same filesystem; both paths live under
    # TOOLS_PATH_SHELLRC).
    mise_shellrc="${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/mise.shellrc"
    {
        # Write environment variables to mise.shellrc
        for var in MISE_DEBUG MISE_QUIET MISE_INSTALL_PATH MISE_VERSION MISE_DATA_DIR MISE_STATE_DIR MISE_CONFIG_DIR MISE_CACHE_DIR; do
            echo "export ${var}=\"${!var}\""
        done
    } > "${mise_shellrc}.tmp" && mv "${mise_shellrc}.tmp" "${mise_shellrc}"

    # `install` removes the old binary and copies the new one in one step.
    mkdir -p "$(dirname "${MISE_INSTALL_PATH}")"
    install -m 0755 "${_mise_dl}/${_mise_asset}" "${MISE_INSTALL_PATH}"
    _mise_got="$("${MISE_INSTALL_PATH}" --version 2>/dev/null)"
    if [[ "${_mise_got}" != "${_mise_want}"* ]]; then
        printf 'FATAL: installed mise reports "%s", pin is %s - marker not written\n' "${_mise_got}" "${GLOBAL_STACK_MISE_VERSION}" >&2
        exit 1
    fi

    # Still fatal on failure, as before: a mise without `usage` is broken, so a marker
    # here would lie; the next boot retries. (`usage` itself floats — pin-audit pass 2.)
    "${MISE_INSTALL_PATH}" use -g usage

    # Marker last: under `set -e` any failure above aborts before this line.
    printf '%s\n' "${GLOBAL_STACK_MISE_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/base.mise"
else
    echo "Mise already installed"
fi
