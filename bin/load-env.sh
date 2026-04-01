#!/bin/bash
# set -euo pipefail

_GS_LE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/load-env"
source "${_GS_LE_LIB_DIR}/config/defaults.sh"
source "${_GS_LE_LIB_DIR}/reporting/help.sh"
source "${_GS_LE_LIB_DIR}/core/args.sh"
source "${_GS_LE_LIB_DIR}/core/extract.sh"
source "${_GS_LE_LIB_DIR}/core/merge.sh"
source "${_GS_LE_LIB_DIR}/reporting/report.sh"
source "${_GS_LE_LIB_DIR}/reporting/profile.sh"
source "${_GS_LE_LIB_DIR}/core/missing.sh"
source "${_GS_LE_LIB_DIR}/main.sh"

le_main "${@}"
