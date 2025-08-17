# shellcheck disable=SC2148
ARG GLOBAL_STACK_IMAGE_MARIADB12_VERSION=12.1.1-noble-rc

# shellcheck disable=SC2148
FROM mariadb:${GLOBAL_STACK_IMAGE_MARIADB12_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>"

LABEL info="local_global_stack"

# @todo fix last user should not be root
# hadolint ignore=DL3002
USER root

SHELL ["/bin/bash", "-xeEu", "-o", "pipefail", "-c"]

COPY docker/images/01mariadb12/conf/etc/ /etc/mysql/mariadb.conf.d/
COPY docker/images/01mariadb12/conf/initdb/ /docker-entrypoint-initdb.d/

ARG GLOBAL_STACK_SHELL_HISTORY
COPY "${GLOBAL_STACK_SHELL_HISTORY}" /root/.bash_history

RUN chown -R root:root /root/ \
    && find /root/ -type f -exec chmod 600 {} \; \
    && find /root/ -type d -exec chmod 700 {} \; \
    && chmod 0444 /etc/mysql/my.cnf /etc/mysql/mariadb.cnf \
    && find /etc/mysql/mariadb.conf.d/ -type f -exec chmod 0444 {} \;