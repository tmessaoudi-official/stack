#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** phpbrew (${PHP_VERSION_AS}) ${PHPBREW_MODE:-} global-stack-phpbrew-php-install-version.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && printf 'line: %s\ncommand: %s\n' "${2}" "${3}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

echo "*** Installing php version ${PHP_VERSION_AS} as ${PHP_VERSION_NAME}"

eval "phpbrew --debug --verbose --profile install ${PHP_VERSION} as ${PHP_VERSION_NAME} ${PHP_INSTALL_CLI_VARIANTS} ${PHP_INSTALL_CLI_OPTIONS}"
