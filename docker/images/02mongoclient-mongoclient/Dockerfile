# shellcheck disable=SC2148
ARG GLOBAL_STACK_IMAGE_MONGOCLIENT_MONGOCLIENT_VERSION=4.0.1

# shellcheck disable=SC2148
FROM mongoclient/mongoclient:${GLOBAL_STACK_IMAGE_MONGOCLIENT_MONGOCLIENT_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>"

LABEL info="local_global_stack"

USER root

ARG GLOBAL_STACK_SHELL_HISTORY

COPY "${GLOBAL_STACK_SHELL_HISTORY}" /home/node/.bash_history

RUN chown -R node:node /home/node/ \
    && find /home/node/ -type f -exec chmod 600 {} \; \
    && find /home/node/ -type d -exec chmod 700 {} \;

USER node