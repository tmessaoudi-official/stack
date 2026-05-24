#!/usr/bin/env bash
# env-update.sh — .env annotation parser, version fetcher, and optional updater.
#
# Exports:   none (entry point — sources main.sh and delegates)
# Sources:   bin/lib/env-update/main.sh (full library tree)
# Deps:      bash 4.3+, curl, jq, perl, sort (GNU coreutils)
# Env:       _GS_EU2_CFG (associative array — populated by args.sh via main.sh)
#
# Two-step safety model:
#   1. Run with --check (or --dry-run --apply) to preview decisions — no writes.
#   2. Run with --apply only after reviewing the dry-run output (30-min session gate).
#
# Usage:
#   bin/env-update.sh --dump                         # parse .env, show all records
#   bin/env-update.sh --filter=POSTGRES --dump       # filter by variable name regex
#   bin/env-update.sh --dump --format=json | jq .    # machine-readable JSON
#   bin/env-update.sh --check                        # fetch latest versions, preview
#   bin/env-update.sh --dry-run --apply              # preview apply changes
#   bin/env-update.sh --apply                        # apply AUTO decisions (after dry-run)
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
