#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** phpbrew ($([[ -n "${PHP_VERSION_AS:-}" && "" != "${PHP_VERSION_AS:-}" ]] && echo "${PHP_VERSION_AS:-}" || echo "${PHP_VERSION:-}")) ${PHPBREW_MODE:-} global-stack-phpbrew-sync-frankenphp.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

php_caddy_dest_dir=$(php-config --prefix)/var/caddy

rm -rf ${php_caddy_dest_dir}

mkdir -p ${php_caddy_dest_dir}/logs ${php_caddy_dest_dir}/vhosts

rsync -raz ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/php${PHP_VERSION_AS}-caddy/ ${php_caddy_dest_dir}/vhosts

if [[ -f ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-caddy/Caddyfile.local ]]; then
  cp ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-caddy/Caddyfile.local ${php_caddy_dest_dir}/Caddyfile
else
  cp ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-caddy/Caddyfile ${php_caddy_dest_dir}/Caddyfile
fi

# Replace placeholders with actual paths
sed -i "s|\${GLOBAL_STACK_DOCKER_TOOLS_PATH}|${GLOBAL_STACK_DOCKER_TOOLS_PATH}|g; s|\${GLOBAL_STACK_DOCKER_WORKDIR}|${GLOBAL_STACK_DOCKER_WORKDIR}|g; s|\${GLOBAL_STACK_SSL_PATH}|${GLOBAL_STACK_SSL_PATH}|g; s|\${CAROOT}|${CAROOT}|g; s|\${PHP_PREFIX}|${php_caddy_dest_dir}|g" \
  ${php_caddy_dest_dir}/Caddyfile

rm -rf ${php_caddy_dest_dir}/vhosts/example*

find ${php_caddy_dest_dir}/vhosts/ -type f -exec sed -i "s|\${GLOBAL_STACK_DOCKER_TOOLS_PATH}|${GLOBAL_STACK_DOCKER_TOOLS_PATH}|g; s|\${GLOBAL_STACK_DOCKER_WORKDIR}|${GLOBAL_STACK_DOCKER_WORKDIR}|g; s|\${GLOBAL_STACK_SSL_PATH}|${GLOBAL_STACK_SSL_PATH}|g; s|\${CAROOT}|${CAROOT}|g; s|\${PHP_PREFIX}|${php_caddy_dest_dir}|g" {} \;