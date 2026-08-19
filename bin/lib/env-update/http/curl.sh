#!/bin/bash
# curl.sh — thin HTTP GET wrapper with fixture injection and session-level memo.
#
# Exports:   _gs_eu2_fixture_path  _gs_eu2_http_url_page  _gs_eu2_http_get_core
#            _gs_eu2_http_get  _gs_eu2_http_get_auth
#            _gs_eu2_http_diag_new  _gs_eu2_http_diag_status  _gs_eu2_http_diag_body
#            _gs_eu2_http_diag_url  _gs_eu2_http_diag_free
# Sources:   none
# Deps:      curl, bash 4.3+ (associative array)
# Env:       _GS_EU2_HTTP_FIXTURE_DIR (test seam — if set, all GETs read local files)
#            _GS_EU2_HTTP_INJECT_STATUS (test seam — force a status / malformed body)
#            _GS_EU2_HTTP_INJECT_STATUS_AT_PAGE (test seam — restrict the above to
#              requests whose URL carries "page=N", so pages 1..N-1 still resolve
#              normally. Needed to simulate a mid-pagination abort such as Docker
#              Hub's anonymous offset cap; the global form fails page 1 instead.)
#
# FAILURE DIAGNOSTICS SINK (_gs_eu2_http_diag_*)
#   Every GET here is invoked from a command substitution, and under --jobs>1 the
#   whole fetcher additionally runs in a background subshell. Globals therefore
#   only propagate DOWNWARD — a variable set by the HTTP layer is lost the moment
#   its subshell exits, and a fixed-path temp file would be a race across workers.
#   So the diagnostics channel is a caller-owned sink: the frame that wants the
#   status calls _gs_eu2_http_diag_new (one mktemp -d, unique per call by
#   construction), passes the path down as an argument, and reads the files back
#   after the substitution returns. No shared global, no fixed path, no race at
#   any --jobs value.
#
#   Sink layout:  <sink>/status  <sink>/url  <sink>/body
#   status/url are written on every terminal path; body only on failure (a
#   success body is already the function's stdout). Passing no sink costs nothing.
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
  local _page
  _page="$(_gs_eu2_http_url_page "${_url}")"
  [[ -n "${_page}" ]] && _safe="${_safe}_page_${_page}"
  printf '%s' "${_safe}"
}

# _gs_eu2_http_url_page — extract the "page=N" query parameter from a URL.
#
# Args:    $1 url — fully qualified URL
# Prints:  the page number (e.g. "11"), or nothing when the URL carries no
#          page= parameter (page 1 of a Docker Hub walk carries none)
# Returns: 0 always — callers use it in a command substitution under
#          'set -eEuo pipefail', so a "no page" answer must not be an error.
#
# Only the query string is inspected, and the match is anchored on "^" or "&"
# so that "page_size=100" is never mistaken for "page=100". Single source of
# truth for both the fixture path suffix and the per-page inject seam.
_gs_eu2_http_url_page() {
  local _url="${1}"
  local _qs="${_url#*\?}"
  [[ "${_qs}" == "${_url}" ]] && return 0 # no query string at all
  if [[ "${_qs}" =~ (^|[\&])page=([0-9]+) ]]; then
    printf '%s' "${BASH_REMATCH[2]}"
  fi
  return 0
}

# ─── failure diagnostics sink ──────────────────────────────────────────────
# See the FAILURE DIAGNOSTICS SINK block in the file header for why this is a
# caller-owned directory rather than a global variable or a fixed-path file.

# _gs_eu2_http_diag_new — create a fresh, private diagnostics sink.
#
# Args:    none
# Prints:  the sink directory path — caller owns it and must free it
# Returns: 0 on success; non-zero if mktemp fails (propagated deliberately:
#          a sink that could not be created is a real error, not a no-op)
_gs_eu2_http_diag_new() {
  mktemp -d -t gs-eu2-httpdiag.XXXXXXXXXX
}

# _gs_eu2_http_diag_status — HTTP status recorded by the last GET on this sink.
#
# Args:    $1 sink — path returned by _gs_eu2_http_diag_new
# Prints:  the status code, or nothing when none was recorded (transport-level
#          failures such as DNS never produce one)
# Returns: 0 always — see _gs_eu2_http_url_page for why.
_gs_eu2_http_diag_status() {
  [[ -f "${1}/status" ]] && cat "${1}/status"
  return 0
}

