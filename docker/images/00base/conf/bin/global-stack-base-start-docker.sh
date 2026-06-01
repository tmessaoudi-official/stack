#!/bin/bash

set -euo pipefail

sudo touch /var/log/docker-$(date '+%d-%m-%Y').log
sudo chmod a+rwx /var/log/docker-$(date '+%d-%m-%Y').log

sudo dockerd > /var/log/docker-$(date '+%d-%m-%Y').log 2>&1 & 
echo "Waiting for docker socket..."
until [ -S /var/run/docker.sock ]; do sleep 0.5; done
echo "Correcting socket permissions"
sudo chmod 666 /var/run/docker.sock