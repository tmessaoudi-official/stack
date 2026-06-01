#!/bin/bash

set -xeE -o pipefail

python setup.py --load-servers servers.json --user root