#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

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

# Row 21. All three guards below were exist-only, and the marker write at the foot
# of this script sat OUTSIDE every condition — so it was rewritten with the current
# pin on every boot and could never serve as a comparison. A PHPMYADMIN_VERSION or
# _TYPE_VERSION bump therefore did nothing at all without RELOAD_PHPMYADMIN.
# The marker is composite because the TYPE (branch/tag/commit) changes what gets
# built from the same version string, so the two together are the identity.
# gs_version_gate comes from the prologue this script already sources.
_pma_want="${GLOBAL_STACK_PHPMYADMIN_VERSION};type=${GLOBAL_STACK_PHPMYADMIN_TYPE_VERSION}"
_pma_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin" "${_pma_want}" "phpmyadmin")"
_pma_install=0
if [ "${_pma_gate}" != "skip" ] || [ "${GLOBAL_STACK_RELOAD_PHPMYADMIN}" = "true" ]; then
  _pma_install=1
fi

if [ "${_pma_install}" = "1" ]; then
  rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin"
fi

mkdir -p "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin"

if [ "${_pma_install}" = "1" ]; then
  global-stack-phpmyadmin-iou.sh
fi

global-stack-phpmyadmin-sync-dist.sh

cd "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin"

if [ "${_pma_install}" = "1" ]; then
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
  # Marker last, and INSIDE the install branch. It used to sit outside every
  # condition, so it was refreshed on every boot and always matched — which is
  # precisely why a version bump was invisible.
  printf '%s\n' "${_pma_want}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin"
fi

chmod 0444 "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/config."*
chmod 0640 "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/config.secret.inc.php"

global-stack-base-init-mkcert.sh

DURATION="${SECONDS}"
global-stack-base-print-success.sh "${DURATION}" "phpmyadmin"

: > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/phpmyadmin"

if [ "${GLOBAL_STACK_RELOAD_PHPMYADMIN:-false}" = "true" ]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_PHPMYADMIN is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi

sleep infinity
