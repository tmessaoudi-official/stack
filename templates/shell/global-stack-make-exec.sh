#!/bin/bash

# set -eEu -o pipefail
# shopt -s extdebug
# IFS=$'\n\t'
# trap 'wickStrictModeFail $?' ERR

# No --ignore-errors / --keep-going (removed 2026-11-07): with them every failing
# recipe line was ignored and this wrapper exited 0, so `make build`'s FATAL
# "local registry not running" gate printed and the run carried on into
# `up-build-force-recreate`, failing later as buildkit's `connection refused`.
# The first failure now stops the run and its exit status is this script's.
# The inner docker-cli sub-makes keep their own flags. Tests:
# bin/tests/local-registry.test.sh §4-5.
make --directory="${GLOBAL_STACK_DOCKER_ROOT_PATH}" --file="${GLOBAL_STACK_DOCKER_ROOT_PATH}"/Makefile "${GLOBAL_STACK_MAKE_EXEC}" --silent --warn-undefined-variables
