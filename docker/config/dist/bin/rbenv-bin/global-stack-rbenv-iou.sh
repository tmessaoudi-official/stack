#!/bin/bash
# iou = install-or-upgrade

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

# @todo use ruby-build

if [ ! -d "${RBENV_ROOT}/.git" ]; then
    git clone --progress --verbose --branch ${GLOBAL_STACK_RBENV_VERSION} https://github.com/sstephenson/rbenv.git "${RBENV_ROOT}"
fi

# Row 21. The two plugin clones used to live INSIDE the fresh-clone branch above,
# so they only ever ran when rbenv itself was cloned for the first time: bumping
# GLOBAL_STACK_RBENV_RUBY_BUILD_VERSION or _GEMSET_VERSION alone did nothing, while
# an rbenv bump silently re-cloned both. They are now gated independently, which is
# what the .env pins imply. Each keeps a directory check as its floor.
if [[ -n "${GLOBAL_STACK_RBENV_RUBY_BUILD_VERSION}" ]]; then
  _rb_build_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv.ruby-build" "${GLOBAL_STACK_RBENV_RUBY_BUILD_VERSION}" "rbenv.ruby-build")"
  if [ "${_rb_build_gate}" != "skip" ] || [[ ! -d "${RBENV_ROOT}/plugins/ruby-build" ]]; then
    rm -rf "${RBENV_ROOT}/plugins/ruby-build"
    mkdir -p "${RBENV_ROOT}"/plugins/ruby-build
    git clone --progress --verbose --branch ${GLOBAL_STACK_RBENV_RUBY_BUILD_VERSION} https://github.com/sstephenson/ruby-build.git "${RBENV_ROOT}"/plugins/ruby-build
    printf '%s\n' "${GLOBAL_STACK_RBENV_RUBY_BUILD_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv.ruby-build"
  fi
fi

if [[ -n "${GLOBAL_STACK_RBENV_GEMSET_VERSION}" ]]; then
  _rb_gemset_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv.gemset" "${GLOBAL_STACK_RBENV_GEMSET_VERSION}" "rbenv.gemset")"
  if [ "${_rb_gemset_gate}" != "skip" ] || [[ ! -d "${RBENV_ROOT}/plugins/rbenv-gemset" ]]; then
    rm -rf "${RBENV_ROOT}/plugins/rbenv-gemset"
    mkdir -p "${RBENV_ROOT}"/plugins/rbenv-gemset
    git clone --progress --verbose --branch ${GLOBAL_STACK_RBENV_GEMSET_VERSION} https://github.com/jf/rbenv-gemset.git ${RBENV_ROOT}/plugins/rbenv-gemset
    printf '%s\n' "${GLOBAL_STACK_RBENV_GEMSET_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv.gemset"
  fi
fi

# git -C "${RBENV_ROOT}" branch --set-upstream-to=origin/master master
# git -C "${RBENV_ROOT}" config core.fileMode false
# git -C "${RBENV_ROOT}" fetch --progress --verbose
# git -C "${RBENV_ROOT}" pull --progress --verbose --rebase