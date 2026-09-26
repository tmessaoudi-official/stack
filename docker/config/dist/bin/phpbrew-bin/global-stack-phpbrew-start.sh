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
    # php.edge RELOAD must also drop the SHA sidecar so the next boot rebuilds from the
    # resolved build ref. Keep this narrow: a broadened php.edge dot-wildcard sweep would
    # also delete the per-package markers, so target php.edge.build explicitly.
    [ "${PHP_VERSION_AS}" = "edge" ] && rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.edge.build"
  fi

  # Version-mismatch gate: compare against $PHP_VERSION_NAME (the value the marker
  # actually stores — the phpbrew install dirname, e.g. php-8.4.23). On mismatch,
  # warn and DECIDE — nothing is deleted here. The install/setup triggers below also
  # fire on "reinstall", and the old php + build dirs, its frankenphp binary and the
  # pkg.* markers are dropped only after the new php is on disk (the cleanup block
  # after the install; pin-audit tranche 2, startup-prologue.test.sh §60). php.edge is
  # inert here (marker=php-master==$PHP_VERSION_NAME → skip); its SHA drift is handled
  # by the checkpoint-7 sidecar below, which stays wipe-then-build. set -eE safe
  # (helper returns 0, WARN on stderr).
  _php_marker="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}"
  _php_gate="$(gs_version_gate "${_php_marker}" "${PHP_VERSION_NAME}" "php.${PHP_VERSION_AS}")"
  _php_old=""
  if [ "${_php_gate}" = "reinstall" ]; then
    _php_old="$(cat "${_php_marker}" 2>/dev/null || true)"
  fi

  # php.edge SHA drift gate (checkpoint 7). The main php.edge marker is invariant
  # ("php-master", consumed as the install dirname), so the content-compare above never
  # rebuilds edge on an upstream commit. Compare the resolved build ref
  # (PHP_VERSION = github.com/php/php-src@<sha>) against the php.edge.build SIDECAR and
  # force a full rebuild whenever the gate is NOT "skip":
  #   - "reinstall" (sidecar present & differs): the SHA moved (gate already WARNed).
  #   - "install"   (sidecar absent): first enablement / fresh / post-RELOAD. We MUST
  #     rebuild here too, otherwise the pre-existing php-master (built from the old ref)
  #     stays installed while the sidecar written at success time would claim the new
  #     SHA — a lying marker + edge never actually reaching the tracked commit. Forcing
  #     the rebuild keeps the sidecar truthful. Idempotent: `make down` does NOT clear
  #     versions/, so the sidecar persists and "install" fires exactly once per
  #     enablement/RELOAD — never a per-boot loop.
  # The ONE runtime site that stays wipe-then-build (pin-audit tranche 2): edge always
  # builds into the same php-master prefix, which phpbrew bakes into the binaries
  # (php-config --prefix), so a new build cannot be staged beside the old one.
  # Per the agreed strategy we do NOT depend on phpbrew's replace-vs-skip behaviour —
  # REMOVE the php.edge marker AND clean the php-master build/install dirs (mirroring the
  # RELOAD path) so the install branch below does a certain fresh build. set -eE safe
  # (helper returns 0; rm -f || true).
  if [ "${PHP_VERSION_AS}" = "edge" ]; then
    _edge_sidecar="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.edge.build"
    _edge_gate="$(gs_version_gate "${_edge_sidecar}" "${PHP_VERSION}" "php.edge (build ${PHP_VERSION})")"
    if [ "${_edge_gate}" != "skip" ]; then
      if [ "${_edge_gate}" = "reinstall" ]; then
        printf '\nphp.edge build ref changed → forcing rebuild of %s\n' "${PHP_VERSION_NAME}"
      else
        printf '\nphp.edge SHA-tracking baseline absent → building %s from the tracked ref %s\n' \
          "${PHP_VERSION_NAME}" "${PHP_VERSION}"
      fi
      rm -rf "${PHPBREW_ROOT}/php/${PHP_VERSION_NAME}" "${PHPBREW_ROOT}/build/${PHP_VERSION_NAME}" \
             "${PHPBREW_BIN}/frankenphp-${GLOBAL_STACK_FRANKENPHP_VERSION}-${PHP_VERSION_NAME}"
      rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.edge.pkg."* || true
      rm -f "${_php_marker}" "${_edge_sidecar}"
    fi
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
# install-tools.sh runs on EVERY install-mode boot: each of its 11 tools carries
# its own equality gate (skip is network-free), so a composer/castor/mago/… pin
# bumped alone — up or down — reaches its gate. It used to sit inside the
# phpbrew-version check below and was never reached on a tool-only bump
# (pin-audit A2, startup-prologue.test.sh §55). It stays BEFORE iou.sh, whose
# `composer update` needs composer.
if [ "${PHPBREW_MODE}" = "install" ]; then
  global-stack-phpbrew-install-tools.sh
fi
if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew" ] || \
   [ "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew" 2>/dev/null)" != "${GLOBAL_STACK_PHPBREW_VERSION}" ] || \
   [ "${GLOBAL_STACK_RELOAD_PHPBREW}" = "true" ]; then
  if [ "${PHPBREW_MODE}" = "install" ]; then
    global-stack-phpbrew-iou.sh
  fi
fi

