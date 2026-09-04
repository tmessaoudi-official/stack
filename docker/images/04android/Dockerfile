# shellcheck disable=SC2148
ARG GLOBAL_STACK_VERSION=2_0_0_local

# shellcheck disable=SC2086
ARG GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000=5000
# shellcheck disable=SC2086
ARG GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS=local-global-stack-registry.local
# shellcheck disable=SC2086
FROM ${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}/local_global_stack_03java26-zulu:${GLOBAL_STACK_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>" \
      info="local_global_stack"

USER root

SHELL ["/bin/bash", "-xeEu", "-o", "pipefail", "-c"]

ARG GLOBAL_STACK_ANDROID_LOCALE
ARG GLOBAL_STACK_ANDROID_SET_LOCALE

ENV GLOBAL_STACK_ANDROID_LOCALE="${GLOBAL_STACK_ANDROID_LOCALE}" \
    GLOBAL_STACK_ANDROID_SET_LOCALE="${GLOBAL_STACK_ANDROID_SET_LOCALE}"

# apt packages are deliberately NOT pinned — see .hadolint.yaml (DL3008 ignored:
# development environment, intentionally tracks latest). Ruling 2026-09-04, row 26.
RUN shopt -s extdebug \
    && IFS=$'\n\t' \
    && apt-get update --allow-releaseinfo-change \
    && apt-get install -y --no-install-recommends --fix-missing \
    usbutils \
    clang \
    ninja-build \
    libblkid-dev \
    android-sdk-platform-tools-common \
    libglu1-mesa \
    xz-utils \
    libc6:amd64 \
    lib32z1 \
    libbz2-1.0:amd64 \
    mesa-utils \
    && { [ "true" = "${GLOBAL_STACK_ANDROID_SET_LOCALE}" ] && global-stack-base-setup-locale.sh "${GLOBAL_STACK_ANDROID_LOCALE}" || echo -e "\n Locale will not be set"; } \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/*

USER "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}"

CMD ["global-stack-base-sync-bin-n-exec.sh", "global-stack-android-start.sh"]