#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

SECONDS=0

PATH="${COMPOSER_HOME}/vendor/bin:${COMPOSER_SOURCE}/bin:${SYMFONY_HOME}/bin:${PHPBREW_SRC}/bin:${PATH}"
export PATH

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${COMPOSER_HOME}/vendor/bin:${COMPOSER_SOURCE}/bin:${SYMFONY_HOME}/bin:${PHPBREW_SRC}/bin:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

if [ "${PHPBREW_MODE}" = "install" ]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/phpbrew"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

  if [ "${GLOBAL_STACK_RELOAD_PHPBREW}" = "true" ]; then
    rm -rf "${COMPOSER_HOME}" "${SYMFONY_HOME}" "${PHPBREW_ROOT}" "${PHPBREW_SRC}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/php"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/phpbrew.shellrc" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php"* "${PHPBREW_BIN}/composer" "${PHPBREW_BIN}/dep" "${PHPBREW_BIN}/phpbrew" "${PHPBREW_BIN}/pickle" "${PHPBREW_BIN}/symfony-installer" "${PHPBREW_BIN}/fabpot-local-php-security-checker" "${PHPBREW_BIN}/phalcon" "${PHPBREW_BIN}/zephir" "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp" "${PHPBREW_BIN}/frankenphp"*
    mkdir -p "${COMPOSER_HOME}" "${COMPOSER_HOME}/bin" "${COMPOSER_SOURCE}" "${SYMFONY_HOME}/bin" "${PHPBREW_ROOT}" "${PHPBREW_SRC}" "${PHPBREW_BIN}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp"
  fi

  mkdir -p "${COMPOSER_HOME}" "${COMPOSER_HOME}/bin" "${COMPOSER_SOURCE}" "${SYMFONY_HOME}/bin" "${PHPBREW_ROOT}" "${PHPBREW_SRC}" "${PHPBREW_BIN}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp"
fi

if [ "${PHPBREW_MODE}" = "setup" ]; then
  rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/php.${PHP_VERSION_AS}"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  if [ "${GLOBAL_STACK_RELOAD_PHP}" = "true" ]; then
    PHPBREW_PHP="${PHP_VERSION_NAME}"
    PHPBREW_PHP_PATH="${PHPBREW_ROOT}/php/${PHPBREW_PHP}"
    PHPBREW_PHP_BUILD_PATH="${PHPBREW_ROOT}/build/${PHPBREW_PHP}"
    rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}" "${PHPBREW_BIN}/frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}-${PHP_VERSION_NAME}" "${PHPBREW_PHP_PATH}/" "${PHPBREW_PHP_BUILD_PATH}/"
  fi

  # Version-mismatch gate: compare against $PHP_VERSION_NAME (the value the marker
  # actually stores — the phpbrew install dirname, e.g. php-8.4.23). On mismatch,
  # warn + clean the old php + build dirs and package markers, then drop the marker
  # so the install/setup blocks below rebuild the new version. php.edge is inert
  # here (marker=php-master==$PHP_VERSION_NAME → skip); its SHA drift is handled by
  # the checkpoint-7 sidecar. set -eE safe (helper returns 0, WARN on stderr).
  _php_marker="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}"
  _php_gate="$(gs_version_gate "${_php_marker}" "${PHP_VERSION_NAME}" "php.${PHP_VERSION_AS}")"
  if [ "${_php_gate}" = "reinstall" ]; then
    _php_old="$(cat "${_php_marker}" 2>/dev/null || true)"
    if [ -n "${_php_old}" ] && [ "${_php_old}" != "${PHP_VERSION_NAME}" ]; then
      printf '\nCleaning old php version dir %s\n' "${_php_old}"
      rm -rf "${PHPBREW_ROOT}/php/${_php_old}" "${PHPBREW_ROOT}/build/${_php_old}"
    fi
    rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}.pkg."* || true
    rm -f "${_php_marker}"
  fi
  sleep 1
  
  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/phpbrew"

  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    echo -e "\nAcquiring phpbrew lock ..."
    exec 200>"${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/phpbrew.flock"
    flock 200
    echo -e "Lock acquired"
  fi
fi

echo -e "\n******** Starting Phpbrew ${PHPBREW_MODE} ${PHP_VERSION:-} ********"



mkdir -p "${COMPOSER_HOME}" "${COMPOSER_HOME}/bin" "${COMPOSER_SOURCE}" "${SYMFONY_HOME}/bin" "${PHPBREW_ROOT}" "${PHPBREW_BIN}"

# ckpt4: version-drift WARN only (single source: gs_version_gate). Reinstall
# decision stays with the existing content-compare below (behavior unchanged);
# `|| true` satisfies the set -eE ERR-trap invariant for a discard-decision call.
gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew" "${GLOBAL_STACK_PHPBREW_VERSION}" "phpbrew" >/dev/null || true
if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew" ] || \
   [ "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew" 2>/dev/null)" != "${GLOBAL_STACK_PHPBREW_VERSION}" ] || \
   [ "${GLOBAL_STACK_RELOAD_PHPBREW}" = "true" ]; then
  if [ "${PHPBREW_MODE}" = "install" ]; then
    global-stack-phpbrew-install-tools.sh
    global-stack-phpbrew-iou.sh
  fi
fi

