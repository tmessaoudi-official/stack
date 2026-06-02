# shellcheck disable=SC2148
ARG GLOBAL_STACK_IMAGE_MONGOCLIENT_MONGOCLIENT_VERSION=4.0.1

# shellcheck disable=SC2148
FROM mongoclient/mongoclient:${GLOBAL_STACK_IMAGE_MONGOCLIENT_MONGOCLIENT_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>" \
      info="local_global_stack"

USER root


RUN chown -R node:node /home/node/ \
    && find /home/node/ -type f -exec chmod 600 {} \; \
    && find /home/node/ -type d -exec chmod 700 {} \;

USER node