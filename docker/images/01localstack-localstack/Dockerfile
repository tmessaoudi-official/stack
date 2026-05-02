# shellcheck disable=SC2148
ARG GLOBAL_STACK_VERSION=2_0_0_local
ARG GLOBAL_STACK_LOCALSTACK_LOCALSTACK_VERSION=4.14.0

# shellcheck disable=SC2086
ARG GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000=5000
# shellcheck disable=SC2086
ARG GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS=local-global-stack-registry.local
# shellcheck disable=SC2086
FROM ${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}/local_global_stack_00base:${GLOBAL_STACK_VERSION} AS local_global_stack_base
FROM localstack/localstack:${GLOBAL_STACK_LOCALSTACK_LOCALSTACK_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>" \
      info="local_global_stack"

USER root

# @todo fix pin versions
RUN apt-get update --allow-releaseinfo-change \
    && apt-get install -y --no-install-recommends --fix-missing \
    libnss3-tools \
    sudo \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /etc/apt/apt.conf.d/docker-clean

COPY --from=local_global_stack_base \
    /usr/local/bin/mkcert \
    /usr/local/bin/

COPY \
    docker/images/00base/conf/bin/ \
    docker/config/dist/bin/base-bin/ \
    docker/config/dist/bin/localstack-bin/ \
    /usr/local/bin/

RUN find /usr/local/bin/ -type f -exec chmod a+x {} \;

USER localstack

ENTRYPOINT ["global-stack-localstack-start.sh"]