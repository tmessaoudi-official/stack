# shellcheck disable=SC2148
ARG GLOBAL_STACK_VERSION=2_0_0_local

# shellcheck disable=SC2086
ARG GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000=5000
# shellcheck disable=SC2086
ARG GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS=local-global-stack-registry.local
# shellcheck disable=SC2086
FROM ${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}/local_global_stack_00base:${GLOBAL_STACK_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>" \
      info="local_global_stack"

USER root

SHELL ["/bin/bash", "-xeEu", "-o", "pipefail", "-c"]

# @todo check-updates conf files

# NOTE: This package list is shared with 01httpd, 01nginx, and 01caddy.
# If you add, remove, or update a package here, do the same in the other two.
# @todo fix pin versions
RUN shopt -s extdebug \
    && IFS=$'\n\t' \
    && apt-get update --allow-releaseinfo-change \
    && apt-get install -y --no-install-recommends --fix-missing \
    subversion \
    libnghttp2-dev \
    libcurl4-gnutls-dev \
    libtool-bin \
    libnghttp2-14 \
    python-is-python3 \
    libexpat1-dev \
    libapr1-dev \
    libaprutil1-dev \
    zlib1g \
    libunwind-dev \
    libxslt-dev \
    libgd-dev \
    libgeoip-dev \
    libmaxminddb-dev \
    libtool \
    uuid-dev \
    libperl-dev \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

EXPOSE 8080 8443

USER "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}"

CMD ["global-stack-base-sync-bin-n-exec.sh", "global-stack-httpd-start.sh"]