# shellcheck disable=SC2148
ARG GLOBAL_STACK_VERSION=1_5_0_local

# shellcheck disable=SC2086
ARG GLOBAL_STACK_LOCAL_REGISTRY_PORT_5000=5000
# shellcheck disable=SC2086
ARG GLOBAL_STACK_LOCAL_REGISTRY_ALIAS=local-global-stack-registry.local
# shellcheck disable=SC2086
FROM ${GLOBAL_STACK_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_LOCAL_REGISTRY_PORT_5000}/local_global_stack_00base:${GLOBAL_STACK_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>"

LABEL info="local_global_stack"

USER root

SHELL ["/bin/bash", "-xeEu", "-o", "pipefail", "-c"]

# @todo check-updates conf files

# @todo fix pin versions
# hadolint ignore=DL3008,DL3018
RUN shopt -s extdebug \
    && IFS=$'\n\t' \
    && apt-get -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change \
    && apt-get --allow-unauthenticated install -y --no-install-recommends --fix-missing \
    subversion \
    libnghttp2-dev \
    libjansson-dev \
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
    libbrotli-dev \
    libtool \
    uuid-dev \
    libperl-dev \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

EXPOSE 8080 8443

USER "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}"

CMD ["global-stack-base-sync-bin-n-exec.sh", "global-stack-nginx-start.sh"]
