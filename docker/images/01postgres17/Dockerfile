# shellcheck disable=SC2148
ARG GLOBAL_STACK_IMAGE_POSTGRES17_VERSION=17.6-alpine3.22

# shellcheck disable=SC2148
FROM postgres:${GLOBAL_STACK_IMAGE_POSTGRES17_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>"

LABEL info="local_global_stack"

# @todo fix last user should not be root
# hadolint ignore=DL3002
USER root

SHELL ["/bin/bash", "-xeEu", "-o", "pipefail", "-c"]

ARG GLOBAL_STACK_SHELL_HISTORY

COPY "${GLOBAL_STACK_SHELL_HISTORY}" /root/.bash_history
COPY docker/images/01postgres17/conf/initdb/ /docker-entrypoint-initdb.d/

RUN chown -R root:root /root/ \
    && find /root/ -type f -exec chmod 600 {} \; \
    && find /root/ -type d -exec chmod 700 {} \;