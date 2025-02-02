#!/bin/bash

# Enable strict error handling and debugging
set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'

NGINX_PATH="${1}"
MODSECURITY_TMP_PATH="${2}"
MODSECURITY_LOGS_PATH="${3}"
MODSECURITY_CONF_PATH="${4}"

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
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - line: $line_num, command: $command, nginx global-stack-nginx-setup.sh" \
      >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

# Navigate to the NGINX directory and clean up old builds
cd ${NGINX_PATH}

# if [ ! -d "${NGINX_PATH}/back-up" ]; then
#   mkdir -p "${NGINX_PATH}/back-up"
#   rsync -av --exclude='back-up' "${NGINX_PATH}/" "${NGINX_PATH}/back-up/"
# fi

# Create required directories for NGINX configuration
mkdir -p \
  "${NGINX_PATH}"/conf/vhosts \
  "${MODSECURITY_TMP_PATH}" \
  "${MODSECURITY_LOGS_PATH}" \
  "${MODSECURITY_CONF_PATH}"

# Remove old configuration and SSL files
rm -rf \
  "${NGINX_PATH}"/conf/vhosts/*

# Sync configuration files from the distribution directory
rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/nginx-conf/sites-available/ "${NGINX_PATH}"/conf/vhosts

# Remove unnecessary files
rm -rf "${NGINX_PATH}"/conf/vhosts/.gitkeep \
  "${NGINX_PATH}"/conf/vhosts/example*

# Backup the existing NGINX configuration
if [ ! -f "${NGINX_PATH}"/conf/nginx.conf.dist ]; then
  mv "${NGINX_PATH}"/conf/nginx.conf "${NGINX_PATH}"/conf/nginx.conf.dist
fi
if [[ -f ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/nginx-conf/nginx.local.conf ]]; then
  cp ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/nginx-conf/nginx.local.conf "${NGINX_PATH}"/conf/nginx.conf
else
  cp ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/nginx-conf/nginx.conf "${NGINX_PATH}"/conf/nginx.conf
fi

# Update ports in the configuration
# sed -i "s|\:80$|\:8080|g" "${NGINX_PATH}/conf/nginx.conf"
# sed -i "s| 80$| 8080|g" "${NGINX_PATH}/conf/nginx.conf"

# Handle ModSecurity configuration if enabled
if [[ -n "${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}" && -n "${GLOBAL_STACK_NGINX_MODSECURITY_MOD_VERSION}" ]]; then
  if [[ -n "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" ]]; then
    mkdir -p "${MODSECURITY_CONF_PATH}"/optional-conf/modsec-conf/
    rm -rf "${MODSECURITY_CONF_PATH}"/optional-conf/modsec-conf/*
    rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/http-common/optional-conf/modsec-conf/ "${MODSECURITY_CONF_PATH}"/optional-conf/modsec-conf/
  fi
fi

# Update SSL configuration
# sed -i "s|\:443|\:8443|g" "${NGINX_PATH}/conf/custom-extra/docker-nginx-ssl.conf"
# sed -i "s| 443$| 8443|g" "${NGINX_PATH}/conf/custom-extra/docker-nginx-ssl.conf"
# sed -i "s|\#Include conf\/extra\/nginx\-ssl\.conf|Include conf\/custom-extra\/docker\-nginx\-ssl\.conf|g" \
#   "${NGINX_PATH}/conf/nginx.conf"

# Replace placeholders with actual paths
sed -i "s|\${GLOBAL_STACK_DOCKER_TOOLS_PATH}|${GLOBAL_STACK_DOCKER_TOOLS_PATH}|g; s|\${GLOBAL_STACK_DOCKER_WORKDIR}|${GLOBAL_STACK_DOCKER_WORKDIR}|g; s|\${GLOBAL_STACK_SSL_PATH}|${GLOBAL_STACK_SSL_PATH}|g; s|\${CAROOT}|${CAROOT}|g" \
  "${NGINX_PATH}"/conf/nginx.conf

find "${NGINX_PATH}"/conf/vhosts/ -type f -exec sed -i "s|\${GLOBAL_STACK_DOCKER_TOOLS_PATH}|${GLOBAL_STACK_DOCKER_TOOLS_PATH}|g; s|\${GLOBAL_STACK_DOCKER_WORKDIR}|${GLOBAL_STACK_DOCKER_WORKDIR}|g; s|\${GLOBAL_STACK_SSL_PATH}|${GLOBAL_STACK_SSL_PATH}|g; s|\${CAROOT}|${CAROOT}|g" {} \;

# Include additional configuration files
# sed -i "s/\#Include conf\/extra\/nginx\-vhosts\.conf/Include conf\/vhosts\/\*\.conf\nInclude conf\/custom\-conf\/\*.conf/g" \
#   "${NGINX_PATH}/conf/nginx.conf"

# Set the server name
# sed -i "s/\#ServerName www\.example\.com\:8080/ServerName 127\.0\.0\.1/g" \
#   "${NGINX_PATH}/conf/nginx.conf"

rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/http-common/ssl/ "${GLOBAL_STACK_SSL_PATH}"