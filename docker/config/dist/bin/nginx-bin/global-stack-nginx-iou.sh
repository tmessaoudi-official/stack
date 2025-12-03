#!/bin/bash

# Enable strict error handling and debugging
set -xeEuo pipefail
shopt -s extdebug
IFS=$'\n\t'

# Define reusable paths
NGINX_PATH="${1}"
HTTP_COMMONS_PATH="${2}"
NGINX_VERSIONS_PATH="${3}"
MODSECURITY_SOURCE_LIB_PATH="${4}"
MODSECURITY_LIB_PATH="${5}"
CORERULESET_PATH="${6}"
CJOSE_SOURCE_PATH="${7}"
CJOSE_PATH="${8}"
LIBOAUTH2_SOURCE_PATH="${9}"
LIBOAUTH2_PATH="${10}"
NGINX_LIBOAUTH2_VERSION_PATH="${11}"
NGINX_CJOSE_VERSION_PATH="${12}"
MODSECURITY_NGINX_PATH="${NGINX_PATH}/mods/modsecurity-source"
MOD_AUTH_OPENIDC_NGINX_SOURCE_PATH="${NGINX_PATH}/mods/mod_auth_openidc-source"
MOD_AUTH_OPENIDC_NGINX_PATH="${NGINX_PATH}/mods/mod_auth_openidc"

# Trap errors and handle cleanup or error reporting
trap 'stackCatch $? ${LINENO} "${BASH_COMMAND}"' ERR EXIT

