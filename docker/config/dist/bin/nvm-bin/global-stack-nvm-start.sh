#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** nvm ($([[ -n "${NODE_VERSION_AS:-}" && "" != "${NODE_VERSION_AS:-}" ]] && echo "${NODE_VERSION_AS:-}" || echo "${NODE_VERSION:-}")) ${NVM_MODE:-} global-stack-nvm-start.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

SECONDS=0

PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/yarn/bin:${DENO_DIR}/bin:${BUN_INSTALL}/bin:${PNPM_HOME}:${PATH}"
export PATH

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${GLOBAL_STACK_DOCKER_TOOLS_PATH}/yarn/bin:${DENO_DIR}/bin:${BUN_INSTALL}/bin:${PNPM_HOME}:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

if [ "${NVM_MODE}" = "install" ]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/nvm"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"
  
  if [ "${GLOBAL_STACK_RELOAD_NVM}" = "true" ]; then
    echo -e "\nReloading node ..."
    rm -rf "${NVM_DIR}" "${DENO_INSTALL}/bin"  "${BUN_INSTALL}/bin" "${YARN_OFFLINE_MIRROR}" "${YARN_CACHE_FOLDER}" "${YARN_GLOBAL_FOLDER}" "${GLOBAL_STACK_PNPM_GLOBAL_DIR}" "${PNPM_HOME}" "${GLOBAL_STACK_PNPM_STORE_DIR}" "${NPM_CACHE_DIR}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/node"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/nvm" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/nvm.installer.sh"
    mkdir -p "${NVM_DIR}" "${DENO_INSTALL}/bin" "${BUN_INSTALL}/bin" "${YARN_OFFLINE_MIRROR}" "${YARN_CACHE_FOLDER}" "${YARN_GLOBAL_FOLDER}/bin" "${GLOBAL_STACK_PNPM_GLOBAL_DIR}" "${PNPM_HOME}" "${GLOBAL_STACK_PNPM_STORE_DIR}" "${NPM_CACHE_DIR}"
  fi
fi

if [ "${NVM_MODE}" = "setup" ]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/node.$([[ -n "${NODE_VERSION_AS:-}" && "" != "${NODE_VERSION_AS:-}" ]] && echo "${NODE_VERSION_AS:-}" || echo "${NODE_VERSION:-}")"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/nvm"

  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/node" && "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    echo "$([[ -n "${NODE_VERSION_AS:-}" && "" != "${NODE_VERSION_AS:-}" ]] && echo "${NODE_VERSION_AS:-}" || echo "${NODE_VERSION:-}")" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/node"
  fi

  if [[ "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/node")" != "$([[ -n "${NODE_VERSION_AS:-}" && "" != "${NODE_VERSION_AS:-}" ]] && echo "${NODE_VERSION_AS:-}" || echo "${NODE_VERSION:-}")" && "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    NODE_SHOW_WAITING=""
    NODE_WAITING_FOR=""
    while [ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/node" ]
    do
      [[ "${NODE_SHOW_WAITING}" != "false" || "${NODE_WAITING_FOR}" != "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/node")" ]] && echo -e "\nWaiting for node $(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/node") ..."
      NODE_SHOW_WAITING="false"
      NODE_WAITING_FOR="$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/node")"
      sleep "$(shuf -i 3-6 -n 1)"
    done
    echo "$([[ -n "${NODE_VERSION_AS:-}" && "" != "${NODE_VERSION_AS:-}" ]] && echo "${NODE_VERSION_AS:-}" || echo "${NODE_VERSION:-}")" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/node"
  fi
fi

echo -e "\n******** Starting nvm ${NVM_MODE} $([[ -n "${NODE_VERSION_AS:-}" && "" != "${NODE_VERSION_AS:-}" ]] && echo "${NODE_VERSION_AS:-}" || echo "${NODE_VERSION:-}") ********"

global-stack-nvm-eval-yarnrc.sh

mkdir -p "${NVM_DIR}" "${DENO_INSTALL}/bin" "${BUN_INSTALL}/bin" "${YARN_OFFLINE_MIRROR}" "${YARN_CACHE_FOLDER}" "${YARN_GLOBAL_FOLDER}/bin" "${GLOBAL_STACK_PNPM_GLOBAL_DIR}" "${PNPM_HOME}" "${GLOBAL_STACK_PNPM_STORE_DIR}" "${NPM_CACHE_DIR}"

# ----------------------------------
if [ "${NVM_MODE}" = "install" ]; then
  if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm" ] || [ "${GLOBAL_STACK_RELOAD_NVM}" = "true" ]; then
    global-stack-nvm-iou.sh
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/nvm.installer.sh
  fi
fi

echo -e "\nLoading nvm bash"
[ -s "${NVM_DIR}/nvm.sh" ] && \. "${NVM_DIR}/nvm.sh"  # This loads nvm
[ -s "${NVM_DIR}/bash_completion" ] && \. "${NVM_DIR}/bash_completion"  # This loads nvm bash_completion

echo -e "\nAdding nvm bash to .shellrc"
echo "[ -s \"${NVM_DIR}/nvm.sh\" ] && \. \"${NVM_DIR}/nvm.sh\"" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"  # This loads nvm
echo "[ -s \"${NVM_DIR}/bash_completion\" ] && \. \"${NVM_DIR}/bash_completion\"" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"  # This loads nvm bash_completion

if [ "${NVM_MODE}" = "setup" ]; then
  if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.$([[ -n "${NODE_VERSION_AS:-}" && "" != "${NODE_VERSION_AS:-}" ]] && echo "${NODE_VERSION_AS:-}" || echo "${NODE_VERSION:-}")" ]; then
    echo -e "\nInstalling node version $([[ -n "${NODE_VERSION_AS:-}" && "" != "${NODE_VERSION_AS:-}" ]] && echo "${NODE_VERSION_AS:-}" || echo "${NODE_VERSION:-}")"
    nvm install "${NODE_VERSION:-}"
  fi
  
  echo "nvm use ${NODE_VERSION:-}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
  echo -e "\nUsing node ${NODE_VERSION:-}"
  nvm use "${NODE_VERSION:-}"

  if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.$([[ -n "${NODE_VERSION_AS:-}" && "" != "${NODE_VERSION_AS:-}" ]] && echo "${NODE_VERSION_AS:-}" || echo "${NODE_VERSION:-}")" ]; then
    echo -e "\nSetting up node ${NODE_VERSION:-}"
    
    source /usr/local/bin/global-stack-base-setup-packages.sh
    global_stack_base_setup_packages \
      --prefix='NODE' \
      --command='echo -e "**** Installing/Updating ${PACKAGE_NAME} ${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}"' \
      --command='echo "y" | npm add --global --force ${PACKAGE_NAME}@${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}'
    
    global-stack-nvm-node${NODE_VERSION_AS}-setup.sh
    if [ -n "${GLOBAL_STACK_NODE_UPGRADE}" ] && [ "${GLOBAL_STACK_NODE_UPGRADE}" = "true" ]; then
      npm --global upgrade --force
    fi
    global-stack-nvm-node${NODE_VERSION_AS}-setup-overrides.sh
  fi
fi

if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/nvm" ]; then
  if [ "${NVM_MODE}" = "install" ]; then
    global-stack-nvm-install-tools.sh
  fi
fi

if [ "${NVM_MODE}" = "setup" ]; then
  echo -e "\nSetting project for node ${NODE_VERSION:-}"
  global-stack-nvm-node${NODE_VERSION_AS}-setup-project.sh
fi

if [ "${NVM_MODE}" = "install" ]; then
  echo -e "\nWriting /.shellrc/.nvm.shellrc"
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

if [ "${NVM_MODE}" = "install" ]; then
  echo -e "\nWriting success"
  touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/nvm"
fi

if [ "${NVM_MODE}" = "setup" ]; then
  echo -e "\nWriting version"
  echo "$(nvm version "${NODE_VERSION:-}")" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.$([[ -n "${NODE_VERSION_AS:-}" && "" != "${NODE_VERSION_AS:-}" ]] && echo "${NODE_VERSION_AS:-}" || echo "${NODE_VERSION:-}")"
  echo -e "\nWriting success"
  touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/node.$([[ -n "${NODE_VERSION_AS:-}" && "" != "${NODE_VERSION_AS:-}" ]] && echo "${NODE_VERSION_AS:-}" || echo "${NODE_VERSION:-}")"
  echo -e "\nRemoving lock"
  rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/node"
fi

global-stack-base-init-mkcert.sh

DURATION="${SECONDS}"
global-stack-base-print-success.sh "${DURATION}" "nvm (${NODE_VERSION:-})"

global-stack-base-prepare-shell.sh

echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

sleep infinity
