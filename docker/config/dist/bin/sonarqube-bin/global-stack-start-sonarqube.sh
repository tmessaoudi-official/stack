#!/bin/bash

SECONDS=0

sleep 1

global-stack-base-wait-for.sh \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

global-stack-base-init-mkcert.sh

exec /opt/sonarqube/docker/entrypoint.sh