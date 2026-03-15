#!/bin/bash

# Load OS information
. /etc/os-release

# @todo change later
UBUNTU_CODENAME="questing"

# Update repositories
sudo apt-get -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change

# Add Ansible PPA key and repository
curl -fsSL 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x6125E2A8C77F2818FB7BD15B93C4A3FD7BB9C367' | gpg --dearmor | sudo tee /usr/share/keyrings/ansible.gpg
echo -e "Types: deb\nTrusted: yes\nSigned-By: /usr/share/keyrings/ansible.gpg\nArch: $(dpkg --print-architecture)\nURIs: https://ppa.launchpadcontent.net/ansible/ansible/ubuntu\nSuites: ${UBUNTU_CODENAME}\nComponents: main" | sudo tee /etc/apt/sources.list.d/ansible.sources

# Update repositories and install Ansible and Python3 argcomplete
sudo apt-get -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change
sudo apt-get --allow-unauthenticated install -y --no-install-recommends --fix-missing \
    ansible \
    python3-argcomplete

# Activate Python argument completion
sudo activate-global-python-argcomplete