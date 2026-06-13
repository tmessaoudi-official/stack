#!/bin/bash

set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

[ -s "${NVM_DIR}"/nvm.sh ] && \. "${NVM_DIR}"/nvm.sh  # This loads nvm
[ -s "${NVM_DIR}"/bash_completion ] && \. "${NVM_DIR}"/bash_completion  # This loads nvm bash_completion

if [[ -n "${NODE_INSTALL_PACKAGE_YARN_VERSION:-}" && "" != "${NODE_INSTALL_PACKAGE_YARN_VERSION:-}" && "1.22.22" == "$(echo y | yarn -v)" ]]; then
    echo -e "Overriding yarn ${NODE_INSTALL_PACKAGE_YARN_VERSION}"
    cp "${NVM_DIR}"/versions/node/"${NODE_VERSION}"/lib/node_modules/yarn/lib/cli.js "${NVM_DIR}"/versions/node/"${NODE_VERSION}"/lib/node_modules/yarn/lib/cli.dist.js
    rsync -rav ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/nvm-conf/yarn/ "${NVM_DIR}"/versions/node/"${NODE_VERSION}"/lib/node_modules/yarn
fi