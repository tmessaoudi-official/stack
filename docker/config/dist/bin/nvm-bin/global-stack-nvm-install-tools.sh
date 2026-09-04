#!/bin/bash

set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

echo -e "\nInstalling tools"
DENO_JS="${DENO_INSTALL}/bin/deno"
# Content-compare gate (row 16). This block used to ask only whether the binary
# existed, so a GLOBAL_STACK_DENO_VERSION bump did nothing and no marker was kept.
# The `-f` check is retained as a FLOOR: a marker can outlive its artifact (a
# hand-cleaned tools/ tree), and `make down` clears successes/ but not versions/.
_deno_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm.deno" "${GLOBAL_STACK_DENO_VERSION}" "nvm.deno")"
if [ "${_deno_gate}" = "skip" ] && [ -f "${DENO_JS}" ]; then
    echo "**** ${DENO_JS} already installed (${GLOBAL_STACK_DENO_VERSION})."
else
    if [ "${_deno_gate}" = "reinstall" ]; then
        rm -rf "${DENO_JS}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm.deno"
    fi
    echo "**** Installing ${DENO_JS}"
    curl --connect-timeout 30 --max-time 300 -fsSL -o deno-insall.sh "https://deno.land/x/install/install.sh"
    chmod a+x ./deno-insall.sh
    ./deno-insall.sh ${GLOBAL_STACK_DENO_VERSION}
    rm -rf ./deno-insall.sh
    # Marker last: under `set -e` any failure above aborts before this line, so a
    # failed download can never leave a satisfied marker behind.
    printf '%s\n' "${GLOBAL_STACK_DENO_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm.deno"
fi
# deno upgrade

# if [ ! -f "${DENO_INSTALL_ROOT}/bin/aleph" ]; then
#   deno install --global --allow-import --allow-read --allow-write --allow-net --force --name aleph https://deno.land/x/aleph@${GLOBAL_STACK_DENO_ALEPH_VERSION}/init.ts
# fi

# if [ ! -f "${DENO_INSTALL_ROOT}/bin/mandarine" ]; then
#   deno install --global --allow-import --allow-read --allow-write --allow-run --force --name mandarine https://deno.land/x/mandarinets@${GLOBAL_STACK_DENO_MANDARINETS_VERSION}/cli.ts
# fi

BUN_JS="${BUN_INSTALL}/bin/bun"
# Same gate as deno above; same floor for the marker-outlives-artifact case.
_bun_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm.bun" "${GLOBAL_STACK_BUN_VERSION}" "nvm.bun")"
if [ "${_bun_gate}" = "skip" ] && [ -f "${BUN_JS}" ]; then
    echo "**** ${BUN_JS} already installed (${GLOBAL_STACK_BUN_VERSION})."
else
    if [ "${_bun_gate}" = "reinstall" ]; then
        rm -rf "${BUN_JS}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm.bun"
    fi
    echo "**** Installing ${BUN_JS}"
    curl --connect-timeout 30 --max-time 300 -fsSL https://bun.sh/install | bash -s ${GLOBAL_STACK_BUN_VERSION}
    printf '%s\n' "${GLOBAL_STACK_BUN_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm.bun"
fi
