# shellcheck disable=SC2148
ARG GLOBAL_STACK_IMAGE_AXLLENT_MAILPIT_VERSION=v1.23.1

# shellcheck disable=SC2086
FROM axllent/mailpit:${GLOBAL_STACK_IMAGE_AXLLENT_MAILPIT_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>"

LABEL info="local_global_stack"

# hadolint ignore=DL3002
USER root

SHELL ["/bin/bash", "-xeEu", "-o", "pipefail", "-c"]