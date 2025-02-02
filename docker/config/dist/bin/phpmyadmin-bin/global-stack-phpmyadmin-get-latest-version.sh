#!/bin/bash

echo "$(curl --silent https://api.github.com/repos/phpmyadmin/phpmyadmin/tags | jq .[0].name -r)"
