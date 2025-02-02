#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** phpbrew ($([[ -n "${PHP_VERSION_AS:-}" && "" != "${PHP_VERSION_AS:-}" ]] && echo "${PHP_VERSION_AS:-}" || echo "${PHP_VERSION:-}")) ${PHPBREW_MODE:-} global-stack-phpbrew-phpnext-install-version.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

echo "*** Installing php version $([[ -n "${PHP_VERSION_AS:-}" && "" != "${PHP_VERSION_AS:-}" ]] && echo "${PHP_VERSION_AS:-}" || echo "${PHP_VERSION:-}") as $(global-stack-phpbrew-find-latest.sh "${PHP_VERSION}")"

if [[ "next" = "${PHP_VERSION}" ]]; then
  phpbrew --debug --verbose --profile install "${PHP_VERSION}" as php-master +default +debug +sodium +pdo +mysql +pgsql +sqlite +fpm -- --with-libxml --with-password-argon2 --enable-embed --enable-zts --disable-zend-signals --enable-zend-max-execution-timers
else
  phpbrew --debug --verbose --profile install "php-${PHP_VERSION}" +default +debug +sodium +pdo +mysql +pgsql +sqlite +fpm -- --with-libxml --with-password-argon2 --enable-embed --enable-zts --disable-zend-signals --enable-zend-max-execution-timers
fi
