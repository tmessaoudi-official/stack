#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** fvm ($([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}")) ${FVM_MODE:-} global-stack-fvm-start.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP

SECONDS=0
PATH="${PUB_CACHE}/bin:${FVM_CACHE_PATH}/versions/${FLUTTER_VERSION:-}/bin:${PATH}"
export PATH

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${PUB_CACHE}/bin:${FVM_CACHE_PATH}/versions/${FLUTTER_VERSION:-}/bin:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

if [ "${FVM_MODE}" = "install" ]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/fvm"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"
  
  if [ "${GLOBAL_STACK_RELOAD_FVM}" = "true" ]; then
    echo -e "\nReloading flutter ..."
    rm -rf "${PUB_CACHE}" "${FVM_CACHE_PATH}" "${FVM_GIT_CACHE_PATH}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/flutter"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/fvm" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/fvm"
    mkdir -p "${PUB_CACHE}" "${FVM_CACHE_PATH}" "${FVM_GIT_CACHE_PATH}"
  fi
fi

if [ "${FVM_MODE}" = "setup" ]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/flutter.$([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}")"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/fvm"

  if [ "${GLOBAL_STACK_RELOAD_FLUTTER3:-false}" = "true" ]; then
    echo -e "\nReloading flutter ${FLUTTER_VERSION:-} ..."
    rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/flutter.$([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}")" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter.$([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}")"
  fi

  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    echo -e "\nAcquiring fvm lock ..."
    exec 200>"${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/fvm.flock"
    flock 200
    echo -e "Lock acquired"
  fi
fi

echo -e "\n******** Starting fvm ${FVM_MODE} $([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}") ********"

mkdir -p "${PUB_CACHE}" "${FVM_CACHE_PATH}" "${FVM_GIT_CACHE_PATH}"

if [ "${FVM_MODE}" = "install" ]; then
  if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/fvm" ] || [ "${GLOBAL_STACK_RELOAD_FVM}" = "true" ]; then
    curl -fsSL -o "fvm-${FVM_VERSION}-linux-x64.tar.gz" "https://github.com/leoafarias/fvm/releases/download/${FVM_VERSION}/fvm-${FVM_VERSION}-linux-x64.tar.gz"
    tar -xvf fvm-${FVM_VERSION}-linux-x64.tar.gz
    sudo mv fvm/fvm ${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/fvm
    sudo chmod +x ${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/fvm
    sudo rm -rf fvm-${FVM_VERSION}-linux-x64.tar.gz fvm/
    echo "${FVM_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/fvm"
  fi
fi

if [ "${FVM_MODE}" = "setup" ]; then
  if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter.$([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}")" ]; then
    echo -e "\nInstalling flutter version $([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}")"
    fvm install "${FLUTTER_VERSION:-}"
  fi
  
  # echo "fvm use ${FLUTTER_VERSION:-}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
  echo -e "\nUsing flutter ${FLUTTER_VERSION:-}"
  # fvm use "${FLUTTER_VERSION:-}"
fi

if [ "${FVM_MODE}" = "install" ]; then
  echo -e "\nWriting /.shellrc/.fvm.shellrc"
  echo "export FVM_CACHE_PATH=${FVM_CACHE_PATH}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/fvm.shellrc"
  echo "export FVM_GIT_CACHE_PATH=${FVM_GIT_CACHE_PATH}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/fvm.shellrc"
  echo "export FVM_USE_GIT_CACHE=${FVM_USE_GIT_CACHE}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/fvm.shellrc"
  echo "export FVM_FLUTTER_URL=${FVM_FLUTTER_URL}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/fvm.shellrc"
  echo "export PUB_CACHE=${PUB_CACHE}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/fvm.shellrc"
fi
# ----------------------------------

global-stack-base-init-mkcert.sh
global-stack-base-prepare-shell.sh
echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION="${SECONDS}"
global-stack-base-print-success.sh "${DURATION}" "fvm (${FLUTTER_VERSION:-})"

if [ "${FVM_MODE}" = "install" ]; then
  echo -e "\nWriting success"
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/fvm"
fi

if [ "${FVM_MODE}" = "setup" ]; then
  flutter precache
  flutter doctor -v
  echo -e "\nWriting version"
  echo "${FLUTTER_VERSION:-}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter.$([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}")"
  echo -e "\nWriting success"
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/flutter.$([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}")"
  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    echo -e "\nReleasing fvm lock"
    flock -u 200
    exec 200>&-
  fi
fi

sleep infinity