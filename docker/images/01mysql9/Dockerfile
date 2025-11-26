# shellcheck disable=SC2148
ARG GLOBAL_STACK_IMAGE_MYSQL9_VERSION=9.5.0-oraclelinux9

# shellcheck disable=SC2148
FROM mysql:${GLOBAL_STACK_IMAGE_MYSQL9_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>"

LABEL info="local_global_stack"

# @todo fix last user should not be root
# hadolint ignore=DL3002
USER root

SHELL ["/bin/bash", "-xeEu", "-o", "pipefail", "-c"]

ARG GLOBAL_STACK_DATABASE_CHARSET
ARG GLOBAL_STACK_DATABASE_COLLATE
ENV GLOBAL_STACK_DATABASE_CHARSET="${GLOBAL_STACK_DATABASE_CHARSET}" \
    GLOBAL_STACK_DATABASE_COLLATE="${GLOBAL_STACK_DATABASE_COLLATE}"

COPY docker/images/01mysql9/conf/etc/mysql/ /etc/mysql/conf.d/
COPY docker/images/01mysql9/conf/initdb/ /docker-entrypoint-initdb.d/

RUN sed -i "s|\${GLOBAL_STACK_DATABASE_CHARSET}|${GLOBAL_STACK_DATABASE_CHARSET}|g" \
    /etc/mysql/conf.d/my.cnf \
    && sed -i "s|\${GLOBAL_STACK_DATABASE_COLLATE}|${GLOBAL_STACK_DATABASE_COLLATE}|g" \
    /etc/mysql/conf.d/my.cnf

ARG GLOBAL_STACK_SHELL_HISTORY

COPY "${GLOBAL_STACK_SHELL_HISTORY}" /root/.bash_history

RUN chown -R root:root /root/ \
    && find /root/ -type f -exec chmod 600 {} \; \
    && find /root/ -type d -exec chmod 700 {} \; \
    # && chmod 0444 /etc/mysql/my.cnf \
    && chown -R mysql:mysql /etc/mysql/conf.d/ \
    && chmod -R 755 /etc/mysql/conf.d/ \
    && chown -R mysql:mysql /var/run/mysqld/ \
    && chmod -R 755 /var/run/mysqld/ \
    && chown -R mysql:mysql /var/lib/mysql/ \
    && chmod -R 755 /var/lib/mysql/
