#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
stackCatch() {
  if [[ "${1}" != "0" ]]; then
    # error handling goes here
    echo "Error detected !!"
    printf "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: %s ** ** message: %s ** fvm (%s) %s global-stack-fvm-start.sh\n" "${2}" "${3}" "$([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}")" "${FVM_MODE:-}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
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

if [[ "${FVM_MODE}" = "install" ]]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/fvm"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

  if [[ "${GLOBAL_STACK_RELOAD_FVM}" = "true" ]]; then
    printf '\nReloading flutter ...\n'
    rm -rf "${PUB_CACHE}" "${FVM_CACHE_PATH}" "${FVM_GIT_CACHE_PATH}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/flutter"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/fvm" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/fvm"
    mkdir -p "${PUB_CACHE}" "${FVM_CACHE_PATH}" "${FVM_GIT_CACHE_PATH}"
  fi
fi

if [[ "${FVM_MODE}" = "setup" ]]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/flutter.$([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}")"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/fvm"

  if [[ "${GLOBAL_STACK_RELOAD_FLUTTER:-false}" = "true" ]]; then
    printf '\nReloading flutter %s ...\n' "${FLUTTER_VERSION:-}"
    rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/flutter.$([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}")" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter.$([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}")"
  fi

  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    printf '\nAcquiring fvm lock ...\n'
    exec 200>"${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/fvm.flock"
    flock 200
    printf 'Lock acquired\n'
  fi
fi

printf '\n******** Starting fvm %s %s ********\n' "${FVM_MODE}" "$([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}")"

mkdir -p "${PUB_CACHE}" "${FVM_CACHE_PATH}" "${FVM_GIT_CACHE_PATH}"

if [[ "${FVM_MODE}" = "install" ]]; then
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/fvm" ]] || [[ "${GLOBAL_STACK_RELOAD_FVM}" = "true" ]]; then
    curl --connect-timeout 30 --max-time 300 -fsSL -o "fvm-${FVM_VERSION}-linux-x64.tar.gz" "https://github.com/leoafarias/fvm/releases/download/${FVM_VERSION}/fvm-${FVM_VERSION}-linux-x64.tar.gz"
    tar -xvf fvm-${FVM_VERSION}-linux-x64.tar.gz
    sudo mv fvm/fvm ${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/fvm
    sudo chmod +x ${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/fvm
    sudo rm -rf fvm-${FVM_VERSION}-linux-x64.tar.gz fvm/
    echo "${FVM_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/fvm"
  fi
fi

if [[ "${FVM_MODE}" = "setup" ]]; then
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter.$([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}")" ]]; then
    printf '\nInstalling flutter version %s\n' "$([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}")"
    fvm install "${FLUTTER_VERSION:-}"
  fi

  # echo "fvm use ${FLUTTER_VERSION:-}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
  printf '\nUsing flutter %s\n' "${FLUTTER_VERSION:-}"
  # fvm use "${FLUTTER_VERSION:-}"
fi

if [[ "${FVM_MODE}" = "install" ]]; then
  printf '\nWriting /.shellrc/.fvm.shellrc\n'
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

if [[ "${FVM_MODE}" = "install" ]]; then
  printf '\nWriting success\n'
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/fvm"
fi

if [[ "${FVM_MODE}" = "setup" ]]; then
  flutter precache
  flutter doctor -v
  printf '\nWriting version\n'
  echo "${FLUTTER_VERSION:-}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter.$([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}")"
  printf '\nWriting success\n'
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/flutter.$([[ -n "${FLUTTER_VERSION_AS:-}" && "" != "${FLUTTER_VERSION_AS:-}" ]] && echo "${FLUTTER_VERSION_AS:-}" || echo "${FLUTTER_VERSION:-}")"
  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    printf '\nReleasing fvm lock\n'
    flock -u 200
    exec 200>&-
  fi
fi

sleep infinity
