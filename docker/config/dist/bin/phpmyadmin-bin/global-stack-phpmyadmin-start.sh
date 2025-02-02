#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** phpmyadmin global-stack-phpmyadmin-start.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

SECONDS=0

sleep 1


global-stack-base-wait-for.sh \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/php.next"

if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin" ] || [ "${GLOBAL_STACK_RELOAD_PHPMYADMIN}" = "true" ]; then
  rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin"
fi

mkdir -p "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin"

if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin" ] || [ "${GLOBAL_STACK_RELOAD_PHPMYADMIN}" = "true" ]; then
  global-stack-phpmyadmin-iou.sh
fi

PHPMYADMIN_CURRENT_RELEASE=$([[ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin" ]] && cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin" || echo "${PHPMYADMIN_LATEST_RELEASE}")

global-stack-phpmyadmin-sync-dist.sh

cd "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin"

if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin" ] || [ "${GLOBAL_STACK_RELOAD_PHPMYADMIN}" = "true" ]; then
  source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/phpbrew.shellrc" && export PATH="${PHPBREW_ROOT}/php/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.next")/bin:${PATH}"
  # composer install --ignore-platform-reqs
fi


echo "$(global-stack-phpmyadmin-get-latest-version.sh)" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin"

chmod 0444 "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/config."*

global-stack-base-init-mkcert.sh

DURATION="${SECONDS}"
global-stack-base-print-success.sh "${DURATION}" "phpmyadmin"

sleep infinity
