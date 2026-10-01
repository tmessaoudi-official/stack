# shellcheck disable=SC2148
ARG GLOBAL_STACK_IMAGE_MONGO9_VERSION=9.0.2-noble

# shellcheck disable=SC2148
FROM mongo:${GLOBAL_STACK_IMAGE_MONGO9_VERSION}

# Upstream sets `ENV GLIBC_TUNABLES glibc.pthread.rseq=0` (an old tcmalloc workaround). On a
# kernel >= 6.19 that tunable is what makes mongod 9.0.x refuse to start with the
# SERVER-121912 "kernel 6.19 and newer" FATAL; cleared, mongod starts and runs fine
# (measured 2026-10-01, kernel 7.0.0-34). Re-probe on every MONGO9 version bump:
# bin/tests/mongo9-rseq.test.sh (GS_MONGO9_PROBE=1 starts a throwaway mongod).
ENV GLIBC_TUNABLES=""

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>" \
      info="local_global_stack"

# @todo fix last user should not be root
# hadolint ignore=DL3002
USER root

SHELL ["/bin/bash", "-xeEu", "-o", "pipefail", "-c"]

COPY docker/images/01mongo9/conf/initdb/ /docker-entrypoint-initdb.d/

RUN chown -R root:root /root/ \
    && find /root/ -type f -exec chmod 600 {} \; \
    && find /root/ -type d -exec chmod 700 {} \;
