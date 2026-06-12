#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
stackCatch() {
  if [[ "${1}" != "0" ]]; then
    # error handling goes here
    echo "Error detected !!"
    printf "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: %s ** ** message: %s ** rbenv (%s) %s global-stack-rbenv-start.sh\n" "${2}" "${3}" "${RUBY_VERSION_AS:-${RUBY_VERSION:-}}" "${RBENV_MODE:-}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP

SECONDS=0

PATH="${RBENV_ROOT}/bin:${PATH}"
export PATH

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${RBENV_ROOT}/bin:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

sleep 1

if [[ "${RBENV_MODE}" = "install" ]]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rbenv"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

  if [[ "${GLOBAL_STACK_RELOAD_RBENV}" = "true" ]]; then
    rm -rf "${RBENV_ROOT}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/ruby"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rbenv" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/fastlane"
    mkdir -p "${RBENV_ROOT}"
  fi
fi

if [[ "${RBENV_MODE}" = "setup" ]]; then
  rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/ruby.${RUBY_VERSION_AS:-${RUBY_VERSION:-}}"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rbenv"

  if [[ "${GLOBAL_STACK_RELOAD_RUBY:-false}" = "true" ]]; then
    printf '\nReloading ruby %s ...\n' "${RUBY_VERSION_AS:-${RUBY_VERSION:-}}"
    rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/ruby.${RUBY_VERSION_AS:-${RUBY_VERSION:-}}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.${RUBY_VERSION_AS:-${RUBY_VERSION:-}}"
  fi

  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    printf '\nAcquiring rbenv lock ...\n'
    exec 200>"${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/rbenv.flock"
    flock 200
    printf 'Lock acquired\n'
  fi
fi

printf '\n******** Starting rbenv %s %s ********\n' "${RBENV_MODE}" "${RUBY_VERSION:-}"

mkdir -p "${RBENV_ROOT}"

if [[ "${RBENV_MODE}" = "install" ]]; then
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv" ]] || \
     [[ "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv" 2>/dev/null)" != "${GLOBAL_STACK_RBENV_VERSION#v}" ]] || \
     [[ "true" = "${GLOBAL_STACK_RELOAD_RBENV}" ]]; then
    global-stack-rbenv-iou.sh
  fi
fi

if [[ "${RBENV_MODE}" = "install" ]]; then
  printf '\nWriting /shellrc/rbenv.shellrc\n'
  echo "export RBENV_ROOT=${RBENV_ROOT}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc"
fi

if [[ "${RBENV_MODE}" = "setup" ]]; then
  printf '%s\n' "source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
fi

printf '%s\n' 'eval "$(rbenv init - ${GLOBAL_STACK_SHELL})"' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
printf '%s\n' 'eval "$(rbenv init - ${GLOBAL_STACK_SHELL})"' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.profile"
source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

if [[ "${RBENV_MODE}" = "install" ]]; then
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv" ]] || \
     [[ "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv" 2>/dev/null)" != "${GLOBAL_STACK_RBENV_VERSION#v}" ]] || \
     [[ "true" = "${GLOBAL_STACK_RELOAD_RBENV}" ]]; then
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" && global-stack-rbenv-install-tools.sh
    echo "$(rbenv --version | sed 's/rbenv //')" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv"
  fi
fi

global-stack-base-init-mkcert.sh
global-stack-base-prepare-shell.sh

if [[ "${RBENV_MODE}" = "install" ]]; then
  printf '\nWriting success\n'
  touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rbenv"
fi

if [[ "${RBENV_MODE}" = "setup" ]]; then
  export RBENV_VERSION=$(global-stack-rbenv-find-latest.sh "${RUBY_VERSION}")

  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.${RUBY_VERSION_AS:-${RUBY_VERSION:-}}" || "true" = "${GLOBAL_STACK_RELOAD_RUBY}" ]]; then
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" && rbenv install --verbose --skip-existing --keep "${RBENV_VERSION}"
    source /usr/local/bin/global-stack-base-setup-packages.sh
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc"
    eval "$(rbenv init - --no-rehash ${GLOBAL_STACK_SHELL})"
    global_stack_base_setup_packages \
      --prefix='RUBY' \
      --command='echo -e "**** Installing/Updating ${PACKAGE_NAME} ${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}"' \
      --command='gem --backtrace --debug install ${PACKAGE_NAME}:${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}'

    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" && eval "$(rbenv init - --no-rehash ${GLOBAL_STACK_SHELL})" && global-stack-rbenv-ruby${RUBY_VERSION_AS}-setup-version.sh
  fi

  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.${RUBY_VERSION_AS:-${RUBY_VERSION:-}}" || "true" = "${GLOBAL_STACK_RELOAD_RUBY}" ]]; then
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" && eval "$(rbenv init - --no-rehash ${GLOBAL_STACK_SHELL})" && rbenv shell && rbenv local "${RBENV_VERSION}" && global-stack-rbenv-ruby${RUBY_VERSION_AS}-setup-version.sh
  fi

  if [[ "" != "${RBENV_VERSION}" ]]; then
    printf '\nWriting version\n'
    echo "${RBENV_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.${RUBY_VERSION_AS:-${RUBY_VERSION:-}}"
    export RBENV_VERSION=$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.${RUBY_VERSION_AS:-${RUBY_VERSION:-}}")
  fi

  echo "export RBENV_VERSION=${RBENV_VERSION}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
  printf '%s\n' "rbenv local ${RBENV_VERSION}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

  printf '\nWriting success\n'
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/ruby.${RUBY_VERSION_AS:-${RUBY_VERSION:-}}"
  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    printf '\nReleasing rbenv lock\n'
    flock -u 200
    exec 200>&-
  fi
fi

echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION="${SECONDS}"
global-stack-base-print-success.sh "${DURATION}" "rbenv (${RUBY_VERSION:-})"

sleep infinity
