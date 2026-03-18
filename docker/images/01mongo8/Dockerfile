# shellcheck disable=SC2148
ARG GLOBAL_STACK_IMAGE_MONGO8_VERSION=8.2.6-rc0-noble

# shellcheck disable=SC2148
FROM mongo:${GLOBAL_STACK_IMAGE_MONGO8_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>"

LABEL info="local_global_stack"

# @todo fix last user should not be root
# hadolint ignore=DL3002
USER root

SHELL ["/bin/bash", "-xeEu", "-o", "pipefail", "-c"]

ARG GLOBAL_STACK_SHELL_HISTORY
COPY "${GLOBAL_STACK_SHELL_HISTORY}" /data/db/.bash_history
COPY docker/images/01mongo8/conf/initdb/ /docker-entrypoint-initdb.d/

RUN chown -R root:root /root/ \
    && find /root/ -type f -exec chmod 600 {} \; \
    && find /root/ -type d -exec chmod 700 {} \; \
    && chown -R root:root /data/db/.bash_history \
    && chmod 600 /data/db/.bash_history