#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** pyenv (${PYTHON_VERSION_AS:-${PYTHON_VERSION:-}}) ${PYENV_MODE:-} global-stack-pyenv-iou.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

if [ ! -d "${PYENV_ROOT}/.git" ]; then
    git clone --progress --verbose --branch ${GLOBAL_STACK_PYENV_VERSION} https://github.com/pyenv/pyenv.git "${PYENV_ROOT}"
fi

# git -C "${PYENV_ROOT}" branch --set-upstream-to=origin/master master
# git -C "${PYENV_ROOT}" config core.fileMode false
# git -C "${PYENV_ROOT}" fetch --progress --verbose
# git -C "${PYENV_ROOT}" pull --progress --verbose --rebase