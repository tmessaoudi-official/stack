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

if [[ "" = "${CURRENT_PYTHON_VERSION}" ]]; then
  PYENV_CURRENT_PYTHON_VERSION="${PYTHON_VERSION}"
fi

echo "${PYENV_CURRENT_PYTHON_VERSION}"
