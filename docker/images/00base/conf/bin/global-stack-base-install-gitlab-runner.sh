#!/bin/bash

sudo apt-get -o Acquire::AllowInsecureRepositories=true update --allow-releaseinfo-change
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo ${GLOBAL_STACK_SHELL}
sudo apt-get --allow-unauthenticated install -y --no-install-recommends --fix-missing gitlab-runner
sudo cp /etc/gitlab-runner/config.toml "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.gitlab-runner/config.toml"
sudo chmod a+rwx "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.gitlab-runner/config.toml"
sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}" /home/"${GLOBAL_STACK_DOCKER_USER_ID}"/.gitlab-runner/