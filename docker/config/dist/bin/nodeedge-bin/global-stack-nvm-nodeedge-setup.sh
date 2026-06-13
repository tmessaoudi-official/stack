#!/bin/bash

set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

[ -s "${NVM_DIR}/nvm.sh" ] && \. "${NVM_DIR}/nvm.sh"  # This loads nvm
[ -s "${NVM_DIR}/bash_completion" ] && \. "${NVM_DIR}/bash_completion"  # This loads nvm bash_completion

# echo "**** Updating npm from $(npm -v) to latest"
# echo 'y' | npm add --global --force npm@latest

# if [[ -n "${GLOBAL_STACK_NODE_UPGRADE_ALL}" ]]; then
#     echo 'Updating npm global'
#     npm --global upgrade
#     echo 'Updating pnpm global'
#     pnpm --global update
#     echo 'Updating yarn global'
#     yarn global upgrade
# fi