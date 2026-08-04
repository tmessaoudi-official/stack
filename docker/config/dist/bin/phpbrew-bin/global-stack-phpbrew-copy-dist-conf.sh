#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

PHPBREW_PHP_PATH="${PHPBREW_ROOT}/php/${PHP_VERSION_NAME}"

touch "${PHPBREW_PHP_PATH}/var/log/xdebug.log"
mkdir -p "${PHPBREW_PHP_PATH}/var/log/profiler" "${PHPBREW_PHP_PATH}/var/session" "${PHPBREW_PHP_PATH}"/etc/fpm "${PHPBREW_PHP_PATH}"/etc/php-fpm.d/ "${PHPBREW_PHP_PATH}"/var/db/

if [[ ! -d "${PHPBREW_PHP_PATH}/etc/dist-fpm" || ! -d "${PHPBREW_PHP_PATH}/etc/dist-php-fpm.d" || ! -d "${PHPBREW_PHP_PATH}/var/dist-db" ]]; then
  mkdir -p "${PHPBREW_ROOT}"/php-dist/"${PHP_VERSION_NAME}"
  rsync -rav "${PHPBREW_PHP_PATH}" "${PHPBREW_ROOT}"/php-dist/"${PHP_VERSION_NAME}"
fi

if [[ ! -d "${PHPBREW_PHP_PATH}/etc/dist-fpm" ]]; then
  mkdir -p "${PHPBREW_PHP_PATH}/etc/dist-fpm"
  rsync -rav "${PHPBREW_PHP_PATH}"/etc/fpm/ "${PHPBREW_PHP_PATH}/etc/dist-fpm"
fi

if [[ ! -d "${PHPBREW_PHP_PATH}/etc/dist-php-fpm.d" ]]; then
  mkdir -p "${PHPBREW_PHP_PATH}/etc/dist-php-fpm.d"
  rsync -rav "${PHPBREW_PHP_PATH}"/etc/php-fpm.d/ "${PHPBREW_PHP_PATH}/etc/dist-php-fpm.d"
fi

if [[ ! -d "${PHPBREW_PHP_PATH}/var/dist-db" ]]; then
  mkdir -p "${PHPBREW_PHP_PATH}/var/dist-db"
  rsync -rav "${PHPBREW_PHP_PATH}"/var/db/ "${PHPBREW_PHP_PATH}/var/dist-db"
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

if [[ -d "${PHPBREW_PHP_PATH}/var/dist-db" ]]; then
  rm -rf "${PHPBREW_PHP_PATH}"/var/db/
  mkdir -p "${PHPBREW_PHP_PATH}"/var/db/fpm "${PHPBREW_PHP_PATH}"/var/db/cli
  rsync -rav "${PHPBREW_PHP_PATH}/var/dist-db/" "${PHPBREW_PHP_PATH}"/var/db
fi

rsync -rav ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-php-fpm.d/ "${PHPBREW_PHP_PATH}"/etc/fpm
rsync -rav ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/php${PHP_VERSION_AS}-php-fpm.d/ "${PHPBREW_PHP_PATH}"/etc/fpm

rsync -rav ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-php-fpm.d/ "${PHPBREW_PHP_PATH}"/etc/php-fpm.d
rsync -rav ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/php${PHP_VERSION_AS}-php-fpm.d/ "${PHPBREW_PHP_PATH}"/etc/php-fpm.d

find "${PHPBREW_PHP_PATH}/etc/fpm/" -type f -exec sed -i "s|\${PHP_LONG_PATH}|${PHPBREW_PHP_PATH}|g" {} \;
find "${PHPBREW_PHP_PATH}/etc/php-fpm.d/" -type f -exec sed -i "s|\${PHP_LONG_PATH}|${PHPBREW_PHP_PATH}|g" {} \;

rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-conf.d/ ${PHPBREW_PHP_PATH}/var/db/fpm
rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-conf.d/ ${PHPBREW_PHP_PATH}/var/db/cli
rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-conf.d/ ${PHPBREW_PHP_PATH}/var/db

rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/php${PHP_VERSION_AS}-conf.d/ ${PHPBREW_PHP_PATH}/var/db/fpm
rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/php${PHP_VERSION_AS}-conf.d/ ${PHPBREW_PHP_PATH}/var/db/cli
rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/php${PHP_VERSION_AS}-conf.d/ ${PHPBREW_PHP_PATH}/var/db

find ${PHPBREW_PHP_PATH}/var/db/fpm -type f -exec sed -i "s|\${PHPBREW_PHP_PATH}|${PHPBREW_PHP_PATH}|g" {} \;
find ${PHPBREW_PHP_PATH}/var/db/cli -type f -exec sed -i "s|\${PHPBREW_PHP_PATH}|${PHPBREW_PHP_PATH}|g" {} \;
find ${PHPBREW_PHP_PATH}/var/db -type f -exec sed -i "s|\${PHPBREW_PHP_PATH}|${PHPBREW_PHP_PATH}|g" {} \;