#!/bin/bash

sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base" "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"

set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** global-stack-base-start.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR

SECONDS=0

global-stack-base-reload-all.sh
global-stack-base-create-directories.sh
global-stack-base-set-permissions.sh

if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/mkcert" ]]; then
  sudo cp /usr/local/bin/mkcert "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/mkcert
fi

if [[ "$(mkcert --version)" != "${GLOBAL_STACK_MKCERT_VERSION}" ]]; then
  sudo cp /usr/local/bin/mkcert "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/mkcert
fi

sudo chown "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/mkcert
sudo chmod a+x "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/mkcert

global-stack-base-sync-mkcert.sh
global-stack-base-init-mkcert.sh
global-stack-base-reinstall-mkcert.sh

global-stack-base-install-go.sh
global-stack-base-install-zig.sh
global-stack-base-install-awscli.sh
global-stack-base-install-hurl.sh

# GLOBAL_STACK_RELOAD_PERMISSIONS=true global-stack-base-set-permissions.sh

global-stack-base-install-mise.sh

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

global-stack-base-prepare-shell.sh

echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

[ "${GLOBAL_STACK_DOCKER_IN_DOCKER}" = "true" ] && global-stack-base-start-docker.sh || echo -e "\n Docker In Docker will not be started"

: > "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/permissions"
echo -e "${GLOBAL_STACK_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/version"

DURATION="${SECONDS}"
global-stack-base-print-success.sh "${DURATION}" "base" "create"

: > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

if [[ "${GLOBAL_STACK_RELOAD_ALL:-false}" = "true" ]]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_ALL is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi

sleep infinity