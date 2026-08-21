# shellcheck disable=SC2148
ARG GLOBAL_STACK_IMAGE_POSTGRES18_VERSION=18.6-alpine3.24

# shellcheck disable=SC2148
FROM postgres:${GLOBAL_STACK_IMAGE_POSTGRES18_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>" \
      info="local_global_stack"

# @todo fix last user should not be root
# hadolint ignore=DL3002
USER root

SHELL ["/bin/bash", "-xeEu", "-o", "pipefail", "-c"]

COPY docker/images/01postgres18/conf/initdb/ /docker-entrypoint-initdb.d/

RUN chown -R root:root /root/ \
    && find /root/ -type f -exec chmod 600 {} \; \
    && find /root/ -type d -exec chmod 700 {} \;