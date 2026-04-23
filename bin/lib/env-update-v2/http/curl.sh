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

  # D4: Add retry logic and explicit User-Agent; detect HTTP 429 (rate-limit) specifically.
  local _body_tmp
  _body_tmp="$(mktemp)"
  local _http_status _curl_exit
  _http_status="$(curl --silent --max-time 15 --location \
    --retry 3 --retry-delay 2 \
    -H "User-Agent: global-stack-env-update-v2/0.2.0" \
    -w "%{http_code}" \
    -o "${_body_tmp}" \
    "${_url}" 2>/dev/null)"
  _curl_exit=$?

  if [[ "${_http_status}" == "429" ]]; then
    printf 'env-update-v2: rate-limited by %s (HTTP 429) — try again later\n' "${_url}" >&2
    rm -f "${_body_tmp}"
    return 1
  fi

  if [[ "${_curl_exit}" -ne 0 || "${_http_status}" -ge 400 ]] 2>/dev/null; then
    rm -f "${_body_tmp}"
    return 1
  fi

  cat "${_body_tmp}"
  rm -f "${_body_tmp}"
}
