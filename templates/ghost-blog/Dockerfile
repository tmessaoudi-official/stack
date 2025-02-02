# shellcheck disable=SC2148
ARG GLOBAL_STACK_VERSION=1_5_0_local
ARG GLOBAL_STACK_LOCALSTACK_LOCALSTACK_VERSION=5.108.2

# shellcheck disable=SC2086
ARG GLOBAL_STACK_LOCAL_REGISTRY_PORT_5000=5000
# shellcheck disable=SC2086
ARG GLOBAL_STACK_LOCAL_REGISTRY_ALIAS=local-global-stack-registry.local
# shellcheck disable=SC2086
FROM ${GLOBAL_STACK_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_LOCAL_REGISTRY_PORT_5000}/local_global_stack_00base:${GLOBAL_STACK_VERSION} AS local_global_stack_base
FROM ghost:${GLOBAL_STACK_IMAGE_GHOST_BLOG_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>"

LABEL info="local_global_stack"

USER root

SHELL ["/bin/bash", "-xeE", "-o", "pipefail", "-c"]

# @todo fix pin versions
# hadolint ignore=DL3008,DL3018
RUN shopt -s extdebug \
    && IFS=$'\n\t' \
    && apt-get update \
    && apt-get install -y --no-install-recommends --fix-missing \
    libnss3-tools \
    sudo \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

COPY --from=local_global_stack_base \
    /usr/local/bin/mkcert \
    /usr/local/bin/

COPY \
    docker/images/00base/conf/bin/ \
    docker/config/dist/bin/base-bin/ \
    docker/config/dist/bin/ghost-blog-bin/ \
    /usr/local/bin/

RUN find /usr/local/bin/ -type f -exec chmod a+x {} \;

EXPOSE 2368

USER node

CMD ["global-stack-ghost-blog-start.sh"]