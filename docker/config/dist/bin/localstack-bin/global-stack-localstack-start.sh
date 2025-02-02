#!/bin/bash

SECONDS=0

sleep 1

global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base" \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/web-server"

global-stack-base-init-mkcert.sh

if [[ ! -d /docker-entrypoint-initaws.d ]]; then
    sudo mkdir -p /docker-entrypoint-initaws.d
fi
if [[ ! -d /etc/localstack/init ]]; then
    sudo mkdir -p /etc/localstack/init
fi

sudo rsync -raz --ignore-times \
  ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/localstack-init/initaws.d/ \
  /docker-entrypoint-initaws.d

sudo rsync -raz --ignore-times \
  ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/localstack-init/init/ \
  /etc/localstack/init

# touch /tmp/localstack/server.test.pem
# cat ${CAROOT}/rootCA-key.pem > /tmp/localstack/server.test.pem
# cat ${CAROOT}/rootCA.pem >> /tmp/localstack/server.test.pem

# mkdir -p /var/lib/localstack/custom/
# touch /var/lib/localstack/custom/server.test.pem
# cp /tmp/localstack/server.test.pem /var/lib/localstack/custom/server.test.pem
# cp ${CAROOT}/rootCA.pem /var/lib/localstack/custom/server.test.pem.crt
# cp ${CAROOT}/rootCA-key.pem /var/lib/localstack/custom/server.test.pem.key
# cp /tmp/localstack/server.test.pem /var/lib/localstack/cache/server.test.pem
# cp ${CAROOT}/rootCA.pem /var/lib/localstack/cache/server.test.pem.crt
# cp ${CAROOT}/rootCA-key.pem /var/lib/localstack/cache/server.test.pem.key

/usr/local/bin/docker-entrypoint.sh