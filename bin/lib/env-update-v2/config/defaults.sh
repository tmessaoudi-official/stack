#!/bin/bash
# defaults.sh — _GS_EU2_CFG defaults

[[ -n "${_GS_EU2_DEFAULTS_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_DEFAULTS_SH_LOADED=1

readonly _GS_EU2_VERSION="0.2.0"

declare -Ag _GS_EU2_CFG

# Override-able env vars (consumed by cache.sh and http/curl.sh)
# Set before sourcing to redirect cache or inject fixtures in tests.
# _GS_EU2_CACHE_DIR — flat-file cache directory (default: /tmp/global-stack-env-update-v2-cache)
# _GS_EU2_CACHE_TTL — TTL in seconds (default: 3600)
# _GS_EU2_HTTP_FIXTURE_DIR — if set, HTTP GET reads files instead of calling curl
