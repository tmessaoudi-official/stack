#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh
# @todo have separate current candidate for each container/space ... "\$\{SDKMAN_CANDIDATES_DIR\}/(\$\{candidate(_name)?\})/current"
# \$\{SDKMAN_CANDIDATES_DIR\}/(\$\{candidate\})/current
# ${HOME}/.sdkman/${candidate}/current

# \$\{SDKMAN_CANDIDATES_DIR\}/(\$\{candidate_name\})/current
# ${HOME}/.sdkman/${candidate_name}/current

# \tmkdir -p "\$\{SDKMAN_CANDIDATES_DIR\}/\$\{candidate\}"
# \tmkdir -p "${SDKMAN_CANDIDATES_DIR}/${candidate}"\n
# \tmkdir -p "${HOME}/.sdkman/${candidate}"

# \t# Just update the \*_HOME and PATH for this shell.
# \t# Just update the *_HOME and PATH for this shell.
# \tmkdir -p "${HOME}/.sdkman/${candidate}/current"

SECONDS=0

if [[ "${SDKMAN_MODE}" = "install" ]]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}"/sdkman
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

  if [[ "${GLOBAL_STACK_RELOAD_SDKMAN}" = "true" ]]; then
    printf '\nReloading java ...\n'
    rm -rf "${SDKMAN_DIR}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/java"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/sdkman" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/java"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/sdkman" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/sdkman.installer.sh" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/sdkman.shellrc"
  fi
fi

if [[ "${SDKMAN_MODE}" = "setup" ]]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/java.${JAVA_VERSION_AS:-${JAVA_VERSION:-}}"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/sdkman"

  # if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
  printf '\nAcquiring sdkman lock ...\n'
  exec 200>"${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/sdkman.flock"
  flock 200
  printf 'Lock acquired\n'
  # fi

  if [[ "${GLOBAL_STACK_RELOAD_JAVA:-false}" = "true" ]]; then
    printf '\nReloading java %s ...\n' "${JAVA_VERSION_AS:-${JAVA_VERSION:-}}"
    rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/java.${JAVA_VERSION_AS:-${JAVA_VERSION:-}}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/java.${JAVA_VERSION_AS:-${JAVA_VERSION:-}}"
  fi

  # Version-mismatch gate: compare against $JAVA_VERSION (the raw value the marker
  # stores — sdkman uses prebuilt binaries, no resolver). On mismatch, warn +
  # clean the old java candidate dir and package markers, then drop the marker so
  # the setup block below reinstalls the new JDK. sdkman package candidates
  # (maven/gradle/…) are JDK-independent, so re-`sdk use` on the fresh markers is
  # harmless/idempotent. set -eE safe (helper returns 0, WARN on stderr).
  _java_label="${JAVA_VERSION_AS:-${JAVA_VERSION:-}}"
  _java_marker="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/java.${_java_label}"
  _java_gate="$(gs_version_gate "${_java_marker}" "${JAVA_VERSION:-}" "java.${_java_label}")"
  if [[ "${_java_gate}" == "reinstall" ]]; then
    _java_old="$(cat "${_java_marker}" 2>/dev/null || true)"
    if [[ -n "${_java_old}" && "${_java_old}" != "${JAVA_VERSION:-}" ]]; then
      printf '\nCleaning old java candidate dir %s\n' "${_java_old}"
      rm -rf "${SDKMAN_DIR}/candidates/java/${_java_old}"
    fi
    rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/java.${_java_label}.pkg."* || true
    rm -f "${_java_marker}"
  fi
fi

printf '\n******** Starting sdkman %s %s ********\n' "${SDKMAN_MODE}" "${JAVA_VERSION:-}"

