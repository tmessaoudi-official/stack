#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
stackCatch() {
  if [[ "${1}" != "0" ]]; then
    # error handling goes here
    echo "Error detected !!"
    printf "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: %s ** ** message: %s ** nvm (%s) %s global-stack-nvm-start.sh\n" "${2}" "${3}" "${_node_version_label}" "${NVM_MODE:-}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP

_node_version_label="${NODE_VERSION_AS:-${NODE_VERSION:-}}"

SECONDS=0

PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/yarn/bin:${DENO_DIR}/bin:${BUN_INSTALL}/bin:${PNPM_HOME}:${PATH}"
export PATH

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${GLOBAL_STACK_DOCKER_TOOLS_PATH}/yarn/bin:${DENO_DIR}/bin:${BUN_INSTALL}/bin:${PNPM_HOME}:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

if [[ "${NVM_MODE}" = "install" ]]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/nvm"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

  if [[ "${GLOBAL_STACK_RELOAD_NVM}" = "true" ]]; then
    printf '\nReloading node ...\n'
    rm -rf "${NVM_DIR}" "${DENO_INSTALL}/bin" "${BUN_INSTALL}/bin" "${YARN_OFFLINE_MIRROR}" "${YARN_CACHE_FOLDER}" "${YARN_GLOBAL_FOLDER}" "${GLOBAL_STACK_PNPM_GLOBAL_DIR}" "${PNPM_HOME}" "${GLOBAL_STACK_PNPM_STORE_DIR}" "${NPM_CACHE_DIR}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/node"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/nvm" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/nvm.installer.sh"
    mkdir -p "${NVM_DIR}" "${DENO_INSTALL}/bin" "${BUN_INSTALL}/bin" "${YARN_OFFLINE_MIRROR}" "${YARN_CACHE_FOLDER}" "${YARN_GLOBAL_FOLDER}/bin" "${GLOBAL_STACK_PNPM_GLOBAL_DIR}" "${PNPM_HOME}" "${GLOBAL_STACK_PNPM_STORE_DIR}" "${NPM_CACHE_DIR}"
  fi
fi

if [[ "${NVM_MODE}" = "setup" ]]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/node.${_node_version_label}"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/nvm"

  if [[ "${GLOBAL_STACK_RELOAD_NODE:-false}" = "true" ]]; then
    printf '\nReloading node %s ...\n' "${_node_version_label}"
    rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/node.${_node_version_label}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.${_node_version_label}"
  fi

  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    printf '\nAcquiring nvm lock ...\n'
    exec 200>"${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/nvm.flock"
    flock 200
    printf 'Lock acquired\n'
  fi
fi

printf '\n******** Starting nvm %s %s ********\n' "${NVM_MODE}" "${_node_version_label}"

global-stack-nvm-eval-yarnrc.sh

mkdir -p "${NVM_DIR}" "${DENO_INSTALL}/bin" "${BUN_INSTALL}/bin" "${YARN_OFFLINE_MIRROR}" "${YARN_CACHE_FOLDER}" "${YARN_GLOBAL_FOLDER}/bin" "${GLOBAL_STACK_PNPM_GLOBAL_DIR}" "${PNPM_HOME}" "${GLOBAL_STACK_PNPM_STORE_DIR}" "${NPM_CACHE_DIR}"

# ----------------------------------
if [[ "${NVM_MODE}" = "install" ]]; then
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm" ]] || \
     [[ "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm" 2>/dev/null)" != "${GLOBAL_STACK_NVM_VERSION}" ]] || \
     [[ "${GLOBAL_STACK_RELOAD_NVM}" = "true" ]]; then
    global-stack-nvm-iou.sh
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/nvm.installer.sh
    echo "${GLOBAL_STACK_NVM_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm"
  fi
fi

printf '\nLoading nvm bash\n'
[ -s "${NVM_DIR}/nvm.sh" ] && \. "${NVM_DIR}/nvm.sh"         # This loads nvm
[ -s "${NVM_DIR}/bash_completion" ] && \. "${NVM_DIR}/bash_completion"  # This loads nvm bash_completion

printf '\nAdding nvm bash to .shellrc\n'
echo "[ -s \"${NVM_DIR}/nvm.sh\" ] && \. \"${NVM_DIR}/nvm.sh\"" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"  # This loads nvm
echo "[ -s \"${NVM_DIR}/bash_completion\" ] && \. \"${NVM_DIR}/bash_completion\"" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"  # This loads nvm bash_completion

if [[ "${NVM_MODE}" = "setup" ]]; then
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.${_node_version_label}" ]]; then
    printf '\nInstalling node version %s\n' "${_node_version_label}"
    nvm install "${NODE_VERSION:-}"
  fi

  echo "nvm use ${NODE_VERSION:-}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
  printf '\nUsing node %s\n' "${NODE_VERSION:-}"
  nvm use "${NODE_VERSION:-}"

  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.${_node_version_label}" ]]; then
    printf '\nSetting up node %s\n' "${NODE_VERSION:-}"

    source /usr/local/bin/global-stack-base-setup-packages.sh
    global_stack_base_setup_packages \
      --prefix='NODE' \
      --command='echo -e "**** Installing/Updating ${PACKAGE_NAME} ${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}"' \
      --command='echo "y" | npm add --global --force ${PACKAGE_NAME}@${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}'

    global-stack-nvm-node${NODE_VERSION_AS}-setup.sh
    if [[ -n "${GLOBAL_STACK_NODE_UPGRADE}" ]] && [[ "${GLOBAL_STACK_NODE_UPGRADE}" = "true" ]]; then
      npm --global upgrade --force
    fi
    global-stack-nvm-node${NODE_VERSION_AS}-setup-overrides.sh
  fi
fi

if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/nvm" ]]; then
  if [[ "${NVM_MODE}" = "install" ]]; then
    global-stack-nvm-install-tools.sh
  fi
fi

if [[ "${NVM_MODE}" = "setup" ]]; then
  printf '\nSetting project for node %s\n' "${NODE_VERSION:-}"
  global-stack-nvm-node${NODE_VERSION_AS}-setup-project.sh
fi

if [[ "${NVM_MODE}" = "install" ]]; then
  printf '\nWriting /.shellrc/.nvm.shellrc\n'
  echo "export NVM_DIR=${NVM_DIR}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc"
  echo "export DENO_INSTALL=${DENO_INSTALL}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc"
  echo "export DENO_INSTALL_ROOT=${DENO_INSTALL_ROOT}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc"
  echo "export DENO_DIR=${DENO_DIR}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc"
  echo "export YARN_OFFLINE_MIRROR=${YARN_OFFLINE_MIRROR}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc"
  echo "export YARN_CACHE_FOLDER=${YARN_CACHE_FOLDER}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc"
  echo "export YARN_GLOBAL_FOLDER=${YARN_GLOBAL_FOLDER}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc"
  echo "export GLOBAL_STACK_PNPM_GLOBAL_DIR=${GLOBAL_STACK_PNPM_GLOBAL_DIR}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc"
  echo "export PNPM_HOME=${PNPM_HOME}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc"
  echo "export GLOBAL_STACK_PNPM_STORE_DIR=${GLOBAL_STACK_PNPM_STORE_DIR}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc"
  echo "export CYPRESS_CACHE_FOLDER=${CYPRESS_CACHE_FOLDER}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc"
  echo "export NPM_CACHE_DIR=${NPM_CACHE_DIR}" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc"
fi
# ----------------------------------

global-stack-base-init-mkcert.sh
global-stack-base-prepare-shell.sh
echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION="${SECONDS}"
global-stack-base-print-success.sh "${DURATION}" "nvm (${NODE_VERSION:-})"

if [[ "${NVM_MODE}" = "install" ]]; then
  printf '\nWriting success\n'
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/nvm"
fi

if [[ "${NVM_MODE}" = "setup" ]]; then
  printf '\nWriting version\n'
  echo "$(nvm version "${NODE_VERSION:-}")" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.${_node_version_label}"
  printf '\nWriting success\n'
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/node.${_node_version_label}"
  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    printf '\nReleasing nvm lock\n'
    flock -u 200
    exec 200>&-
  fi
fi

if [[ "${NVM_MODE:-}" = "install" ]] && [[ "${GLOBAL_STACK_RELOAD_NVM:-false}" = "true" ]]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_NVM is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi
if [[ "${NVM_MODE:-}" = "setup" ]] && [[ "${GLOBAL_STACK_RELOAD_NODE:-false}" = "true" ]]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_NODE is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi

sleep infinity
