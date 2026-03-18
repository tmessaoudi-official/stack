# shellcheck disable=SC2148
ARG GLOBAL_STACK_IMAGE_KEYCLOAK_KEYCLOAK_VERSION=26.5.5-0

# shellcheck disable=SC2148
FROM quay.io/keycloak/keycloak:${GLOBAL_STACK_IMAGE_KEYCLOAK_KEYCLOAK_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>"

LABEL info="local_global_stack"

# # @todo fix last user should not be root
# # hadolint ignore=DL3002
USER root

ARG GLOBAL_STACK_SHELL_HISTORY
COPY "${GLOBAL_STACK_SHELL_HISTORY}" /opt/keycloak/.bash_history

# RUN chown -R root:root /root/ \
#     && find /root/ -type f -exec chmod 600 {} \; \
#     && find /root/ -type d -exec chmod 700 {} \; \
#     && chown root:root /entrypoint.sh \
#     && chmod a+x /entrypoint.sh

USER keycloak