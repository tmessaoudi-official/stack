#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

pyenv install --verbose --skip-existing --keep "${PYENV_VERSION}"