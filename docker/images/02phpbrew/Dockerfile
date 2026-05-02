# shellcheck disable=SC2148
ARG GLOBAL_STACK_VERSION=2_0_0_local

# shellcheck disable=SC2086
ARG GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000=5000
# shellcheck disable=SC2086
ARG GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS=local-global-stack-registry.local
# shellcheck disable=SC2086
FROM ${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}/local_global_stack_00base:${GLOBAL_STACK_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>" \
      info="local_global_stack"

USER root

SHELL ["/bin/bash", "-xeEu", "-o", "pipefail", "-c"]

ARG GLOBAL_STACK_FRANKENPHP_WATCHER_VERSION
ENV GLOBAL_STACK_FRANKENPHP_WATCHER_VERSION=${GLOBAL_STACK_FRANKENPHP_WATCHER_VERSION}

# curl -fsSL 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x14AA40EC0831756756D7F66C4F4EA0AAE5267A6C' | gpg --dearmor | tee /usr/share/keyrings/php.gpg \
# && sh -c 'echo "Types: deb\nTrusted: yes\nSigned-By: /usr/share/keyrings/php.gpg\nArch: $(dpkg --print-architecture)\nURIs: http://ppa.launchpad.net/ondrej/php/ubuntu\nSuites: noble\nComponents: main" > /etc/apt/sources.list.d/php-noble-main.sources' \
# @todo fix pin versions
RUN apt-get update --allow-releaseinfo-change \
    && apt-get install -y --no-install-recommends --fix-missing \
    bison \
    re2c \
    libzip5 \
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
    # php8.5 is intentionally installed here as the bootstrap PHP version required by phpbrew.
    # phpbrew needs a working PHP binary to function — this is NOT the target PHP version
    # for end-user images. The actual PHP version for each image (8.2, 8.3, 8.4, etc.)
    # is managed and installed by phpbrew at runtime.
    php8.5-cli \
    php8.5-phar \
    php8.5-readline \
    php8.5-bz2 \
    php8.5-xml \
    php8.5-curl \
    php8.5-sqlite3 \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/lib/x86_64-linux-gnu/libldap.so /usr/lib/libldap.so \
    && ln -s /usr/lib/x86_64-linux-gnu/liblber.so /usr/lib/liblber.so \
    && mkdir /tmp/watcher-c \
    && cd /tmp/watcher-c \
    && curl -fsSL -o "watcher-${GLOBAL_STACK_FRANKENPHP_WATCHER_VERSION}.tar.gz" "https://api.github.com/repos/e-dant/watcher/tarball/${GLOBAL_STACK_FRANKENPHP_WATCHER_VERSION}" \
    && tar -xf watcher-${GLOBAL_STACK_FRANKENPHP_WATCHER_VERSION}.tar.gz --strip-components 1 -C /tmp/watcher-c \
    && rm -rf watcher-${GLOBAL_STACK_FRANKENPHP_WATCHER_VERSION}.tar.gz \
    && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build \
    && cmake --install build \
    && ldconfig \
    && rm -rf /tmp/watcher-c \
    && ulimit -c unlimited
    # && echo "/tmp/core.%e.%p" | tee /proc/sys/kernel/core_pattern

EXPOSE 9000 9001

USER "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}"

CMD ["global-stack-base-sync-bin-n-exec.sh", "global-stack-phpbrew-start.sh"]


#    && IMAGEMAGICK_LATEST=$(curl --silent https://api.github.com/repos/ImageMagick/ImageMagick/releases/latest | jq .tag_name -r) \
#    && mkdir -p "${GLOBAL_STACK_DOCKER_ROOT_PATH}/imagemagick" && git clone --progress --verbose --branch "${IMAGEMAGICK_LATEST}" https://github.com/ImageMagick/ImageMagick.git --depth 1 "${GLOBAL_STACK_DOCKER_ROOT_PATH}/imagemagick" \
#    && cd "${GLOBAL_STACK_DOCKER_ROOT_PATH}/imagemagick" && ./configure \
#    && cd "${GLOBAL_STACK_DOCKER_ROOT_PATH}/imagemagick" && make \
#    && cd "${GLOBAL_STACK_DOCKER_ROOT_PATH}/imagemagick" && make install \
#    && cd "${GLOBAL_STACK_DOCKER_ROOT_PATH}/imagemagick" && ldconfig /usr/local/lib \
