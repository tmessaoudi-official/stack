#!/bin/bash

if [ -n "${1}" ]; then
  if [ -e "${PYENV_ROOT}/versions/${1}" ]; then
    echo "${1}"
  else
    if [ "${GLOBAL_STACK_PYTHON_STABLE}" = "false" ]; then
      echo "$(ls "${PYENV_ROOT}/versions" | grep "^${1}" | cut -c1- | tail -n1)"
    else
      echo "$(ls "${PYENV_ROOT}/versions" | grep "^${1}" | awk '!/dev/ && !/[a-zA-Z]/' | cut -c1- | tail -n1)"
    fi
  fi
fi