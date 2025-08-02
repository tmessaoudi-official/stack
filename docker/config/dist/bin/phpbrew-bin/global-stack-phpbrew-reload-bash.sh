#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** phpbrew (${PHP_VERSION_AS}) ${PHPBREW_MODE:-} global-stack-phpbrew-reload-bash.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

PHPBREW_PHP="${PHP_VERSION_NAME}"
export PHPBREW_PHP
PHPBREW_PHP_PATH="${PHPBREW_ROOT}/php/${PHPBREW_PHP}"
export PHPBREW_PHP_PATH
PHPBREW_PATH="${PHPBREW_PHP_PATH}/bin"
export PHPBREW_PATH
PATH="${PHPBREW_PATH}:${PHPBREW_PHP_PATH}/sbin:${PATH}"
export PATH

echo "source ${PHPBREW_HOME}/bashrc" > "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc"
# echo "phpbrew switch ${PHPBREW_PHP}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc"
# echo "find ${PHPBREW_ROOT}/ -type f -name init -exec sed -i 's|Deprecated.*||g' {} \;" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc"
# echo "source ${PHPBREW_HOME}/bashrc" > "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc"
# echo "phpbrew switch ${PHPBREW_PHP}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc"
echo "PHPBREW_PHP=${PHPBREW_PHP}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc"
echo "export PHPBREW_PHP" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc"
echo "PHPBREW_PHP_PATH=${PHPBREW_PHP_PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc"
echo "export PHPBREW_PHP_PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc"
echo "PHPBREW_PATH=${PHPBREW_PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc"
echo "export PHPBREW_PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc"
echo "PATH=${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc"

echo "source /home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc"