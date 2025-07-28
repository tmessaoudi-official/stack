# shellcheck disable=SC2148
ARG GLOBAL_STACK_VERSION=2_0_0_local

# shellcheck disable=SC2086
ARG GLOBAL_STACK_LOCAL_REGISTRY_PORT_5000=5000
# shellcheck disable=SC2086
ARG GLOBAL_STACK_LOCAL_REGISTRY_ALIAS=local-global-stack-registry.local
# shellcheck disable=SC2086
FROM ${GLOBAL_STACK_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_LOCAL_REGISTRY_PORT_5000}/local_global_stack_00base:${GLOBAL_STACK_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>"

LABEL info="local_global_stack"

USER root

SHELL ["/bin/bash", "-xeEu", "-o", "pipefail", "-c"]

ARG GLOBAL_STACK_RBENV_LOCALE
ARG GLOBAL_STACK_RBENV_SET_LOCALE

ENV GLOBAL_STACK_RBENV_LOCALE="${GLOBAL_STACK_RBENV_LOCALE}" \
    GLOBAL_STACK_RBENV_SET_LOCALE="${GLOBAL_STACK_RBENV_SET_LOCALE}"
    
RUN shopt -s extdebug \
    && IFS=$'\n\t' \
    && [ "true" = "${GLOBAL_STACK_RBENV_SET_LOCALE}" ] && global-stack-base-setup-locale.sh "${GLOBAL_STACK_RBENV_LOCALE}" || echo -e "\n Locale will not be set"

USER "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}"

CMD ["global-stack-base-sync-bin-n-exec.sh", "global-stack-rbenv-start.sh"]
