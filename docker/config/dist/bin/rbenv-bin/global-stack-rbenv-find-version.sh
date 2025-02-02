#!/bin/bash

if [ -n "${1}" ]; then
  if [ -e "${RBENV_ROOT}/versions/${1}" ]; then
    echo "${1}"
  else
    echo "$(ls "${RBENV_ROOT}/versions" | grep "^${1}" | cut -c1- | tail -n1)"
  fi
fi