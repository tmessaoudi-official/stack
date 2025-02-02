#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** phpbrew ($([[ -n "${PHP_VERSION_AS:-}" && "" != "${PHP_VERSION_AS:-}" ]] && echo "${PHP_VERSION_AS:-}" || echo "${PHP_VERSION:-}")) ${PHPBREW_MODE:-} global-stack-phpbrew-copy-dist-conf.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

PHPBREW_PHP_PATH="${PHPBREW_ROOT}/php/$(global-stack-phpbrew-find-version.sh "${PHP_VERSION}")"

touch "${PHPBREW_PHP_PATH}/var/log/xdebug.log"
mkdir -p "${PHPBREW_PHP_PATH}/var/log/profiler"

if [[ ! -d "${PHPBREW_PHP_PATH}/etc/dist-fpm" ]]; then
  mkdir -p "${PHPBREW_PHP_PATH}/etc/dist-fpm"
  rsync -rav "${PHPBREW_PHP_PATH}"/etc/fpm/ "${PHPBREW_PHP_PATH}/etc/dist-fpm"
fi

if [[ ! -d "${PHPBREW_PHP_PATH}/etc/dist-php-fpm.d" ]]; then
  mkdir -p "${PHPBREW_PHP_PATH}/etc/dist-php-fpm.d"
  rsync -rav "${PHPBREW_PHP_PATH}"/etc/php-fpm.d/ "${PHPBREW_PHP_PATH}/etc/dist-php-fpm.d"
fi

if [[ -d "${PHPBREW_PHP_PATH}/etc/dist-fpm" ]]; then
  rm -rf "${PHPBREW_PHP_PATH}"/etc/fpm/
  mkdir -p "${PHPBREW_PHP_PATH}"/etc/fpm/
  rsync -rav "${PHPBREW_PHP_PATH}/etc/dist-fpm/" "${PHPBREW_PHP_PATH}"/etc/fpm 
fi

if [[ -d "${PHPBREW_PHP_PATH}/etc/dist-php-fpm.d" ]]; then
  rm -rf "${PHPBREW_PHP_PATH}"/etc/php-fpm.d/
  mkdir -p "${PHPBREW_PHP_PATH}"/etc/php-fpm.d/
  rsync -rav "${PHPBREW_PHP_PATH}/etc/dist-php-fpm.d/" "${PHPBREW_PHP_PATH}"/etc/php-fpm.d
fi

rsync -rav ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-php-fpm.d/ "${PHPBREW_PHP_PATH}"/etc/fpm
rsync -rav ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/php${PHP_VERSION_AS}-php-fpm.d/ "${PHPBREW_PHP_PATH}"/etc/fpm

rsync -rav ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-php-fpm.d/ "${PHPBREW_PHP_PATH}"/etc/php-fpm.d
rsync -rav ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/php${PHP_VERSION_AS}-php-fpm.d/ "${PHPBREW_PHP_PATH}"/etc/php-fpm.d

find "${PHPBREW_PHP_PATH}/etc/fpm/" -type f -exec sed -i "s|\${PHP_LONG_PATH}|${PHPBREW_PHP_PATH}|g" {} \;
find "${PHPBREW_PHP_PATH}/etc/php-fpm.d/" -type f -exec sed -i "s|\${PHP_LONG_PATH}|${PHPBREW_PHP_PATH}|g" {} \;

if [[ ! -d "${PHPBREW_PHP_PATH}/var/dist-db" ]]; then
  mkdir -p "${PHPBREW_PHP_PATH}/var/dist-db"
  rsync -rav "${PHPBREW_PHP_PATH}"/var/db/ "${PHPBREW_PHP_PATH}/var/dist-db"
fi

if [[ -d "${PHPBREW_PHP_PATH}/var/dist-db" ]]; then
  rm -rf "${PHPBREW_PHP_PATH}"/var/db/
  mkdir -p "${PHPBREW_PHP_PATH}"/var/db/fpm "${PHPBREW_PHP_PATH}"/var/db/cli
  rsync -rav "${PHPBREW_PHP_PATH}/var/dist-db/" "${PHPBREW_PHP_PATH}"/var/db
fi

rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-conf.d/ ${PHPBREW_PHP_PATH}/var/db/fpm
rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-conf.d/ ${PHPBREW_PHP_PATH}/var/db/cli
rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-conf.d/ ${PHPBREW_PHP_PATH}/var/db

rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/php${PHP_VERSION_AS}-conf.d/ ${PHPBREW_PHP_PATH}/var/db/fpm
rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/php${PHP_VERSION_AS}-conf.d/ ${PHPBREW_PHP_PATH}/var/db/cli
rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/php${PHP_VERSION_AS}-conf.d/ ${PHPBREW_PHP_PATH}/var/db

find ${PHPBREW_PHP_PATH}/var/db/fpm -type f -exec sed -i "s|\${PHPBREW_PHP_PATH}|${PHPBREW_PHP_PATH}|g" {} \;
find ${PHPBREW_PHP_PATH}/var/db/cli -type f -exec sed -i "s|\${PHPBREW_PHP_PATH}|${PHPBREW_PHP_PATH}|g" {} \;
find ${PHPBREW_PHP_PATH}/var/db -type f -exec sed -i "s|\${PHPBREW_PHP_PATH}|${PHPBREW_PHP_PATH}|g" {} \;