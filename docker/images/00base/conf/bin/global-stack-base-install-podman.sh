#!/bin/bash

# @todo check-updates
sudo apt-get -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change
curl -fsSL https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/${GLOBAL_STACK_PODMAN_CHANNEL}/Release.key | sudo gpg --dearmor -o /usr/share/keyrings/podman.gpg
echo -e "Types: deb\nTrusted: yes\nSigned-By: /usr/share/keyrings/podman.gpg\nArch: $(dpkg --print-architecture)\nURIs: https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/${GLOBAL_STACK_PODMAN_CHANNEL}/\nSuites: /" | sudo tee /etc/apt/sources.list.d/podman.sources
sudo apt-get -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change
sudo apt-get -y --no-install-recommends --fix-missing install podman

sudo curl -L https://raw.githubusercontent.com/containers/podman-compose/${GLOBAL_STACK_PODMAN_COMPOSE_VERSION}/podman_compose.py -o /usr/local/bin/podman-compose
sudo chmod a+rwx /usr/local/bin/podman-compose