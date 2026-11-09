#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

echo "*** Installing php version ${PHP_VERSION_AS} as ${PHP_VERSION_NAME}"

eval "phpbrew --debug --verbose --profile install ${PHP_VERSION} as ${PHP_VERSION_NAME} ${PHP_INSTALL_CLI_VARIANTS} ${PHP_INSTALL_CLI_OPTIONS}"

# The FPM SAPI for a build made with -fpm (php-src >= 8.6 refuses phpbrew's own
# FPM pass). Called for EVERY version: it skips when sbin/php-fpm already exists,
# so a +fpm build passes straight through. It used to be looked up by a
# php${PHP_VERSION_AS} name that only edge shipped, and 8.6 silently got no FPM.
global-stack-phpbrew-php-install-fpm.sh
