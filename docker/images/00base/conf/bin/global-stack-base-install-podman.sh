#!/bin/bash

# @todo check-updates
sudo apt-get -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change
curl -fsSL https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/${GLOBAL_STACK_PODMAN_CHANEL}/Release.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/podman.gpg
echo "deb [trusted=yes signed-by=/etc/apt/trusted.gpg.d/podman.gpg arch=$(dpkg --print-architecture)] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/${GLOBAL_STACK_PODMAN_CHANEL}/ /" | sudo tee /etc/apt/sources.list.d/podman.list
sudo apt-get -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change
sudo apt-get -y --no-install-recommends --fix-missing install podman

sudo curl -L https://raw.githubusercontent.com/containers/podman-compose/${GLOBAL_STACK_PODMAN_COMPOSE_VERSION}/podman_compose.py -o /usr/local/bin/podman-compose
sudo chmod a+rwx /usr/local/bin/podman-compose