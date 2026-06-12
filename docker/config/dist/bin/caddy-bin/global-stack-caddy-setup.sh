#!/bin/bash

# Enable strict error handling and debugging
set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'

CADDY_PATH="${1}"

# Trap for specific signals and errors
trap '' PIPE SIGPIPE SIGHUP
trap 'stackCatch $? ${LINENO} "${BASH_COMMAND}"' EXIT ERR

# Function to handle errors and trap cleanup
stackCatch() {
  local exit_code=$1
  local line_num=$2
  local command=$3
  if [[ $exit_code -ne 0 && $exit_code -ne 141 && $exit_code -ne 1 ]]; then
    echo "Error detected!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - line: $line_num, command: $command, caddy global-stack-caddy-setup.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && printf 'line: %s\ncommand: %s\n' "${2}" "${3}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

# Navigate to the CADDY directory and clean up old builds
cd ${CADDY_PATH}

# Create required directories for CADDY configuration
mkdir -p \
  "${CADDY_PATH}"/vhosts

# Remove old configuration and SSL files
rm -rf \
  "${CADDY_PATH}"/vhosts/*

# Sync configuration files from the distribution directory
rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/caddy-conf/sites-available/ "${CADDY_PATH}"/vhosts

# Remove unnecessary files
rm -rf "${CADDY_PATH}"/vhosts/.gitkeep \
  "${CADDY_PATH}"/vhosts/example*

if [[ -f ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/caddy-conf/Caddyfile.local ]]; then
  cp ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/caddy-conf/Caddyfile.local "${CADDY_PATH}"/Caddyfile
else
  cp ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/caddy-conf/Caddyfile "${CADDY_PATH}"/Caddyfile
fi

# Replace placeholders with actual paths
sed -i "s|\${GLOBAL_STACK_DOCKER_TOOLS_PATH}|${GLOBAL_STACK_DOCKER_TOOLS_PATH}|g; s|\${GLOBAL_STACK_DOCKER_WORKDIR}|${GLOBAL_STACK_DOCKER_WORKDIR}|g; s|\${GLOBAL_STACK_SSL_PATH}|${GLOBAL_STACK_SSL_PATH}|g; s|\${CAROOT}|${CAROOT}|g" \
  "${CADDY_PATH}"/Caddyfile

find "${CADDY_PATH}"/vhosts/ -type f -exec sed -i "s|\${GLOBAL_STACK_DOCKER_TOOLS_PATH}|${GLOBAL_STACK_DOCKER_TOOLS_PATH}|g; s|\${GLOBAL_STACK_DOCKER_WORKDIR}|${GLOBAL_STACK_DOCKER_WORKDIR}|g; s|\${GLOBAL_STACK_SSL_PATH}|${GLOBAL_STACK_SSL_PATH}|g; s|\${CAROOT}|${CAROOT}|g" {} \;

rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/http-common/ssl/ "${GLOBAL_STACK_SSL_PATH}"
