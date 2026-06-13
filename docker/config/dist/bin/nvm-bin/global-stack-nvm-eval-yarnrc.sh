#!/bin/bash

set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

echo -e "\nPopulating yarnrc"
find "/home/${GLOBAL_STACK_DOCKER_USER_ID}/" -type f -exec sed -i "s|\${YARN_OFFLINE_MIRROR}|${YARN_OFFLINE_MIRROR}|g" {} \;
find "/home/${GLOBAL_STACK_DOCKER_USER_ID}/" -type f -exec sed -i "s|\${YARN_CACHE_FOLDER}|${YARN_CACHE_FOLDER}|g" {} \;
find "/home/${GLOBAL_STACK_DOCKER_USER_ID}/" -type f -exec sed -i "s|\${GLOBAL_STACK_DOCKER_TOOLS_PATH}|${GLOBAL_STACK_DOCKER_TOOLS_PATH}|g" {} \;
find "/home/${GLOBAL_STACK_DOCKER_USER_ID}/" -type f -exec sed -i "s|\${YARN_GLOBAL_FOLDER}|${YARN_GLOBAL_FOLDER}|g" {} \;
