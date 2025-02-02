# shellcheck disable=SC2148
ARG GLOBAL_STACK_VERSION=1_5_0_local

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

# @todo fix pin versions
# hadolint ignore=DL3008,DL3018
RUN apt-key adv \
    --keyserver hkp://keyserver.ubuntu.com:80 \
    --recv-keys 14AA40EC0831756756D7F66C4F4EA0AAE5267A6C \
    && apt-key export 14AA40EC0831756756D7F66C4F4EA0AAE5267A6C | gpg --dearmor | sudo dd of=/etc/apt/trusted.gpg.d/php.gpg \
    && sh -c 'echo "deb [signed-by=/etc/apt/trusted.gpg.d/php.gpg arch=$(dpkg --print-architecture)] http://ppa.launchpad.net/ondrej/php/ubuntu noble main" > /etc/apt/sources.list.d/php-noble-main.list' \
    && apt-get update --allow-releaseinfo-change \
    && apt-get install -y --no-install-recommends --fix-missing \
    bison \
    re2c \
    libzip4 \
    libzip-dev \
    libedit-dev \
    libxslt1-dev \
    libxslt1.1 \
    libcurl4-openssl-dev \
    libonig-dev \
    imagemagick \
    libmagick++-dev \
    libmagickwand-dev \
    libmagickcore-dev \
    graphicsmagick \
    libjpeg-turbo8 \
    libjpeg8 \
    ghostscript \
    libpng-dev \
    libwebp-dev \
    libxpm-dev \
    libfreetype6-dev \
    graphviz \
    libzmq3-dev \
    libicu-dev \
    icu-devtools \
    libmariadb-dev \
    libpq5 \
    libsodium-dev \
    libxpm4 \
    libltdl-dev \
    libgd3 \
    libmhash2 \
    libmhash-dev \
    libmcrypt4 \
    libmcrypt-dev \
    libgmp-dev \
    libmemcached-dev \
    bsdmainutils \
    libldb-dev \
    libldap2-dev \
    librabbitmq-dev \
    libssh2-1 \
    libssh2-1-dev \
    libargon2-1 \
    libargon2-dev \
    libidn2-0 \
    libzstd1 \
    libgpgme-dev \
    libc-ares-dev \
    libsystemd-dev \
    php8.4-cli \
    php8.4-phar \
    php8.4-readline \
    php8.4-bz2 \
    php8.4-xml \
    php8.4-curl \
    php8.4-sqlite3 \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/lib/x86_64-linux-gnu/libldap.so /usr/lib/libldap.so \
    && ln -s /usr/lib/x86_64-linux-gnu/liblber.so /usr/lib/liblber.so

EXPOSE 9000 9001

USER "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}"

CMD ["global-stack-base-sync-bin-n-exec.sh", "global-stack-phpbrew-start.sh"]


#    && IMAGEMAGICK_LATEST=$(curl --silent https://api.github.com/repos/ImageMagick/ImageMagick/releases/latest | jq .tag_name -r) \
#    && mkdir -p "${GLOBAL_STACK_DOCKER_ROOT_PATH}/imagemagick" && git clone --progress --verbose --branch "${IMAGEMAGICK_LATEST}" https://github.com/ImageMagick/ImageMagick.git --depth 1 "${GLOBAL_STACK_DOCKER_ROOT_PATH}/imagemagick" \
#    && cd "${GLOBAL_STACK_DOCKER_ROOT_PATH}/imagemagick" && ./configure \
#    && cd "${GLOBAL_STACK_DOCKER_ROOT_PATH}/imagemagick" && make \
#    && cd "${GLOBAL_STACK_DOCKER_ROOT_PATH}/imagemagick" && make install \
#    && cd "${GLOBAL_STACK_DOCKER_ROOT_PATH}/imagemagick" && ldconfig /usr/local/lib \
