#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** phpbrew (${PHP_VERSION_AS}) ${PHPBREW_MODE:-} global-stack-phpbrew-php8.4-setup-project.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

echo "LD_LIBRARY_PATH='$(php-config --lib-dir):${LD_LIBRARY_PATH}'" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export LD_LIBRARY_PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
