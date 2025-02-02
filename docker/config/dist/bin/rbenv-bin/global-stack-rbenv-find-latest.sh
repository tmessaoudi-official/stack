#!/bin/bash

RBENV_CURRENT_RUBY_VERSION=""
if [ -n "${1}" ]; then
  if [ -e "${RBENV_ROOT}/versions/${1}" ]; then
    RBENV_CURRENT_RUBY_VERSION="${1}"
  else
    RBENV_CURRENT_RUBY_VERSION="$(rbenv install --list-all | grep "^${1}" | cut -c1- | tail -n1)"
  fi
fi

if [[ "" = "${CURRENT_RUBY_VERSION}" ]]; then
  RBENV_CURRENT_RUBY_VERSION="${RUBY_VERSION}"
fi

echo "${RBENV_CURRENT_RUBY_VERSION}"