# _gs_eu2_http_diag_body — response body recorded by the last FAILED GET.
#
# Args:    $1 sink — path returned by _gs_eu2_http_diag_new
# Prints:  the body, or nothing (successful GETs return their body on stdout
#          instead, so the sink deliberately holds no copy)
# Returns: 0 always.
_gs_eu2_http_diag_body() {
  [[ -f "${1}/body" ]] && cat "${1}/body"
  return 0
}

# _gs_eu2_http_diag_url — URL of the last GET recorded on this sink.
#
# Args:    $1 sink — path returned by _gs_eu2_http_diag_new
# Prints:  the URL, or nothing when none was recorded
# Returns: 0 always. Lets a caller recover WHICH request failed — for a
#          paginated walk that is the only way to know the page number, since
#          the loop variable itself died with the command substitution.
_gs_eu2_http_diag_url() {
  [[ -f "${1}/url" ]] && cat "${1}/url"
  return 0
}

# _gs_eu2_http_diag_free — remove a sink created by _gs_eu2_http_diag_new.
#
# Args:    $1 sink — path returned by _gs_eu2_http_diag_new
# Returns: 0 always
#
# Removes the three known children by name, then rmdir's the directory.
# Deliberately NOT "rm -rf ${1}": this repo has no permission deny list, so a
# recursive delete driven by a variable is a blast radius with no backstop.
#
# The "|| true" is load-bearing, not error suppression: the library runs under
# 'set -eEuo pipefail', so an rmdir that failed (only possible if something put
# an unexpected file in the sink) would abort the whole run. Cleaning up a
# diagnostic must never be able to fail the run it was diagnosing. stderr is
# deliberately NOT silenced — if that ever happens it should be visible.
_gs_eu2_http_diag_free() {
  local _sink="${1:-}"
  [[ -z "${_sink}" || ! -d "${_sink}" ]] && return 0
  rm -f "${_sink}/status" "${_sink}/url" "${_sink}/body"
  rmdir "${_sink}" || true
  return 0
}

# _gs_eu2_http_diag_record — write one request outcome into a sink.
#
# Args:    $1 sink      — sink path (empty string = no-op, the common case)
#          $2 url       — the request URL
#          $3 status    — HTTP status, or empty when the request never got one
#          $4 body_file — optional file holding the failure body; omitted or
#                         absent means "no body" and truncates any stale one
# Returns: 0 always
#
# Always writes all three files so the sink reflects the LAST call only — a
# stale status from an earlier page must never be read as this page's answer.
_gs_eu2_http_diag_record() {
  local _sink="${1:-}" _url="${2:-}" _status="${3:-}" _body_file="${4:-}"
  [[ -z "${_sink}" || ! -d "${_sink}" ]] && return 0
  printf '%s' "${_url}" >"${_sink}/url"
  printf '%s' "${_status}" >"${_sink}/status"
  if [[ -n "${_body_file}" && -f "${_body_file}" ]]; then
    cat "${_body_file}" >"${_sink}/body"
  else
    : >"${_sink}/body"
  fi
  return 0
}

