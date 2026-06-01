#!/bin/bash

set -xeEu
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** nvm ($([[ -n "${NODE_VERSION_AS:-}" && "" != "${NODE_VERSION_AS:-}" ]] && echo "${NODE_VERSION_AS:-}" || echo "${NODE_VERSION:-}")) ${NVM_MODE:-} global-stack-nvm-iou.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

# NVM_LATEST_VERSION=$(curl --silent https://api.github.com/repos/nvm-sh/nvm/releases/latest | jq .name -r)
NVM_LATEST_VERSION=${GLOBAL_STACK_NVM_VERSION}
NVM_CURRENT_VERSION=$([[ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm" ]] && cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm" || echo "null")

set -xeEu -o pipefail

if [ "${NVM_LATEST_VERSION}" != "${NVM_CURRENT_VERSION}" ]; then
  echo -e "\nUpdating nvm from ${NVM_CURRENT_VERSION} to ${NVM_LATEST_VERSION}"
  rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/nvm.installer.sh"
  curl -fsSL -o "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/nvm.installer.sh" "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_LATEST_VERSION}/install.sh"
  chmod a+x "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/nvm.installer.sh"
fi