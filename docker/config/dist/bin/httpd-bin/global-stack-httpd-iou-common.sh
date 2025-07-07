#!/bin/bash

# Enable strict error handling and debugging
set -xeEuo pipefail
shopt -s extdebug
IFS=$'\n\t'

# Define reusable paths passed as arguments
HTTP_COMMONS_PATH="${1}"
HTTP_COMMON_MOD_SECURITY_VERSION_PATH="${2}"
HTTP_COMMON_CORERULESET_VERSION_PATH="${3}"
MODSECURITY_SOURCE_LIB_PATH="${4}"
MODSECURITY_LIB_PATH="${5}"
CORERULESET_PATH="${6}"
HTTP_COMMON_CJOSE_VERSION_PATH="${7}"
CJOSE_SOURCE_PATH="${8}"
CJOSE_PATH="${9}"

# Function to handle errors and trap cleanup
stackCatch() {
  local exit_code=$1
  local line_num=$2
  local command=$3
  if [[ $exit_code -ne 0 && $exit_code -ne 141 && $exit_code -ne 1 ]]; then
    echo "Error detected!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - line: $line_num, command: $command, httpd global-stack-httpd-iou-common.sh" \
      >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

# Trap errors for cleanup or error reporting
trap 'stackCatch $? ${LINENO} "${BASH_COMMAND}"' ERR EXIT

# Install ModSecurity if needed
if [[ -n "${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}" ]] && \
   { [[ ! -e "${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}" ]] || \
     [[ "$(cat "${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}")" != "${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}" ]]; }; then
  
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
   { [[ ! -e "${HTTP_COMMON_CORERULESET_VERSION_PATH}" ]] || \
     [[ "$(cat "${HTTP_COMMON_CORERULESET_VERSION_PATH}")" != "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" ]]; }; then
  
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

# # Install cJOSE if needed
# if [[ -n "${GLOBAL_STACK_HTTP_CJOSE_VERSION}" ]] && \
#    { [[ ! -e "${HTTP_COMMON_CJOSE_VERSION_PATH}" ]] || \
#      [[ "$(cat "${HTTP_COMMON_CJOSE_VERSION_PATH}")" != "${GLOBAL_STACK_HTTP_CJOSE_VERSION}" ]]; }; then
  
#   # Create directory for cJOSE source & lib
#   mkdir -p \
#     "${CJOSE_SOURCE_PATH}" \
#     "${CJOSE_PATH}"
  
#   # Clone the cJOSE repository
#   git clone --progress \
#     --branch "${GLOBAL_STACK_HTTP_CJOSE_VERSION}" \
#     https://github.com/OpenIDC/cjose.git \
#     --depth 1 \
#     "${CJOSE_SOURCE_PATH}"
  
#   # Configure Git and update submodules
#   git -C "${CJOSE_SOURCE_PATH}" config core.fileMode false
#   git -C "${CJOSE_SOURCE_PATH}" submodule update --init
  
#   # Build and install cJOSE
#   cd "${CJOSE_SOURCE_PATH}"
#   CFLAGS="-Og" ./configure \
#     --prefix="${CJOSE_PATH}"
#   make
#   make install

#   cd "${HTTP_COMMONS_PATH}"

#   rm -rf \
#     "${CJOSE_SOURCE_PATH}"

#   find ${CJOSE_PATH}/bin -type f -exec sudo chmod a+x {} \;
  
#   # Save the installed version
#   echo "${GLOBAL_STACK_HTTP_CJOSE_VERSION}" > "${HTTP_COMMON_CJOSE_VERSION_PATH}"
# fi
