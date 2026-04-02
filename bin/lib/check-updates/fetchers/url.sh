#!/bin/bash
# URL fetcher — manual-only placeholder.
# For URLs that cannot be checked automatically (SVN, custom registries, etc.)

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_CU_URL_SH_LOADED:-}" ]] && return 0
readonly _GS_CU_URL_SH_LOADED=1

# Manual-only URL check.
# Always returns SKIP with the URL for manual inspection.
# Usage: _gs_cu_url_fetch_latest "https://svn.apache.org/repos/asf/..." "tags/1.6.3"
_gs_cu_url_fetch_latest() {
  local identifier="${1}"    # the URL
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"

  # URL type is always manual — return empty to signal no automation
  echo ""
  return 0
}
