#!/bin/bash
set -xeE -o pipefail

PYENV_CURRENT_PYTHON_VERSION=""
if [ -n "${1}" ]; then
  if [ -e "${PYENV_ROOT}/versions/${1}" ]; then
    PYENV_CURRENT_PYTHON_VERSION="${1}"
  else
    if [ "${GLOBAL_STACK_PYTHON_STABLE}" = "false" ]; then
      PYENV_CURRENT_PYTHON_VERSION="$(pyenv install --list | grep "^  ${1}" | sed "s|  ||" | cut -c1- | tail -n1 || true)"
    else
      PYENV_CURRENT_PYTHON_VERSION="$(pyenv install --list | grep "^  ${1}" | awk '!/dev/ && !/[a-zA-Z]/' | sed "s|  ||" | cut -c1- | tail -n1 || true)"
    fi
  fi
fi

# No match is a hard error, not a fallback. This used to echo the raw pin, so a pin
# newer than this pyenv's python-build definitions reached the gate as a "new version"
# and the start script deleted the working interpreter before `pyenv install` failed
# on it (pin-audit A1, startup-prologue.test.sh §57). Exiting non-zero with nothing on
# stdout fails the caller's assignment under set -eE: the prologue writes the error
# token and the installed interpreter is left alone. Remedy: bump GLOBAL_STACK_PYENV_VERSION.
if [[ "" = "${PYENV_CURRENT_PYTHON_VERSION}" ]]; then
  printf 'FATAL: no installed python and no pyenv definition matches "%s" (pyenv %s) - bump GLOBAL_STACK_PYENV_VERSION or fix the pin\n' \
    "${1:-}" "$(pyenv --version 2>/dev/null || echo unknown)" >&2
  exit 1
fi

echo "${PYENV_CURRENT_PYTHON_VERSION}"
