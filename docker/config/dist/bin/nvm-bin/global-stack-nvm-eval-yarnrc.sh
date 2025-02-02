#!/bin/bash

set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** nvm ($([[ -n "${NODE_VERSION_AS:-}" && "" != "${NODE_VERSION_AS:-}" ]] && echo "${NODE_VERSION_AS:-}" || echo "${NODE_VERSION:-}")) ${NVM_MODE:-} global-stack-nvm-eval-yarnrc.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

echo -e "\nPopulating yarnrc"
find "/home/${GLOBAL_STACK_DOCKER_USER_ID}/" -type f -exec sed -i "s|\${YARN_OFFLINE_MIRROR}|${YARN_OFFLINE_MIRROR}|g" {} \;
find "/home/${GLOBAL_STACK_DOCKER_USER_ID}/" -type f -exec sed -i "s|\${YARN_CACHE_FOLDER}|${YARN_CACHE_FOLDER}|g" {} \;
find "/home/${GLOBAL_STACK_DOCKER_USER_ID}/" -type f -exec sed -i "s|\${GLOBAL_STACK_DOCKER_TOOLS_PATH}|${GLOBAL_STACK_DOCKER_TOOLS_PATH}|g" {} \;
find "/home/${GLOBAL_STACK_DOCKER_USER_ID}/" -type f -exec sed -i "s|\${YARN_GLOBAL_FOLDER}|${YARN_GLOBAL_FOLDER}|g" {} \;
