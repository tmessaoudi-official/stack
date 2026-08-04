. /etc/os-release

# ── APT configuration ────────────────────────────────────────────────────────

echo 'APT::Key::Assert-Pubkey-Algo "";' | sudo tee /etc/apt/apt.conf.d/99weakkey-warning > /dev/null

# ── Architecture setup ────────────────────────────────────────────────────────

sudo dpkg --add-architecture i386
sudo dpkg --remove-architecture i386

# ── Third-party APT sources (keyrings + .sources files) ──────────────────────

# PostgreSQL
sudo curl -o /usr/share/keyrings/postgresql.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
sudo sh -c 'echo "Types: deb\nSigned-By: /usr/share/keyrings/postgresql.asc\nArch: $(dpkg --print-architecture)\nURIs: https://apt.postgresql.org/pub/repos/apt\nSuites: ${UBUNTU_CODENAME}-pgdg\nComponents: main" > /etc/apt/sources.list.d/pgdg.sources'

# Git PPA
sudo curl -fsSL 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF911AB184317630C59970973E363C90F8F1B6217' | gpg --dearmor | sudo tee /usr/share/keyrings/git.gpg
sudo echo -e "Types: deb\nSigned-By: /usr/share/keyrings/git.gpg\nArch: $(dpkg --print-architecture)\nURIs: https://ppa.launchpadcontent.net/git-core/ppa/ubuntu\nSuites: $(lsb_release -cs)\nComponents: main" | sudo dd of=/etc/apt/sources.list.d/git.sources

# Google Chrome
sudo curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor | sudo dd of=/usr/share/keyrings/google-chrome.gpg
sudo echo -e "Types: deb\nSigned-By: /usr/share/keyrings/google-chrome.gpg\nArch: $(dpkg --print-architecture)\nURIs: http://dl.google.com/linux/chrome/deb/\nSuites: stable\nComponents: main" | sudo dd of=/etc/apt/sources.list.d/google-chrome.sources

# Docker CE
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
sudo echo -e "Types: deb\nSigned-By: /usr/share/keyrings/docker.gpg\nArch: $(dpkg --print-architecture)\nURIs: https://download.docker.com/linux/ubuntu\nSuites: ${UBUNTU_CODENAME}\nComponents: stable" | sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null

# Podman
sudo curl -fsSL https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/${GLOBAL_STACK_PODMAN_CHANEL}/Release.key | sudo gpg --dearmor -o /usr/share/keyrings/podman.gpg
sudo echo -e "Types: deb\nSigned-By: /usr/share/keyrings/podman.gpg\nArch: $(dpkg --print-architecture)\nURIs: https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/${GLOBAL_STACK_PODMAN_CHANEL}/\nSuites: /" | sudo tee /etc/apt/sources.list.d/podman.sources

# Ansible
sudo curl -fsSL 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x6125E2A8C77F2818FB7BD15B93C4A3FD7BB9C367' | gpg --dearmor | sudo tee /usr/share/keyrings/ansible.gpg
sudo echo -e "Types: deb\nSigned-By: /usr/share/keyrings/ansible.gpg\nArch: $(dpkg --print-architecture)\nURIs: https://ppa.launchpadcontent.net/ansible/ansible/ubuntu\nSuites: resolute\nComponents: main" | sudo tee /etc/apt/sources.list.d/ansible.sources

# GitLab Runner
sudo curl -o /tmp/gitlab-runner.sh "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh"
sudo chmod a+x /tmp/gitlab-runner.sh
sudo os=ubuntu dist=resolute /tmp/gitlab-runner.sh
sudo rm /tmp/gitlab-runner.sh /etc/apt/sources.list.d/runner_gitlab-runner.list
echo -e "Types: deb\nSigned-By: /etc/apt/keyrings/runner_gitlab-runner-archive-keyring.gpg\nArch: $(dpkg --print-architecture)\nURIs: https://packages.gitlab.com/runner/gitlab-runner/ubuntu/\nSuites: resolute\nComponents: main\n\nTypes: deb-src\nSigned-By: /etc/apt/keyrings/runner_gitlab-runner-archive-keyring.gpg\nArch: $(dpkg --print-architecture)\nURIs: https://packages.gitlab.com/runner/gitlab-runner/ubuntu/\nSuites: resolute\nComponents: main" | sudo dd of=/etc/apt/sources.list.d/runner_gitlab-runner.sources


sudo apt-get update --allow-releaseinfo-change

# ── Locale and timezone ───────────────────────────────────────────────────────

sudo apt-get install -y --no-install-recommends --fix-missing tzdata
sudo dpkg-reconfigure tzdata

# ── Core system tools ─────────────────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    sudo \
    sendmail \
    locales \
    iptables \
    bash-completion \
    pkg-config \
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
    openssh-client \
    dnsutils \
    less \
    make \
    bsdextrautils \
    bsdmainutils \
    iputils-ping \
    usbutils \

# ── Build tools and compilers ─────────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    gcc \
    g++ \
    build-essential \
    autoconf \
    automake \
    autotools-dev \
    gettext \
    clang \
    llvm \
    ninja-build \
    cmake \
    bison \
    re2c \
    debootstrap \

# ── Language runtimes ─────────────────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    golang \
    python3 \
    python3-pip \
    python3-argcomplete \

# ── PHP (base CLI for bootstrapping) ─────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    systemtap-sdt-dev \
    libsnmp-dev \
    libtidy-dev \
    php8.5-cli \
    php8.5-phar \
    php8.5-readline \
    php8.5-bz2 \
    php8.5-xml \
    php8.5-curl \
    php8.5-sqlite3 \

