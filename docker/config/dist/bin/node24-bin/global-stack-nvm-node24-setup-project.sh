#!/bin/bash

set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

# if [[ -n "${NODE_INSTALL_PACKAGE_CORDOVA_VERSION:-}" && "" != "${NODE_INSTALL_PACKAGE_CORDOVA_VERSION:-}" ]]; then
#   # cordova telemetry off
# fi

if [[ -n "${NODE_INSTALL_PACKAGE_IONIC_CLI_VERSION:-}" && "" != "${NODE_INSTALL_PACKAGE_IONIC_CLI_VERSION:-}" ]]; then
  ionic config set -g telemetry false
  ionic config set -g npmClient npm
fi

if [[ -n "${NODE_INSTALL_PACKAGE_ANGULAR_CLI_VERSION:-}" && "" != "${NODE_INSTALL_PACKAGE_ANGULAR_CLI_VERSION:-}" ]]; then
  ng config --global cli.packageManager npm
fi

# if [[ -n "${NODE_INSTALL_PACKAGE_NX_VERSION:-}" && "" != "${NODE_INSTALL_PACKAGE_NX_VERSION:-}" ]]; then
# #  nx config --global cli.packageManager npm
# fi
