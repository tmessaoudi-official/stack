#!/bin/bash

set -xeE -o pipefail

echo "$(curl --silent https://api.github.com/repos/phpmyadmin/phpmyadmin/tags | jq .[0].name -r)"
