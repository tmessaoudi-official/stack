#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
stackCatch() {
  if [[ "${1}" != "0" ]] && [[ "${1}" != "1" ]]; then
    # error handling goes here
    echo "Error detected !!"
    printf "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: %s ** ** message: %s ** sdkman (%s) %s global-stack-sdkman-start.sh\n" "${2}" "${3}" "${JAVA_VERSION:-}" "${SDKMAN_MODE:-}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP

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
fi

printf '\n******** Starting sdkman %s %s ********\n' "${SDKMAN_MODE}" "${JAVA_VERSION:-}"

# @todo check-updates (also dist-bin/dist-src)
# @todo update manually until i find a better solution to separate current from candidate (to have different envs in different containers in the same machine)
SDK_LATEST_VERSION=${GLOBAL_STACK_SDKMAN_VERSION}
SDK_CURRENT_VERSION=$([[ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/sdkman" ]] && cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/sdkman" || echo "null")

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

  source /home/"${GLOBAL_STACK_DOCKER_USER_ID}"/${GLOBAL_STACK_SHELL_RC_TARGET} && sdk install java "${JAVA_VERSION}"
  [[ -d "${SDKMAN_DIR}/candidates/java/${JAVA_VERSION}" ]] || { printf 'Error: java %s directory missing after sdk install\n' "${JAVA_VERSION}"; exit 2; }
  echo "sdk use java '${JAVA_VERSION}'" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

  source /usr/local/bin/global-stack-base-setup-packages.sh
  source /home/"${GLOBAL_STACK_DOCKER_USER_ID}"/${GLOBAL_STACK_SHELL_RC_TARGET}

  if [[ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/java.${JAVA_VERSION_AS:-${JAVA_VERSION:-}}" ]]; then
    global_stack_base_setup_packages \
      --prefix='SDKMAN' \
      --command='echo -e "**** Using ${PACKAGE_NAME} ${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}"' \
      --command='sdk use ${PACKAGE_NAME} "${PACKAGE_VERSION}"' \
      --command='echo "sdk use ${PACKAGE_NAME} "${PACKAGE_VERSION}"" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"' \
      --command='chmod -R a+rwx "${SDKMAN_DIR}"/candidates/"${PACKAGE_NAME}"/"${PACKAGE_VERSION}"/bin'
  else
    global_stack_base_setup_packages \
      --prefix='SDKMAN' \
      --command='echo -e "**** Installing/Updating and using ${PACKAGE_NAME} ${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}"' \
      --command='sdk install "${PACKAGE_NAME}" "${PACKAGE_VERSION}" ${PACKAGE_COMMAND_SUFFIX}' \
      --command='sdk use ${PACKAGE_NAME} "${PACKAGE_VERSION}"' \
      --command='echo "sdk use ${PACKAGE_NAME} "${PACKAGE_VERSION}"" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"' \
      --command='chmod -R a+rwx "${SDKMAN_DIR}"/candidates/"${PACKAGE_NAME}"/"${PACKAGE_VERSION}"/bin'
  fi
fi

if [[ "${SDKMAN_MODE}" = "install" ]]; then
  printf '\nWriting /shellrc/sdkman.shellrc\n'
  echo "export SDKMAN_DIR=${SDKMAN_DIR}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/sdkman.shellrc"
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

sleep infinity
