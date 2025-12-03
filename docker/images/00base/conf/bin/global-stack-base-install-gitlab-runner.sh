#!/bin/bash

sudo apt-get -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change
sudo curl -o /tmp/gitlab-runner.sh "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh"
sudo chmod a+x /tmp/gitlab-runner.sh
# @todo check for updates
sudo os=ubuntu dist=plucky /tmp/gitlab-runner.sh
sudo rm /tmp/gitlab-runner.sh /etc/apt/sources.list.d/runner_gitlab-runner.list
echo -e "Types: deb\nTrusted: yes\nSigned-By: /usr/share/keyrings/runner_gitlab-runner-archive-keyring.gpg\nArch: $(dpkg --print-architecture)\nURIs: https://packages.gitlab.com/runner/gitlab-runner/ubuntu/\nSuites: plucky\nComponents: main\n\nTypes: deb-src\nTrusted: yes\nSigned-By: /usr/share/keyrings/runner_gitlab-runner-archive-keyring.gpg\nArch: $(dpkg --print-architecture)\nURIs: https://packages.gitlab.com/runner/gitlab-runner/ubuntu/\nSuites: plucky\nComponents: main" | sudo dd of=/etc/apt/sources.list.d/runner_gitlab-runner.sources \
sudo apt-get --allow-unauthenticated install -y --no-install-recommends --fix-missing gitlab-runner
sudo cp /etc/gitlab-runner/config.toml "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.gitlab-runner/config.toml"
sudo chmod a+rwx "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.gitlab-runner/config.toml"
sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}" /home/"${GLOBAL_STACK_DOCKER_USER_ID}"/.gitlab-runner/