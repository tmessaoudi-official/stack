#!/bin/bash
set -euo pipefail

rsync -raz "${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/caroot/" "${CAROOT}"