stackCatch() {
  local exit_code=${1}
  local line_num=${2}
  local command=${3}
  if [[ "${exit_code}" -ne 0 && "${exit_code}" -ne 141 && "${exit_code}" -ne 1 ]]; then
    echo "Error detected !!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${line_num} ** ** command: ${command} ** nginx global-stack-nginx-iou.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

cd "${NGINX_PATH}"

# Extract the latest and current versions of NGINX
LATEST_NGINX_VERSION=${GLOBAL_STACK_NGINX_VERSION}
CURRENT_NGINX_VERSION=$( [[ -f "${NGINX_VERSIONS_PATH}" ]] && cat "${NGINX_VERSIONS_PATH}" || echo "null" )

# Install the Nginx ModSecurity connector if needed
if [[ -n "${GLOBAL_STACK_NGINX_MODSECURITY_MOD_VERSION}" ]]; then
  mkdir -p "${MODSECURITY_NGINX_PATH}"
  git clone --progress --branch "${GLOBAL_STACK_NGINX_MODSECURITY_MOD_VERSION}" \
    https://github.com/SpiderLabs/ModSecurity-nginx.git \
    --depth 1 "${MODSECURITY_NGINX_PATH}"

  git -C "${MODSECURITY_NGINX_PATH}" config core.fileMode false
  git -C "${MODSECURITY_NGINX_PATH}" submodule update --init
fi

# If the versions differ, update NGINX
if [[ "${LATEST_NGINX_VERSION}" != "${CURRENT_NGINX_VERSION}" ]]; then
  echo -e "\nUpdating nginx from ${CURRENT_NGINX_VERSION} to ${LATEST_NGINX_VERSION}"
  # Remove old build directory and checkout the new version
  rm -rf \
    "${NGINX_PATH}/nginx-build"
  mkdir -p \
    "${NGINX_PATH}/nginx-build"

  wget -O "${NGINX_PATH}/nginx.tar.gz" "https://nginx.org/download/nginx-${LATEST_NGINX_VERSION}.tar.gz"
  tar -xzf "${NGINX_PATH}/nginx.tar.gz" --strip-components=1 -C "${NGINX_PATH}/nginx-build"
  
  cd "${NGINX_PATH}/nginx-build"
  ./configure \
    --prefix="${NGINX_PATH}" \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module \
    --with-http_gzip_static_module \
    --with-http_stub_status_module \
    --with-http_auth_request_module \
    --with-http_addition_module \
    --with-http_sub_module \
    --with-http_flv_module \
    --with-http_mp4_module \
    --with-pcre \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-mail \
    --with-mail_ssl_module \
    --with-http_geoip_module \
    --with-http_xslt_module \
    --with-http_image_filter_module \
    --with-http_slice_module \
    --with-http_random_index_module \
    --with-http_secure_link_module \
    --with-http_degradation_module \
    --with-http_dav_module \
    --with-compat \
    --add-module="${MODSECURITY_NGINX_PATH}" \
    --with-cc-opt="-I${MODSECURITY_LIB_PATH}/include \
                   -I${CJOSE_PATH}/include" \
    --with-ld-opt="-Wl,-rpath=${MODSECURITY_LIB_PATH}/lib \
                   -Wl,-rpath=${CJOSE_PATH}/lib \
                   -L${MODSECURITY_LIB_PATH}/lib \
                   -L${CJOSE_PATH}/lib"

  # @todo install quic http3 support
  # --with-http_v3_module \
  # --add-module="${MOD_AUTH_OPENIDC_NGINX_PATH}" \
  # -I${LIBOAUTH2_PATH}/include" \
  # -Wl,-rpath=${LIBOAUTH2_PATH}/lib \
  # -L${LIBOAUTH2_PATH}/lib"
    
  make prefix="${NGINX_PATH}"
  make prefix="${NGINX_PATH}" install

  cd "${NGINX_PATH}"
else
  echo -e "\nNginx is already latest (${GLOBAL_STACK_NGINX_VERSION} - ${CURRENT_NGINX_VERSION}"
fi

# Install cJOSE if needed
if [[ -n "${GLOBAL_STACK_NGINX_CJOSE_VERSION}" ]] && \
   { [[ ! -e "${NGINX_CJOSE_VERSION_PATH}" ]] || \
     [[ "$(cat "${NGINX_CJOSE_VERSION_PATH}")" != "${GLOBAL_STACK_NGINX_CJOSE_VERSION}" ]]; }; then
  
  # Create directory for cJOSE source & lib
  mkdir -p \
    "${CJOSE_SOURCE_PATH}" \
    "${CJOSE_PATH}"
  
  # Clone the cJOSE repository
  git clone --progress \
    --branch "${GLOBAL_STACK_NGINX_CJOSE_VERSION}" \
    https://github.com/OpenIDC/cjose.git \
    --depth 1 \
    "${CJOSE_SOURCE_PATH}"
  
  # Configure Git and update submodules
  git -C "${CJOSE_SOURCE_PATH}" config core.fileMode false
  git -C "${CJOSE_SOURCE_PATH}" submodule update --init
  
  # Build and install cJOSE
  cd "${CJOSE_SOURCE_PATH}"

  CFLAGS="-Og" ./configure \
    --prefix="${CJOSE_PATH}"

  make
  make install

  cd "${HTTP_COMMONS_PATH}"

  # rm -rf \
  #   "${CJOSE_SOURCE_PATH}"
  
  # Save the installed version
  echo "${GLOBAL_STACK_NGINX_CJOSE_VERSION}" > "${NGINX_CJOSE_VERSION_PATH}"

  cd "${NGINX_PATH}"
fi

# Install liboauth2 if needed
if [[ -n "${GLOBAL_STACK_NGINX_LIBOAUTH2_VERSION}" ]] && \
   { [[ ! -e "${NGINX_LIBOAUTH2_VERSION_PATH}" ]] || \
     [[ "$(cat "${NGINX_LIBOAUTH2_VERSION_PATH}")" != "${GLOBAL_STACK_NGINX_LIBOAUTH2_VERSION}" ]]; }; then
  rm -rf \
    "${LIBOAUTH2_SOURCE_PATH}" \
    "${LIBOAUTH2_PATH}"

  # Create directory for liboauth2 source & lib
  mkdir -p \
    "${LIBOAUTH2_SOURCE_PATH}" \
    "${LIBOAUTH2_PATH}"
  
  # Clone the cJOSE repository
  git clone --progress \
    --branch "${GLOBAL_STACK_NGINX_LIBOAUTH2_VERSION}" \
    https://github.com/OpenIDC/liboauth2.git \
    --depth 1 \
    "${LIBOAUTH2_SOURCE_PATH}"
  
  # Configure Git and update submodules
  git -C "${LIBOAUTH2_SOURCE_PATH}" config core.fileMode false
  git -C "${LIBOAUTH2_SOURCE_PATH}" submodule update --init
  
  # Build and install cJOSE
  cd "${LIBOAUTH2_SOURCE_PATH}"

  ./autogen.sh

  CFLAGS="-Og" ./configure \
    --prefix="${LIBOAUTH2_PATH}" \
    --with-nginx=${NGINX_PATH}/nginx-build \
    --without-apache \
    CFLAGS="-I${CJOSE_PATH}/include" \
    LDFLAGS="-L${CJOSE_PATH}/lib -Wl,-rpath=${CJOSE_PATH}/lib"

  make
  make install

  # rm -rf \
  #   "${LIBOAUTH2_SOURCE_PATH}"
  
  # Save the installed version
  echo "${GLOBAL_STACK_NGINX_LIBOAUTH2_VERSION}" > "${NGINX_LIBOAUTH2_VERSION_PATH}"

  cd "${NGINX_PATH}"
fi

# Install the Nginx mod_auth_openidc connector if needed
if [[ -n "${GLOBAL_STACK_NGINX_MOD_AUTH_OPENIDC_VERSION}" && "" != "${GLOBAL_STACK_NGINX_MOD_AUTH_OPENIDC_VERSION}" ]]; then
  mkdir -p \
    "${MOD_AUTH_OPENIDC_NGINX_SOURCE_PATH}" \
    "${MOD_AUTH_OPENIDC_NGINX_PATH}"

  git clone --progress --branch "${GLOBAL_STACK_NGINX_MOD_AUTH_OPENIDC_VERSION}" \
    https://github.com/OpenIDC/ngx_openidc_module.git \
    --depth 1 "${MOD_AUTH_OPENIDC_NGINX_SOURCE_PATH}"

  git -C "${MOD_AUTH_OPENIDC_NGINX_SOURCE_PATH}" config core.fileMode false
  git -C "${MOD_AUTH_OPENIDC_NGINX_SOURCE_PATH}" submodule update --init

  cd "${MOD_AUTH_OPENIDC_NGINX_SOURCE_PATH}"

  ./autogen.sh

  OAUTH2_NGINX_CFLAGS="-I${LIBOAUTH2_PATH}/include -I${CJOSE_PATH}/include" OAUTH2_NGINX_LIBS="-L${LIBOAUTH2_PATH}/lib -L${CJOSE_PATH}/lib -loauth2_nginx -loauth2 -lcjose" OAUTH2_CFLAGS="-I${LIBOAUTH2_PATH}/include -I${CJOSE_PATH}/include" OAUTH2_LIBS="-L${LIBOAUTH2_PATH}/lib -L${CJOSE_PATH}/lib -loauth2 -lcjose" CFLAGS="-Og" CFLAGS="-Og" ./configure \
     --prefix="${MOD_AUTH_OPENIDC_NGINX_PATH}" \
     --with-nginx=${NGINX_PATH}/nginx-build

  make
  make install

  # rm -rf \
  #   "${MOD_AUTH_OPENIDC_NGINX_SOURCE_PATH}"

  cd "${NGINX_PATH}"
fi

if [[ "${LATEST_NGINX_VERSION}" != "${CURRENT_NGINX_VERSION}" ]]; then
  rm -rf \
    "${NGINX_PATH}/nginx-build" \
    "${NGINX_PATH}/nginx.tar.gz"
fi

# Final permissions and cleanup
cd "${NGINX_PATH}"
find sbin -type f -exec sudo chmod a+x {} \;

cd "${GLOBAL_STACK_DOCKER_TOOLS_PATH}"
