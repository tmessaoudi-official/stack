#!/bin/bash

set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

[ -s "${NVM_DIR}/nvm.sh" ] && \. "${NVM_DIR}/nvm.sh"  # This loads nvm
# This loads nvm bash_completion.
# An `if`, not `[ ... ] && ...`: everything below is commented out, so this is
# the script's last executed statement and a false test would become the
# script's own exit status. nvm-start.sh runs this as a bare statement inside
# its `[[ ! -f versions/node.<label> ]]` install branch, under `set -xeEu` with
# the prologue's ERR trap -- so that would abort the node install and write an
# error token over a missing completion file. (A NAME, not a line number: row 31
# shipped a comment citing `setup.sh:30` that a later edit turned into `}`.)
if [ -s "${NVM_DIR}/bash_completion" ]; then
  \. "${NVM_DIR}/bash_completion"
fi

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