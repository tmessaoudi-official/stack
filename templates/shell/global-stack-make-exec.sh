#!/bin/bash

# set -eEu -o pipefail
# shopt -s extdebug
# IFS=$'\n\t'
# trap 'wickStrictModeFail $?' ERR

make --directory="${GLOBAL_STACK_DOCKER_ROOT_PATH}" --file="${GLOBAL_STACK_DOCKER_ROOT_PATH}"/Makefile "${GLOBAL_STACK_MAKE_EXEC}" --silent --ignore-errors --keep-going --warn-undefined-variables
