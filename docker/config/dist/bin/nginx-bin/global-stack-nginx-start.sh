#!/bin/bash

# Enable strict error handling and debugging
set -xeEuo pipefail
shopt -s extdebug
IFS=$'\n\t'

PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/nginx/sbin:${GLOBAL_STACK_DOCKER_TOOLS_PATH}/http/libs/modsecurity/bin:/opt/automake-${GLOBAL_STACK_NGINX_AUTOMAKE_VERSION}/bin:${PATH}"
export PATH

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${GLOBAL_STACK_DOCKER_TOOLS_PATH}/nginx/sbin:${GLOBAL_STACK_DOCKER_TOOLS_PATH}/http/libs/modsecurity/bin:/opt/automake-${GLOBAL_STACK_NGINX_AUTOMAKE_VERSION}/bin:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

# Define reusable paths
NGINX_PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/nginx"
HTTP_COMMONS_PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/http"
NGINX_LOGS_PATH="${NGINX_PATH}/logs"
NGINX_VERSIONS_PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nginx"
NGINX_SUCCESSES_PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/web-server"
HTTP_COMMON_MOD_SECURITY_VERSION_PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/http.mod_security"
HTTP_COMMON_CORERULESET_VERSION_PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/http.coreruleset"
MODSECURITY_SOURCE_LIB_PATH="${HTTP_COMMONS_PATH}/libs/modsecurity-source"
MODSECURITY_LIB_PATH="${HTTP_COMMONS_PATH}/libs/modsecurity"
NGINX_CJOSE_VERSION_PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nginx.cjose"
CJOSE_SOURCE_PATH="${NGINX_PATH}/libs/cjose-source"
CJOSE_PATH="${NGINX_PATH}/libs/cjose"
NGINX_LIBOAUTH2_VERSION_PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nginx.liboauth2"
LIBOAUTH2_SOURCE_PATH="${NGINX_PATH}/libs/liboauth2-source"
LIBOAUTH2_PATH="${NGINX_PATH}/libs/liboauth2"
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
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - line: $line_num, command: $command, nginx global-stack-nginx-start.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

# Trap errors for cleanup or error reporting
trap 'stackCatch $? ${LINENO} "${BASH_COMMAND}"' ERR EXIT

SECONDS=0

# Remove old nginx success directory
sudo rm -rf \
  "${NGINX_SUCCESSES_PATH}"

global-stack-base-wait-for.sh \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

# Clean up old installations if needed
if [[ "${GLOBAL_STACK_RELOAD_NGINX}" == "true" ]] || \
   [[ ! -e "${NGINX_VERSIONS_PATH}" ]] || \
   [[ "$(cat "${NGINX_VERSIONS_PATH}")" != "${GLOBAL_STACK_NGINX_VERSION}" ]]; then
  rm -rf \
    "${NGINX_PATH}" \
    "${NGINX_VERSIONS_PATH}" \
    "${NGINX_CJOSE_VERSION_PATH}" \
    "${NGINX_LIBOAUTH2_VERSION_PATH}" \
    "${NGINX_SUCCESSES_PATH}"
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

# Clean mod_auth_openidc if version mismatch
if [[ -n "${GLOBAL_STACK_NGINX_CJOSE_VERSION}" ]] && \
   { [[ ! -e "${NGINX_CJOSE_VERSION_PATH}" ]] || \
     [[ "$(cat "${NGINX_CJOSE_VERSION_PATH}")" != "${GLOBAL_STACK_NGINX_CJOSE_VERSION}" ]]; }; then
  rm -rf \
    "${CJOSE_SOURCE_PATH}" \
    "${CJOSE_PATH}" \
    "${NGINX_CJOSE_VERSION_PATH}"
fi

# Clean mod_auth_openidc if version mismatch
if [[ -n "${GLOBAL_STACK_NGINX_LIBOAUTH2_VERSION}" ]] && \
   { [[ ! -e "${NGINX_LIBOAUTH2_VERSION_PATH}" ]] || \
     [[ "$(cat "${NGINX_LIBOAUTH2_VERSION_PATH}")" != "${GLOBAL_STACK_NGINX_LIBOAUTH2_VERSION}" ]]; }; then
  rm -rf \
    "${LIBOAUTH2_SOURCE_PATH}" \
    "${LIBOAUTH2_PATH}" \
    "${NGINX_LIBOAUTH2_VERSION_PATH}"
