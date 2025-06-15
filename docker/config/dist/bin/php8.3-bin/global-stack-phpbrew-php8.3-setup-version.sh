#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** phpbrew ($([[ -n "${PHP_VERSION_AS:-}" && "" != "${PHP_VERSION_AS:-}" ]] && echo "${PHP_VERSION_AS:-}" || echo "${PHP_VERSION:-}")) ${PHPBREW_MODE:-} global-stack-phpbrew-php8.3-setup-version.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

cd ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp
mkdir ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp/frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}-${PHP_VERSION}

tar -xzf ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp/frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}.tar.gz --directory=${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp/frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}-${PHP_VERSION} --strip-components=1

cd ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp/frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}-${PHP_VERSION}/caddy/frankenphp
LD_LIBRARY_PATH="$(php-config --prefix)/lib:${LD_LIBRARY_PATH}" CGO_CFLAGS=$(php-config --includes) CGO_LDFLAGS="-L$(php-config --prefix)/lib $(php-config --ldflags) $(php-config --libs)" go build -ldflags="-v" -o ${PHPBREW_BIN}/frankenphp-${PHP_VERSION} || true

rm -rf ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp/frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}-${PHP_VERSION}