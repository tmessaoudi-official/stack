#!/bin/bash

set -xeE -o pipefail

echo "$(curl --connect-timeout 30 --max-time 300 --silent https://api.github.com/repos/phpmyadmin/phpmyadmin/tags | jq .[0].name -r)"
