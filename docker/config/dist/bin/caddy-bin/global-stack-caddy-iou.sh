#!/bin/bash
# iou = install-or-upgrade

# Enable strict error handling and debugging
set -xeEuo pipefail
shopt -s extdebug
IFS=$'\n\t'

# Define reusable paths
CADDY_PATH="${1}"
HTTP_COMMONS_PATH="${2}"
CADDY_VERSIONS_PATH="${3}"

# Trap errors and handle cleanup or error reporting
trap 'stackCatch $? ${LINENO} "${BASH_COMMAND}"' ERR EXIT

stackCatch() {
  local exit_code=${1}
  local line_num=${2}
  local command=${3}
  # Re-entry guard: ERR fires first, then this handler's own `exit 1` comes back
  # through the EXIT trap and would overwrite the error token with the trap's own
  # line number. The `-ne 1` arm removed below had been doing this by accident, at
  # the cost of silencing exit 1 — the most common real failure in this script's
  # own chain, so a failed INSTALL wrote no error token at all (row 25).
  if [[ -n "${_STACK_CAUGHT:-}" ]]; then
    return 0
  fi
  if [[ "${exit_code}" -ne 0 && "${exit_code}" -ne 141 ]]; then
    _STACK_CAUGHT=1
    echo "Error detected !!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${line_num} ** ** command: ${command} ** caddy global-stack-caddy-iou.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && printf 'line: %s\ncommand: %s\n' "${2}" "${3}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

cd "${CADDY_PATH}"

# Extract the latest and current versions of CADDY
CURRENT_CADDY_VERSION=$( [[ -f "${CADDY_VERSIONS_PATH}" ]] && cat "${CADDY_VERSIONS_PATH}" || echo "null" )

# If the versions differ, update CADDY
if [[ "${GLOBAL_STACK_CADDY_VERSION}" != "${CURRENT_CADDY_VERSION}" ]]; then
  echo -e "\nUpdating caddy from ${CURRENT_CADDY_VERSION} to ${GLOBAL_STACK_CADDY_VERSION}"
  
  # Remove old build directory and checkout the new version
  rm -rf \
    "${CADDY_PATH}/caddy-build"
  mkdir -p \
    "${CADDY_PATH}/caddy-build"
  
  git clone --progress --branch "${GLOBAL_STACK_CADDY_VERSION}" "https://github.com/caddyserver/caddy.git" --depth 1 ${CADDY_PATH}/caddy-build

  # Checkout APR and APR-util if necessary
  cd "${CADDY_PATH}/caddy-build/cmd/caddy/"
  
  # Build and configure caddy
  go build -o ${CADDY_PATH}/bin/caddy

  # Every plugin is version-pinned. A bare `add-package <module>` resolves to whatever Go
  # considers latest AT BUILD TIME, so two builds from the same commit could produce
  # different binaries while the caddy core itself was pinned. transform-encoder has no
  # tagged release at all, so it is pinned by commit SHA (see the .env annotation).
  ${CADDY_PATH}/bin/caddy add-package "github.com/caddyserver/transform-encoder@${GLOBAL_STACK_CADDY_TRANSFORM_ENCODER_VERSION}"
  ${CADDY_PATH}/bin/caddy add-package "github.com/ueffel/caddy-brotli@${GLOBAL_STACK_CADDY_BROTLI_VERSION}"
  ${CADDY_PATH}/bin/caddy add-package "github.com/greenpau/caddy-security@${GLOBAL_STACK_CADDY_SECURITY_VERSION}"
  ${CADDY_PATH}/bin/caddy add-package "github.com/caddyserver/cache-handler@${GLOBAL_STACK_CADDY_CACHE_HANDLER_VERSION}"
  # ${CADDY_PATH}/bin/caddy add-package github.com/dunglas/caddy-cbrotli

  cd "${CADDY_PATH}"

  rm -rf \
    "${CADDY_PATH}/caddy-build"
else
  echo -e "\nCaddy is already the latest version (${GLOBAL_STACK_CADDY_VERSION} - ${CURRENT_CADDY_VERSION})"
fi

# Final permissions and cleanup
cd "${CADDY_PATH}"
chmod a+x "${CADDY_PATH}/bin/caddy"

cd "${GLOBAL_STACK_DOCKER_TOOLS_PATH}"
