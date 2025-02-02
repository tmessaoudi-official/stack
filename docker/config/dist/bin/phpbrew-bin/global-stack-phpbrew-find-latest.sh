#!/bin/bash

PHPBREW_LATEST=""

if [[ -n "${PHP_VERSION_AS:-}" && "next" = "${PHP_VERSION_AS:-}" ]]; then
  PHPBREW_LATEST="php-master"
else
  if [ -n "${1}" ]; then
    if [ -e "${PHPBREW_HOME}/php/${1}" ]; then
      PHPBREW_LATEST="${1}"
    elif [ -e "${PHPBREW_HOME}/php/php-${1}" ]; then
      PHPBREW_LATEST="php-${1}"
    else
      PHPBREW_LATEST="php-$(phpbrew known | grep "^${1}: [0-9\\.]\+" | sed "s|${1}: ||" | sed "s| \.\.\.||" | sed "s|,.*||")"
    fi
  fi
fi

if [[ "" = "${PHPBREW_LATEST}" ]]; then
  PHPBREW_LATEST="${1}"
fi

echo "${PHPBREW_LATEST}"

