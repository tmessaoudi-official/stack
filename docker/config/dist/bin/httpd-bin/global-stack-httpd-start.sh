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
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - line: $line_num, command: $command, httpd global-stack-httpd-start.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && printf 'line: %s\ncommand: %s\n' "${2}" "${3}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

# Trap errors for cleanup or error reporting
trap 'stackCatch $? ${LINENO} "${BASH_COMMAND}"' ERR EXIT

SECONDS=0

# Clear this run's stale error token before doing anything that can fail, so a
# consumer waiting on successes/web-server does not fail-fast on the PREVIOUS
# boot's failure. Byte-matches the repo-wide literal the convention audit
# greps for — no count here, a number in a comment only rots.
rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"

# Remove old httpd success directory
sudo rm -rf \
  "${HTTPD_SUCCESSES_PATH}"

global-stack-base-wait-for.sh \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

# Row 20. Prologue-EXEMPT script, so the version gate is sourced ALONE — that is
# what row 15's extraction exists for. Sourced here, above the first use.
source global-stack-base-version-gate.sh

# The marker is composite (tranche 3 step 23, startup-prologue.test.sh §75): apr and apr-util
# are built into httpd, and the ModSecurity connector links the shared libmodsecurity, so a
# bump of any of them must rebuild httpd too — the gate used to hold HTTPD_VERSION alone (A5).
_httpd_want="${GLOBAL_STACK_HTTPD_VERSION};apr=${GLOBAL_STACK_HTTPD_APR_VERSION};apr-util=${GLOBAL_STACK_HTTPD_APR_UTIL_VERSION};modsec-lib=${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION};modsec-apache=${GLOBAL_STACK_HTTPD_MODSECURITY_MOD_VERSION};openidc=${GLOBAL_STACK_HTTPD_MOD_AUTH_OPENIDC_VERSION}"
_httpd_gate="$(gs_version_gate "${HTTPD_VERSIONS_PATH}" "${_httpd_want}" "httpd")"

# RELOAD_HTTP_COMMON is the explicit full reinstall of the shared tree, so it still wipes
# up front. Nothing else is wiped here any more: iou-common and the iou fetch and check
# every input first and only then replace what they build (tranche 3 step 23).
if [[ "${GLOBAL_STACK_RELOAD_HTTP_COMMON}" == "true" ]]; then
  rm -rf \
    "${HTTP_COMMONS_PATH}" \
    "${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}" \
    "${HTTP_COMMON_CORERULESET_VERSION_PATH}"
fi

# The shared ModSecurity library and the CoreRuleSet gate THEMSELVES inside iou-common,
# which runs on every boot: a current marker is a no-op there. It must run before the
# httpd iou, whose ModSecurity connector links the library.
global-stack-httpd-iou-common.sh \
  "${HTTP_COMMONS_PATH}" \
  "${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}" \
  "${HTTP_COMMON_CORERULESET_VERSION_PATH}" \
  "${MODSECURITY_SOURCE_LIB_PATH}" \
  "${MODSECURITY_LIB_PATH}" \
  "${CORERULESET_PATH}"

# Build httpd if necessary. The iou fetches and checks every source before it wipes
# ${HTTPD_PATH} (logs/ kept), builds at that prefix and checks the result; the marker
# follows its success.
if [[ "${_httpd_gate}" != "skip" || "${GLOBAL_STACK_RELOAD_HTTPD}" == "true" ]]; then
  global-stack-httpd-iou.sh \
    "${HTTPD_PATH}" \
    "${MODSECURITY_LIB_PATH}"
  printf '%s\n' "${_httpd_want}" >"${HTTPD_VERSIONS_PATH}"
fi

# Create temporary directory for httpd
mkdir -p \
  "${HTTPD_PATH}/tmp"

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

global-stack-base-prepare-shell.sh

echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION=${SECONDS}
global-stack-base-print-success.sh "${DURATION}" "httpd"

: > "${HTTPD_SUCCESSES_PATH}"

if [[ "${GLOBAL_STACK_RELOAD_HTTPD:-false}" = "true" ]]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_HTTPD is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi
if [[ "${GLOBAL_STACK_RELOAD_HTTP_COMMON:-false}" = "true" ]]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_HTTP_COMMON is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi

# Prevent the script from exiting
sleep infinity
