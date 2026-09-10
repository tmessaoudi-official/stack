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

# var/dist-db is the pristine baseline that var/db is RESET to further down. It
# used to be captured once, on the first cold run, and then frozen forever. That
# silently lost every extension added afterwards: the package loop runs BEFORE
# this script (phpbrew-start.sh:148 sources setup-packages, :161 runs this), so
# a new extension was built, phpbrew wrote and enabled its ini, and the `rm -rf
# var/db` below then deleted it -- the frozen snapshot had never heard of it and
# could not restore it. The .so stayed on disk, `php -m` never listed it, and
# nothing wrote an error token, so the container reported healthy.
# Refresh the baseline ADDITIVELY instead. `--ignore-existing` never overwrites
# an entry already in it, so the reset-to-pristine property is unchanged and a
# hand-edit to var/db still cannot poison the baseline -- only a newcomer is
# picked up. Repo-owned inis are excluded because conf.d is re-applied on every
# start below: a copy of one in the baseline would outlive its deletion from the
# repo, and would also re-enable the four deliberately opt-in extensions
# (zephir_parser, phalcon, swoole, xdebug) that conf.d ships commented out.
mkdir -p "${PHPBREW_PHP_PATH}/var/dist-db"
_dist_db_excludes=()
for _repo_conf_d in "${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-conf.d" \
  "${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/php${PHP_VERSION_AS}-conf.d"; do
  [[ -d "${_repo_conf_d}" ]] || continue
  for _repo_conf_f in "${_repo_conf_d}"/*; do
    # An `if`, not `[[ … ]] && …`: the latter returns 1 when the last iteration
    # is a non-file, which is the loop's exit status, which `set -e` acts on.
    if [[ -f "${_repo_conf_f}" ]]; then
      _dist_db_excludes+=(--exclude "${_repo_conf_f##*/}")
    fi
  done
done
rsync -rav --ignore-existing "${_dist_db_excludes[@]}" \
  "${PHPBREW_PHP_PATH}"/var/db/ "${PHPBREW_PHP_PATH}/var/dist-db"

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