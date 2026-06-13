#!/bin/bash

set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

echo -e "\nInstalling tools"
DENO_JS="${DENO_INSTALL}/bin/deno"
if [ -f "${DENO_JS}" ]; then
    echo "**** ${DENO_JS} already installed."
else
    echo "**** Installing ${DENO_JS}"
    curl --connect-timeout 30 --max-time 300 -fsSL -o deno-insall.sh "https://deno.land/x/install/install.sh"
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
    curl --connect-timeout 30 --max-time 300 -fsSL https://bun.sh/install | bash -s ${GLOBAL_STACK_BUN_VERSION}
fi
