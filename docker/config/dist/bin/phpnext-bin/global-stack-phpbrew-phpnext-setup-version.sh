#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** phpbrew ($([[ -n "${PHP_VERSION_AS:-}" && "" != "${PHP_VERSION_AS:-}" ]] && echo "${PHP_VERSION_AS:-}" || echo "${PHP_VERSION:-}")) ${PHPBREW_MODE:-} global-stack-phpbrew-phpnext-setup-version.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

if [[ ! -f ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp/frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}.tar.gz ]]; then
    FRANKENPHP_REFS_VALUE=$( { [[ "${GLOBAL_STACK_FRANKENPHP_VERSION}" =~ ^[0-9a-f]{7,40}$ ]] && echo "archive/${GLOBAL_STACK_FRANKENPHP_VERSION}"; } || { [[ "${GLOBAL_STACK_FRANKENPHP_VERSION}" =~ ^v?[0-9]+(\.[0-9]+)*(-.+)?$ ]] && echo "archive/refs/tags/${GLOBAL_STACK_FRANKENPHP_VERSION}"; } || echo "archive/refs/heads/${GLOBAL_STACK_FRANKENPHP_VERSION}" )
    curl -LsS "https://github.com/dunglas/frankenphp/${FRANKENPHP_REFS_VALUE}.tar.gz" -o ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp/frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}.tar.gz
fi

ACTUAL_PHP_VERSION="${PHP_VERSION:-}"
if [[ "${PHP_VERSION:-}" =~ ^github\.com/php/php-src* ]]; then
  ACTUAL_PHP_VERSION="${PHP_VERSION_AS:-}"
fi

cd ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp
if [[ ! -d ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp/frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}-${ACTUAL_PHP_VERSION} ]]; then
  mkdir -p ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp/frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}-${ACTUAL_PHP_VERSION}
fi

tar -xzf ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp/frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}.tar.gz --directory=${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp/frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}-${ACTUAL_PHP_VERSION} --strip-components=1

cd ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp/frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}-${ACTUAL_PHP_VERSION}/caddy/frankenphp
LD_LIBRARY_PATH="$(php-config --lib-dir):${LD_LIBRARY_PATH}" CGO_CFLAGS=$(php-config --includes) CGO_LDFLAGS="-L$(php-config --lib-dir) $(php-config --ldflags) $(php-config --libs)" go build -ldflags="-v" -o ${PHPBREW_BIN}/frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}-${ACTUAL_PHP_VERSION} || true

rm -rf ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp/frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}-${ACTUAL_PHP_VERSION}