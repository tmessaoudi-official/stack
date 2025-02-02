#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** rbenv ($([[ -n "${RUBY_VERSION_AS:-}" && "" != "${RUBY_VERSION_AS:-}" ]] && echo "${RUBY_VERSION_AS:-}" || echo "${RUBY_VERSION:-}")) ${RBENV_MODE:-} global-stack-rbenv-iou.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

# @todo use ruby-build

if [ ! -d "${RBENV_ROOT}/.git" ]; then
    git clone --progress --verbose --branch ${GLOBAL_STACK_RBENV_VERSION} https://github.com/sstephenson/rbenv.git "${RBENV_ROOT}"
    if [[ -n "${GLOBAL_STACK_RBENV_RUBY_BUILD_VERSION}" && "" != "${GLOBAL_STACK_RBENV_RUBY_BUILD_VERSION}" ]]; then
      mkdir -p "${RBENV_ROOT}"/plugins/ruby-build
      git clone --progress --verbose --branch ${GLOBAL_STACK_RBENV_RUBY_BUILD_VERSION} https://github.com/sstephenson/ruby-build.git "${RBENV_ROOT}"/plugins/ruby-build
    fi
    if [[ -n "${GLOBAL_STACK_RBENV_GEMSET_VERSION}" && "" != "${GLOBAL_STACK_RBENV_GEMSET_VERSION}" ]]; then
      mkdir -p "${RBENV_ROOT}"/plugins/rbenv-gemset
      git clone --progress --verbose --branch ${GLOBAL_STACK_RBENV_GEMSET_VERSION} https://github.com/jf/rbenv-gemset.git ${RBENV_ROOT}/plugins/rbenv-gemset
    fi
fi

# git -C "${RBENV_ROOT}" branch --set-upstream-to=origin/master master
# git -C "${RBENV_ROOT}" config core.fileMode false
# git -C "${RBENV_ROOT}" fetch --progress --verbose
# git -C "${RBENV_ROOT}" pull --progress --verbose --rebase