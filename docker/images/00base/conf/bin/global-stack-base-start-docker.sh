#!/bin/bash

set -euo pipefail

sudo touch /var/log/docker-$(date '+%d-%m-%Y').log
sudo chmod a+rwx /var/log/docker-$(date '+%d-%m-%Y').log

sudo dockerd > /var/log/docker-$(date '+%d-%m-%Y').log 2>&1 & 
sleep 05
echo "Correcting socket permissions"
sudo chmod 666 /var/run/docker.sock 1> /dev/null 2> /dev/null