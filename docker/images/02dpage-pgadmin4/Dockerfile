# shellcheck disable=SC2148
ARG GLOBAL_STACK_IMAGE_DPAGE_PGADMIN4_VERSION=8.14.0

# shellcheck disable=SC2148
FROM dpage/pgadmin4:${GLOBAL_STACK_IMAGE_DPAGE_PGADMIN4_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>"

LABEL info="local_global_stack"

# @todo fix last user should not be root
# hadolint ignore=DL3002
USER root

COPY docker/images/02dpage-pgadmin4/dist/conf/ /pgadmin4/
# COPY docker/images/02dpage-pgadmin4/config/servers.git.ignore.json? /pgadmin4/servers.json
COPY docker/images/02dpage-pgadmin4/dist/bin/ /usr/local/bin/

ARG GLOBAL_STACK_SHELL_HISTORY
COPY "${GLOBAL_STACK_SHELL_HISTORY}" /root/.bash_history

RUN chown -R root:root /root/ \
    && find /root/ -type f -exec chmod 600 {} \; \
    && find /root/ -type d -exec chmod 700 {} \;

CMD ["global-stack-dpage-pgadmin4-restore-servers.sh"]