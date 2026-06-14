#!/bin/bash
set -euo pipefail

# Check if mise installation is required
if [[ -n "${GLOBAL_STACK_MISE_VERSION}" && "${GLOBAL_STACK_BASE_INSTALL_TOOLS}" == "true" && ! -f "${MISE_INSTALL_PATH}" ]]; then
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
else
    echo "Mise already installed"
fi