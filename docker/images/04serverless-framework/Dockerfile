# shellcheck disable=SC2148
ARG GLOBAL_STACK_VERSION=1_5_0_local

# shellcheck disable=SC2086
ARG GLOBAL_STACK_LOCAL_REGISTRY_PORT_5000=5000
# shellcheck disable=SC2086
ARG GLOBAL_STACK_LOCAL_REGISTRY_ALIAS=local-global-stack-registry.local
# shellcheck disable=SC2086
FROM ${GLOBAL_STACK_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_LOCAL_REGISTRY_PORT_5000}/local_global_stack_03php8-5:${GLOBAL_STACK_VERSION}

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
    && apt-get -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change \
    && apt-get --allow-unauthenticated install -y --no-install-recommends --fix-missing \
    llvm \
    libncurses5-dev \
    tk-dev \
    libxmlsec1-dev \
    libffi-dev \
    libncursesw5-dev \
    xz-utils \
    && [ "true" = "${GLOBAL_STACK_RBENV_SET_LOCALE}" ] && global-stack-base-setup-locale.sh "${GLOBAL_STACK_RBENV_LOCALE}" || echo -e "\n Locale will not be set" \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

USER "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}"


# Expose ports
EXPOSE 3000 3002 4569 9324 9325 4002

# Default command
CMD ["global-stack-base-sync-bin-n-exec.sh", "global-stack-serverless-framework-start.sh"]