# _gs_eu2_http_inject_applies — should the INJECT_STATUS test seam fire for this URL?
#
# Args:    $1 url — the URL about to be fetched
# Returns: 0 (fire) / 1 (do not fire)
#
# Unset _GS_EU2_HTTP_INJECT_STATUS_AT_PAGE keeps the original global behaviour:
# the seam fires for every request. Set, it fires only for the request whose URL
# carries that page number — which is what makes "pages 1..N-1 succeed, page N
# is rejected" expressible, and hence what makes a mid-pagination abort testable.
_gs_eu2_http_inject_applies() {
  local _url="${1}"
  [[ -n "${_GS_EU2_HTTP_INJECT_STATUS:-}" ]] || return 1
  local _at="${_GS_EU2_HTTP_INJECT_STATUS_AT_PAGE:-}"
  [[ -z "${_at}" ]] && return 0
  local _page
  _page="$(_gs_eu2_http_url_page "${_url}")"
  [[ "${_page}" == "${_at}" ]]
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
#          $4 sink   — optional diagnostics sink from _gs_eu2_http_diag_new.
#                      When given, the status, URL and (on failure) the response
#                      body are recorded there so the caller can tell a 403
#                      offset-cap from a 404 from a DNS failure.
# Prints:  response body on success
# Returns: 0 on success; 1 on failure (definitive 4xx, repeated transient failure)
# Side fx: stores body in _GS_EU2_HTTP_MEMO keyed on "${url}:${auth_flag}"
#          writes <sink>/status, <sink>/url, <sink>/body when a sink is given
#
# Callers must handle fixture-seam and memo fast-paths before calling this.
# Retry strategy: inner curl --retry 3 for TCP/DNS errors; outer 3-attempt loop
# with 5s/10s back-off for transient conditions — curl timeout (exit 28 / HTTP
# 000), HTTP 429, and HTTP 502/503/504. 404 and other 4xx fast-fail (no retry).
# Note: with --max-time 15, a sustained upstream timeout will exhaust all 3
# attempts at ~15s each; the retry is for transient single blips, not outages.
_gs_eu2_http_get_core() {
  local _url="${1}" _token="${2:-}" _scheme="${3:-Bearer}" _sink="${4:-}"
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
    _gs_eu2_http_diag_record "${_sink}" "${_url}" "${_http_status:-}" "${_body_tmp}"
    rm -f "${_body_tmp}" "${_curl_stderr_file}"
    return 1
  fi

  local _http_status_safe="${_http_status:-0}"
  if [[ "${_curl_exit}" -ne 0 || "${_http_status_safe}" -ge 400 ]]; then
    local _curl_detail
    _curl_detail="$(head -3 "${_curl_stderr_file}" 2>/dev/null || true)"
    [[ -n "${_curl_detail}" ]] && printf 'env-update: curl failed: %s\n' "${_curl_detail}" >&2
    # Record BEFORE the body is removed. This is the exact line that used to
    # throw the status and the body away, leaving every caller with an opaque
    # failure it could not attribute (403 offset-cap vs 404 vs DNS vs timeout).
    _gs_eu2_http_diag_record "${_sink}" "${_url}" "${_http_status:-}" "${_body_tmp}"
    rm -f "${_body_tmp}" "${_curl_stderr_file}"
    return 1
  fi

  local _core_body
  _core_body="$(cat "${_body_tmp}")"
  _gs_eu2_http_diag_record "${_sink}" "${_url}" "${_http_status:-}"
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
# Args:    $1 url  — URL to fetch
#          $2 sink — optional diagnostics sink from _gs_eu2_http_diag_new
# Prints:  response body
# Returns: 0 on success; 1 on failure
# Side fx: reads _GS_EU2_HTTP_MEMO; may write to it via _gs_eu2_http_get_core
#          writes <sink>/status, <sink>/url, <sink>/body when a sink is given
#
# The sink is populated on the fixture, memo and inject fast-paths too, not only
# by _gs_eu2_http_get_core — the contract is "the sink reflects the LAST call",
# and three of the four terminal paths here never reach the core function.
_gs_eu2_http_get() {
  local _url="${1}" _sink="${2:-}"

  # HTTP_INJECT_STATUS test seam: simulate HTTP error codes or malformed responses.
  # Values: 429, 503, or any 3-digit status code → return 1 with error message.
  #         "malformed-json" → return 0 with incomplete JSON body (parse-failure testing).
  # Scope: every request, unless _GS_EU2_HTTP_INJECT_STATUS_AT_PAGE narrows it to
  # one page — see _gs_eu2_http_inject_applies.
  if _gs_eu2_http_inject_applies "${_url}"; then
    if [[ "${_GS_EU2_HTTP_INJECT_STATUS}" == "malformed-json" ]]; then
      _gs_eu2_http_diag_record "${_sink}" "${_url}" "200"
      printf '{"not": "valid json"'
      return 0
    else
      printf 'env-update: injected HTTP error %s for URL: %s\n' "${_GS_EU2_HTTP_INJECT_STATUS}" "${_url}" >&2
      _gs_eu2_http_diag_record "${_sink}" "${_url}" "${_GS_EU2_HTTP_INJECT_STATUS}"
      return 1
    fi
  fi

  if [[ -n "${_GS_EU2_HTTP_FIXTURE_DIR:-}" ]]; then
    local _safe
    _safe="$(_gs_eu2_fixture_path "${_url}")"
    local _f="${_GS_EU2_HTTP_FIXTURE_DIR}/${_safe}"
    if [[ -f "${_f}" ]]; then
      _gs_eu2_http_diag_record "${_sink}" "${_url}" "200"
      cat "${_f}"
      return 0
    fi
    printf 'env-update: HTTP fixture not found: %s\n' "${_f}" >&2
    # No status: a missing fixture stands in for a transport-level failure,
    # which genuinely produces no HTTP status. Recording a fake one would make
    # the seam lie about the very distinction this sink exists to preserve.
    _gs_eu2_http_diag_record "${_sink}" "${_url}" ""
    return 1
  fi

  # In-session URL memo: return cached body if this URL was already fetched without auth.
  if [[ -n "${_GS_EU2_HTTP_MEMO[${_url}:0]+x}" ]]; then
    _gs_eu2_http_diag_record "${_sink}" "${_url}" "200"
    printf '%s' "${_GS_EU2_HTTP_MEMO[${_url}:0]}"
    return 0
  fi

  _gs_eu2_http_get_core "${_url}" "" "" "${_sink}"
}

# _gs_eu2_http_get_auth — authenticated HTTP GET.
#
# Args:    $1 url    — URL to fetch
#          $2 token  — auth token (empty → delegates to _gs_eu2_http_get, no duplication)
#          $3 scheme — auth header scheme: "Bearer" (default, GitHub/GHCR) or
#                      "token" (Gitea/Forgejo PATs, e.g. Codeberg). Forgejo accepts
#                      both, but the canonical/Gitea-compatible form is "token".
#          $4 sink   — optional diagnostics sink from _gs_eu2_http_diag_new
# Prints:  response body
# Returns: 0 on success; 1 on failure
# Side fx: reads _GS_EU2_HTTP_MEMO[url:1]; may write to it via _gs_eu2_http_get_core
#          writes <sink>/status, <sink>/url, <sink>/body when a sink is given
#
# Fixture injection: path derived from URL only — token is NOT part of the fixture path.
# This means authenticated and unauthenticated test fixtures share the same file.
_gs_eu2_http_get_auth() {
  local _url="${1}" _token="${2:-}" _scheme="${3:-Bearer}" _sink="${4:-}"

  # Empty token: reuse plain GET (handles fixture path identically, including inject seam)
  if [[ -z "${_token}" ]]; then
    _gs_eu2_http_get "${_url}" "${_sink}"
    return
  fi

  # HTTP_INJECT_STATUS also applies to authenticated calls
  if _gs_eu2_http_inject_applies "${_url}"; then
    if [[ "${_GS_EU2_HTTP_INJECT_STATUS}" == "malformed-json" ]]; then
      _gs_eu2_http_diag_record "${_sink}" "${_url}" "200"
      printf '{"not": "valid json"'
      return 0
    else
      printf 'env-update: injected HTTP error %s for URL: %s\n' "${_GS_EU2_HTTP_INJECT_STATUS}" "${_url}" >&2
      _gs_eu2_http_diag_record "${_sink}" "${_url}" "${_GS_EU2_HTTP_INJECT_STATUS}"
      return 1
    fi
  fi

  # Fixture seam: same path derivation as _gs_eu2_http_get (token not part of path)
  if [[ -n "${_GS_EU2_HTTP_FIXTURE_DIR:-}" ]]; then
    local _safe
    _safe="$(_gs_eu2_fixture_path "${_url}")"
    local _f="${_GS_EU2_HTTP_FIXTURE_DIR}/${_safe}"
    if [[ -f "${_f}" ]]; then
      _gs_eu2_http_diag_record "${_sink}" "${_url}" "200"
      cat "${_f}"
      return 0
    fi
    printf 'env-update: HTTP fixture not found: %s\n' "${_f}" >&2
    _gs_eu2_http_diag_record "${_sink}" "${_url}" ""
    return 1
  fi

  # In-session URL memo: return cached body if this URL was already fetched with auth.
  if [[ -n "${_GS_EU2_HTTP_MEMO[${_url}:1]+x}" ]]; then
    _gs_eu2_http_diag_record "${_sink}" "${_url}" "200"
    printf '%s' "${_GS_EU2_HTTP_MEMO[${_url}:1]}"
    return 0
  fi

  _gs_eu2_http_get_core "${_url}" "${_token}" "${_scheme}" "${_sink}"
}
