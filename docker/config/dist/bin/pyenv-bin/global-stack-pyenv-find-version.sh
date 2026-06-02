#!/bin/bash
set -xeE -o pipefail

if [ -n "${1}" ]; then
  if [ -e "${PYENV_ROOT}/versions/${1}" ]; then
    echo "${1}"
  else
    # SC2005 (useless echo) and SC2010 (ls|grep) are pre-existing and intentional:
    # the echo wrapper is load-bearing — it masks the grep exit code (1 on no match)
    # under set -e / pipefail. Do NOT remove the echo to "fix" SC2005.
    if [ "${GLOBAL_STACK_PYTHON_STABLE}" = "false" ]; then
      # shellcheck disable=SC2005,SC2010
      echo "$(ls "${PYENV_ROOT}/versions" | grep "^${1}" | cut -c1- | tail -n1 || true)"
    else
      # shellcheck disable=SC2005,SC2010
      echo "$(ls "${PYENV_ROOT}/versions" | grep "^${1}" | awk '!/dev/ && !/[a-zA-Z]/' | cut -c1- | tail -n1 || true)"
    fi
  fi
fi
