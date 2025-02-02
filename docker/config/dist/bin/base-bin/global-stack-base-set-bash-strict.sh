#!/bin/bash

if [ "${1}" != "0" ]; then
  # error handling goes here
  echo "Error detected !!"
  echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - global-stack-base-set-bash-strict.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
  sleep infinity
fi