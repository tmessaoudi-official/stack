#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** rbenv ($([[ -n "${RUBY_VERSION_AS:-}" && "" != "${RUBY_VERSION_AS:-}" ]] && echo "${RUBY_VERSION_AS:-}" || echo "${RUBY_VERSION:-}")) ${RBENV_MODE:-} global-stack-rbenv-start.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

SECONDS=0

PATH="${RBENV_ROOT}/bin:${PATH}"
export PATH

echo "PATH=${RBENV_ROOT}/bin:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

sleep 1

if [ "${RBENV_MODE}" = "install" ]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rbenv"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

  if [ "${GLOBAL_STACK_RELOAD_RUBY}" = "true" ]; then
    rm -rf "${RBENV_ROOT}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/ruby"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rbenv" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/fastlane"
    mkdir -p "${RBENV_ROOT}"
  fi
fi

if [ "${RBENV_MODE}" = "setup" ]; then
  rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/ruby.$([[ -n "${RUBY_VERSION_AS:-}" && "" != "${RUBY_VERSION_AS:-}" ]] && echo "${RUBY_VERSION_AS:-}" || echo "${RUBY_VERSION:-}")"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rbenv"


  if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/ruby" && "true" = "${GLOBAL_STACK_USE_LOCKS}" ]; then
    echo "$([[ -n "${RUBY_VERSION_AS:-}" && "" != "${RUBY_VERSION_AS:-}" ]] && echo "${RUBY_VERSION_AS:-}" || echo "${RUBY_VERSION:-}")" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/ruby"
  fi

  if [ "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/ruby")" != "$([[ -n "${RUBY_VERSION_AS:-}" && "" != "${RUBY_VERSION_AS:-}" ]] && echo "${RUBY_VERSION_AS:-}" || echo "${RUBY_VERSION:-}")" && "true" = "${GLOBAL_STACK_USE_LOCKS}" ]; then
    RUBY_SHOW_WAITING=""
    RUBY_WAITING_FOR=""
    while [ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/ruby" ]
    do
      [[ "${RUBY_SHOW_WAITING}" != "false" || "${RUBY_WAITING_FOR}" != "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/ruby")" ]] && echo -e "\nWaiting for ruby $(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/ruby") ..."
      RUBY_SHOW_WAITING="false"
      RUBY_WAITING_FOR=$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/ruby")
      sleep "$(shuf -i 3-6 -n 1)"
    done
    echo "$([[ -n "${RUBY_VERSION_AS:-}" && "" != "${RUBY_VERSION_AS:-}" ]] && echo "${RUBY_VERSION_AS:-}" || echo "${RUBY_VERSION:-}")" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/ruby"
  fi
fi

echo -e "\n******** Starting rbenv ${RBENV_MODE} ${RUBY_VERSION:-} ********"

mkdir -p "${RBENV_ROOT}"

if [ "${RBENV_MODE}" = "install" ]; then
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv" || "true" = "${GLOBAL_STACK_RELOAD_RUBY}" ]]; then
    global-stack-rbenv-iou.sh
  fi
fi

if [ "${RBENV_MODE}" = "install" ]; then
  echo -e "\nWriting /shellrc/rbenv.shellrc"
  echo "export RBENV_ROOT=${RBENV_ROOT}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc"
fi

if [ "${RBENV_MODE}" = "setup" ]; then
  echo -e "source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
fi

echo -e 'eval "$(rbenv init - ${GLOBAL_STACK_SHELL})"' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo -e 'eval "$(rbenv init - ${GLOBAL_STACK_SHELL})"' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.profile"
source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

if [ "${RBENV_MODE}" = "install" ]; then
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv" || "true" = "${GLOBAL_STACK_RELOAD_RUBY}" ]]; then
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" && global-stack-rbenv-install-tools.sh
    echo "$(rbenv --version | sed 's/rbenv //')" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv"
  fi
fi

if [ "${RBENV_MODE}" = "install" ]; then
  echo -e "\nWriting success"
  touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rbenv"
fi

if [ "${RBENV_MODE}" = "setup" ]; then
  export RBENV_VERSION=""
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.$([[ -n "${RUBY_VERSION_AS:-}" && "" != "${RUBY_VERSION_AS:-}" ]] && echo "${RUBY_VERSION_AS:-}" || echo "${RUBY_VERSION:-}")" || "true" = "${GLOBAL_STACK_RELOAD_RUBY}" ]]; then
    export RBENV_VERSION=$(global-stack-rbenv-find-latest.sh "${RUBY_VERSION}")
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" && global-stack-rbenv-ruby${RUBY_VERSION_AS}-install-version.sh
    
    source /usr/local/bin/global-stack-base-setup-packages.sh
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc"
    eval "$(rbenv init - ${GLOBAL_STACK_SHELL})"
    global_stack_base_setup_packages \
      --prefix='RUBY' \
      --command='echo -e "**** Installing/Updating ${PACKAGE_NAME} ${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}"' \
      --command='gem --backtrace --debug install ${PACKAGE_NAME}:${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}'

    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" && eval "$(rbenv init - ${GLOBAL_STACK_SHELL})" && global-stack-rbenv-ruby${RUBY_VERSION_AS}-setup-version.sh
  fi
  if [ "" != "${RBENV_VERSION}" ]; then
    echo -e "\nWriting version"
    echo "${RBENV_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.$([[ -n "${RUBY_VERSION_AS:-}" && "" != "${RUBY_VERSION_AS:-}" ]] && echo "${RUBY_VERSION_AS:-}" || echo "${RUBY_VERSION:-}")"
  fi
  if [ "" = "${RBENV_VERSION}" ]; then
    export RBENV_VERSION=$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.$([[ -n "${RUBY_VERSION_AS:-}" && "" != "${RUBY_VERSION_AS:-}" ]] && echo "${RUBY_VERSION_AS:-}" || echo "${RUBY_VERSION:-}")")
  fi
  
  echo "export RBENV_VERSION=${RBENV_VERSION}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

  echo -e "rbenv local ${RBENV_VERSION}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.$([[ -n "${RUBY_VERSION_AS:-}" && "" != "${RUBY_VERSION_AS:-}" ]] && echo "${RUBY_VERSION_AS:-}" || echo "${RUBY_VERSION:-}")" || "true" = "${GLOBAL_STACK_RELOAD_RUBY}" ]]; then
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" && eval "$(rbenv init - ${GLOBAL_STACK_SHELL})" && rbenv shell && rbenv local "${RBENV_VERSION}" && global-stack-rbenv-ruby${RUBY_VERSION_AS}-setup-version.sh
  fi
  
  echo -e "\nWriting success"
  touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/ruby.$([[ -n "${RUBY_VERSION_AS:-}" && "" != "${RUBY_VERSION_AS:-}" ]] && echo "${RUBY_VERSION_AS:-}" || echo "${RUBY_VERSION:-}")"
  echo -e "\nRemoving lock"
  rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/ruby"
fi

global-stack-base-init-mkcert.sh

DURATION="${SECONDS}"

global-stack-base-print-success.sh "${DURATION}" "rbenv (${RUBY_VERSION:-})"

global-stack-base-prepare-shell.sh

sleep infinity
