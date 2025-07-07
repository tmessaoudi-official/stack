#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** phpbrew (${PHPBREW_PHP_FINAL_VERSION}) ${PHPBREW_MODE:-} global-stack-phpbrew-phpnext-install-version.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

echo "*** Installing php version ${PHPBREW_PHP_FINAL_VERSION} as $(global-stack-phpbrew-find-latest.sh "${PHP_VERSION}")"

PHP_VERSION_INSTALL=""
PHP_VERSION_INSTALL_AS=""
PHP_VERSION_INSTALL_AS_NAME=""
if [[ "next" == "${PHP_VERSION_AS:-}" ]]; then
  PHP_VERSION_INSTALL="${PHP_VERSION}"
  PHP_VERSION_INSTALL_AS="as"
  PHP_VERSION_INSTALL_AS_NAME="php-master"
else
  PHP_VERSION_INSTALL="php-${PHP_VERSION}"
fi

if [[ "${PHP_VERSION:-}" =~ ^github\.com/php/php-src* ]]; then
  if [[ "${PHP_VERSION_INSTALL_AS_NAME}" == "php-master" ]]; then
    PHP_VERSION_INSTALL="${PHP_VERSION}"
  else
    PHP_VERSION_INSTALL="${PHP_VERSION}"
    PHP_VERSION_INSTALL_AS="as"
    PHP_VERSION_INSTALL_AS_NAME="php-${PHP_VERSION_AS}"
  fi
fi

# phpbrew --debug --verbose --profile install ${PHP_VERSION_INSTALL} ${PHP_VERSION_INSTALL_AS} ${PHP_VERSION_INSTALL_AS_NAME} +default +debug +sodium +pdo +mysql +pgsql +sqlite +fpm -- --with-libxml --with-password-argon2 --enable-embed --enable-debug --enable-zts --disable-zend-signals --enable-zend-max-execution-timers
phpbrew --debug --verbose --profile install ${PHP_VERSION_INSTALL} ${PHP_VERSION_INSTALL_AS} ${PHP_VERSION_INSTALL_AS_NAME} +default +debug +sodium +pdo +mysql +pgsql +sqlite +fpm -- --with-libxml --with-password-argon2 --enable-embed --enable-zts --disable-zend-signals --enable-zend-max-execution-timers
