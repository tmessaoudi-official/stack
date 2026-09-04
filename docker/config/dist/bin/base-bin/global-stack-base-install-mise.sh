#!/bin/bash
set -euo pipefail

# Row 21 — see global-stack-base-install-go.sh for why the gate helper is sourced
# here rather than the prologue.
source global-stack-base-version-gate.sh

# Was exist-only on ! -f "${MISE_INSTALL_PATH}", so a GLOBAL_STACK_MISE_VERSION
# bump did nothing. The file check is KEPT as a floor; the BASE_INSTALL_TOOLS
# opt-out is unchanged and still short-circuits everything.
_mise_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/base.mise" "${GLOBAL_STACK_MISE_VERSION}" "base.mise")"
# Check if mise installation is required
if [[ -n "${GLOBAL_STACK_MISE_VERSION}" && "${GLOBAL_STACK_BASE_INSTALL_TOOLS}" == "true" ]] &&
   { [[ "${_mise_gate}" != "skip" ]] || [[ ! -f "${MISE_INSTALL_PATH}" ]]; }; then
    echo "Installing mise..."

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

    # Install mise
    curl --connect-timeout 30 --max-time 300 -sSL https://mise.run | sh

    mise use -g usage

    # Marker last: under `set -e` any failure above aborts before this line.
    printf '%s\n' "${GLOBAL_STACK_MISE_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/base.mise"
else
    echo "Mise already installed"
fi