fi

# Clean CoreRuleSet if version mismatch
if [[ -n "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" ]] && \
   { [[ ! -e "${HTTP_COMMON_CORERULESET_VERSION_PATH}" ]] || \
     [[ "$(cat "${HTTP_COMMON_CORERULESET_VERSION_PATH}")" != "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" ]]; }; then
  rm -rf \
    "${CORERULESET_PATH}" \
    "${HTTP_COMMON_CORERULESET_VERSION_PATH}"
fi

# Create temporary directory for nginx
mkdir -p \
  "${NGINX_PATH}/tmp"

# Run IOU setup for common HTTPd components if required
if [[ "${GLOBAL_STACK_RELOAD_HTTP_COMMON}" == "true" ]] || \
   { [[ -n "${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}" ]] && \
     { [[ ! -e "${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}" ]] || \
       [[ "$(cat "${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}")" != "${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}" ]]; }; } || \
   { [[ -n "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" ]] && \
     { [[ ! -e "${HTTP_COMMON_CORERULESET_VERSION_PATH}" ]] || \
       [[ "$(cat "${HTTP_COMMON_CORERULESET_VERSION_PATH}")" != "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" ]]; }; }; then
  global-stack-nginx-iou-common.sh \
    "${HTTP_COMMONS_PATH}" \
    "${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}" \
    "${HTTP_COMMON_CORERULESET_VERSION_PATH}" \
    "${MODSECURITY_SOURCE_LIB_PATH}" \
    "${MODSECURITY_LIB_PATH}" \
    "${CORERULESET_PATH}"
fi

# Install nginx if necessary
if [[ ! -f "${NGINX_VERSIONS_PATH}" || "${GLOBAL_STACK_RELOAD_NGINX}" == "true" ]]; then
  global-stack-nginx-iou.sh \
    "${NGINX_PATH}" \
    "${HTTP_COMMONS_PATH}" \
    "${NGINX_VERSIONS_PATH}" \
    "${MODSECURITY_SOURCE_LIB_PATH}" \
    "${MODSECURITY_LIB_PATH}" \
    "${CORERULESET_PATH}" \
    "${CJOSE_SOURCE_PATH}" \
    "${CJOSE_PATH}" \
    "${LIBOAUTH2_SOURCE_PATH}" \
    "${LIBOAUTH2_PATH}" \
    "${NGINX_LIBOAUTH2_VERSION_PATH}" \
    "${NGINX_CJOSE_VERSION_PATH}"
fi

# Run nginx setup and mkcert commands
global-stack-nginx-setup.sh \
    "${NGINX_PATH}" \
    "${MODSECURITY_TMP_PATH}" \
    "${MODSECURITY_LOGS_PATH}" \
    "${MODSECURITY_CONF_PATH}"

global-stack-base-init-mkcert.sh

# Stop any running instance of Nginx (ignore errors)
"${NGINX_PATH}/sbin/nginx" stop 2>/dev/null || true

# Remove old PID and cgisock files
sudo rm -rf \
  "${NGINX_LOGS_PATH}/nginx.pid"

# Start Nginx in the foreground
"${NGINX_PATH}/sbin/nginx" -g "daemon off;" &

# Save the updated nginx version if installed or reloaded
if [[ ! -f "${NGINX_VERSIONS_PATH}" || "${GLOBAL_STACK_RELOAD_NGINX}" == "true" ]]; then
  echo "${GLOBAL_STACK_NGINX_VERSION}" > "${NGINX_VERSIONS_PATH}"
fi

global-stack-base-prepare-shell.sh

echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION=${SECONDS}
global-stack-base-print-success.sh "${DURATION}" "nginx"

: > "${NGINX_SUCCESSES_PATH}"

# Prevent the script from exiting
sleep infinity