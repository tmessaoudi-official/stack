#!/bin/bash

# Enable strict error handling and debugging
set -xeEuo pipefail
shopt -s extdebug
IFS=$'\n\t'

PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/httpd/bin:${GLOBAL_STACK_DOCKER_TOOLS_PATH}/http/libs/modsecurity/bin:${PATH}"
export PATH

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${GLOBAL_STACK_DOCKER_TOOLS_PATH}/httpd/bin:${GLOBAL_STACK_DOCKER_TOOLS_PATH}/http/libs/modsecurity/bin:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

# Define reusable paths
HTTPD_PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/httpd"
HTTP_COMMONS_PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/http"
HTTPD_LOGS_PATH="${HTTPD_PATH}/logs"
HTTPD_VERSIONS_PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/httpd"
HTTPD_SUCCESSES_PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/web-server"
HTTP_COMMON_MOD_SECURITY_VERSION_PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/http.mod_security"
HTTP_COMMON_CORERULESET_VERSION_PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/http.coreruleset"
MODSECURITY_SOURCE_LIB_PATH="${HTTP_COMMONS_PATH}/libs/modsecurity-source"
MODSECURITY_LIB_PATH="${HTTP_COMMONS_PATH}/libs/modsecurity"
CORERULESET_PATH="${HTTP_COMMONS_PATH}/rules/coreruleset"
MODSECURITY_TMP_PATH="${HTTP_COMMONS_PATH}/mod_security/tmp"
MODSECURITY_LOGS_PATH="${HTTP_COMMONS_PATH}/mod_security/logs"
MODSECURITY_CONF_PATH="${HTTP_COMMONS_PATH}/mod_security/conf"

# Function to handle errors and trap cleanup
stackCatch() {
  local exit_code=$1
  local line_num=$2
  local command=$3
  if [[ $exit_code -ne 0 && $exit_code -ne 141 && $exit_code -ne 1 ]]; then
    echo "Error detected!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - line: $line_num, command: $command, httpd global-stack-httpd-start.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

# Trap errors for cleanup or error reporting
trap 'stackCatch $? ${LINENO} "${BASH_COMMAND}"' ERR EXIT

SECONDS=0

# Remove old httpd success directory
sudo rm -rf \
  "${HTTPD_SUCCESSES_PATH}"

global-stack-base-wait-for.sh \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

# Clean up old installations if needed
if [[ "${GLOBAL_STACK_RELOAD_HTTPD}" == "true" ]] || \
   [[ ! -e "${HTTPD_VERSIONS_PATH}" ]] || \
   [[ "$(cat "${HTTPD_VERSIONS_PATH}")" != "${GLOBAL_STACK_HTTPD_VERSION}" ]]; then
  rm -rf \
    "${HTTPD_PATH}" \
    "${HTTPD_VERSIONS_PATH}" \
    "${HTTPD_SUCCESSES_PATH}"
fi

# Clean up old http common installations if needed
if [[ "${GLOBAL_STACK_RELOAD_HTTP_COMMON}" == "true" ]]; then
  rm -rf \
    "${HTTP_COMMONS_PATH}" \
    "${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}" \
    "${HTTP_COMMON_CORERULESET_VERSION_PATH}"
fi

# Clean mod_security if version mismatch
if [[ -n "${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}" ]] && \
   { [[ ! -e "${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}" ]] || \
     [[ "$(cat "${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}")" != "${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}" ]]; }; then
  rm -rf \
    "${MODSECURITY_SOURCE_LIB_PATH}" \
    "${MODSECURITY_LIB_PATH}" \
    "${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}" \
    "${MODSECURITY_TMP_PATH}" \
    "${MODSECURITY_LOGS_PATH}" \
    "${MODSECURITY_CONF_PATH}"
fi

# Clean CoreRuleSet if version mismatch
if [[ -n "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" ]] && \
   { [[ ! -e "${HTTP_COMMON_CORERULESET_VERSION_PATH}" ]] || \
     [[ "$(cat "${HTTP_COMMON_CORERULESET_VERSION_PATH}")" != "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" ]]; }; then
  rm -rf \
    "${CORERULESET_PATH}" \
    "${HTTP_COMMON_CORERULESET_VERSION_PATH}"
fi

# Create temporary directory for httpd
mkdir -p \
  "${HTTPD_PATH}/tmp"

# Run IOU setup for common HTTPd components if required
if [[ "${GLOBAL_STACK_RELOAD_HTTP_COMMON}" == "true" ]] || \
   { [[ -n "${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}" ]] && \
     { [[ ! -e "${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}" ]] || \
       [[ "$(cat "${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}")" != "${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}" ]]; }; } || \
   { [[ -n "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" ]] && \
     { [[ ! -e "${HTTP_COMMON_CORERULESET_VERSION_PATH}" ]] || \
       [[ "$(cat "${HTTP_COMMON_CORERULESET_VERSION_PATH}")" != "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" ]]; }; }; then
  global-stack-httpd-iou-common.sh \
    "${HTTP_COMMONS_PATH}" \
    "${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}" \
    "${HTTP_COMMON_CORERULESET_VERSION_PATH}" \
    "${MODSECURITY_SOURCE_LIB_PATH}" \
    "${MODSECURITY_LIB_PATH}" \
    "${CORERULESET_PATH}"
fi

# Install httpd if necessary
if [[ ! -f "${HTTPD_VERSIONS_PATH}" || "${GLOBAL_STACK_RELOAD_HTTPD}" == "true" ]]; then
  global-stack-httpd-iou.sh \
    "${HTTPD_PATH}" \
    "${HTTP_COMMONS_PATH}" \
    "${HTTPD_VERSIONS_PATH}" \
    "${MODSECURITY_SOURCE_LIB_PATH}" \
    "${MODSECURITY_LIB_PATH}" \
    "${CORERULESET_PATH}"
fi

# Run httpd setup and mkcert commands
global-stack-httpd-setup.sh \
    "${HTTPD_PATH}" \
    "${MODSECURITY_TMP_PATH}" \
    "${MODSECURITY_LOGS_PATH}" \
    "${MODSECURITY_CONF_PATH}"

global-stack-base-init-mkcert.sh

# Stop any running instance of Apache (ignore errors)
"${HTTPD_PATH}/bin/apachectl" stop 2>/dev/null || true

# Remove old PID and cgisock files
sudo rm -rf \
  "${HTTPD_LOGS_PATH}/httpd.pid" \
  ${HTTPD_LOGS_PATH}/cgisock*

# Start Apache in the foreground
"${HTTPD_PATH}/bin/apachectl" -D FOREGROUND &

# Save the updated httpd version if installed or reloaded
if [[ ! -f "${HTTPD_VERSIONS_PATH}" || "${GLOBAL_STACK_RELOAD_HTTPD}" == "true" ]]; then
  echo "${GLOBAL_STACK_HTTPD_VERSION}" > "${HTTPD_VERSIONS_PATH}"
fi

global-stack-base-prepare-shell.sh

echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION=${SECONDS}
global-stack-base-print-success.sh "${DURATION}" "httpd"

: > "${HTTPD_SUCCESSES_PATH}"

# Prevent the script from exiting
sleep infinity