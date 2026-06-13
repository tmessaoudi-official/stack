#!/bin/bash
# iou = install-or-upgrade

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

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