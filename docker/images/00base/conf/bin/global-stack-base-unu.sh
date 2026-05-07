#!/bin/bash

set -euo pipefail

# Update and fix broken dependencies
sudo apt-get update --allow-releaseinfo-change
sudo dpkg --configure -a
sudo apt-get install -y --fix-broken --no-install-recommends --fix-missing

# Perform upgrades
sudo apt-get upgrade -y
sudo apt-get dist-upgrade -y
sudo apt-get full-upgrade -y

# Clean up unnecessary packages and cache
sudo apt-get purge -y
sudo apt-get autoremove -y
sudo apt-get clean -y
sudo apt-get autoclean -y
sudo apt-get autopurge -y

# Final update and cleanup of remaining cached files
sudo apt-get update --allow-releaseinfo-change
sudo rm -rf /var/lib/apt/lists/* /etc/apt/apt.conf.d/docker-clean