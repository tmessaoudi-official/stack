#!/bin/bash
# defaults.sh — global constants and _GS_EU2_CFG associative array declaration.
#
# Exports:   _GS_EU2_VERSION (readonly string), _GS_EU2_CFG (associative array)
# Sources:   none
# Deps:      bash 4.3+ (declare -Ag for global associative array)
# Env:       (test hooks — set before sourcing to override defaults)
#              _GS_EU2_CACHE_DIR   flat-file cache dir (default: /tmp/global-stack-env-update-cache)
#              _GS_EU2_CACHE_TTL   TTL in seconds (default: 3600; can also be set via --cache-ttl)
#              _GS_EU2_HTTP_FIXTURE_DIR  if set, HTTP GET reads local files instead of curl
#              _GS_EU2_ENV_SCAN_PATH     override path to env-scan.sh for --scan (test hook)
#              _GS_EU2_TALLY_FORCE=1     bypass TTY gate for tally display in tests
#
# _GS_EU2_CFG is declared with -Ag (global associative array) so that sourcing
# this file from any depth always writes to the same global variable, not a
# local shadow.  All CLI flags populate this array (see args.sh).

[[ -n "${_GS_EU2_DEFAULTS_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_DEFAULTS_SH_LOADED=1

readonly _GS_EU2_VERSION="2.0.0"

declare -Ag _GS_EU2_CFG

# Test hooks — documented in module header above.