if [ "${PHPBREW_MODE}" = "setup" ]; then
  if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}" ] || [ "${_php_gate}" = "reinstall" ]; then
    echo -e "\n**** global-stack-phpbrew-php-install-version.sh"
    global-stack-phpbrew-php-install-version.sh
    _php_new="${PHP_VERSION_NAME}"
    # phpbrew's exit status is not proof of a working php, so the php it built must RUN and
    # report the pin before anything below cleans the old php or writes a marker: X.Y.Z-dev
    # for edge (php-src master), exactly ${PHP_VERSION} otherwise. This runs on EVERY install,
    # edge included — edge never reaches the reinstall branch (its marker is always
    # php-master), so before this an edge build that yielded no php still wrote its
    # php.edge.build sidecar (tranche 3 step 25, startup-prologue.test.sh §77). `-n` skips
    # php.ini: the CLI prints startup warnings ("Unable to load dynamic library") on STDOUT,
    # ahead of the version [measured on php-8.4.25], and this runs before the extensions and
    # the dist conf are set up — the question here is the binary, not its config. The
    # substitution may fail (no php, a php that cannot load its libs): that is caught by the
    # compare below, which names it with php's own stderr, instead of by an unnamed ERR trap.
    _php_bin="${PHPBREW_ROOT}/php/${_php_new}/bin/php"
    _php_says="$("${_php_bin}" -n -r 'echo PHP_VERSION;' 2>/dev/null || true)"
    if { [ "${PHP_VERSION_AS}" = "edge" ] && [[ "${_php_says}" != [0-9]*-dev ]]; } \
      || { [ "${PHP_VERSION_AS}" != "edge" ] && [ "${_php_says}" != "${PHP_VERSION}" ]; }; then
      printf 'FATAL: php %s does not report its pin after the install step (reports "%s", want %s)%s\n' \
        "${_php_new}" "${_php_says}" "$([ "${PHP_VERSION_AS}" = "edge" ] && echo 'X.Y.Z-dev' || echo "${PHP_VERSION}")" \
        "${_php_old:+; keeping ${_php_old}}" >&2
      printf '  php said: %s\n' "$("${_php_bin}" -n -r 'echo PHP_VERSION;' 2>&1 >/dev/null | head -3 || true)" >&2
      exit 1
    fi
    # Delete-after-install: only now, with the new php proven on disk, drop the old
    # php + build dirs and its frankenphp binaries — any frankenphp pin, since both pins
    # can move in one boot — (unless another label still records that php) and every
    # pkg.* marker; the PECL loop below then rebuilds the exts.
    if [ "${_php_gate}" = "reinstall" ]; then
      if [ ! -x "${PHPBREW_ROOT}/php/${_php_new}/bin/php" ]; then
        printf 'FATAL: php %s is not installed after the install step; keeping %s\n' "${_php_new}" "${_php_old}" >&2
        exit 1
      fi
      if [ -n "${_php_old}" ] && [ "${_php_old}" != "${_php_new}" ] \
        && [ "$(gs_version_in_use "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}" php "${PHP_VERSION_AS}" "${_php_old}")" = "free" ]; then
        printf '\nCleaning old php version dir %s\n' "${_php_old}"
        rm -rf "${PHPBREW_ROOT}/php/${_php_old}" "${PHPBREW_ROOT}/build/${_php_old}" \
          "${PHPBREW_BIN}/frankenphp-"*"-${_php_old}"
      fi
      rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}.pkg."* || true
    fi
  fi

  echo -e "\n*** Activating php version ${PHP_VERSION_NAME}"
  global-stack-phpbrew-reload-bash.sh

  # PECL ext loop runs EVERY boot after activation, gated per-package by slot
  # markers (--marker-prefix), so a package-only bump is detected even when the
  # php runtime marker is unchanged; unchanged exts skip cheaply. On a runtime
  # bump the post-install cleanup above wiped php.<AS>.pkg.* (for edge, the edge
  # branch wiped php.edge.pkg.* — never the php.edge.build sidecar).
  echo -e "\n**** stack-phpbrew-setup-packages.sh"
  source /usr/local/bin/global-stack-base-setup-packages.sh
  source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc"
  global_stack_base_setup_packages \
    --prefix='PHP' \
    --marker-prefix="php.${PHP_VERSION_AS}" \
    --command='echo -e "**** Installing/Updating ${PACKAGE_NAME} ${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}"' \
    --command='phpbrew --debug --verbose --profile ext install ${PACKAGE_NAME} ${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}'

  if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}" ] || [ "${_php_gate}" = "reinstall" ]; then
    source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc" && mkdir -p "${PHPBREW_ROOT}/php/${PHPBREW_PHP}/var/db"
    source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.phpbrew.shellrc" && printf '[PHP]\ndate.timezone = %s\n' "${GLOBAL_STACK_TIMEZONE}" > "${PHPBREW_ROOT}/php/${PHPBREW_PHP}/var/db/tzone.ini"
  fi

  global-stack-phpbrew-copy-dist-conf.sh

  if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}" ] || [ "${_php_gate}" = "reinstall" ]; then
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
  # php.edge SHA sidecar (checkpoint 7): the main php.edge marker is always "php-master"
  # (the install dirname consumed by PATH scripts) and cannot record commit drift. Store the
  # resolved build ref (PHP_VERSION = github.com/php/php-src@<sha>) so the setup-mode gate
  # rebuilds when the SHA moves. SUCCESS-GATED: this line is reached only after a verified
  # build (set -eE + prologue ERR trap abort earlier on any failure), so a failed edge build
  # never leaves a satisfied sidecar — same discipline as the package engine's --tolerant.
  if [ "${PHP_VERSION_AS}" = "edge" ]; then
    echo "${PHP_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.edge.build"
  fi
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
