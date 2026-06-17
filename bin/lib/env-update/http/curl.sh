#!/bin/bash
# curl.sh — thin HTTP GET wrapper with fixture injection and session-level memo.
#
# Exports:   _gs_eu2_fixture_path  _gs_eu2_http_get_core
#            _gs_eu2_http_get  _gs_eu2_http_get_auth
# Sources:   none
# Deps:      curl, bash 4.3+ (associative array)
# Env:       _GS_EU2_HTTP_FIXTURE_DIR (test seam — if set, all GETs read local files)
#
# FIXTURE INJECTION (test seam)
#   If _GS_EU2_HTTP_FIXTURE_DIR is set, all requests are served from files in
#   that directory. File name is derived from the URL by sanitizing non-alnum
#   chars to underscores (same scheme as cache key sanitization).
#   This is the single seam that makes all fetchers deterministically testable.
#   Pagination disambiguation: when the URL contains a "page=N" query param,
#   the fixture filename includes "_page_N" as a suffix so that page=1 and page=2
#   map to distinct fixture files.
#
# SESSION-LEVEL MEMO (_GS_EU2_HTTP_MEMO)
#   Avoids redundant HTTP round-trips for the same URL within one run.
#   Example: npm:@types/node with major_hint=22 and major_hint=24 both fetch
#   the same registry URL — the second call returns the body instantly.
#   Scope: process lifetime only; NOT persisted to the TTL cache.
#   Key format: "${url}:${auth_flag}" where auth_flag=1 (token present) or 0.
#
# RETRY STRATEGY (_gs_eu2_http_get_core)
#   Two-level: inner curl --retry 3 handles TCP/DNS failures; outer 3-attempt
#   loop with exponential back-off (5s, 10s) handles transient conditions:
#   curl timeout (exit 28 / HTTP 000), HTTP 429 rate-limit, and HTTP 502/503/504.
#   404 and other 4xx fast-fail (no outer retry) — they are definitive signals.
#   Together: up to 9 curl attempts per URL, outer back-off on transient only.

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

# _gs_eu2_fixture_path — derive the fixture filename from a URL.
#
# Args:    $1 url — fully qualified URL
# Prints:  fixture filename (e.g. "api.github.com_repos_owner_repo_tags")
# Returns: 0 always
#
# Shared by _gs_eu2_http_get and _gs_eu2_http_get_auth so the derivation logic
# lives in exactly one place. Sanitizes: strips query string, replaces non-alnum
# chars with underscores, strips leading "https___" protocol prefix, then appends
# "_page_N" when "page=N" appears in the original query string.
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

# _gs_eu2_is_transient_failure — true when a request should be retried.
#
# Args:    $1 http_status — curl's %{http_code} (000 on no-response/timeout)
#          $2 curl_exit   — curl's process exit code
# Returns: 0 (true) for transient conditions worth retrying:
#            - curl exit 28 (CURLE_OPERATION_TIMEDOUT) or HTTP 000 (no response)
#            - HTTP 429 (rate-limit), 502/503/504 (transient upstream errors)
#          1 (false) for everything else — notably 404 and other 4xx, which are
#            definitive client-side signals and must fast-fail (e.g. codeberg.sh
#            uses releases-404 as the control-flow trigger for its tags fallback).
_gs_eu2_is_transient_failure() {
  local _status="${1}" _exit="${2:-0}"
  [[ "${_exit}" == "28" || "${_status}" == "000" ]] && return 0
  [[ "${_status}" == "429" || "${_status}" == "502" \
    || "${_status}" == "503" || "${_status}" == "504" ]]
}

