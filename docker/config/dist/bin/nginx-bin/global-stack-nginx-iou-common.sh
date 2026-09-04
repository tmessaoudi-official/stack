#!/bin/bash

# Enable strict error handling and debugging
set -xeEuo pipefail
shopt -s extdebug
IFS=$'\n\t'

# Row 20: prologue-exempt, so the version gate is sourced alone.
source global-stack-base-version-gate.sh

# Define reusable paths passed as arguments
HTTP_COMMONS_PATH="${1}"
HTTP_COMMON_MOD_SECURITY_VERSION_PATH="${2}"
HTTP_COMMON_CORERULESET_VERSION_PATH="${3}"
MODSECURITY_SOURCE_LIB_PATH="${4}"
MODSECURITY_LIB_PATH="${5}"
CORERULESET_PATH="${6}"

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
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - line: $line_num, command: $command, nginx global-stack-nginx-iou-common.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && printf 'line: %s\ncommand: %s\n' "${2}" "${3}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

# Trap errors for cleanup or error reporting
trap 'stackCatch $? ${LINENO} "${BASH_COMMAND}"' ERR EXIT

# Install ModSecurity if needed
if [[ -n "${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}" ]] && \
   [ "$(gs_version_gate "${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}" "${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}" "http.mod_security")" != "skip" ]; then
  
  # Create directory for the ModSecurity source & lib
  mkdir -p \
    "${MODSECURITY_SOURCE_LIB_PATH}" \
    "${MODSECURITY_LIB_PATH}"
  
  # Clone the ModSecurity repository
  git clone --progress \
    --branch "${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}" \
    https://github.com/SpiderLabs/ModSecurity.git \
    --depth 1 \
    "${MODSECURITY_SOURCE_LIB_PATH}"
  
  # Configure Git and update submodules
  git -C "${MODSECURITY_SOURCE_LIB_PATH}" config core.fileMode false
  git -C "${MODSECURITY_SOURCE_LIB_PATH}" submodule update --init
  
  # Build and install ModSecurity
  cd "${MODSECURITY_SOURCE_LIB_PATH}"
  ./build.sh
  CFLAGS="-Og" ./configure \
    --prefix="${MODSECURITY_LIB_PATH}" \
    --enable-shared \
    --with-lua=/usr/lib/x86_64-linux-gnu/pkgconfig/
  make
  make install

  cd "${HTTP_COMMONS_PATH}"

  rm -rf \
    "${MODSECURITY_SOURCE_LIB_PATH}"
  
  find ${MODSECURITY_LIB_PATH}/bin -type f -exec sudo chmod a+x {} \;
  
  # Save the installed version
  echo "${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}" > "${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}"
fi

# Install Core Rule Set if needed
if [[ -n "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" ]] && \
   [ "$(gs_version_gate "${HTTP_COMMON_CORERULESET_VERSION_PATH}" "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" "http.coreruleset")" != "skip" ]; then
  
  # Create directory for Core Rule Set
  mkdir -p \
    "${CORERULESET_PATH}"
  
  # Clone the Core Rule Set repository
  git clone --progress \
    --branch "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" \
    https://github.com/coreruleset/coreruleset.git \
    --depth 1 \
    "${CORERULESET_PATH}"
  
  # Configure Git and update submodules
  git -C "${CORERULESET_PATH}" config core.fileMode false
  git -C "${CORERULESET_PATH}" submodule update --init
  
  # Copy the example setup config
  cp "${CORERULESET_PATH}/crs-setup.conf.example" "${CORERULESET_PATH}/crs-setup.conf"
  
  # Save the installed version
  echo "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" > "${HTTP_COMMON_CORERULESET_VERSION_PATH}"
fi