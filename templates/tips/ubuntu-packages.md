. /etc/os-release

sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys E1DD270288B4E6030699E45FA1715D88E1DF1F24
sudo apt-key export E1DD270288B4E6030699E45FA1715D88E1DF1F24 | sudo gpg --dearmor | sudo dd of=/etc/apt/trusted.gpg.d/git.gpg
sudo echo "deb [trusted=yes signed-by=/etc/apt/trusted.gpg.d/git.gpg arch=$(dpkg --print-architecture)] https://ppa.launchpadcontent.net/git-core/ppa/ubuntu noble main" | sudo dd of=/etc/apt/sources.list.d/git.list

sudo wget -qO- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor | sudo dd of=/etc/apt/trusted.gpg.d/google-chrome.gpg 
sudo echo "deb [trusted=yes signed-by=/etc/apt/trusted.gpg.d/google-chrome.gpg arch=$(dpkg --print-architecture)] http://dl.google.com/linux/chrome/deb/ stable main" | sudo dd of=/etc/apt/sources.list.d/google-chrome.list

sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 6125E2A8C77F2818FB7BD15B93C4A3FD7BB9C367
sudo apt-key export 6125E2A8C77F2818FB7BD15B93C4A3FD7BB9C367 | sudo gpg --dearmor | sudo dd of=/etc/apt/trusted.gpg.d/ansible.gpg
sudo echo "deb [trusted=yes signed-by=/etc/apt/trusted.gpg.d/ansible.gpg arch=$(dpkg --print-architecture)] https://ppa.launchpadcontent.net/ansible/ansible/ubuntu noble main" | sudo dd of=/etc/apt/sources.list.d/ansible.list

sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
echo "deb [trusted=yes signed-by=/etc/apt/trusted.gpg.d/docker.gpg arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu noble stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

VERSION_ID=22.04
export VERSION_ID
sudo curl -fsSL https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/Release.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/podman.gpg
sudo echo "deb [trusted=yes signed-by=/etc/apt/trusted.gpg.d/podman.gpg arch=$(dpkg --print-architecture)] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/xUbuntu_${VERSION_ID}/ /" | sudo tee /etc/apt/sources.list.d/podman.list

sudo apt-key adv \
    --keyserver hkp://keyserver.ubuntu.com:80 \
    --recv-keys 14AA40EC0831756756D7F66C4F4EA0AAE5267A6C
sudo apt-key export 14AA40EC0831756756D7F66C4F4EA0AAE5267A6C | sudo gpg --dearmor | sudo dd of=/etc/apt/trusted.gpg.d/php.gpg
sudo sh -c 'echo "deb [trusted=yes signed-by=/etc/apt/trusted.gpg.d/php.gpg arch=$(dpkg --print-architecture)] http://ppa.launchpad.net/ondrej/php/ubuntu noble main" > /etc/apt/sources.list.d/php-noble-main.list'

sudo apt-get --allow-unauthenticated install -y --no-install-recommends --fix-missing usbutils clang cmake ninja-build libblkid-dev android-sdk-platform-tools-common tzdata sudo locales iptables bash-completion pkg-config libpq-dev fontforge ttfautohint zlib1g-dev libpcre3-dev libpcre2-8-0 libpcre3 libpcre3-dev g++ aptitude jq vim rsync wget zip nano unzip openssl libssl-dev gnupg gnupg2 software-properties-common apt-transport-https ca-certificates curl lsb-release ssh dnsutils less debootstrap make gcc build-essential autoconf automake autotools-dev gettext mercurial supervisor libgtk2.0-0 libgtk-3-0 libgtk-3-dev libgbm-dev libnotify-dev libnss3 libxss1 libasound2-dev libxtst6 xauth xvfb libxml2 libxml2-dev golang libnss3-tools libbz2-dev libreadline-dev libsqlite3-dev liblzma-dev mysql-client openssh-client postgresql-client python3 python3-pip libyaml-dev git google-chrome-stable ansible python3-argcomplete docker-ce docker-ce-cli containerd.io subversion libnghttp2-dev libjansson-dev libtool-bin libnghttp2-14 python-is-python3 libexpat1-dev libapr1-dev libaprutil1-dev zlib1g libunwind-dev libxslt-dev libgd-dev libgeoip-dev libmaxminddb-dev libbrotli-dev libnghttp2-dev libtool uuid-dev libperl-dev libtinfo6 bison re2c libzip4 libzip-dev libedit-dev libxslt1-dev libxslt1.1 libonig-dev imagemagick libmagick++-dev libmagickwand-dev libmagickcore-dev graphicsmagick libjpeg-turbo8 libjpeg8 ghostscript libpng-dev libwebp-dev libxpm-dev libfreetype6-dev graphviz libzmq3-dev libicu-dev icu-devtools libmariadb-dev libpq5 libsodium-dev libxpm4 libltdl-dev libgd3 libmhash2 libmhash-dev libmcrypt4 libmcrypt-dev libgmp-dev libmemcached-dev bsdmainutils libldb-dev libldap2-dev librabbitmq-dev libssh2-1 libssh2-1-dev libargon2-1 libargon2-dev libidn2-0 libzstd1 libgpgme-dev libc-ares-dev libsystemd-dev php8.4-cli php8.4-phar php8.4-readline php8.4-bz2 php8.4-xml php8.4-curl php8.4-sqlite3 llvm libncurses5-dev tk-dev libxmlsec1-dev libffi-dev libncursesw5-dev xz-utils libnss3-tools sudo