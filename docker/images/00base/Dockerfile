# shellcheck disable=SC2148
ARG GLOBAL_STACK_IMAGE_UBUNTU_VERSION=resolute-20251130

# shellcheck disable=SC2148
FROM ubuntu:${GLOBAL_STACK_IMAGE_UBUNTU_VERSION}

LABEL maintainer="Takieddine Messaoudi <takieddine.messaoudi.official@gmail.com>"

LABEL info="local_global_stack"

USER root

SHELL ["/bin/bash", "-xeEu", "-o", "pipefail", "-c"]

ARG GLOBAL_STACK_TIMEZONE
# shellcheck disable=SC2148
ARG GLOBAL_STACK_VERSION
ARG GLOBAL_STACK_RELOAD_ALL
ARG GLOBAL_STACK_DOCKER_ROOT_PATH
ARG GLOBAL_STACK_DOCKER_WORKDIR
ARG GLOBAL_STACK_DOCKER_TOOLS_PATH
ARG GLOBAL_STACK_DOCKER_USER_UID
ARG GLOBAL_STACK_DOCKER_USER_ID
ARG GLOBAL_STACK_DOCKER_PASSWORD
ARG GLOBAL_STACK_DOCKER_GROUP_UID
ARG GLOBAL_STACK_DOCKER_GROUP_ID
ARG GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN
ARG GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS
ARG GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES
ARG GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS
ARG GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC
ARG GLOBAL_STACK_DOCKER_TOOLS_PATH_CACHE
ARG GLOBAL_STACK_DOCKER_ROOT_DIST_PATH
ARG GLOBAL_STACK_DOCKER_TOOLS_PATH_LOGS
ARG GLOBAL_STACK_SSL_PATH
ARG GOROOT
ARG GOPATH
ARG ZIGPATH
ARG HURLPATH
ARG GLOBAL_STACK_CARGO_HOME
ARG GLOBAL_STACK_PYTHON3_INSTALL_PACKAGE_AWSCLI_LOCAL_VERSION
ARG GLOBAL_STACK_PYTHON3_INSTALL_PACKAGE_SETUPTOOLS_VERSION
ARG GLOBAL_STACK_SHELL_RC_TARGET
ARG GLOBAL_STACK_SHELL
ARG GLOBAL_STACK_INSTALL_ANSIBLE
ARG GLOBAL_STACK_GO_VERSION
ARG GLOBAL_STACK_ZIG_VERSION
ARG GLOBAL_STACK_DOCKER_IN_DOCKER
ARG GLOBAL_STACK_INSTALL_GITLAB_RUNNER
ARG GLOBAL_STACK_INSTALL_PODMAN
ARG GLOBAL_STACK_UNU
ARG GLOBAL_STACK_DOCKER_COMPOSE_V1_VERSION
ARG GLOBAL_STACK_DOCKER_COMPOSE_V2_VERSION
ARG GLOBAL_STACK_DOCKER_BUILDX_VERSION
ARG GLOBAL_STACK_MKCERT_VERSION
ARG GLOBAL_STACK_PODMAN_COMPOSE_VERSION
ARG GLOBAL_STACK_PODMAN_CHANEL
ARG GLOBAL_STACK_BASE_INSTALL_TOOLS
ARG GLOBAL_STACK_SONAR_SCANNER_CLI_VERSION
ARG GLOBAL_STACK_HADOLINT_VERSION
ARG GLOBAL_STACK_SHELL_CHECK_VERSION
ARG GLOBAL_STACK_GITLEAKS_VERSION
ARG GLOBAL_STACK_DIFFTASTIC_VERSION
ARG GLOBAL_STACK_SHFMT_VERSION
ARG GLOBAL_STACK_MISE_VERSION
ARG GLOBAL_STACK_BAT_VERSION
ARG GLOBAL_STACK_TASK_VERSION
ARG GLOBAL_STACK_SOPS_VERSION
ARG GLOBAL_STACK_YQ_VERSION
ARG GLOBAL_STACK_YAMLFMT_VERSION
ARG GLOBAL_STACK_HURL_VERSION
ARG GLOBAL_STACK_WKHTMLTOPDF_VERSION
ARG GLOBAL_STACK_WKHTMLTOPDF_DISTRO
ARG GLOBAL_STACK_JUJUTSU_VERSION
ARG GLOBAL_STACK_MERGIRAF_VERSION
ARG GLOBAL_STACK_USE_LOCKS
ARG MISE_DEBUG
ARG MISE_QUIET
ARG MISE_INSTALL_PATH
ARG MISE_VERSION
ARG MISE_DATA_DIR
ARG MISE_STATE_DIR
ARG MISE_CONFIG_DIR
ARG MISE_CACHE_DIR
ARG CAROOT

