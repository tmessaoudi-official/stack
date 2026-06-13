#!/bin/bash
# iou = install-or-upgrade

set -xeEu
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

# NVM_LATEST_VERSION=$(curl --silent https://api.github.com/repos/nvm-sh/nvm/releases/latest | jq .name -r)
NVM_LATEST_VERSION=${GLOBAL_STACK_NVM_VERSION}
NVM_CURRENT_VERSION=$([[ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm" ]] && cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm" || echo "null")

set -xeEu -o pipefail

if [ "${NVM_LATEST_VERSION}" != "${NVM_CURRENT_VERSION}" ]; then
  echo -e "\nUpdating nvm from ${NVM_CURRENT_VERSION} to ${NVM_LATEST_VERSION}"
  rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/nvm.installer.sh"
  curl --connect-timeout 30 --max-time 300 -fsSL -o "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/nvm.installer.sh" "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_LATEST_VERSION}/install.sh"
  chmod a+x "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/nvm.installer.sh"
fi