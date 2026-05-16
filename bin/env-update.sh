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

# Capture the exit code from _gs_eu2_main to allow intentional non-zero returns
# (e.g. _gs_eu2_run_check returns 1 when ERROR decisions are present) without
# triggering the ERR trap, which is reserved for unexpected failures.
_gs_eu2_main "${@}" || exit $?
