#!/bin/bash
# sdkman.sh — SDKMAN! version fetcher using the record-index contract.
#
# Exports:   _gs_eu2_sdkman_extract_versions  _gs_eu2_sdkman_extract_java_versions
#            _gs_eu2_sdkman_select_java  _gs_eu2_fetch_sdkman
# Sources:   core/records.sh  core/semver.sh  core/channel.sh
#            core/cache.sh  http/curl.sh
# Deps:      curl, grep, sort, awk
# Env:       _GS_EU2_CFG[no_cache]  SDKMAN_DIR  GLOBAL_STACK_SDKMAN_DIR
#
# Input:  record index — reads identifier/channel/major_hint/current_version/
#                        watch_major_depth
# Output: writes proposed_version + error_message + latest_unconstrained
#         back into record (decision is NOT written — that is owned by decide.sh)
#
# Strategy (tried in order):
#   1. SDKMAN REST API  — GET /2/candidates/{c}/linux/versions/list?current=...
#      Response: formatted text table; version tokens extracted via grep/sort.
#   2. SDKMAN REST API  — GET /2/candidates/{c}/linux/versions/all
#      Comma-separated list; used when /versions/list returns nothing or HTTP fails.
#      Java ALWAYS uses this endpoint (the /list endpoint rejects Java with 400).
#
# Java special case: versions carry distribution suffixes (e.g. 11.0.31-zulu, 11.0.31-tem).
# The fetcher extracts preferred_dist from current_version suffix and biases selection toward
# the same distribution.  Preference order: preferred_dist > -tem > others.
# Distribution suffixes are NOT pre-release markers; only rc/beta/alpha/ea in the base part are.
#
# SDKMAN CLI is NOT used in v2 (CLI-first was v1 strategy; v2 prefers deterministic HTTP).
# When sdkman is not available (HTTP fixture dir absent AND SDKMAN_DIR missing), the fetcher
# sets error_message and returns without proposing a version (decide.sh → SKIP).

