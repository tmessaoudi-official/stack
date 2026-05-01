#!/bin/bash
# help.sh — usage text

[[ -n "${_GS_EU2_HELP_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_HELP_SH_LOADED=1

# shellcheck source=./../config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/defaults.sh"

_gs_eu2_show_help() {
  cat << EOF
bin/env-update.sh v${_GS_EU2_VERSION} — annotation parser + version checker (12 fetcher types)

Usage: env-update.sh [OPTIONS]

Options:
  --version               Print version and exit
  --help                  Show this help and exit
  --env-file=<path>       Source .env file (default: /stack/.env)
  --filter=<regex>        Only parse records whose env_var matches regex
  --dump                  Emit parsed records to stdout
  --format=<text|json>    Dump format (default: text)
  --check                 Fetch latest versions and stream [AUTO|HOLD|SKIP|ERROR] report
  --apply                 Apply all AUTO decisions to the env file; implies --check.
                          Creates a timestamped .env backup before writing.
                          Use with --dry-run to preview without writing.
  --no-cache              Bypass the fetch cache
  --cache-ttl=<seconds>   Cache TTL in seconds (default: 3600)
  --dry-run               No writes (gates cache, .env, and Dockerfile propagation).

Default (no flags): print a parser summary with per-type breakdown and hints.

Fetcher types: dockerhub, github, npm, pecl, pecl-git, pypi, quay, rubygems,
sdkman, sdkmanager, url, codeberg.

Examples:
  bin/env-update.sh                                # parser summary (no network)
  bin/env-update.sh --check                        # fetch all, stream report
  bin/env-update.sh --check --filter=POSTGRES      # fetch only POSTGRES* vars
  bin/env-update.sh --check --no-cache             # bypass cache
  bin/env-update.sh --dump --format=json | jq .    # structured record dump
  bin/env-update.sh --check --apply                # fetch + apply all AUTO updates
  bin/env-update.sh --check --apply --dry-run      # preview what would be applied
EOF
}