# ── Database clients ──────────────────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    mysql-client \
    postgresql-client-18 \
    libpq-dev \
    libpq5 \

# ── Container and DevOps tools ────────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    gitlab-runner \
    podman \
    ansible \

# ── Image and font processing ─────────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
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
    libxpm4 \
    libfreetype6-dev \
    fontforge \
    ttfautohint \
    graphviz \
    libfontconfig1 \
    libxrender1 \

# ── GTK and display (for headless browser / Cypress / Electron testing) ───────

sudo apt-get install -y --fix-missing \
    libgtk2.0-0 \
    libgtk-3-0 \
    libgtk-3-dev \
    libgbm-dev \
    libnotify-dev \
    libnss3 \
    libnss3-tools \
    libxss1 \
    libxtst6 \
    xauth \
    xvfb \
    libglu1-mesa \
    mesa-utils \

# ── Audio ─────────────────────────────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    libasound2-dev \

# ── Compression and archive ───────────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    zlib1g-dev \
    libbz2-dev \
    liblzma-dev \
    libzip5 \
    libzip-dev \
    xz-utils \

# ── Cryptography and security ─────────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    libsodium-dev \
    libgpgme-dev \
    libcjose-dev \
    libjansson-dev \
    libargon2-1 \
    libargon2-dev \
    libssh2-1 \
    libssh2-1-dev \

# ── Networking and protocols ──────────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    libc-ares-dev \
    libidn2-0 \
    httpie \
    ripgrep \

# ── XML / HTML / XSLT ────────────────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    libxml2-16 \
    libxml2-dev \
    libxslt1-dev \
    libxslt1.1 \
    libxmlsec1-dev \

# ── Database and message queue client libs ────────────────────────────────────

sudo apt-get install -y --fix-missing \
    libmariadb-dev \
    libmemcached-dev \
    librabbitmq-dev \
    libzmq3-dev \

# ── LDAP ─────────────────────────────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    libldb-dev \
    libldap2-dev \
    && sudo ln -s /usr/lib/x86_64-linux-gnu/libldap.so /usr/lib/libldap.so \
    && sudo ln -s /usr/lib/x86_64-linux-gnu/liblber.so /usr/lib/liblber.so \

# ── GD and graphics (PHP gd extension deps) ───────────────────────────────────

sudo apt-get install -y --fix-missing \
    libgd3 \
    libgoffice-0.10-10t64 \
    libgoffice-0.10-dev \

# ── Math, encoding, locale ────────────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    libgmp-dev \
    libicu-dev \
    icu-devtools \
    libyaml-dev \
    libedit-dev \
    libreadline-dev \
    libsqlite3-dev \
    libpcre3-dev \
    libpcre2-8-0 \
    libpcre3 \
    libzstd1 \
    libbrotli-dev \
    libstdc++6 \

# ── Miscellaneous C libs ──────────────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    libmhash2 \
    libmhash-dev \
    libmcrypt4 \
    libmcrypt-dev \
    libltdl-dev \
    libtinfo6 \
    libncurses5-dev \
    libncursesw5-dev \
    libsystemd-dev \
    libblkid-dev \

# ── Python build deps (pyenv) ─────────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    tk-dev \
    libffi-dev \

# ── Android / mobile development ─────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    android-sdk-platform-tools-common \
    libc6:amd64 \
    lib32z1 \
    libbz2-1.0:amd64 \

# ── Source control ────────────────────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    git \
    mercurial \

# ── Process supervision ───────────────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    supervisor \

# ── Google Chrome stable ──────────────────────────────────────────────────────

sudo apt-get install -y --fix-missing \
    google-chrome-stable \
    && sudo rm -rf /etc/apt/sources.list.d/google-chrome.list \

# ── watcher-c (inotify-based file watcher, for FrankenPHP) ───────────────────

    && sudo mkdir /tmp/watcher-c \
    && cd /tmp/watcher-c \
    && sudo curl -fsSL -o "watcher-${GLOBAL_STACK_FRANKENPHP_WATCHER_VERSION}.tar.gz" "https://api.github.com/repos/e-dant/watcher/tarball/${GLOBAL_STACK_FRANKENPHP_WATCHER_VERSION}" \
    && sudo tar -xf watcher-${GLOBAL_STACK_FRANKENPHP_WATCHER_VERSION}.tar.gz --strip-components 1 -C /tmp/watcher-c \
    && sudo rm -rf watcher-${GLOBAL_STACK_FRANKENPHP_WATCHER_VERSION}.tar.gz \
    && sudo cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
    && sudo cmake --build build \
    && sudo cmake --install build \
    && sudo ldconfig \
    && sudo rm -rf /tmp/watcher-c \
    && ulimit -c unlimited

# Note: default-libmysqlclient-dev is an alternative to libmariadb-dev
# (add just after libffi-dev if needed)

# ── GitLab Runner post-install ────────────────────────────────────────────────

mkdir -p /home/"${GLOBAL_STACK_DOCKER_USER_ID}"/.gitlab-runner/
sudo cp /etc/gitlab-runner/config.toml "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.gitlab-runner/config.toml"
sudo chmod a+rwx "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.gitlab-runner/config.toml"
sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}" /home/"${GLOBAL_STACK_DOCKER_USER_ID}"/.gitlab-runner/

# ── Python argcomplete ────────────────────────────────────────────────────────

sudo activate-global-python-argcomplete

# ── Locale (Android) ─────────────────────────────────────────────────────────

[ "true" = "${GLOBAL_STACK_ANDROID_SET_LOCALE}" ] && global-stack-base-setup-locale.sh "${GLOBAL_STACK_ANDROID_LOCALE}" || echo -e "\n Locale will not be set"
