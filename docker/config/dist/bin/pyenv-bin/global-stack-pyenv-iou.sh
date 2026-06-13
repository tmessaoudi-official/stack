#!/bin/bash
# iou = install-or-upgrade

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

if [ ! -d "${PYENV_ROOT}/.git" ]; then
    git clone --progress --verbose --branch ${GLOBAL_STACK_PYENV_VERSION} https://github.com/pyenv/pyenv.git "${PYENV_ROOT}"
fi

# git -C "${PYENV_ROOT}" branch --set-upstream-to=origin/master master
# git -C "${PYENV_ROOT}" config core.fileMode false
# git -C "${PYENV_ROOT}" fetch --progress --verbose
# git -C "${PYENV_ROOT}" pull --progress --verbose --rebase