#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

php_frankenphp_dest_dir=$(php-config --prefix)/var/frankenphp

rm -rf ${php_frankenphp_dest_dir}

mkdir -p ${php_frankenphp_dest_dir}/logs ${php_frankenphp_dest_dir}/vhosts

rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/php${PHP_VERSION_AS}-frankenphp/ ${php_frankenphp_dest_dir}/vhosts

if [[ -f ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-frankenphp/Caddyfile.local ]]; then
  cp ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-frankenphp/Caddyfile.local ${php_frankenphp_dest_dir}/Caddyfile
else
  cp ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-frankenphp/Caddyfile ${php_frankenphp_dest_dir}/Caddyfile
fi

# Replace placeholders with actual paths
sed -i "s|\${GLOBAL_STACK_DOCKER_TOOLS_PATH}|${GLOBAL_STACK_DOCKER_TOOLS_PATH}|g; s|\${GLOBAL_STACK_DOCKER_WORKDIR}|${GLOBAL_STACK_DOCKER_WORKDIR}|g; s|\${GLOBAL_STACK_SSL_PATH}|${GLOBAL_STACK_SSL_PATH}|g; s|\${CAROOT}|${CAROOT}|g; s|\${PHP_PREFIX}|${php_frankenphp_dest_dir}|g" \
  ${php_frankenphp_dest_dir}/Caddyfile

rm -rf ${php_frankenphp_dest_dir}/vhosts/example*

find ${php_frankenphp_dest_dir}/vhosts/ -type f -exec sed -i "s|\${GLOBAL_STACK_DOCKER_TOOLS_PATH}|${GLOBAL_STACK_DOCKER_TOOLS_PATH}|g; s|\${GLOBAL_STACK_DOCKER_WORKDIR}|${GLOBAL_STACK_DOCKER_WORKDIR}|g; s|\${GLOBAL_STACK_SSL_PATH}|${GLOBAL_STACK_SSL_PATH}|g; s|\${CAROOT}|${CAROOT}|g; s|\${PHP_PREFIX}|${php_frankenphp_dest_dir}|g" {} \;