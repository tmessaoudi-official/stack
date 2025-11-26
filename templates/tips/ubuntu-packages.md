. /etc/os-release

echo 'APT::Key::Assert-Pubkey-Algo "";' | sudo tee /etc/apt/apt.conf.d/99weakkey-warning > /dev/null

sudo dpkg --add-architecture i386
sudo dpkg --remove-architecture i386

sudo curl -o /usr/share/keyrings/postgresql.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
sudo sh -c 'echo "Types: deb\nTrusted: yes\nSigned-By: /usr/share/keyrings/postgresql.asc\nArch: $(dpkg --print-architecture)\nURIs: https://apt.postgresql.org/pub/repos/apt\nSuites: questing-pgdg\nComponents: main" > /etc/apt/sources.list.d/pgdg.sources'
sudo curl -fsSL 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF911AB184317630C59970973E363C90F8F1B6217' | gpg --dearmor | sudo tee /usr/share/keyrings/git.gpg
sudo echo -e "Types: deb\nTrusted: yes\nSigned-By: /usr/share/keyrings/git.gpg\nArch: $(dpkg --print-architecture)\nURIs: https://ppa.launchpadcontent.net/git-core/ppa/ubuntu\nSuites: $(lsb_release -cs)\nComponents: main" | sudo dd of=/etc/apt/sources.list.d/git.sources
sudo wget -qO- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor | sudo dd of=/usr/share/keyrings/google-chrome.gpg
sudo echo -e "Types: deb\nTrusted: yes\nSigned-By: /usr/share/keyrings/google-chrome.gpg\nArch: $(dpkg --print-architecture)\nURIs: http://dl.google.com/linux/chrome/deb/\nSuites: stable\nComponents: main" | sudo dd of=/etc/apt/sources.list.d/google-chrome.sources
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
sudo echo -e "Types: deb\nTrusted: yes\nSigned-By: /usr/share/keyrings/docker.gpg\nArch: $(dpkg --print-architecture)\nURIs: https://download.docker.com/linux/ubuntu\nSuites: questing\nComponents: stable" | sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null
sudo curl -fsSL https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/${GLOBAL_STACK_PODMAN_CHANEL}/Release.key | sudo gpg --dearmor -o /usr/share/keyrings/podman.gpg
sudo echo -e "Types: deb\nTrusted: yes\nSigned-By: /usr/share/keyrings/podman.gpg\nArch: $(dpkg --print-architecture)\nURIs: https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/${GLOBAL_STACK_PODMAN_CHANEL}/\nSuites: /" | sudo tee /etc/apt/sources.list.d/podman.sources
sudo curl -fsSL 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x6125E2A8C77F2818FB7BD15B93C4A3FD7BB9C367' | gpg --dearmor | sudo tee /usr/share/keyrings/ansible.gpg
sudo echo -e "Types: deb\nTrusted: yes\nSigned-By: /usr/share/keyrings/ansible.gpg\nArch: $(dpkg --print-architecture)\nURIs: https://ppa.launchpadcontent.net/ansible/ansible/ubuntu\nSuites: plucky\nComponents: main" | sudo tee /etc/apt/sources.list.d/ansible.sources
sudo curl -o /tmp/gitlab-runner.sh "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh"
sudo chmod a+x /tmp/gitlab-runner.sh
sudo os=ubuntu dist=oracular /tmp/gitlab-runner.sh
sudo rm /tmp/gitlab-runner.sh /etc/apt/sources.list.d/runner_gitlab-runner.list
echo -e "Types: deb\nTrusted: yes\nSigned-By: /usr/share/keyrings/runner_gitlab-runner-archive-keyring.gpg\nArch: $(dpkg --print-architecture)\nURIs: https://packages.gitlab.com/runner/gitlab-runner/ubuntu/\nSuites: noble\nComponents: main\n\nTypes: deb-src\nTrusted: yes\nSigned-By: /usr/share/keyrings/runner_gitlab-runner-archive-keyring.gpg\nArch: $(dpkg --print-architecture)\nURIs: https://packages.gitlab.com/runner/gitlab-runner/ubuntu/\nSuites: noble\nComponents: main" | sudo dd of=/etc/apt/sources.list.d/runner_gitlab-runner.sources


sudo apt-get -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change

sudo apt-get --allow-unauthenticated install -y --no-install-recommends --fix-missing tzdata

sudo dpkg-reconfigure tzdata

sudo apt-get --allow-unauthenticated install -y --fix-missing \
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
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    gitlab-runner \
    podman \
    ansible \
    python3-argcomplete \
    libtinfo6 \
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
    php8.4-cli \
    php8.4-phar \
    php8.4-readline \
    php8.4-bz2 \
    php8.4-xml \
    php8.4-curl \
    php8.4-sqlite3 \
    llvm \
    libncurses5-dev \
    tk-dev \
    libxmlsec1-dev \
    libffi-dev \
    libncursesw5-dev \
    xz-utils \
    usbutils \
    clang \
    ninja-build \
    libblkid-dev \
    android-sdk-platform-tools-common \
    libglu1-mesa \
    libc6:amd64 \
    lib32z1 \
    libbz2-1.0:amd64 \
    && sudo ln -s /usr/lib/x86_64-linux-gnu/libldap.so /usr/lib/libldap.so \
    && sudo ln -s /usr/lib/x86_64-linux-gnu/liblber.so /usr/lib/liblber.so \
    && sudo mkdir /tmp/watcher-c \
    && cd /tmp/watcher-c \
    && sudo wget -O watcher-${GLOBAL_STACK_FRANKENPHP_WATCHER_VERSION}.tar.gz https://api.github.com/repos/e-dant/watcher/tarball/${GLOBAL_STACK_FRANKENPHP_WATCHER_VERSION} \
    && sudo tar -xf watcher-${GLOBAL_STACK_FRANKENPHP_WATCHER_VERSION}.tar.gz --strip-components 1 -C /tmp/watcher-c \
    && sudo rm -rf watcher-${GLOBAL_STACK_FRANKENPHP_WATCHER_VERSION}.tar.gz \
    && sudo cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
    && sudo cmake --build build \
    && sudo cmake --install build \
    && sudo ldconfig \
    && sudo rm -rf /tmp/watcher-c \
    && ulimit -c unlimited \
    && sudo rm -rf /etc/apt/sources.list.d/google-chrome.list

# just after libffi-dev
# default-libmysqlclient-dev \

mkdir -p /home/"${GLOBAL_STACK_DOCKER_USER_ID}"/.gitlab-runner/
sudo cp /etc/gitlab-runner/config.toml "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.gitlab-runner/config.toml"
sudo chmod a+rwx "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.gitlab-runner/config.toml"
sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}" /home/"${GLOBAL_STACK_DOCKER_USER_ID}"/.gitlab-runner/

sudo activate-global-python-argcomplete

[ "true" = "${GLOBAL_STACK_ANDROID_SET_LOCALE}" ] && global-stack-base-setup-locale.sh "${GLOBAL_STACK_ANDROID_LOCALE}" || echo -e "\n Locale will not be set" \