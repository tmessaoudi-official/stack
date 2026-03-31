#!/bin/bash

# Enable strict error handling and debugging
set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'

HTTPD_PATH="${1}"
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
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - line: $line_num, command: $command, httpd global-stack-httpd-setup.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

# Navigate to the HTTPD directory and clean up old builds
cd ${HTTPD_PATH}

# if [ ! -d "${HTTPD_PATH}/back-up" ]; then
#   mkdir -p "${HTTPD_PATH}/back-up"
#   rsync -av --exclude='back-up' "${HTTPD_PATH}/" "${HTTPD_PATH}/back-up/"
# fi

# Create required directories for HTTPD configuration
mkdir -p \
  "${HTTPD_PATH}"/conf/vhosts \
  "${HTTPD_PATH}"/conf/custom-conf \
  "${HTTPD_PATH}"/conf/custom-extra \
  "${MODSECURITY_TMP_PATH}" \
  "${MODSECURITY_LOGS_PATH}" \
  "${MODSECURITY_CONF_PATH}"

# Remove old configuration and SSL files
rm -rf \
  "${HTTPD_PATH}"/conf/vhosts/*.conf \
  "${HTTPD_PATH}"/conf/custom-conf/*.conf \
  "${HTTPD_PATH}"/conf/custom-extra/*.conf

# Sync configuration files from the distribution directory
rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/httpd-conf/sites-available/ "${HTTPD_PATH}"/conf/vhosts
rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/httpd-conf/conf-available/ "${HTTPD_PATH}"/conf/custom-conf
rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/httpd-conf/extra-conf/ "${HTTPD_PATH}"/conf/custom-extra

# Remove unnecessary files
rm -rf "${HTTPD_PATH}"/conf/vhosts/.gitkeep \
  "${HTTPD_PATH}"/conf/vhosts/example*

# Backup the existing HTTPD configuration
if [ ! -f "${HTTPD_PATH}"/conf/httpd.conf.dist ]; then
  mv "${HTTPD_PATH}"/conf/httpd.conf "${HTTPD_PATH}"/conf/httpd.conf.dist
fi
if [[ -f ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/httpd-conf/httpd.local.conf ]]; then
  cp ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/httpd-conf/httpd.local.conf "${HTTPD_PATH}"/conf/httpd.conf
else
  cp ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/httpd-conf/httpd.conf "${HTTPD_PATH}"/conf/httpd.conf
fi

# Update ports in the configuration
# sed -i "s|\:80$|\:8080|g" "${HTTPD_PATH}/conf/httpd.conf"
# sed -i "s| 80$| 8080|g" "${HTTPD_PATH}/conf/httpd.conf"

# Handle ModSecurity configuration if enabled
if [[ -n "${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}" && -n "${GLOBAL_STACK_HTTPD_MODSECURITY_MOD_VERSION}" ]]; then
  sed -i "s/\# LoadModule foo_module modules\/mod_foo\.so/\# LoadModule foo_module modules\/mod_foo\.so\nLoadModule security3_module modules\/mod_security3\.so/g" \
    "${HTTPD_PATH}"/conf/httpd.conf
  
  if [[ -n "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" ]]; then
    mkdir -p "${MODSECURITY_CONF_PATH}"/optional-conf/modsec-conf/
    rm -rf "${MODSECURITY_CONF_PATH}"/optional-conf/modsec-conf/*
    rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/http-common/optional-conf/modsec-conf/ "${MODSECURITY_CONF_PATH}"/optional-conf/modsec-conf/
  fi
fi

# Handle mod_auth_openidc configuration if enabled
if [[ -n "${GLOBAL_STACK_HTTPD_MOD_AUTH_OPENIDC_VERSION}" ]]; then
  sed -i "s/\# LoadModule foo_module modules\/mod_foo\.so/\# LoadModule foo_module modules\/mod_foo\.so\nLoadModule auth_openidc_module modules\/mod_auth_openidc\.so/g" \
    "${HTTPD_PATH}"/conf/httpd.conf
fi

# Update SSL configuration
# sed -i "s|\:443|\:8443|g" "${HTTPD_PATH}/conf/custom-extra/docker-httpd-ssl.conf"
# sed -i "s| 443$| 8443|g" "${HTTPD_PATH}/conf/custom-extra/docker-httpd-ssl.conf"
# sed -i "s|\#Include conf\/extra\/httpd\-ssl\.conf|Include conf\/custom-extra\/docker\-httpd\-ssl\.conf|g" \
#   "${HTTPD_PATH}/conf/httpd.conf"

# Replace placeholders with actual paths
sed -i "s|\${GLOBAL_STACK_DOCKER_TOOLS_PATH}|${GLOBAL_STACK_DOCKER_TOOLS_PATH}|g; s|\${GLOBAL_STACK_DOCKER_WORKDIR}|${GLOBAL_STACK_DOCKER_WORKDIR}|g; s|\${GLOBAL_STACK_SSL_PATH}|${GLOBAL_STACK_SSL_PATH}|g; s|\${CAROOT}|${CAROOT}|g" \
  "${HTTPD_PATH}"/conf/httpd.conf

find "${HTTPD_PATH}"/conf/vhosts -type f -exec sed -i "s|\${GLOBAL_STACK_DOCKER_TOOLS_PATH}|${GLOBAL_STACK_DOCKER_TOOLS_PATH}|g; s|\${GLOBAL_STACK_DOCKER_WORKDIR}|${GLOBAL_STACK_DOCKER_WORKDIR}|g; s|\${GLOBAL_STACK_SSL_PATH}|${GLOBAL_STACK_SSL_PATH}|g; s|\${CAROOT}|${CAROOT}|g" {} \;

# Include additional configuration files
# sed -i "s/\#Include conf\/extra\/httpd\-vhosts\.conf/Include conf\/vhosts\/\*\.conf\nInclude conf\/custom\-conf\/\*.conf/g" \
#   "${HTTPD_PATH}/conf/httpd.conf"

# Set the server name
# sed -i "s/\#ServerName www\.example\.com\:8080/ServerName 127\.0\.0\.1/g" \
#   "${HTTPD_PATH}/conf/httpd.conf"

rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/http-common/ssl/ "${GLOBAL_STACK_SSL_PATH}"