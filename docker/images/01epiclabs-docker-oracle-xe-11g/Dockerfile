# shellcheck disable=SC2148
ARG GLOBAL_STACK_IMAGE_EPICLABS_DOCKER_ORACLE_XE_11G_VERSION=latest

# hadolint ignore=DL3006,DL3007
FROM epiclabs/docker-oracle-xe-11g:${GLOBAL_STACK_IMAGE_EPICLABS_DOCKER_ORACLE_XE_11G_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>" \
      info="local_global_stack"

# @todo fix last user should not be root
# hadolint ignore=DL3002
USER root

SHELL ["/bin/bash", "-xeEu", "-o", "pipefail", "-c"]


RUN chown -R root:root /root/ \
    && find /root/ -type f -exec chmod 600 {} \; \
    && find /root/ -type d -exec chmod 700 {} \;