if [ "${PHPBREW_MODE}" = "setup" ]; then
  if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}" ]; then
    echo -e "\n**** global-stack-phpbrew-php-install-version.sh"
    global-stack-phpbrew-php-install-version.sh
  fi

  echo -e "\n*** Activating php version ${PHP_VERSION_NAME}"
  global-stack-phpbrew-reload-bash.sh

  # PECL ext loop runs EVERY boot after activation, gated per-package by slot
  # markers (--marker-prefix), so a package-only bump is detected even when the
  # php runtime marker is unchanged; unchanged exts skip cheaply. On a runtime
  # bump the checkpoint-2 gate wiped php.<AS>.pkg.* (php.edge.pkg.* for edge —
  # never the php.edge.build sidecar).
  echo -e "\n**** stack-phpbrew-setup-packages.sh"
  source /usr/local/bin/global-stack-base-setup-packages.sh
  source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc"
  global_stack_base_setup_packages \
    --prefix='PHP' \
    --marker-prefix="php.${PHP_VERSION_AS}" \
    --command='echo -e "**** Installing/Updating ${PACKAGE_NAME} ${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}"' \
    --command='phpbrew --debug --verbose --profile ext install ${PACKAGE_NAME} ${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}'

  if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}" ]; then
    source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc" && mkdir -p "${PHPBREW_ROOT}/php/${PHPBREW_PHP}/var/db"
    source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc" && printf '[PHP]\ndate.timezone = %s\n' "${GLOBAL_STACK_TIMEZONE}" > "${PHPBREW_ROOT}/php/${PHPBREW_PHP}/var/db/tzone.ini"
  fi

  global-stack-phpbrew-copy-dist-conf.sh

  if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}" ]; then
    echo -e "\n**** global-stack-phpbrew-php${PHP_VERSION_AS}-setup-version.sh"
    source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc" && global-stack-phpbrew-php${PHP_VERSION_AS}-setup-version.sh
  fi

  source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc" && global-stack-phpbrew-php${PHP_VERSION_AS}-setup-project.sh
  source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc" && global-stack-phpbrew-sync-frankenphp.sh

  source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc" && phpbrew fpm start "${PHPBREW_PHP}" &

  LD_LIBRARY_PATH="$(php-config --prefix)/lib:${LD_LIBRARY_PATH}"
  export LD_LIBRARY_PATH
  
  if [[ -f ${PHPBREW_BIN}/frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}-${PHP_VERSION_NAME} ]]; then
    source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc" && LD_LIBRARY_PATH="${LD_LIBRARY_PATH}" frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}-${PHP_VERSION_NAME} run --config $(php-config --prefix)/var/frankenphp/Caddyfile &
  fi
fi

if [ "${PHPBREW_MODE}" = "install" ]; then
  echo -e "\nWriting /shellrc/phpbrew.shellrc"
  # E-4: write to a temp file then atomic-rename onto the shared volume so the
  # host never sources a partially-written phpbrew.shellrc (rename is atomic on
  # the same filesystem; both paths live under TOOLS_PATH_SHELLRC).
  phpbrew_shellrc="${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/phpbrew.shellrc"
  {
    echo "export PHPBREW_BIN=${PHPBREW_BIN}"
    echo "export PHPBREW_HOME=${PHPBREW_HOME}"
    echo "export PHPBREW_ROOT=${PHPBREW_ROOT}"
    echo "export PHPBREW_SRC=${PHPBREW_SRC}"
    echo "export PHPBREW_SET_PROMPT=${PHPBREW_SET_PROMPT}"
    echo "export PHPBREW_SKIP_INIT=${PHPBREW_SKIP_INIT}"
    echo "export PHPBREW_RC_ENABLE=${PHPBREW_RC_ENABLE}"
    echo "export COMPOSER_HOME=${COMPOSER_HOME}"
    echo "export COMPOSER_SOURCE=${COMPOSER_SOURCE}"
    echo "export SYMFONY_HOME=${SYMFONY_HOME}"
  } > "${phpbrew_shellrc}.tmp" && mv "${phpbrew_shellrc}.tmp" "${phpbrew_shellrc}"
fi

# ----------------------------------

global-stack-base-init-mkcert.sh
global-stack-base-prepare-shell.sh
echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION="${SECONDS}"
global-stack-base-print-success.sh "${DURATION}" "phpbrew (${PHP_VERSION} - ${PHP_VERSION_NAME:-})"

if [ "${PHPBREW_MODE}" = "install" ]; then
  echo -e "\nWriting success"
  echo "${GLOBAL_STACK_PHPBREW_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew"
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/phpbrew"
fi

if [ "${PHPBREW_MODE}" = "setup" ]; then
  echo -e "\nWriting version"
  echo "${PHP_VERSION_NAME}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}"
  echo -e "\nWriting success"
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/php.${PHP_VERSION_AS}"
  
  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    echo -e "\nReleasing phpbrew lock"
    flock -u 200
    exec 200>&-
  fi
fi

if [ "${PHPBREW_MODE:-}" = "install" ] && [ "${GLOBAL_STACK_RELOAD_PHPBREW:-false}" = "true" ]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_PHPBREW is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi
if [ "${PHPBREW_MODE:-}" = "setup" ] && [ "${GLOBAL_STACK_RELOAD_PHP:-false}" = "true" ]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_PHP is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi

sleep infinity
