#!/bin/bash

# Enable strict error handling and debugging
set -xeEuo pipefail
shopt -s extdebug
IFS=$'\n\t'

# Define reusable paths
HTTPD_PATH="${1}"
HTTP_COMMONS_PATH="${2}"
HTTPD_VERSIONS_PATH="${3}"
MODSECURITY_SOURCE_LIB_PATH="${4}"
MODSECURITY_LIB_PATH="${5}"
CORERULESET_PATH="${6}"
MODSECURITY_APACHE_PATH="${HTTPD_PATH}/mods/modsecurity-source"
MOD_AUTH_OPENIDC_APACHE_PATH="${HTTPD_PATH}/mods/mod_auth_openidc-source"

# Trap errors and handle cleanup or error reporting
trap 'stackCatch $? ${LINENO} "${BASH_COMMAND}"' ERR EXIT

stackCatch() {
  local exit_code=${1}
  local line_num=${2}
  local command=${3}
  if [[ "${exit_code}" -ne 0 && "${exit_code}" -ne 141 && "${exit_code}" -ne 1 ]]; then
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${line_num} ** ** command: ${command} ** httpd global-stack-httpd-iou.sh" \
      >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

cd "${HTTPD_PATH}"

# Extract the latest and current versions of HTTPD
LATEST_HTTPD_VERSION=$(echo "${GLOBAL_STACK_HTTPD_VERSION}" | sed 's/.*\///g')
CURRENT_HTTPD_VERSION=$( [[ -f "${HTTPD_VERSIONS_PATH}" ]] && cat "${HTTPD_VERSIONS_PATH}" || echo "null" )

# If the versions differ, update HTTPD
if [[ "${LATEST_HTTPD_VERSION}" != "${CURRENT_HTTPD_VERSION}" ]]; then
  echo -e "\nUpdating httpd from ${CURRENT_HTTPD_VERSION} to (${GLOBAL_STACK_HTTPD_VERSION}) ${LATEST_HTTPD_VERSION}"
  
  # Remove old build directory and checkout the new version
  rm -rf \
    "${HTTPD_PATH}/httpd-build"
  mkdir -p \
    "${HTTPD_PATH}/httpd-build"
  
  svn checkout "http://svn.apache.org/repos/asf/httpd/httpd/${GLOBAL_STACK_HTTPD_VERSION}" \
    "${HTTPD_PATH}/httpd-build"

  # Checkout APR and APR-util if necessary
  cd "${HTTPD_PATH}/httpd-build"
  svn co "http://svn.apache.org/repos/asf/apr/apr/${GLOBAL_STACK_HTTPD_APR_VERSION}" "srclib/apr"
  [[ -n "${GLOBAL_STACK_HTTPD_APR_UTIL_VERSION}" ]] && svn co "http://svn.apache.org/repos/asf/apr/apr-util/${GLOBAL_STACK_HTTPD_APR_UTIL_VERSION}" "srclib/apr-util"

  # Build and configure httpd
  ./buildconf
  CFLAGS="-Og" ./configure \
    --prefix="${HTTPD_PATH}" \
    --enable-load-all-modules \
    --with-ssl=/usr/lib/ssl \
    --enable-ssl \
    --enable-mods-shared=all \
    --enable-mods-static=all \
    --enable-modules=all \
    --enable-debugger-mode \
    --enable-rewrite \
    --enable-log-debug \
    --with-libxml2=/usr/lib \
    --with-ldap=ldap \
    --with-openssl
  
  # Make and install
  make prefix="${HTTPD_PATH}"
  make prefix="${HTTPD_PATH}" install

  cd "${HTTPD_PATH}"

  rm -rf \
    "${HTTPD_PATH}/httpd-build"
else
  echo -e "\nHttpd is already the latest version (${GLOBAL_STACK_HTTPD_VERSION} - ${CURRENT_HTTPD_VERSION})"
fi

# Install the Apache ModSecurity connector if needed
if [[ -n "${GLOBAL_STACK_HTTPD_MODSECURITY_MOD_VERSION}" && "" != "${GLOBAL_STACK_HTTPD_MODSECURITY_MOD_VERSION}" ]]; then
  mkdir -p "${MODSECURITY_APACHE_PATH}"
  git clone --progress --branch "${GLOBAL_STACK_HTTPD_MODSECURITY_MOD_VERSION}" \
    https://github.com/SpiderLabs/ModSecurity-apache.git \
    --depth 1 "${MODSECURITY_APACHE_PATH}"

  git -C "${MODSECURITY_APACHE_PATH}" config core.fileMode false
  git -C "${MODSECURITY_APACHE_PATH}" submodule update --init

  # Build and install the Apache connector
  cd "${MODSECURITY_APACHE_PATH}"
  ./autogen.sh
  CFLAGS="-Og" ./configure \
    --with-apxs="${HTTPD_PATH}/bin/apxs" \
    --with-apache="${HTTPD_PATH}/bin/httpd" \
    --with-libmodsecurity="${MODSECURITY_LIB_PATH}"
  make
  make install

  cd "${HTTPD_PATH}"

  rm -rf "${MODSECURITY_APACHE_PATH}"
fi

# Install the Apache mod_auth_openidc connector if needed
if [[ -n "${GLOBAL_STACK_HTTPD_MOD_AUTH_OPENIDC_VERSION}" && "" != "${GLOBAL_STACK_HTTPD_MOD_AUTH_OPENIDC_VERSION}" ]]; then
  mkdir -p "${MOD_AUTH_OPENIDC_APACHE_PATH}"
  git clone --progress --branch "${GLOBAL_STACK_HTTPD_MOD_AUTH_OPENIDC_VERSION}" \
    https://github.com/OpenIDC/mod_auth_openidc.git \
    --depth 1 "${MOD_AUTH_OPENIDC_APACHE_PATH}"

  git -C "${MOD_AUTH_OPENIDC_APACHE_PATH}" config core.fileMode false
  git -C "${MOD_AUTH_OPENIDC_APACHE_PATH}" submodule update --init

  # Build and install the Apache connector
  cd "${MOD_AUTH_OPENIDC_APACHE_PATH}"
  ./autogen.sh
  CFLAGS="-Og" ./configure \
    --with-apxs="${HTTPD_PATH}/bin/apxs"
  make
  make install

  cd "${HTTPD_PATH}"

  rm -rf "${MOD_AUTH_OPENIDC_APACHE_PATH}"
fi

# Final permissions and cleanup
cd "${HTTPD_PATH}"
find bin -type f -exec sudo chmod a+x {} \;

cd "${GLOBAL_STACK_DOCKER_TOOLS_PATH}"