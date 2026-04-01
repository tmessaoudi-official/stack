#!/bin/bash
# set -euo pipefail

_LE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/load-env"
source "${_LE_LIB_DIR}/config.sh"
source "${_LE_LIB_DIR}/help.sh"
source "${_LE_LIB_DIR}/args.sh"
source "${_LE_LIB_DIR}/extract.sh"
source "${_LE_LIB_DIR}/merge.sh"
source "${_LE_LIB_DIR}/report.sh"
source "${_LE_LIB_DIR}/missing.sh"
source "${_LE_LIB_DIR}/main.sh"

le_main "${@}"
