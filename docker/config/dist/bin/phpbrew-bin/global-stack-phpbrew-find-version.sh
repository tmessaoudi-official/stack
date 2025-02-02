#!/bin/bash

PHPBREW_FIND=""

if [[ -n "${PHP_VERSION_AS:-}" && "next" = "${PHP_VERSION_AS:-}" ]]; then
  PHPBREW_FIND="php-master"
else
  if [ -n "${1}" ]; then
    if [ -e "${PHPBREW_HOME}/php/${1}" ]; then
      PHPBREW_FIND="${1}"
    elif [ -e "${PHPBREW_HOME}/php/php-${1}" ]; then
      PHPBREW_FIND="php-${1}"
    else
      PHPBREW_FIND="$(ls "${PHPBREW_HOME}/php" | grep "^php-${1}[0-9\.]\*$" | cut -c1- | sort -n | tail -n1)"
    fi
  fi
fi

if [[ "" = "${PHPBREW_FIND}" ]]; then
  PHPBREW_FIND="${1}"
fi

echo "${PHPBREW_FIND}"
