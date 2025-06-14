#!/bin/bash

set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** nvm ($([[ -n "${NODE_VERSION_AS:-}" && "" != "${NODE_VERSION_AS:-}" ]] && echo "${NODE_VERSION_AS:-}" || echo "${NODE_VERSION:-}")) ${NVM_MODE:-} global-stack-nvm-install-tools.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

echo -e "\nInstalling tools"
DENO_JS="${DENO_INSTALL}/bin/deno"
if [ -f "${DENO_JS}" ]; then
    echo "**** ${DENO_JS} already installed."
else
    echo "**** Installing ${DENO_JS}"
    wget https://deno.land/x/install/install.sh -O deno-insall.sh
    chmod a+x ./deno-insall.sh
    ./deno-insall.sh ${GLOBAL_STACK_DENO_VERSION}
    rm -rf ./deno-insall.sh
fi
# deno upgrade

if [ ! -f "${DENO_INSTALL_ROOT}/bin/aleph" ]; then
  deno install --global --allow-import --allow-read --allow-write --allow-net --force --name aleph https://deno.land/x/aleph@${GLOBAL_STACK_DENO_ALEPH_VERSION}/init.ts
fi

if [ ! -f "${DENO_INSTALL_ROOT}/bin/mandarine" ]; then
  deno install --global --allow-import --allow-read --allow-write --allow-run --force --name mandarine https://deno.land/x/mandarinets@${GLOBAL_STACK_DENO_MANDARINETS_VERSION}/cli.ts
fi

BUN_JS="${BUN_INSTALL}/bin/bun"
if [ -f "${BUN_JS}" ]; then
    echo "**** ${BUN_JS} already installed."
else
    echo "**** Installing ${BUN_JS}"
    curl -fsSL https://bun.sh/install | bash -s ${GLOBAL_STACK_BUN_VERSION}
fi
