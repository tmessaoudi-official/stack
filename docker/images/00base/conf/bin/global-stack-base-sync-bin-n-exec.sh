#!/bin/bash
set -euo pipefail

find "${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/bin/" -type f -exec sudo cp {} /usr/local/bin/ \;

find /usr/local/bin -type f -exec sudo chmod a+x {} \;

global-stack-base-chown-home.sh

${1}