#!/bin/bash
# curl.sh — thin HTTP GET wrapper with fixture injection for testing
#
# If _GS_EU2_HTTP_FIXTURE_DIR is set, all requests are served from files in
# that directory. File name is derived from the URL by sanitizing non-alnum
# chars to underscores (same scheme as cache key sanitization).
# This is the single seam that makes all fetchers deterministically testable.
#
# Pagination disambiguation: when the URL contains a "page=N" query param,
# the fixture filename includes "_page_N" as a suffix so that page=1 and page=2
# map to distinct fixture files.  Without this, stripping the query string
# collapses both URLs to the same path.

[[ -n "${_GS_EU2_CURL_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_CURL_SH_LOADED=1

# In-session URL memo: avoids redundant HTTP round-trips for the same URL within one run.
# Example: npm:@types/node with major_hint=22 and major_hint=24 both fetch the same registry
# URL — the second call returns the cached body instantly instead of making a network request.
# Scope: process lifetime only. NOT written to the TTL cache (cross-run deduplication handled
# by cache.sh independently). git ls-remote calls in github.sh use a separate code path and
# are naturally excluded.
#
# Key format: "${_url}:${auth}" where auth=1 (Bearer token present) or 0 (no token).
# This prevents an unauthenticated response cached under the bare URL from being returned
# to an authenticated caller that would receive a richer (or rate-limit-exempt) response.
declare -gA _GS_EU2_HTTP_MEMO=()

# _gs_eu2_fixture_path URL
# Derive the fixture filename from a URL.  Shared by _gs_eu2_http_get and
# _gs_eu2_http_get_auth so the logic stays in exactly one place.
_gs_eu2_fixture_path() {
  local _url="${1}"
  local _noquery="${_url%%\?*}"                       # strip query string
  local _safe="${_noquery//[^a-zA-Z0-9._-]/_}"
  _safe="${_safe#https___}"                           # strip leading protocol
  local _qs="${_url#*\?}"
  if [[ "${_qs}" != "${_url}" ]]; then
    local _page
    _page="$(printf '%s' "${_qs}" | grep -oE '(^|[&])page=[0-9]+' | grep -oE 'page=[0-9]+' | head -1 || true)"
    [[ -n "${_page}" ]] && _safe="${_safe}_${_page/=/_}"
  fi
  printf '%s' "${_safe}"
}

# _gs_eu2_http_get_core URL [TOKEN]
# Shared network layer: two-level retry loop + memo store.
# Called by _gs_eu2_http_get (no token) and _gs_eu2_http_get_auth (with token).
# Callers must have already handled the fixture-seam and memo fast-paths.
#
# Two-level retry strategy (D4):
# - Inner: curl --retry 3 --retry-delay 2 handles transient network failures
#   (connection reset, DNS timeout, brief server hiccups) at the TCP/HTTP level.
# - Outer: the for-loop (3 attempts) specifically handles HTTP 429 rate-limiting
#   with exponential back-off (5s, 10s). This is layered on top of curl's retry
#   because curl does not retry 429 by default (it only retries on connection
#   errors and transient HTTP 5xx per --retry-all-errors).
# Together: up to 3*3 = 9 curl attempts, with outer back-off on 429 only.
_gs_eu2_http_get_core() {
  local _url="${1}" _token="${2:-}"
  local _body_tmp _curl_stderr_file
  _body_tmp="$(mktemp)"
  _curl_stderr_file="$(mktemp)"
  local _attempt _http_status _curl_exit
  for _attempt in 1 2 3; do
    if [[ -n "${_token}" ]]; then
      _http_status="$(curl --silent --max-time 15 --connect-timeout 5 --location \
        --retry 3 --retry-delay 2 \
        -H "User-Agent: global-stack-env-update/2.0.0" \
        -H "Authorization: Bearer ${_token}" \
        -w "%{http_code}" \
        -o "${_body_tmp}" \
        "${_url}" 2>"${_curl_stderr_file}")"
    else
      _http_status="$(curl --silent --max-time 15 --connect-timeout 5 --location \
        --retry 3 --retry-delay 2 \
        -H "User-Agent: global-stack-env-update/2.0.0" \
        -w "%{http_code}" \
        -o "${_body_tmp}" \
        "${_url}" 2>"${_curl_stderr_file}")"
    fi
    _curl_exit=$?
    [[ "${_http_status}" != "429" ]] && break
    [[ $_attempt -lt 3 ]] && {
      printf 'env-update: rate-limited (HTTP 429), retry %d/3 in %ds\n' "$_attempt" "$((_attempt * 5))" >&2
      sleep $((_attempt * 5))
    }
  done

  if [[ "${_http_status}" == "429" ]]; then
    printf 'env-update: rate-limited by %s after 3 attempts — try again later\n' "${_url}" >&2
    rm -f "${_body_tmp}" "${_curl_stderr_file}"
    return 1
  fi

  local _http_status_safe="${_http_status:-0}"
  if [[ "${_curl_exit}" -ne 0 || "${_http_status_safe}" -ge 400 ]]; then
    local _curl_detail
    _curl_detail="$(head -3 "${_curl_stderr_file}" 2>/dev/null || true)"
    [[ -n "${_curl_detail}" ]] && printf 'env-update: curl failed: %s\n' "${_curl_detail}" >&2
    rm -f "${_body_tmp}" "${_curl_stderr_file}"
    return 1
  fi

  local _core_body
  _core_body="$(cat "${_body_tmp}")"
  rm -f "${_body_tmp}" "${_curl_stderr_file}"
  # Store in memo for this session (process lifetime only — not persisted to TTL cache).
  # Key includes auth flag to prevent unauthenticated responses being served to auth callers.
  local _auth_flag=0
  [[ -n "${_token}" ]] && _auth_flag=1
  _GS_EU2_HTTP_MEMO["${_url}:${_auth_flag}"]="${_core_body}"
  printf '%s' "${_core_body}"
}

# Fetch URL contents. Returns 0 on success, 1 on failure.
# Stdout: response body. Stderr: error message on failure.
_gs_eu2_http_get() {
  local _url="${1}"

  if [[ -n "${_GS_EU2_HTTP_FIXTURE_DIR:-}" ]]; then
    local _safe
    _safe="$(_gs_eu2_fixture_path "${_url}")"
    local _f="${_GS_EU2_HTTP_FIXTURE_DIR}/${_safe}"
    if [[ -f "${_f}" ]]; then
      cat "${_f}"
      return 0
    fi
    printf 'env-update: HTTP fixture not found: %s\n' "${_f}" >&2
    return 1
  fi

  # In-session URL memo: return cached body if this URL was already fetched without auth.
  if [[ -n "${_GS_EU2_HTTP_MEMO[${_url}:0]+x}" ]]; then
    printf '%s' "${_GS_EU2_HTTP_MEMO[${_url}:0]}"
    return 0
  fi

  _gs_eu2_http_get_core "${_url}"
}

# Authenticated HTTP GET — injects Authorization: Bearer <token>.
# If token is empty, delegates entirely to _gs_eu2_http_get (no copy-paste).
# Fixture injection is identical: path derived from URL only, token ignored.
# Args: $1 url, $2 token
_gs_eu2_http_get_auth() {
  local _url="${1}" _token="${2:-}"

  # Empty token: reuse plain GET (handles fixture path identically)
  if [[ -z "${_token}" ]]; then
    _gs_eu2_http_get "${_url}"
    return
  fi

  # Fixture seam: same path derivation as _gs_eu2_http_get (token not part of path)
  if [[ -n "${_GS_EU2_HTTP_FIXTURE_DIR:-}" ]]; then
    local _safe
    _safe="$(_gs_eu2_fixture_path "${_url}")"
    local _f="${_GS_EU2_HTTP_FIXTURE_DIR}/${_safe}"
    if [[ -f "${_f}" ]]; then
      cat "${_f}"
      return 0
    fi
    printf 'env-update: HTTP fixture not found: %s\n' "${_f}" >&2
    return 1
  fi

  # In-session URL memo: return cached body if this URL was already fetched with auth.
  if [[ -n "${_GS_EU2_HTTP_MEMO[${_url}:1]+x}" ]]; then
    printf '%s' "${_GS_EU2_HTTP_MEMO[${_url}:1]}"
    return 0
  fi

  _gs_eu2_http_get_core "${_url}" "${_token}"
}
