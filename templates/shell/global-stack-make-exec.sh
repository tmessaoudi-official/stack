#!/bin/bash

# set -eEu -o pipefail
# shopt -s extdebug
# IFS=$'\n\t'
# trap 'wickStrictModeFail $?' ERR

if [ -f "${GLOBAL_STACK_DOCKER_ROOT_PATH}"/local.Makefile ]; then
	make --directory="${GLOBAL_STACK_DOCKER_ROOT_PATH}" --file="${GLOBAL_STACK_DOCKER_ROOT_PATH}"/local.Makefile "${GLOBAL_STACK_MAKE_EXEC}" --silent --ignore-errors --keep-going --warn-undefined-variables
else
	make --directory="${GLOBAL_STACK_DOCKER_ROOT_PATH}" --file="${GLOBAL_STACK_DOCKER_ROOT_PATH}"/Makefile "${GLOBAL_STACK_MAKE_EXEC}" --silent --ignore-errors --keep-going --warn-undefined-variables
fi
