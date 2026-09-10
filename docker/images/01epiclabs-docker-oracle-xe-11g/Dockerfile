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


# This image declares TZ=${GLOBAL_STACK_TIMEZONE} in its compose file but shipped no
# tzdata, so glibc could not resolve the zone: it ran UTC and printed the literal "Europe"
# as the zone name -- a wrong LABEL, which is worse than plainly reporting UTC.
# apt packages are deliberately NOT pinned -- see .hadolint.yaml (DL3008 ignored).
ENV DEBIAN_FRONTEND="noninteractive"
RUN apt-get update --allow-releaseinfo-change \
    && apt-get install -y --no-install-recommends --fix-missing \
    tzdata \
    && dpkg-reconfigure tzdata \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

RUN chown -R root:root /root/ \
    && find /root/ -type f -exec chmod 600 {} \; \
    && find /root/ -type d -exec chmod 700 {} \;