[[ -n "${_GS_EU2_SDKMAN_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_SDKMAN_SH_LOADED=1

# shellcheck source=../core/records.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/records.sh"
# shellcheck source=../core/semver.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/semver.sh"
# shellcheck source=../core/channel.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/channel.sh"
# shellcheck source=../core/cache.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/cache.sh"
# shellcheck source=../http/curl.sh
source "$(dirname "${BASH_SOURCE[0]}")/../http/curl.sh"

readonly _GS_EU2_SDKMAN_API_BASE="https://api.sdkman.io/2"

# _gs_eu2_sdkman_extract_versions — extract version tokens from SDKMAN text response.
#
# Args:    $1 raw  — raw text from the SDKMAN API (formatted table or CSV)
#          $2 major — optional major version to filter (e.g. "21"); empty = no filter
# Prints:  newline-separated sorted version list (sort -V)
# Returns: 0 always
#
# Used for non-Java candidates (gradle, groovy, etc.) where versions have no
# distribution suffix. Tokens matching N.N[.N]* patterns are extracted and deduped.
_gs_eu2_sdkman_extract_versions() {
  local _raw="${1}" _major="${2:-}"
  # Extract tokens that look like versions (1+ digit groups, optional pre-release suffix)
  local _versions
  _versions="$(printf '%s' "${_raw}" \
    | grep -oE '[0-9]+\.[0-9]+[.0-9]*(-[a-zA-Z0-9_]+)*' \
    | grep -v '^[[:space:]]*$' \
    | sort -V \
    | uniq \
    2>/dev/null || true)"
  if [[ -n "${_major}" ]]; then
    _versions="$(printf '%s\n' "${_versions}" \
      | grep -E "^${_major}([.^-]|\$)" 2>/dev/null || true)"
  fi
  printf '%s' "${_versions}"
}

# _gs_eu2_sdkman_extract_java_versions — extract Java versions from SDKMAN /all response.
#
# Args:    $1 raw       — comma-or-newline-separated list from SDKMAN /versions/all
#          $2 major     — optional major version filter (e.g. "21"); empty = no filter
#          $3 preferred — distribution suffix to prefer (e.g. "zulu", "tem"); empty OK
# Prints:  newline-separated list of N.N.N-dist versioned strings (sort -t- -k1,1V)
# Returns: 0 always
#
# Java versions have the form N.N.N-distN (e.g. "21.0.7-zulu", "11.0.31-tem").
# The distribution suffix is part of the SDKMAN identifier and is preserved here;
# _gs_eu2_sdkman_select_java uses it for distribution-preference selection.
_gs_eu2_sdkman_extract_java_versions() {
  local _raw="${1}" _major="${2:-}" _preferred="${3:-}"
  # Normalise: replace commas with newlines so we get one entry per line
  local _lines
  _lines="$(printf '%s' "${_raw}" | tr ',' '\n' \
    | grep -oE '[0-9]+\.[0-9]+[.0-9]*-[a-zA-Z]+([0-9]+)?' \
    | grep -v '^[[:space:]]*$' \
    | sort -t- -k1,1V \
    | uniq \
    2>/dev/null || true)"
  if [[ -n "${_major}" ]]; then
    _lines="$(printf '%s\n' "${_lines}" \
      | grep -E "^${_major}([.^-]|\$)" 2>/dev/null || true)"
  fi
  printf '%s' "${_lines}"
}

# _gs_eu2_sdkman_select_java — select best Java version with distribution preference.
#
# Args:    $1 versions  — newline-separated Java version list (N.N.N-dist form)
#          $2 preferred — distribution suffix to prefer (e.g. "zulu"); may be empty
# Prints:  single best version string (e.g. "21.0.7-zulu")
# Returns: 0 always (prints nothing if no stable version found)
#
# Selection priority: preferred_dist > -tem (Temurin) > other distributions.
# Within each tier, highest version wins (sort -t- -k1,1V | tail -1).
# Pre-release Java versions (rc/beta/alpha/ea in base or dist) are filtered out.
_gs_eu2_sdkman_select_java() {
  local _versions="${1}" _preferred="${2:-}"
  local _preferred_list="" _tem_list="" _other_list=""
  local _ver _ver_base _ver_dist _is_pre

  while IFS= read -r _ver; do
    [[ -z "${_ver}" ]] && continue
    _ver_base="${_ver%%-*}"
    _ver_dist="${_ver##*-}"
    # Skip Java pre-releases (rc/beta/alpha/ea) in stable mode.
    # The EA marker may appear in _ver_base (e.g. "17.0.0-ea" → base="17.0.0" — no EA in base)
    # OR in _ver_dist after extraction (e.g. "26.0.0-ea.1-zulu" → grep-oE → "26.0.0-ea" → dist="ea").
    # Check both to catch all forms.
    _is_pre=false
    if [[ "${_ver_base,,}" =~ (rc|beta|alpha|ea) || "${_ver_dist,,}" =~ ^(rc|beta|alpha|ea)$ ]]; then
      _is_pre=true
    fi
    [[ "${_is_pre}" == "true" ]] && continue
    if [[ -n "${_preferred}" && "${_ver_dist}" == "${_preferred}" ]]; then
      _preferred_list="${_preferred_list}${_ver}"$'\n'
    elif [[ "${_ver}" == *"-tem" ]]; then
      _tem_list="${_tem_list}${_ver}"$'\n'
    else
      _other_list="${_other_list}${_ver}"$'\n'
    fi
  done <<< "${_versions}"

  if [[ -n "${_preferred_list}" ]]; then
    printf '%s' "${_preferred_list}" | sort -t- -k1,1V | tail -1
    return
  fi
  if [[ -n "${_tem_list}" ]]; then
    printf '%s' "${_tem_list}" | sort -t- -k1,1V | tail -1
    return
  fi
  if [[ -n "${_other_list}" ]]; then
    printf '%s' "${_other_list}" | sort -t- -k1,1V | tail -1
    return
  fi
}

# _gs_eu2_fetch_sdkman — main entry point for the sdkman: fetcher type.
#
# Args:    $1 record_index — 0-based record index
# Reads:   record fields: identifier, channel, major_hint, current_version,
#          watch_major_depth
# Sets:    record fields: proposed_version, error_message, latest_unconstrained
#          (decision is NOT written — owned by decide.sh)
# Prints:  nothing
# Returns: 0 always
#
# Note: channel flag is read but effectively ignored for all SDKMAN candidates.
# The SDKMAN API returns all versions (stable + pre-release) via the same endpoint;
# pre-releases are filtered by this fetcher when channel != unstable.
_gs_eu2_fetch_sdkman() {
  local _idx="${1}"

  local _identifier _channel _major_hint _current _no_cache
  _identifier="$(_gs_eu2_record_get "${_idx}" identifier)"
  # NOTE: channel flag is read but effectively ignored for all SDKMAN candidates.
  # The SDKMAN API does not expose a pre-release channel — all versions (stable,
  # rc, beta, alpha, ea) are returned by the same endpoint.  The fetcher then
  # filters out pre-releases (rc/beta/alpha/ea in the numeric base) when
  # channel != unstable.  There is no way to request ONLY pre-releases from SDKMAN.
  # Java specifically: alpha/beta/ea/rc are excluded in stable mode; no API gate exists.
  _channel="$(_gs_eu2_record_get "${_idx}" channel)"
  _major_hint="$(_gs_eu2_record_get "${_idx}" major_hint)"
  _current="$(_gs_eu2_record_get "${_idx}" current_version)"
  _no_cache="${_GS_EU2_CFG[no_cache]:-false}"

  # watch_major_depth read early for cache key: watch-major runs must not share
  # a cache entry with non-watch-major runs (cache-hit returns before latest_unconstrained
  # is populated, so a shared entry would silently suppress WATCH on subsequent runs).
  local _wm_depth_ck
  _wm_depth_ck="$(_gs_eu2_record_get "${_idx}" watch_major_depth)"

  # Build cache key
  local _cache_key="sdkman:${_identifier}:${_major_hint}:${_channel}:${_wm_depth_ck}"

  # Cache read
  if [[ "${_no_cache}" != "true" ]]; then
    local _cached
    if _cached="$(_gs_eu2_cache_read "${_cache_key}")" && [[ -n "${_cached}" ]]; then
      _gs_eu2_record_set "${_idx}" proposed_version "${_cached}"
      return 0
    fi
  fi

  # Determine if this is a Java candidate (requires special handling)
  local _is_java=false
  [[ "${_identifier}" == "java" ]] && _is_java=true

  # ── Strategy 1: /versions/list (skipped for Java — API returns 400) ───────
  local _raw=""
  local _list_url="${_GS_EU2_SDKMAN_API_BASE}/candidates/${_identifier}/linux/versions/list?current=${_current}&pageSize=40"

  if [[ "${_is_java}" != "true" ]]; then
    local _resp
    if _resp="$(_gs_eu2_http_get "${_list_url}" 2>/dev/null)"; then
      # Validate: looks like a version list (contains something that looks like a version)
      if printf '%s' "${_resp}" | grep -qE '[0-9]+\.[0-9]+' 2>/dev/null; then
        _raw="${_resp}"
      fi
    fi
  fi

  # ── Strategy 2: /versions/all (always used for Java; fallback for others) ─
  if [[ -z "${_raw}" ]]; then
    local _all_url="${_GS_EU2_SDKMAN_API_BASE}/candidates/${_identifier}/linux/versions/all"
    local _resp2
    if _resp2="$(_gs_eu2_http_get "${_all_url}" 2>/dev/null)"; then
      if printf '%s' "${_resp2}" | grep -qE '[0-9]+\.[0-9]+' 2>/dev/null; then
        _raw="${_resp2}"
      fi
    fi
  fi

  # ── No data — set error_message and return (decide.sh will SKIP) ──────────
  if [[ -z "${_raw}" ]]; then
    # Determine whether SDKMAN is installed at all (distinguish "not installed" from "API error")
    local _sdk_dir="${SDKMAN_DIR:-${GLOBAL_STACK_SDKMAN_DIR:-/stack/tools/sdkman}}"
    local _err_msg
    if [[ -n "${_GS_EU2_HTTP_FIXTURE_DIR:-}" ]]; then
      _err_msg="no fixture found for sdkman:${_identifier} — HTTP fixture dir set but fixture missing"
    elif [[ ! -f "${_sdk_dir}/bin/sdkman-init.sh" ]]; then
      _err_msg="sdkman not installed (SDKMAN_DIR=${_sdk_dir})"
    else
      _err_msg="sdkman API fetch failed for candidate '${_identifier}'"
    fi
    _gs_eu2_record_set "${_idx}" error_message "${_err_msg}"
    return 0
  fi

  # ── Extract and filter versions ────────────────────────────────────────────
  local _proposed=""

  if [[ "${_is_java}" == "true" ]]; then
    # Java: distribution-aware selection
    local _preferred_dist=""
    if [[ "${_current}" == *"-"* ]]; then
      _preferred_dist="${_current##*-}"
    fi
    local _java_versions
    _java_versions="$(_gs_eu2_sdkman_extract_java_versions "${_raw}" "${_major_hint}" "${_preferred_dist}")"

    if [[ -z "${_java_versions}" ]]; then
      _gs_eu2_record_set "${_idx}" error_message "no java versions matched filters for ${_identifier}:${_major_hint}"
      return 0
    fi

    _proposed="$(_gs_eu2_sdkman_select_java "${_java_versions}" "${_preferred_dist}")"
  else
    # Non-Java: plain version extraction + major-pin + channel selection
    local _versions
    _versions="$(_gs_eu2_sdkman_extract_versions "${_raw}" "${_major_hint}")"

    if [[ -z "$(printf '%s\n' "${_versions}" | grep -v '^$' || true)" ]]; then
      _gs_eu2_record_set "${_idx}" error_message "no versions matched filters for sdkman:${_identifier}"
      return 0
    fi

    _proposed="$(_gs_eu2_channel_select_best "${_versions}" "${_channel}")"
  fi

  if [[ -z "${_proposed}" ]]; then
    _gs_eu2_record_set "${_idx}" error_message "channel selection returned nothing for sdkman:${_identifier}"
    return 0
  fi

  # ── (watch-major) — populate latest_unconstrained ─────────────────────────
  # _raw holds the full unfiltered API response (all versions, no major-pin).
  # Re-run extraction without the major_hint to get the unconstrained best;
  # compare against _proposed (which IS major-pinned) in main.sh to fire WATCH.
  local _wm_depth
  _wm_depth="$(_gs_eu2_record_get "${_idx}" watch_major_depth)"
  if [[ -n "${_wm_depth}" && -n "${_major_hint}" ]]; then
    if [[ "${_is_java}" == "true" ]]; then
      local _all_java_versions _unconstrained
      _all_java_versions="$(_gs_eu2_sdkman_extract_java_versions "${_raw}" "" "${_preferred_dist}")"
      _unconstrained="$(_gs_eu2_sdkman_select_java "${_all_java_versions}" "${_preferred_dist}")"
      [[ -n "${_unconstrained}" ]] && _gs_eu2_record_set "${_idx}" latest_unconstrained "${_unconstrained}"
    else
      local _all_versions _unconstrained_best
      _all_versions="$(_gs_eu2_sdkman_extract_versions "${_raw}" "")"
      _unconstrained_best="$(_gs_eu2_channel_select_best "${_all_versions}" "${_channel:-stable}")"
      [[ -n "${_unconstrained_best}" ]] && _gs_eu2_record_set "${_idx}" latest_unconstrained "${_unconstrained_best}"
    fi
  fi

  # ── Write result — proposed_version only; decision left empty for decide.sh ─
  _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"

  # ── Cache the result ───────────────────────────────────────────────────────
  [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"

  return 0
}
