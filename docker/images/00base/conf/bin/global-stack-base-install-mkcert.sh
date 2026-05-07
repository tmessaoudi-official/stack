#!/bin/bash

set -euo pipefail

# STACK_MKCERT_LATEST_VERSION=$(curl --silent https://api.github.com/repos/FiloSottile/mkcert/releases/latest | jq .tag_name -r )
STACK_MKCERT_LATEST_VERSION=${GLOBAL_STACK_MKCERT_VERSION}

curl -fsSL -o /usr/local/bin/mkcert "https://github.com/FiloSottile/mkcert/releases/download/${STACK_MKCERT_LATEST_VERSION}/mkcert-${STACK_MKCERT_LATEST_VERSION}-linux-amd64"
sudo chmod a+x /usr/local/bin/mkcert