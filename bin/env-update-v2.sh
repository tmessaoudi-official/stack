#!/usr/bin/env bash
# bin/env-update-v2.sh — annotation parser + version checker (replaces env-update.sh)
#
# Phase 1: parse .env annotations → structured records → dump
# No network, no writes, no version comparison.
#
# Usage:
#   bin/env-update-v2.sh --dump
#   bin/env-update-v2.sh --filter=POSTGRES --dump
#   bin/env-update-v2.sh --dump --format=json | jq .
#
set -euo pipefail

# shellcheck source=./lib/env-update-v2/main.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/env-update-v2/main.sh"

_gs_eu2_main "${@}"
