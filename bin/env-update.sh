#!/usr/bin/env bash
# bin/env-update.sh — annotation parser + version checker
#
# Phase 1: parse .env annotations → structured records → dump
# No network, no writes, no version comparison.
#
# Usage:
#   bin/env-update.sh --dump
#   bin/env-update.sh --filter=POSTGRES --dump
#   bin/env-update.sh --dump --format=json | jq .
#
set -eEuo pipefail
trap 'printf "env-update: error in %s at line %d: %s\n" "${BASH_SOURCE[0]}" "${LINENO}" "${BASH_COMMAND}" >&2' ERR

# shellcheck disable=SC1091
# shellcheck source=./lib/env-update/main.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/env-update/main.sh"

_gs_eu2_main "${@}"
