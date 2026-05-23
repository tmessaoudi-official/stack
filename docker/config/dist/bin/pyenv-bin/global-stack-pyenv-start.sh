#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** pyenv ($([[ -n "${PYTHON_VERSION_AS:-}" && "" != "${PYTHON_VERSION_AS:-}" ]] && echo "${PYTHON_VERSION_AS:-}" || echo "${PYTHON_VERSION:-}")) ${PYENV_MODE:-} global-stack-pyenv-start.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

SECONDS=0

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

PATH="${RUSTUP_HOME}/bin:${RUSTUP_HOME}/toolchains/stable-x86_64-unknown-linux-gnu/bin:${CARGO_HOME}/bin:${PYENV_ROOT}/bin:${PATH}"
export PATH

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${RUSTUP_HOME}/bin:${RUSTUP_HOME}/toolchains/stable-x86_64-unknown-linux-gnu/bin:${CARGO_HOME}/bin:${PYENV_ROOT}/bin:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

sleep 1

if [ "${PYENV_MODE}" = "install" ]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/pyenv"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

  if [ "${GLOBAL_STACK_RELOAD_PYENV}" = "true" ]; then
    rm -rf "${PYENV_ROOT}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/python"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/pyenv" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/pyenv"
    mkdir -p "${PYENV_ROOT}"
  fi
fi

if [ "${PYENV_MODE}" = "setup" ]; then
  rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/python.$([[ -n "${PYTHON_VERSION_AS:-}" && "" != "${PYTHON_VERSION_AS:-}" ]] && echo "${PYTHON_VERSION_AS:-}" || echo "${PYTHON_VERSION:-}")"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1
  
  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/pyenv" \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rust"

  if [ "${GLOBAL_STACK_RELOAD_PYTHON:-false}" = "true" ]; then
    echo -e "\nReloading python $([[ -n "${PYTHON_VERSION_AS:-}" && "" != "${PYTHON_VERSION_AS:-}" ]] && echo "${PYTHON_VERSION_AS:-}" || echo "${PYTHON_VERSION:-}") ..."
    rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/python.$([[ -n "${PYTHON_VERSION_AS:-}" && "" != "${PYTHON_VERSION_AS:-}" ]] && echo "${PYTHON_VERSION_AS:-}" || echo "${PYTHON_VERSION:-}")" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python.$([[ -n "${PYTHON_VERSION_AS:-}" && "" != "${PYTHON_VERSION_AS:-}" ]] && echo "${PYTHON_VERSION_AS:-}" || echo "${PYTHON_VERSION:-}")"
  fi

  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    echo -e "\nAcquiring pyenv lock ..."
    exec 200>"${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/pyenv.flock"
    flock 200
    echo -e "Lock acquired"
  fi
fi

echo -e "\n******** Starting pyenv ${PYENV_MODE} ${PYTHON_VERSION:-} ********"

mkdir -p "${PYENV_ROOT}"

if [ "${PYENV_MODE}" = "install" ]; then
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/pyenv" || "true" = "${GLOBAL_STACK_RELOAD_PYENV}" ]]; then
    global-stack-pyenv-iou.sh
  fi
fi

if [ "${PYENV_MODE}" = "install" ]; then
  echo -e "\nWriting /shrllrc/pyenv.shellrc"
  echo "export PYENV_ROOT=${PYENV_ROOT}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/pyenv.shellrc"
fi

if [ "${PYENV_MODE}" = "setup" ]; then
  echo -e "source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/pyenv.shellrc" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
fi

echo -e 'eval "$(pyenv init -)"' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo -e 'eval "$(pyenv init --path)"' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo -e 'eval "$(pyenv init --path)"' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.profile"
source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

if [ "${PYENV_MODE}" = "install" ]; then
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/pyenv" || "true" = "${GLOBAL_STACK_RELOAD_PYENV}" ]]; then
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/pyenv.shellrc" && global-stack-pyenv-install-tools.sh
    echo "$(pyenv --version | sed 's/pyenv //')" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/pyenv"
  fi
fi

if [ "${PYENV_MODE}" = "setup" ]; then
  echo "export PYENV_VERSION=${PYENV_VERSION}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
  echo -e "pyenv local ${PYENV_VERSION}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
fi

global-stack-base-init-mkcert.sh
global-stack-base-prepare-shell.sh

if [ "${PYENV_MODE}" = "install" ]; then
  echo -e "\nWriting success"
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/pyenv"
fi

if [ "${PYENV_MODE}" = "setup" ]; then
  export PYENV_VERSION=""
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python.$([[ -n "${PYTHON_VERSION_AS:-}" && "" != "${PYTHON_VERSION_AS:-}" ]] && echo "${PYTHON_VERSION_AS:-}" || echo "${PYTHON_VERSION:-}")" || "true" = "${GLOBAL_STACK_RELOAD_PYENV}" ]]; then
    export PYENV_VERSION=$(global-stack-pyenv-find-latest.sh "${PYTHON_VERSION}")
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/pyenv.shellrc" && global-stack-pyenv-python${PYTHON_VERSION_AS}-install-version.sh
    
    source /usr/local/bin/global-stack-base-setup-packages.sh
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/pyenv.shellrc"
    eval "$(pyenv init -)"
    eval "$(pyenv init --path)"
    pyenv shell
    global_stack_base_setup_packages \
      --prefix='PYTHON' \
      --command='echo -e "**** Installing/Updating ${PACKAGE_NAME} ${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}"' \
      --command='pip install ${PACKAGE_NAME}==${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}'

    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/pyenv.shellrc" && eval "$(pyenv init -)" && eval "$(pyenv init --path)" && pyenv shell && global-stack-pyenv-python${PYTHON_VERSION_AS}-setup-version.sh
  fi
  if [ "" != "${PYENV_VERSION}" ]; then
    echo -e "\nWriting version"
    echo "${PYENV_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python.$([[ -n "${PYTHON_VERSION_AS:-}" && "" != "${PYTHON_VERSION_AS:-}" ]] && echo "${PYTHON_VERSION_AS:-}" || echo "${PYTHON_VERSION:-}")"
  fi
  if [ "" = "${PYENV_VERSION}" ]; then
    export PYENV_VERSION=$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python.$([[ -n "${PYTHON_VERSION_AS:-}" && "" != "${PYTHON_VERSION_AS:-}" ]] && echo "${PYTHON_VERSION_AS:-}" || echo "${PYTHON_VERSION:-}")")
  fi

  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python.$([[ -n "${PYTHON_VERSION_AS:-}" && "" != "${PYTHON_VERSION_AS:-}" ]] && echo "${PYTHON_VERSION_AS:-}" || echo "${PYTHON_VERSION:-}")" || "true" = "${GLOBAL_STACK_RELOAD_PYENV}" ]]; then
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/pyenv.shellrc" && eval "$(pyenv init -)" && pyenv shell && pyenv local "${PYENV_VERSION}" && global-stack-pyenv-python${PYTHON_VERSION_AS}-setup-version.sh
  fi
  
  echo -e "\nWriting success"
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/python.$([[ -n "${PYTHON_VERSION_AS:-}" && "" != "${PYTHON_VERSION_AS:-}" ]] && echo "${PYTHON_VERSION_AS:-}" || echo "${PYTHON_VERSION:-}")"
  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    echo -e "\nReleasing pyenv lock"
    flock -u 200
    exec 200>&-
  fi
fi

echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION="${SECONDS}"
global-stack-base-print-success.sh "${DURATION}" "pyenv (${PYTHON_VERSION:-})"

sleep infinity
