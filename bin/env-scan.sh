#!/bin/bash
set -eEuo pipefail
trap 'printf "env-scan: error in %s at line %d: %s\n" "${BASH_SOURCE[0]}" "${LINENO}" "${BASH_COMMAND}" >&2' ERR

_GS_ES_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/env-scan"
source "${_GS_ES_LIB_DIR}/config/defaults.sh"
source "${_GS_ES_LIB_DIR}/reporting/help.sh"
source "${_GS_ES_LIB_DIR}/core/args.sh"
source "${_GS_ES_LIB_DIR}/core/extract.sh"
source "${_GS_ES_LIB_DIR}/core/merge.sh"
source "${_GS_ES_LIB_DIR}/reporting/report.sh"
source "${_GS_ES_LIB_DIR}/reporting/profile.sh"
source "${_GS_ES_LIB_DIR}/core/missing.sh"
source "${_GS_ES_LIB_DIR}/main.sh"

gs_es_main "${@}"
