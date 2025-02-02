#!/bin/bash

set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** nvm ($([[ -n "${NODE_VERSION_AS:-}" && "" != "${NODE_VERSION_AS:-}" ]] && echo "${NODE_VERSION_AS:-}" || echo "${NODE_VERSION:-}")) ${NVM_MODE:-} global-stack-nvm-node18-setup-overrides.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

[ -s "${NVM_DIR}/nvm.sh" ] && \. "${NVM_DIR}/nvm.sh"  # This loads nvm
[ -s "${NVM_DIR}/bash_completion" ] && \. "${NVM_DIR}/bash_completion"  # This loads nvm bash_completion

if [[ -n "${NODE_INSTALL_PACKAGE_YARN_VERSION:-}" && "" != "${NODE_INSTALL_PACKAGE_YARN_VERSION:-}" && "1.22.22" == "$(echo y | yarn -v)" ]]; then
    echo -e "Overriding yarn ${NODE_INSTALL_PACKAGE_YARN_VERSION}"
    cp "${NVM_DIR}"/versions/node/"${NODE_VERSION}"/lib/node_modules/yarn/lib/cli.js "${NVM_DIR}"/versions/node/"${NODE_VERSION}"/lib/node_modules/yarn/lib/cli.dist.js
    rsync -rav ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/nvm-conf/yarn/ "${NVM_DIR}"/versions/node/"${NODE_VERSION}"/lib/node_modules/yarn
fi