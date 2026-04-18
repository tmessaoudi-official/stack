#!/bin/bash
# help.sh — usage text

[[ -n "${_GS_EU2_HELP_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_HELP_SH_LOADED=1

# shellcheck source=./../config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/defaults.sh"

_gs_eu2_show_help() {
  cat << EOF
bin/env-update-v2.sh v${_GS_EU2_VERSION} — annotation parser + dockerhub version checker

Usage: env-update-v2.sh [OPTIONS]

Options:
  --version               Print version and exit
  --help                  Show this help and exit
  --env-file=<path>       Source .env file (default: /stack/.env)
  --filter=<regex>        Only parse records whose env_var matches regex
  --dump                  Emit parsed records to stdout
  --format=<text|json>    Dump format (default: text)
  --check                 Fetch latest versions and stream [AUTO|HOLD|SKIP|ERROR] report
  --no-cache              Bypass the fetch cache
  --cache-ttl=<seconds>   Cache TTL in seconds (default: 3600)
  --dry-run               No-op placeholder; Phase 2 gates cache writes. Reserved for
                          future phases that will gate .env writes.

Default (no flags): print a parser summary with per-type breakdown and hints.

Phase 2 fetcher support: dockerhub only.
Remaining fetchers (github, npm, pecl, pypi, quay, rubygems, sdkman, url) are
planned for Phase 3+. Non-dockerhub records show [SKIP] with an informational note.

Examples:
  bin/env-update-v2.sh                                # parser summary (no network)
  bin/env-update-v2.sh --check                        # fetch all, stream report
  bin/env-update-v2.sh --check --filter=POSTGRES      # fetch only POSTGRES* vars
  bin/env-update-v2.sh --check --no-cache             # bypass cache
  bin/env-update-v2.sh --dump --format=json | jq .    # structured record dump
EOF
}
