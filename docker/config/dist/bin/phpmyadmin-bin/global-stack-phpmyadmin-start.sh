#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** phpmyadmin global-stack-phpmyadmin-start.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

SECONDS=0
rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"

sleep 1

global-stack-base-wait-for.sh \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/php.${PHP_VERSION_AS}" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/node.${NODE_VERSION_AS}"

PATH="${COMPOSER_HOME}/vendor/bin:${COMPOSER_SOURCE}/bin:${SYMFONY_HOME}/bin:${PHPBREW_SRC}/bin:${GLOBAL_STACK_DOCKER_TOOLS_PATH}/yarn/bin:${DENO_DIR}/bin:${BUN_INSTALL}/bin:${PNPM_HOME}:${PATH}"
export PATH

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${COMPOSER_HOME}/vendor/bin:${COMPOSER_SOURCE}/bin:${SYMFONY_HOME}/bin:${PHPBREW_SRC}/bin:${GLOBAL_STACK_DOCKER_TOOLS_PATH}/yarn/bin:${DENO_DIR}/bin:${BUN_INSTALL}/bin:${PNPM_HOME}:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc
source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/phpbrew.shellrc
source "${NVM_DIR}/nvm.sh"

PATH=${PHPBREW_ROOT}/php/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}")/bin:${PHPBREW_ROOT}/php/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}")/sbin:${NVM_DIR}/versions/node/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.${NODE_VERSION_AS}")/bin:${PNPM_GLOBAL_DIR}/4/node_modules/.bin:${PNPM_GLOBAL_DIR}/5/node_modules/.bin:${YARN_GLOBAL_FOLDER}/bin:${GLOBAL_STACK_DOCKER_TOOLS_PATH}/deno/bin:${PATH}
export PATH

global-stack-nvm-eval-yarnrc.sh

echo 'source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo 'source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/phpbrew.shellrc' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo 'source "${NVM_DIR}/nvm.sh"' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo 'PATH=${PHPBREW_ROOT}/php/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}")/bin:${PHPBREW_ROOT}/php/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}")/sbin:${NVM_DIR}/versions/node/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.${NODE_VERSION_AS}")/bin:${PNPM_GLOBAL_DIR}/4/node_modules/.bin:${PNPM_GLOBAL_DIR}/5/node_modules/.bin:${YARN_GLOBAL_FOLDER}/bin:${GLOBAL_STACK_DOCKER_TOOLS_PATH}/deno/bin:${PATH}' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin" ] || [ "${GLOBAL_STACK_RELOAD_PHPMYADMIN}" = "true" ]; then
  rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin"
fi

mkdir -p "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin"

if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin" ] || [ "${GLOBAL_STACK_RELOAD_PHPMYADMIN}" = "true" ]; then
  global-stack-phpmyadmin-iou.sh
fi

global-stack-phpmyadmin-sync-dist.sh

cd "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin"

if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin" ] || [ "${GLOBAL_STACK_RELOAD_PHPMYADMIN}" = "true" ]; then
  if [[ "${GLOBAL_STACK_PHPMYADMIN_TYPE_VERSION}" == "branch" ]]; then
    sed -i 's/"name": "phpmyadmin\/phpmyadmin",/"name": "phpmyadmin\/phpmyadminx",/' "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/composer.json" 
    composer install --ignore-platform-reqs
    yarn install
    yarn build
  elif [[ "${GLOBAL_STACK_PHPMYADMIN_TYPE_VERSION}" == "tag" ]]; then
    sed -i 's/"name": "phpmyadmin\/phpmyadmin",/"name": "phpmyadmin\/phpmyadminx",/' "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/composer.json" 
    composer install --ignore-platform-reqs
    yarn install
    yarn build
  elif [[ "${GLOBAL_STACK_PHPMYADMIN_TYPE_VERSION}" == "commit" ]]; then
    sed -i 's/"name": "phpmyadmin\/phpmyadmin",/"name": "phpmyadmin\/phpmyadminx",/' "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/composer.json" 
    composer install --ignore-platform-reqs
    yarn install
    yarn build
  fi
fi

echo "${GLOBAL_STACK_PHPMYADMIN_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin"

chmod 0444 "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/config."*

global-stack-base-init-mkcert.sh

DURATION="${SECONDS}"
global-stack-base-print-success.sh "${DURATION}" "phpmyadmin"

: > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/phpmyadmin"

sleep infinity
