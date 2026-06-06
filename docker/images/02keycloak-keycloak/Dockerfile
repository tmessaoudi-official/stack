# shellcheck disable=SC2148
ARG GLOBAL_STACK_IMAGE_KEYCLOAK_KEYCLOAK_VERSION=26.6.3-0

# shellcheck disable=SC2148
FROM quay.io/keycloak/keycloak:${GLOBAL_STACK_IMAGE_KEYCLOAK_KEYCLOAK_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>" \
      info="local_global_stack"

# @todo fix: last USER should not be root
# hadolint ignore=DL3002
USER root


USER keycloak