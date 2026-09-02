#!/bin/bash

# Enable strict error handling and debugging
set -xeEuo pipefail
shopt -s extdebug
IFS=$'\n\t'

PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/caddy/bin${PATH}"
export PATH

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${GLOBAL_STACK_DOCKER_TOOLS_PATH}/caddy/bin:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

# Define reusable paths
CADDY_PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/caddy"
CADDY_LOGS_PATH="${CADDY_PATH}/logs"
CADDY_VERSIONS_PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/caddy"
CADDY_SUCCESSES_PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/web-server"

# Function to handle errors and trap cleanup
stackCatch() {
  local exit_code=$1
  local line_num=$2
  local command=$3
  # Re-entry guard: ERR fires first, then this handler's own `exit 1` comes back
  # through the EXIT trap and would overwrite the error token with the trap's own
  # line number. The `-ne 1` arm removed below had been doing this by accident,
  # at the cost of silencing exit 1 — the most common real failure here.
  if [[ -n "${_STACK_CAUGHT:-}" ]]; then
    return 0
  fi
  if [[ $exit_code -ne 0 && $exit_code -ne 141 ]]; then
    _STACK_CAUGHT=1
    echo "Error detected!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - line: $line_num, command: $command, caddy global-stack-caddy-start.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && printf 'line: %s\ncommand: %s\n' "${2}" "${3}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

# Trap errors for cleanup or error reporting
trap 'stackCatch $? ${LINENO} "${BASH_COMMAND}"' ERR EXIT

SECONDS=0

# Clear this run's stale error token before doing anything that can fail, so a
# consumer waiting on successes/web-server does not fail-fast on the PREVIOUS
# boot's failure. Byte-matches the repo-wide literal (19 sites).
rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"

# Remove old caddy success directory
sudo rm -rf \
  "${CADDY_SUCCESSES_PATH}"

global-stack-base-wait-for.sh \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

# Clean up old installations if needed
if [[ "${GLOBAL_STACK_RELOAD_CADDY}" = "true" ]] || \
   [[ ! -f "${CADDY_VERSIONS_PATH}" ]] || \
   [[ "$(cat "${CADDY_VERSIONS_PATH}")" != "${GLOBAL_STACK_CADDY_VERSION}" ]]; then
  rm -rf \
    "${CADDY_PATH}" \
    "${CADDY_VERSIONS_PATH}" \
    "${CADDY_SUCCESSES_PATH}"
fi

# Create temporary directory for caddy
mkdir -p \
  "${CADDY_PATH}/tmp" \
  "${CADDY_PATH}/logs" \
  "${CADDY_PATH}/vhosts" \
  "${CADDY_PATH}/bin"

# Install caddy if necessary
if [[ ! -f "${CADDY_VERSIONS_PATH}" || "${GLOBAL_STACK_RELOAD_CADDY}" == "true" ]]; then
  global-stack-caddy-iou.sh \
    "${CADDY_PATH}" \
    "${CADDY_VERSIONS_PATH}" \
    "${CADDY_VERSIONS_PATH}"
fi

# Run caddy setup and mkcert commands
global-stack-caddy-setup.sh \
    "${CADDY_PATH}"

global-stack-base-init-mkcert.sh

# Stop any running instance of Caddy (ignore errors)
"${CADDY_PATH}"/bin/caddy stop &

# # Remove old PID and cgisock files
# sudo rm -rf \
#   "${CADDY_LOGS_PATH}/httpd.pid" \
#   ${CADDY_LOGS_PATH}/cgisock*

# Start Caddy in the foreground
"${CADDY_PATH}"/bin/caddy run --config ${CADDY_PATH}/Caddyfile &

# Save the updated caddy version if installed or reloaded
if [[ ! -f "${CADDY_VERSIONS_PATH}" || "${GLOBAL_STACK_RELOAD_CADDY}" == "true" ]]; then
  echo "${GLOBAL_STACK_CADDY_VERSION}" > "${CADDY_VERSIONS_PATH}"
fi

global-stack-base-prepare-shell.sh

echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION=${SECONDS}
global-stack-base-print-success.sh "${DURATION}" "caddy"

: > "${CADDY_SUCCESSES_PATH}"

if [[ "${GLOBAL_STACK_RELOAD_CADDY:-false}" = "true" ]]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_CADDY is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi

sleep infinity