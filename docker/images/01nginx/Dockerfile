# shellcheck disable=SC2148
ARG GLOBAL_STACK_VERSION=2_0_0_local

# shellcheck disable=SC2086
ARG GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000=5000
# shellcheck disable=SC2086
ARG GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS=local-global-stack-registry.local
# shellcheck disable=SC2086
FROM ${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}/local_global_stack_00base:${GLOBAL_STACK_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>"

LABEL info="local_global_stack"

USER root

SHELL ["/bin/bash", "-xeEu", "-o", "pipefail", "-c"]

ARG GLOBAL_STACK_AUTOMAKE_VERSION
ARG GLOBAL_STACK_AUTOMAKE_MIRROR

ENV GLOBAL_STACK_AUTOMAKE_VERSION="${GLOBAL_STACK_AUTOMAKE_VERSION}" \
    GLOBAL_STACK_AUTOMAKE_MIRROR="${GLOBAL_STACK_AUTOMAKE_MIRROR}" \
    PATH="/opt/automake-${GLOBAL_STACK_AUTOMAKE_VERSION}/bin:${PATH}"

# @todo check-updates conf files

# @todo fix pin versions
# hadolint ignore=DL3008,DL3018
RUN shopt -s extdebug \
    && [ "${GLOBAL_STACK_AUTOMAKE_VERSION}" != "" ] && [ "${GLOBAL_STACK_AUTOMAKE_MIRROR}" != "" ] && (wget ${GLOBAL_STACK_AUTOMAKE_MIRROR}/automake-${GLOBAL_STACK_AUTOMAKE_VERSION}.tar.gz && tar -xf automake-${GLOBAL_STACK_AUTOMAKE_VERSION}.tar.gz && cd automake-${GLOBAL_STACK_AUTOMAKE_VERSION} && ./configure --prefix=/opt/automake-${GLOBAL_STACK_AUTOMAKE_VERSION} && make -j$(nproc) && make install && rm -rf automake-${GLOBAL_STACK_AUTOMAKE_VERSION}) || echo -e "\n automake will not be installed" \
    && IFS=$'\n\t' \
    && apt-get -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change \
    && apt-get --allow-unauthenticated install -y --no-install-recommends --fix-missing \
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
    # liboauth2-0 \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

EXPOSE 8080 8443

USER "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}"

CMD ["global-stack-base-sync-bin-n-exec.sh", "global-stack-nginx-start.sh"]