ENV DEBIAN_FRONTEND="noninteractive" \
    GLOBAL_STACK_TIMEZONE="${GLOBAL_STACK_TIMEZONE}" \
    TZ="${GLOBAL_STACK_TIMEZONE}" \
    GLOBAL_STACK_VERSION="${GLOBAL_STACK_VERSION}" \
    GLOBAL_STACK_RELOAD_ALL="${GLOBAL_STACK_RELOAD_ALL}" \
    GLOBAL_STACK_DOCKER_ROOT_PATH="${GLOBAL_STACK_DOCKER_ROOT_PATH}" \
    GLOBAL_STACK_DOCKER_WORKDIR="${GLOBAL_STACK_DOCKER_WORKDIR}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH}" \
    GLOBAL_STACK_DOCKER_USER_UID="${GLOBAL_STACK_DOCKER_USER_UID}" \
    GLOBAL_STACK_DOCKER_USER_ID="${GLOBAL_STACK_DOCKER_USER_ID}" \
    GLOBAL_STACK_DOCKER_PASSWORD="${GLOBAL_STACK_DOCKER_PASSWORD}" \
    GLOBAL_STACK_DOCKER_GROUP_UID="${GLOBAL_STACK_DOCKER_GROUP_UID}" \
    GLOBAL_STACK_DOCKER_GROUP_ID="${GLOBAL_STACK_DOCKER_GROUP_ID}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN="${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES="${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS="${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC="${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_CACHE="${GLOBAL_STACK_DOCKER_TOOLS_PATH_CACHE}" \
    GLOBAL_STACK_DOCKER_ROOT_DIST_PATH="${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_LOGS="${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOGS}" \
    GLOBAL_STACK_SSL_PATH="${GLOBAL_STACK_SSL_PATH}" \
    GOROOT="${GOROOT}" \
    GOPATH="${GOPATH}" \
    ZIGPATH="${ZIGPATH}" \
    HURLPATH="${HURLPATH}" \
    GLOBAL_STACK_CARGO_HOME="${GLOBAL_STACK_CARGO_HOME}" \
    GLOBAL_STACK_PYTHON3_INSTALL_PACKAGE_SETUPTOOLS_VERSION="${GLOBAL_STACK_PYTHON3_INSTALL_PACKAGE_SETUPTOOLS_VERSION}" \
    GLOBAL_STACK_PYTHON3_INSTALL_PACKAGE_AWSCLI_LOCAL_VERSION="${GLOBAL_STACK_PYTHON3_INSTALL_PACKAGE_AWSCLI_LOCAL_VERSION}" \
    GLOBAL_STACK_SHELL_RC_TARGET="${GLOBAL_STACK_SHELL_RC_TARGET}" \
    GLOBAL_STACK_SHELL="${GLOBAL_STACK_SHELL}" \
    GLOBAL_STACK_DOCKER_IN_DOCKER="${GLOBAL_STACK_DOCKER_IN_DOCKER}" \
    GLOBAL_STACK_INSTALL_ANSIBLE="${GLOBAL_STACK_INSTALL_ANSIBLE}" \
    GLOBAL_STACK_GO_VERSION="${GLOBAL_STACK_GO_VERSION}" \
    GLOBAL_STACK_ZIG_VERSION="${GLOBAL_STACK_ZIG_VERSION}" \
    GLOBAL_STACK_DOCKER_COMPOSE_V1_VERSION="${GLOBAL_STACK_DOCKER_COMPOSE_V1_VERSION}" \
    GLOBAL_STACK_DOCKER_COMPOSE_V2_VERSION="${GLOBAL_STACK_DOCKER_COMPOSE_V2_VERSION}" \
    GLOBAL_STACK_DOCKER_BUILDX_VERSION="${GLOBAL_STACK_DOCKER_BUILDX_VERSION}" \
    GLOBAL_STACK_MKCERT_VERSION="${GLOBAL_STACK_MKCERT_VERSION}" \
    GLOBAL_STACK_PODMAN_COMPOSE_VERSION="${GLOBAL_STACK_PODMAN_COMPOSE_VERSION}" \
    GLOBAL_STACK_INSTALL_GITLAB_RUNNER="${GLOBAL_STACK_INSTALL_GITLAB_RUNNER}" \
    GLOBAL_STACK_INSTALL_PODMAN="${GLOBAL_STACK_INSTALL_PODMAN}" \
    GLOBAL_STACK_PODMAN_CHANEL="${GLOBAL_STACK_PODMAN_CHANEL}" \
    GLOBAL_STACK_BASE_INSTALL_TOOLS="${GLOBAL_STACK_BASE_INSTALL_TOOLS}" \
    GLOBAL_STACK_SONAR_SCANNER_CLI_VERSION="${GLOBAL_STACK_SONAR_SCANNER_CLI_VERSION}" \
    GLOBAL_STACK_HADOLINT_VERSION="${GLOBAL_STACK_HADOLINT_VERSION}" \
    GLOBAL_STACK_SHELL_CHECK_VERSION="${GLOBAL_STACK_SHELL_CHECK_VERSION}" \
    GLOBAL_STACK_GITLEAKS_VERSION="${GLOBAL_STACK_GITLEAKS_VERSION}" \
    GLOBAL_STACK_DIFFTASTIC_VERSION="${GLOBAL_STACK_DIFFTASTIC_VERSION}" \
    GLOBAL_STACK_SHFMT_VERSION="${GLOBAL_STACK_SHFMT_VERSION}" \
    GLOBAL_STACK_MISE_VERSION="${GLOBAL_STACK_MISE_VERSION}" \
    GLOBAL_STACK_BAT_VERSION="${GLOBAL_STACK_BAT_VERSION}" \
    GLOBAL_STACK_TASK_VERSION="${GLOBAL_STACK_TASK_VERSION}" \
    GLOBAL_STACK_SOPS_VERSION="${GLOBAL_STACK_SOPS_VERSION}" \
    GLOBAL_STACK_YQ_VERSION="${GLOBAL_STACK_YQ_VERSION}" \
    GLOBAL_STACK_YAMLFMT_VERSION="${GLOBAL_STACK_YAMLFMT_VERSION}" \
    GLOBAL_STACK_HURL_VERSION="${GLOBAL_STACK_HURL_VERSION}" \
    GLOBAL_STACK_JUJUTSU_VERSION="${GLOBAL_STACK_JUJUTSU_VERSION}" \
    GLOBAL_STACK_MERGIRAF_VERSION="${GLOBAL_STACK_MERGIRAF_VERSION}" \
    GLOBAL_STACK_UNU="${GLOBAL_STACK_UNU}" \
    GLOBAL_STACK_USE_LOCKS="${GLOBAL_STACK_USE_LOCKS}" \
    MISE_DEBUG="${MISE_DEBUG}" \
    MISE_QUIET="${MISE_QUIET}" \
    MISE_INSTALL_PATH="${MISE_INSTALL_PATH}" \
    MISE_VERSION="${MISE_VERSION}" \
    MISE_DATA_DIR="${MISE_DATA_DIR}" \
    MISE_STATE_DIR="${MISE_STATE_DIR}" \
    MISE_CONFIG_DIR="${MISE_CONFIG_DIR}" \
    MISE_CACHE_DIR="${MISE_CACHE_DIR}" \
    CAROOT="${CAROOT}" \
    GLOBAL_STACK_WKHTMLTOPDF_VERSION="${GLOBAL_STACK_WKHTMLTOPDF_VERSION}" \
    GLOBAL_STACK_WKHTMLTOPDF_DISTRO="${GLOBAL_STACK_WKHTMLTOPDF_DISTRO}" \
    PATH="${GLOBAL_STACK_CARGO_HOME}/bin:${HURLPATH}/bin:${ZIGPATH}:${GOROOT}/bin:/opt/${GLOBAL_STACK_DOCKER_USER_ID}/sonar-scanner-cli/bin/:/opt/${GLOBAL_STACK_DOCKER_USER_ID}/task:/opt/${GLOBAL_STACK_DOCKER_USER_ID}/bat:${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}:${PATH}"

COPY docker/images/00base/conf/bin/ /usr/local/bin/

# && sed -i "s|questing|resolute|g" /etc/apt/sources.list \
# && sed -i "s|questing|resolute|g" /etc/apt/sources.list.d/ubuntu.sources \
# @todo fix pin versions
# hadolint ignore=DL3008,DL3018
RUN shopt -s extdebug \
    && IFS=$'\n\t' \
    && [ "${GLOBAL_STACK_DOCKER_USER_UID}" = "" ] || [ "${GLOBAL_STACK_DOCKER_USER_ID}" = "" ] || [ "${GLOBAL_STACK_DOCKER_PASSWORD}" = "" ] || [ "${GLOBAL_STACK_DOCKER_GROUP_UID}" = "" ] || [ "${GLOBAL_STACK_DOCKER_GROUP_ID}" = "" ] && exit 1 || echo -e "\n Seems like everything is set !" \
    && mkdir -p /usr/share/zoneinfo/"${GLOBAL_STACK_TIMEZONE}" \
    && echo "${GLOBAL_STACK_TIMEZONE}" > /etc/timezone \
    && echo 'APT::Key::Assert-Pubkey-Algo "";' > /etc/apt/apt.conf.d/99weakkey-warning \
    && mkdir -p /usr/share/man/man1 \
    && apt-get -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change \
    && dpkg --add-architecture i386 \
    && apt-get dist-upgrade -y \
    && apt-get --allow-unauthenticated install -y --no-install-recommends --fix-missing \
    tzdata \
    && dpkg-reconfigure tzdata \
    && apt-get --allow-unauthenticated install -y --no-install-recommends --fix-missing \
    sudo \
    sendmail \
    locales \
    iptables \
    bash-completion \
    pkg-config \
    libpq-dev \
    fontforge \
    ttfautohint \
    zlib1g-dev \
    libpcre3-dev \
    libpcre2-8-0 \
    libpcre3 \
    g++ \
    aptitude \
    jq \
    vim \
    rsync \
    wget \
    zip \
    nano \
    unzip \
    openssl \
    libssl-dev \
    gnupg \
    gnupg2 \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    curl \
    lsb-release \
    ssh \
    dnsutils \
    less \
    debootstrap \
    make \
    gcc \
    build-essential \
    autoconf \
    automake \
    autotools-dev \
    gettext \
    mercurial \
    supervisor \
    libgtk2.0-0 \
    libgtk-3-0 \
    libgtk-3-dev \
    libgbm-dev \
    libnotify-dev \
    libnss3 \
    libxss1 \
    libasound2-dev \
    libxtst6 \
    xauth \
    xvfb \
    libxml2-16 \
    libxml2-dev \
    golang \
    libnss3-tools \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    liblzma-dev \
    mysql-client \
    openssh-client \
    python3 \
    python3-pip \
    libyaml-dev \
    ripgrep \
    httpie \
    iputils-ping \
    bsdextrautils \
    && pip install --no-cache-dir --upgrade setuptools==${GLOBAL_STACK_PYTHON3_INSTALL_PACKAGE_SETUPTOOLS_VERSION} --break-system-packages \
    && pip install --no-cache-dir awscli-local==${GLOBAL_STACK_PYTHON3_INSTALL_PACKAGE_AWSCLI_LOCAL_VERSION} --break-system-packages \
    && curl -o /usr/share/keyrings/postgresql.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    # @todo make it $(lsb_release -cs) later
    && sh -c 'echo "Types: deb\nTrusted: yes\nSigned-By: /usr/share/keyrings/postgresql.asc\nArch: $(dpkg --print-architecture)\nURIs: https://apt.postgresql.org/pub/repos/apt\nSuites: questing-pgdg\nComponents: main" > /etc/apt/sources.list.d/pgdg.sources' \
    && curl -fsSL 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF911AB184317630C59970973E363C90F8F1B6217' | gpg --dearmor | tee /usr/share/keyrings/git.gpg \
    && echo -e "Types: deb\nTrusted: yes\nSigned-By: /usr/share/keyrings/git.gpg\nArch: $(dpkg --print-architecture)\nURIs: https://ppa.launchpadcontent.net/git-core/ppa/ubuntu\nSuites: $(lsb_release -cs)\nComponents: main" | dd of=/etc/apt/sources.list.d/git.sources \
    && wget -qO- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor | dd of=/usr/share/keyrings/google-chrome.gpg \
    && echo -e "Types: deb\nTrusted: yes\nSigned-By: /usr/share/keyrings/google-chrome.gpg\nArch: $(dpkg --print-architecture)\nURIs: http://dl.google.com/linux/chrome/deb/\nSuites: stable\nComponents: main" | dd of=/etc/apt/sources.list.d/google-chrome.sources \
    && apt-get -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change \
    && apt-get --allow-unauthenticated install -y --no-install-recommends --fix-missing \
    git \
    google-chrome-stable \
    postgresql-client-18 \
    libgoffice-0.10-10t64 \
    libgoffice-0.10-dev \
    libfontconfig1 \
    libxrender1 \
    cmake \
	libbrotli-dev \
    libstdc++6 \
    libcjose-dev \
    libjansson-dev \
    && rm -rf /etc/apt/sources.list.d/google-chrome.list \
    && [ "${GLOBAL_STACK_WKHTMLTOPDF_VERSION}" != "" ] && [ "${GLOBAL_STACK_WKHTMLTOPDF_DISTRO}" != "" ] && (wget https://github.com/wkhtmltopdf/packaging/releases/download/${GLOBAL_STACK_WKHTMLTOPDF_VERSION}/wkhtmltox_${GLOBAL_STACK_WKHTMLTOPDF_VERSION}.${GLOBAL_STACK_WKHTMLTOPDF_DISTRO}_amd64.deb && apt-get --allow-unauthenticated install -y --no-install-recommends --fix-missing ./wkhtmltox_${GLOBAL_STACK_WKHTMLTOPDF_VERSION}.${GLOBAL_STACK_WKHTMLTOPDF_DISTRO}_amd64.deb && rm wkhtmltox_${GLOBAL_STACK_WKHTMLTOPDF_VERSION}.${GLOBAL_STACK_WKHTMLTOPDF_DISTRO}_amd64.deb) || echo -e "\n wkhtmltopdf will not be installed" \
    && usermod -u 1001 ubuntu \
    && (find / -user 1000 -exec chown -h 1001 {} \; 2>/dev/null || true) \
    && groupmod -g 1001 ubuntu \
    && (find / -group 1000 -exec chgrp -h 1001 {} \; 2>/dev/null || true) \
    && groupadd -f --gid "${GLOBAL_STACK_DOCKER_GROUP_UID}" "${GLOBAL_STACK_DOCKER_GROUP_ID}" \
    && useradd --uid "${GLOBAL_STACK_DOCKER_USER_UID}" -p "$(openssl passwd -6 "${GLOBAL_STACK_DOCKER_PASSWORD}")" --gid "${GLOBAL_STACK_DOCKER_GROUP_ID}" --shell /bin/bash --create-home "${GLOBAL_STACK_DOCKER_USER_ID}" \
    && adduser "${GLOBAL_STACK_DOCKER_USER_ID}" sudo \
    && echo "${GLOBAL_STACK_DOCKER_USER_ID} ALL = NOPASSWD : ALL" >> /etc/sudoers \
    && chmod 0440 /etc/sudoers \
    && GNUPGHOME="$(mktemp -d)" \
    && export GNUPGHOME \
    && rm -rf "$GNUPGHOME" \
    && shopt -s extdebug \
    && IFS=$'\n\t' \
    && find /usr/local/bin -type f -exec chmod a+x {} \; \
    && [ "${GLOBAL_STACK_DOCKER_IN_DOCKER}" = "true" ] && global-stack-base-install-docker-in-docker.sh || echo -e "\n Docker In Docker will not be installed" \
    && [ "${GLOBAL_STACK_INSTALL_GITLAB_RUNNER}" = "true" ] && global-stack-base-install-gitlab-runner.sh || echo -e "\n Gitlab runner will not be installed" \
    && [ "${GLOBAL_STACK_INSTALL_PODMAN}" = "true" ] && global-stack-base-install-podman.sh || echo -e "\n Podman will not be installed" \
    && [ "${GLOBAL_STACK_INSTALL_ANSIBLE}" = "true" ] && global-stack-base-install-ansible.sh || echo -e "\n Ansible will not be installed" \
    && [ "${GLOBAL_STACK_BASE_INSTALL_TOOLS}" = "true" ] && global-stack-base-install-tools.sh || echo -e "\n Tools will not be installed" \
    && global-stack-base-install-mkcert.sh \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /etc/apt/apt.conf.d/docker-clean \
    && mkdir -p ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/caroot \
    && chmod -R a+rwx ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/caroot \
    && [ "${GLOBAL_STACK_UNU}" = "true" ] && global-stack-base-unu.sh || echo -e "\n Will not upgrade the distribution"

USER "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}"

RUN mkcert -CAROOT ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/caroot -install \
    && shopt -s extdebug \
    && IFS=$'\n\t' \
    && eval "$(ssh-agent -s)"

CMD ["global-stack-base-sync-bin-n-exec.sh", "global-stack-base-start.sh"]
