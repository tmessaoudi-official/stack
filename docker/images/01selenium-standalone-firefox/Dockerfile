# shellcheck disable=SC2148
ARG GLOBAL_STACK_VERSION=2_0_0_local
ARG GLOBAL_STACK_IMAGE_SELENIUM_STANDALONE_FIREFOX_VERSION=4.39.0-20251202

# shellcheck disable=SC2086
ARG GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000=5000
# shellcheck disable=SC2086
ARG GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS=local-global-stack-registry.local
# shellcheck disable=SC2086
FROM ${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}/local_global_stack_00base:${GLOBAL_STACK_VERSION} AS local_global_stack_base
FROM selenium/standalone-firefox:${GLOBAL_STACK_IMAGE_SELENIUM_STANDALONE_FIREFOX_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>"

LABEL info="local_global_stack"

USER root

# @todo fix pin versions
# hadolint ignore=DL3008
RUN apt-get -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change \
    && apt-get --allow-unauthenticated install -y --no-install-recommends --fix-missing \
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
    docker/config/dist/bin/selenium-standalone-firefox-bin/ \
    /usr/local/bin/

RUN find /usr/local/bin/ -type f -exec chmod a+x {} \;

USER seluser

CMD ["global-stack-selenium-standalone-firefox-start.sh"]