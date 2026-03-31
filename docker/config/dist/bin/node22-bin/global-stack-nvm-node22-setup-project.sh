#!/bin/bash

set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** nvm ($([[ -n "${NODE_VERSION_AS:-}" && "" != "${NODE_VERSION_AS:-}" ]] && echo "${NODE_VERSION_AS:-}" || echo "${NODE_VERSION:-}")) ${NVM_MODE:-} global-stack-nvm22-node-setup-project.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

# if [[ -n "${NODE_INSTALL_PACKAGE_CORDOVA_VERSION:-}" && "" != "${NODE_INSTALL_PACKAGE_CORDOVA_VERSION:-}" ]]; then
#   # cordova telemetry off
# fi

if [[ -n "${NODE_INSTALL_PACKAGE_IONIC_CLI_VERSION:-}" && "" != "${NODE_INSTALL_PACKAGE_IONIC_CLI_VERSION:-}" ]]; then
  ionic config set -g telemetry false
  ionic config set -g npmClient npm
fi

if [[ -n "${NODE_INSTALL_PACKAGE_ANGULAR_CLI_VERSION:-}" && "" != "${NODE_INSTALL_PACKAGE_ANGULAR_CLI_VERSION:-}" ]]; then
  ng config --global cli.packageManager npm
fi

# if [[ -n "${NODE_INSTALL_PACKAGE_NX_VERSION:-}" && "" != "${NODE_INSTALL_PACKAGE_NX_VERSION:-}" ]]; then
# #  nx config --global cli.packageManager npm
# fi