# @todo check-updates (also dist-bin/dist-src)
# @todo update manually until i find a better solution to separate current from candidate (to have different envs in different containers in the same machine)
SDK_LATEST_VERSION=${GLOBAL_STACK_SDKMAN_VERSION}
SDK_CURRENT_VERSION=$([[ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/sdkman" ]] && cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/sdkman" || echo "null")

# ckpt4: version-drift WARN only (single source: gs_version_gate). Reinstall
# decision stays with the bespoke SDK_LATEST/SDK_CURRENT compare below (the
# @todo current-vs-candidate design is deliberate — behavior unchanged);
# `|| true` satisfies the set -eE ERR-trap invariant for a discard-decision call.
gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/sdkman" "${GLOBAL_STACK_SDKMAN_VERSION}" "sdkman" >/dev/null || true
if [[ "${SDK_LATEST_VERSION}" != "${SDK_CURRENT_VERSION}" ]]; then
  rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/sdkman.installer.sh"
  #curl -fsSL -o "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/sdkman.installer.sh" "https://get.sdkman.io"
  cp ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/sdkman/bin/sdkman.installer.sh "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/sdkman.installer.sh

  echo "${SDK_LATEST_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/sdkman"
fi

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

chmod a+x "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/sdkman.installer.sh"
"${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/sdkman.installer.sh
echo '"${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/sdkman.installer.sh' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
source "${SDKMAN_DIR}"/bin/sdkman-init.sh
echo 'source "${SDKMAN_DIR}"/bin/sdkman-init.sh' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

# @todo this is temporary
rsync -rav ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/sdkman/src/ "${SDKMAN_DIR}"/src
rsync -rav ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/sdkman/bin/ "${SDKMAN_DIR}"/bin
"${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/sdkman.installer.sh
source "${SDKMAN_DIR}"/bin/sdkman-init.sh

# @todo to be done manually for now !!
#source /home/"${GLOBAL_STACK_DOCKER_USER_ID}"/${GLOBAL_STACK_SHELL_RC_TARGET} && sdk selfupdate force
#source /home/"${GLOBAL_STACK_DOCKER_USER_ID}"/${GLOBAL_STACK_SHELL_RC_TARGET} && sdk update

# @todo refactor
if [[ "${SDKMAN_MODE}" = "setup" ]]; then
  printf '\n \033[0;31m Setting up java %s\n' "${JAVA_VERSION}"
  if [[ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/java.${JAVA_VERSION_AS:-${JAVA_VERSION:-}}" ]]; then
    mkdir -p "${HOME}/.sdkman/etc/"
    touch "${HOME}/.sdkman/etc/config"
    echo "sdkman_healthcheck_enable=false" > "${HOME}/.sdkman/etc/config"

    source "${HOME}/.sdkman/etc/config"
  fi

  set +E
  source /home/"${GLOBAL_STACK_DOCKER_USER_ID}"/${GLOBAL_STACK_SHELL_RC_TARGET} && sdk install java "${JAVA_VERSION}"
  set -E
  [[ -d "${SDKMAN_DIR}/candidates/java/${JAVA_VERSION}" ]] || { printf 'Error: java %s directory missing after sdk install\n' "${JAVA_VERSION}"; exit 2; }
  echo "sdk use java '${JAVA_VERSION}'" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

  source /usr/local/bin/global-stack-base-setup-packages.sh
  source /home/"${GLOBAL_STACK_DOCKER_USER_ID}"/${GLOBAL_STACK_SHELL_RC_TARGET}

  # Install loop: gated per-slot by markers so only new/changed sdkman candidates
  # are installed — a package-only bump is detected even when the java runtime
  # marker is unchanged (the former dual-branch only installed when the runtime
  # marker was absent). Slot-keyed markers keep the maven/gradle/groovy/spark
  # multi-slot cases distinct. sdkman candidates are JDK-independent, so a java
  # runtime bump (ckpt-2 gate wiped java.<AS>.pkg.*) just re-installs them
  # idempotently. --cleanup-command uninstalls the OLD version on a bump
  # (candidates accumulate). set +E: sdk commands return non-zero benignly.
  set +E
  global_stack_base_setup_packages \
    --prefix='SDKMAN' \
    --marker-prefix="java.${JAVA_VERSION_AS:-${JAVA_VERSION:-}}" \
    --tolerant \
    --success-check='[[ -d "${SDKMAN_DIR}/candidates/${PACKAGE_NAME}/${PACKAGE_VERSION}" ]]' \
    --cleanup-command='sdk uninstall ${PACKAGE_NAME} "${PACKAGE_OLD_VERSION}" || true' \
    --command='echo -e "**** Installing/Updating ${PACKAGE_NAME} ${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}"' \
    --command='sdk install "${PACKAGE_NAME}" "${PACKAGE_VERSION}" ${PACKAGE_COMMAND_SUFFIX}'
  set -E

  # Activation loop: `sdk use` + shellrc line + chmod run EVERY boot for EVERY
  # package (NO --marker-prefix) so PATH/shellrc are correct even when nothing was
  # reinstalled. Runs after the install loop so every candidate exists.
  set +E
  global_stack_base_setup_packages \
    --prefix='SDKMAN' \
    --command='echo -e "**** Using ${PACKAGE_NAME} ${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}"' \
    --command='sdk use ${PACKAGE_NAME} "${PACKAGE_VERSION}"' \
    --command='echo "sdk use ${PACKAGE_NAME} "${PACKAGE_VERSION}"" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"' \
    --command='chmod -R a+rwx "${SDKMAN_DIR}"/candidates/"${PACKAGE_NAME}"/"${PACKAGE_VERSION}"/bin'
  set -E
fi

if [[ "${SDKMAN_MODE}" = "install" ]]; then
  printf '\nWriting /shellrc/sdkman.shellrc\n'
  # E-4: write to a temp file then atomic-rename onto the shared volume so the
  # host never sources a partially-written sdkman.shellrc (rename is atomic on
  # the same filesystem; both paths live under TOOLS_PATH_SHELLRC).
  sdkman_shellrc="${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/sdkman.shellrc"
  echo "export SDKMAN_DIR=${SDKMAN_DIR}" > "${sdkman_shellrc}.tmp" && mv "${sdkman_shellrc}.tmp" "${sdkman_shellrc}"
fi

global-stack-base-init-mkcert.sh
global-stack-base-prepare-shell.sh
echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION="${SECONDS}"
global-stack-base-print-success.sh "${DURATION}" "sdkman (${JAVA_VERSION:-})"

if [[ "${SDKMAN_MODE}" = "install" ]]; then
  printf '\nWriting success\n'
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/sdkman"
fi

if [[ "${SDKMAN_MODE}" = "setup" ]]; then
  printf '\nWriting version\n'
  echo "${JAVA_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/java.${JAVA_VERSION_AS:-${JAVA_VERSION:-}}"
  printf '\nWriting success\n'
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/java.${JAVA_VERSION_AS:-${JAVA_VERSION:-}}"
  # if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
  printf '\nReleasing sdkman lock\n'
  flock -u 200
  exec 200>&-
  # fi
fi

if [[ "${SDKMAN_MODE:-}" = "install" ]] && [[ "${GLOBAL_STACK_RELOAD_SDKMAN:-false}" = "true" ]]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_SDKMAN is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi
if [[ "${SDKMAN_MODE:-}" = "setup" ]] && [[ "${GLOBAL_STACK_RELOAD_JAVA:-false}" = "true" ]]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_JAVA is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi

sleep infinity
