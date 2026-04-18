#!/bin/bash
# curl.sh — thin HTTP GET wrapper with fixture injection for testing
#
# If _GS_EU2_HTTP_FIXTURE_DIR is set, all requests are served from files in
# that directory. File name is derived from the URL by sanitizing non-alnum
# chars to underscores (same scheme as cache key sanitization).
# This is the single seam that makes all fetchers deterministically testable.

[[ -n "${_GS_EU2_CURL_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_CURL_SH_LOADED=1

# Fetch URL contents. Returns 0 on success, 1 on failure.
# Stdout: response body. Stderr: error message on failure.
_gs_eu2_http_get() {
  local _url="${1}"

  if [[ -n "${_GS_EU2_HTTP_FIXTURE_DIR:-}" ]]; then
    local _noquery="${_url%%\?*}"            # strip query string
    local _safe="${_noquery//[^a-zA-Z0-9._-]/_}"
    _safe="${_safe#https___}"               # strip leading protocol
    local _f="${_GS_EU2_HTTP_FIXTURE_DIR}/${_safe}"
    if [[ -f "${_f}" ]]; then
      cat "${_f}"
      return 0
    fi
    printf 'env-update-v2: HTTP fixture not found: %s\n' "${_f}" >&2
    return 1
  fi

  curl --silent --fail --max-time 15 --location "${_url}"
}
