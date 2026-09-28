#!/bin/bash
# iou = install-or-upgrade

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

if [ ! -d "${PYENV_ROOT}/.git" ]; then
  git clone --progress --verbose --branch ${GLOBAL_STACK_PYENV_VERSION} https://github.com/pyenv/pyenv.git "${PYENV_ROOT}"
else
  # An existing clone follows the pin in EITHER direction (pin-audit A1; this used to
  # be clone-only, so a bump or a rollback never moved it). Network is touched only
  # when HEAD is not already the pin's tagged commit; `rev-parse -q --verify` exits 1
  # when the tag is not known locally yet, which is exactly the "fetch" case. An
  # unknown tag or an unreachable origin fails loud and leaves the checkout as it was.
  # versions/, shims/ and plugins/ are gitignored upstream, so installed runtimes stay.
  _pyenv_want="$(git -C "${PYENV_ROOT}" rev-parse -q --verify "refs/tags/${GLOBAL_STACK_PYENV_VERSION}^{commit}" || true)"
  if [ -z "${_pyenv_want}" ] || [ "${_pyenv_want}" != "$(git -C "${PYENV_ROOT}" rev-parse HEAD)" ]; then
    git -C "${PYENV_ROOT}" fetch --force --tags origin
    git -C "${PYENV_ROOT}" -c advice.detachedHead=false checkout --force "refs/tags/${GLOBAL_STACK_PYENV_VERSION}"
  fi
fi

# git -C "${PYENV_ROOT}" branch --set-upstream-to=origin/master master
# git -C "${PYENV_ROOT}" config core.fileMode false
# git -C "${PYENV_ROOT}" fetch --progress --verbose
# git -C "${PYENV_ROOT}" pull --progress --verbose --rebase
