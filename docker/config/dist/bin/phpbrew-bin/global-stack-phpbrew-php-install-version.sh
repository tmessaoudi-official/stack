#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

echo "*** Installing php version ${PHP_VERSION_AS} as ${PHP_VERSION_NAME}"

eval "phpbrew --debug --verbose --profile install ${PHP_VERSION} as ${PHP_VERSION_NAME} ${PHP_INSTALL_CLI_VARIANTS} ${PHP_INSTALL_CLI_OPTIONS}"

if command -v global-stack-phpbrew-php${PHP_VERSION_AS}-install-fpm.sh >/dev/null 2>&1; then
  global-stack-phpbrew-php${PHP_VERSION_AS}-install-fpm.sh
fi