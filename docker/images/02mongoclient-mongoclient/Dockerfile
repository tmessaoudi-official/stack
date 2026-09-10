# shellcheck disable=SC2148
ARG GLOBAL_STACK_IMAGE_MONGOCLIENT_MONGOCLIENT_VERSION=4.0.1

# shellcheck disable=SC2148
FROM mongoclient/mongoclient:${GLOBAL_STACK_IMAGE_MONGOCLIENT_MONGOCLIENT_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>" \
      info="local_global_stack"

USER root


# Same as 01epiclabs-docker-oracle-xe-11g: TZ is declared in the compose file but the
# upstream image ships no tzdata, so the zone cannot be resolved and the container runs UTC
# while printing "Europe" as the zone name.
# apt packages are deliberately NOT pinned -- see .hadolint.yaml (DL3008 ignored).
ENV DEBIAN_FRONTEND="noninteractive"
RUN apt-get update --allow-releaseinfo-change \
    && apt-get install -y --no-install-recommends --fix-missing \
    tzdata \
    && dpkg-reconfigure tzdata \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

RUN chown -R node:node /home/node/ \
    && find /home/node/ -type f -exec chmod 600 {} \; \
    && find /home/node/ -type d -exec chmod 700 {} \;

USER node