# _gs_eu2_http_get_core — shared network layer with two-level retry + memo store.
#
# Args:    $1 url    — fully qualified URL to fetch
#          $2 token  — optional auth token (empty = unauthenticated)
#          $3 scheme — auth header scheme: "Bearer" (default, GitHub/GHCR) or
#                      "token" (Gitea/Forgejo PATs, e.g. Codeberg). Ignored when
#                      token is empty.
# Prints:  response body on success
# Returns: 0 on success; 1 on failure (definitive 4xx, repeated transient failure)
# Side fx: stores body in _GS_EU2_HTTP_MEMO keyed on "${url}:${auth_flag}"
#
# Callers must handle fixture-seam and memo fast-paths before calling this.
# Retry strategy: inner curl --retry 3 for TCP/DNS errors; outer 3-attempt loop
# with 5s/10s back-off for transient conditions — curl timeout (exit 28 / HTTP
# 000), HTTP 429, and HTTP 502/503/504. 404 and other 4xx fast-fail (no retry).
# Note: with --max-time 15, a sustained upstream timeout will exhaust all 3
# attempts at ~15s each; the retry is for transient single blips, not outages.
_gs_eu2_http_get_core() {
  local _url="${1}" _token="${2:-}" _scheme="${3:-Bearer}"
  local _body_tmp _curl_stderr_file
  _body_tmp="$(mktemp)"
  _curl_stderr_file="$(mktemp)"
  local _attempt _http_status _curl_exit
  for _attempt in 1 2 3; do
    if [[ -n "${_token}" ]]; then
      _http_status="$(curl --silent --max-time 15 --connect-timeout 5 --location \
        --retry 3 --retry-delay 2 \
        -H "User-Agent: global-stack-env-update/2.0.0" \
        -H "Authorization: ${_scheme} ${_token}" \
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
    # Stop unless this is a retryable transient condition.
    _gs_eu2_is_transient_failure "${_http_status}" "${_curl_exit}" || break
    [[ $_attempt -lt 3 ]] && {
      if [[ "${_http_status}" == "429" ]]; then
        printf 'env-update: rate-limited (HTTP 429), retry %d/3 in %ds\n' \
          "$_attempt" "$((_attempt * 5))" >&2
      elif [[ "${_curl_exit}" == "28" || "${_http_status}" == "000" ]]; then
        printf 'env-update: upstream timeout (no response within 15s), retry %d/3 in %ds\n' \
          "$_attempt" "$((_attempt * 5))" >&2
      else
        printf 'env-update: transient upstream error HTTP %s, retry %d/3 in %ds\n' \
          "${_http_status}" "$_attempt" "$((_attempt * 5))" >&2
      fi
      sleep $((_attempt * 5))
    }
  done

  # Transient failure persisted through all attempts — emit an honest, mode-specific
  # message so the user knows it is an upstream/network condition, not their config.
  if _gs_eu2_is_transient_failure "${_http_status}" "${_curl_exit}"; then
    if [[ "${_http_status}" == "429" ]]; then
      printf 'env-update: rate-limited by %s after 3 attempts — try again later\n' "${_url}" >&2
    elif [[ "${_curl_exit}" == "28" || "${_http_status}" == "000" ]]; then
      printf 'env-update: upstream timeout: no response from %s within 15s — try again later\n' \
        "${_url}" >&2
    else
      printf 'env-update: transient upstream error HTTP %s from %s — try again later\n' \
        "${_http_status}" "${_url}" >&2
    fi
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

# _gs_eu2_http_get — unauthenticated HTTP GET with fixture injection and memo.
#
# Args:    $1 url — URL to fetch
# Prints:  response body
# Returns: 0 on success; 1 on failure
# Side fx: reads _GS_EU2_HTTP_MEMO; may write to it via _gs_eu2_http_get_core
_gs_eu2_http_get() {
  local _url="${1}"

  # HTTP_INJECT_STATUS test seam: simulate HTTP error codes or malformed responses.
  # Values: 429, 503, or any 3-digit status code → return 1 with error message.
  #         "malformed-json" → return 0 with incomplete JSON body (parse-failure testing).
  if [[ -n "${_GS_EU2_HTTP_INJECT_STATUS:-}" ]]; then
    if [[ "${_GS_EU2_HTTP_INJECT_STATUS}" == "malformed-json" ]]; then
      printf '{"not": "valid json"'
      return 0
    else
      printf 'env-update: injected HTTP error %s for URL: %s\n' "${_GS_EU2_HTTP_INJECT_STATUS}" "${_url}" >&2
      return 1
    fi
  fi

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

# _gs_eu2_http_get_auth — authenticated HTTP GET.
#
# Args:    $1 url    — URL to fetch
#          $2 token  — auth token (empty → delegates to _gs_eu2_http_get, no duplication)
#          $3 scheme — auth header scheme: "Bearer" (default, GitHub/GHCR) or
#                      "token" (Gitea/Forgejo PATs, e.g. Codeberg). Forgejo accepts
#                      both, but the canonical/Gitea-compatible form is "token".
# Prints:  response body
# Returns: 0 on success; 1 on failure
# Side fx: reads _GS_EU2_HTTP_MEMO[url:1]; may write to it via _gs_eu2_http_get_core
#
# Fixture injection: path derived from URL only — token is NOT part of the fixture path.
# This means authenticated and unauthenticated test fixtures share the same file.
_gs_eu2_http_get_auth() {
  local _url="${1}" _token="${2:-}" _scheme="${3:-Bearer}"

  # Empty token: reuse plain GET (handles fixture path identically, including inject seam)
  if [[ -z "${_token}" ]]; then
    _gs_eu2_http_get "${_url}"
    return
  fi

  # HTTP_INJECT_STATUS also applies to authenticated calls
  if [[ -n "${_GS_EU2_HTTP_INJECT_STATUS:-}" ]]; then
    if [[ "${_GS_EU2_HTTP_INJECT_STATUS}" == "malformed-json" ]]; then
      printf '{"not": "valid json"'
      return 0
    else
      printf 'env-update: injected HTTP error %s for URL: %s\n' "${_GS_EU2_HTTP_INJECT_STATUS}" "${_url}" >&2
      return 1
    fi
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

  _gs_eu2_http_get_core "${_url}" "${_token}" "${_scheme}"
}
