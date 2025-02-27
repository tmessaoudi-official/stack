#!/bin/bash

# Enable strict error handling and debugging
set -xeEuo pipefail
shopt -s extdebug
IFS=$'\n\t'

PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/caddy/bin:${PATH}"
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
  if [[ $exit_code -ne 0 && $exit_code -ne 141 && $exit_code -ne 1 ]]; then
    echo "Error detected!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - line: $line_num, command: $command, caddy global-stack-caddy-start.sh" \
      >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

# Trap errors for cleanup or error reporting
trap 'stackCatch $? ${LINENO} "${BASH_COMMAND}"' ERR EXIT

SECONDS=0

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

# Mark caddy as successfully started
: > "${CADDY_SUCCESSES_PATH}"

# Print success message with duration
DURATION=${SECONDS}
global-stack-base-print-success.sh "${DURATION}" "caddy"

global-stack-base-prepare-shell.sh

echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

# Prevent the script from exiting
sleep infinity