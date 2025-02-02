#!/bin/bash

SECONDS=0

sleep 1

global-stack-base-wait-for.sh \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

# you need to install it manually inside the container !! #bug
global-stack-base-init-mkcert.sh
node current/index.js

sleep infinity