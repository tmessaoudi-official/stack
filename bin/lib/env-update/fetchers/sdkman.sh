#!/bin/bash
# SDKMAN REST API fetcher.
# Fetches available versions for SDKMAN candidates.
# Supports major version constraint via sdkman:<candidate>:<major> format.
# Strategy: try SDKMAN CLI first (via subshell), fall back to REST API.

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_EU_SDKMAN_SH_LOADED:-}" ]] && return 0
readonly _GS_EU_SDKMAN_SH_LOADED=1

readonly _GS_EU_SDKMAN_API_BASE="https://api.sdkman.io/2"

# Fetch latest version of an SDKMAN candidate, optionally constrained to a major version
# Usage: _gs_eu_sdkman_fetch_latest "gradle:8" "8.14"    → latest 8.x
# Usage: _gs_eu_sdkman_fetch_latest "gradle" "9.4.0"     → latest overall
_gs_eu_sdkman_fetch_latest() {
  local identifier="${1}"    # "candidate" or "candidate:major"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"
  local channel="${5:-}"

  # Parse identifier to extract candidate and optional major constraint
  local candidate=""
  local major_constraint=""

  if [[ "${identifier}" =~ ^([^:]+):([0-9]+(\.[0-9]+)*)$ ]]; then
    candidate="${BASH_REMATCH[1]}"
    major_constraint="${BASH_REMATCH[2]}"
  else
    candidate="${identifier}"
    # Infer major from current version (strip distribution suffix for Java e.g. "21.0.7-tem")
    local ver_base="${current_version%%-*}"
    major_constraint="${ver_base%%.*}"
  fi

  local cache_key="sdkman:${identifier}:${channel}"

  if [[ "${no_cache}" != "true" ]]; then
    local cached
    if cached="$(_gs_eu_cache_read "${cache_key}" 2>/dev/null)"; then
      echo "${cached}"
      return 0
    fi
  fi

  if [[ "${offline}" == "true" ]]; then
    return 1
  fi

  # ------------------------------------------------------------------
  # Try SDKMAN CLI first via subshell
  # ------------------------------------------------------------------
  local cli_result=""
  local _sdk_dir="${SDKMAN_DIR:-${GLOBAL_STACK_SDKMAN_DIR:-/stack/tools/sdkman}}"
  if [[ -z "${_sdk_dir}" || ! -f "${_sdk_dir}/bin/sdkman-init.sh" ]]; then
    if [[ "${candidate}" == "java" ]]; then
      _gs_eu_set_fetch_error "sdkman:java requires SDKMAN CLI (install from sdkman.io) — REST API does not support multi-distribution Java candidates"
    else
      _gs_eu_set_fetch_error "sdkman CLI unavailable (SDKMAN_DIR not set or sdkman-init.sh missing at ${_sdk_dir})"
    fi
  else
    # Source sdkman-init and run sdk list in a subshell.
    # We capture stdout; errors go to error file explicitly so they survive subshell boundary.
    local _sdk_err_tmp
    _sdk_err_tmp="$(mktemp)"
    cli_result="$(
      # shellcheck source=/dev/null
      # Source directly (not inside $()) so the sdk function is defined in this subshell
      # set +u: sdkman-init.sh references $ZSH_VERSION/$FISH_VERSION which may be unbound in bash
      _gs_eu_sdk_init_err_file="$(mktemp)"
      set +u
      source "${_sdk_dir}/bin/sdkman-init.sh" 2>"${_gs_eu_sdk_init_err_file}" || {
        set -u
        printf '%s' "sdkman CLI: sdkman-init.sh failed to source: $(cat "${_gs_eu_sdk_init_err_file}" 2>/dev/null)" \
          > "${_GS_EU_FETCH_ERROR_FILE:-/tmp/gs-fetch-error}" 2>/dev/null || true
        rm -f "${_gs_eu_sdk_init_err_file}"
        exit 1
      }
      set -u
      rm -f "${_gs_eu_sdk_init_err_file}"
      sdk offline disable 2>/dev/null || true
      list_out="$(sdk list "${candidate}" 2>&1)" || {
        printf '%s' "sdkman CLI: sdk list ${candidate} failed: ${list_out}" \
          > "${_GS_EU_FETCH_ERROR_FILE:-/tmp/gs-fetch-error}" 2>/dev/null || true
        exit 1
      }
      printf '%s\n' "${list_out}"
    )" 2>"${_sdk_err_tmp}" || true
    # If cli_result is empty and the subshell wrote stderr, surface it
    if [[ -z "${cli_result}" ]]; then
      local _sdk_stderr
      _sdk_stderr="$(cat "${_sdk_err_tmp}" 2>/dev/null || true)"
      if [[ -n "${_sdk_stderr}" ]]; then
        # Only write to error file if not already written by subshell
        local _existing_err
        _existing_err="$(cat "${_GS_EU_FETCH_ERROR_FILE:-/tmp/gs-fetch-error}" 2>/dev/null || true)"
        if [[ -z "${_existing_err}" ]]; then
          printf '%s' "sdkman CLI subshell error: ${_sdk_stderr}" \
            > "${_GS_EU_FETCH_ERROR_FILE:-/tmp/gs-fetch-error}" 2>/dev/null || true
        fi
      fi
    fi
    rm -f "${_sdk_err_tmp}" 2>/dev/null || true
  fi

  if [[ -n "${cli_result}" ]]; then
    local cli_proposed
    cli_proposed="$(_gs_eu_sdkman_select_best_version "${cli_result}" "${major_constraint}" "${candidate}" "${channel}" "${current_version}")"
    if [[ -n "${cli_proposed}" ]]; then
      _gs_eu_cache_write "${cache_key}" "${cli_proposed}"
      echo "${cli_proposed}"
      return 0
    fi
  fi

  # ------------------------------------------------------------------
  # Fallback: SDKMAN API  (v2: /candidates/{c}/linux/versions/list)
  # Java is distribution-based (e.g. 21.0.7-tem, 21.0.7-zulu) but the same
  # /versions/list endpoint returns the full distribution table, which
  # _gs_eu_sdkman_select_best_java_version already knows how to parse.
  # ------------------------------------------------------------------
  local url="${_GS_EU_SDKMAN_API_BASE}/candidates/${candidate}/linux/versions/list?current=${current_version}&pageSize=40"
  _gs_eu_log_debug "sdkman API: GET ${url}"
  local response http_code
  http_code="$(curl --silent --location --max-time 15 --retry 2 -o /tmp/gs-sdkman-resp -w "%{http_code}" "${url}" 2>/dev/null || echo "0")"
  response="$(cat /tmp/gs-sdkman-resp 2>/dev/null || true)"
  rm -f /tmp/gs-sdkman-resp
  _gs_eu_log_debug "sdkman API response HTTP ${http_code}: ${response:0:200}"
  if [[ "${http_code:0:1}" != "2" ]]; then
    # Try /versions/all endpoint — may work for multi-distribution candidates like Java
    url="${_GS_EU_SDKMAN_API_BASE}/candidates/${candidate}/linux/versions/all"
    _gs_eu_log_debug "sdkman API fallback 1: GET ${url}"
    http_code="$(curl --silent --location --max-time 15 --retry 2 -o /tmp/gs-sdkman-resp -w "%{http_code}" "${url}" 2>/dev/null || echo "0")"
    response="$(cat /tmp/gs-sdkman-resp 2>/dev/null || true)"
    rm -f /tmp/gs-sdkman-resp
    _gs_eu_log_debug "sdkman /versions/all HTTP ${http_code}: ${response:0:200}"
  fi

  if [[ "${http_code:0:1}" != "2" ]]; then
    # Try /default fallback
    url="${_GS_EU_SDKMAN_API_BASE}/candidates/${candidate}/default"
    _gs_eu_log_debug "sdkman API fallback 2: GET ${url}"
    http_code="$(curl --silent --location --max-time 15 --retry 2 -o /tmp/gs-sdkman-resp -w "%{http_code}" "${url}" 2>/dev/null || echo "0")"
    response="$(cat /tmp/gs-sdkman-resp 2>/dev/null || true)"
    rm -f /tmp/gs-sdkman-resp
    _gs_eu_log_debug "sdkman fallback HTTP ${http_code}: ${response:0:200}"
    if [[ "${http_code:0:1}" != "2" ]]; then
      _gs_eu_set_fetch_error "sdkman API HTTP ${http_code} for '${candidate}' (tried: list, versions/all, default endpoints)"
      return 1
    fi
    # Response is just the default version string
    local default_ver="${response}"
    default_ver="${default_ver//[[:space:]]/}"
    if [[ -n "${default_ver}" && -n "${major_constraint}" ]]; then
      local dv_base="${default_ver%%-*}"
      if [[ "${dv_base}" == "${major_constraint}."* ]]; then
        _gs_eu_cache_write "${cache_key}" "${default_ver}"
        echo "${default_ver}"
      fi
    elif [[ -n "${default_ver}" ]]; then
      _gs_eu_cache_write "${cache_key}" "${default_ver}"
      echo "${default_ver}"
    fi
    return 0
  fi

  # Parse version list response — it's a text list of versions
  local proposed
  proposed="$(_gs_eu_sdkman_select_best_version "${response}" "${major_constraint}" "${candidate}" "${channel}" "${current_version}")"

  if [[ -n "${proposed}" ]]; then
    _gs_eu_cache_write "${cache_key}" "${proposed}"
    echo "${proposed}"
  fi
}

# Select best version from SDKMAN list response
# SDKMAN list output is a formatted table; extract version numbers
# For Java: strips distribution suffix before comparison, prefers -tem (Temurin)
_gs_eu_sdkman_select_best_version() {
  local response="${1}"
  local major_constraint="${2}"
  local candidate="${3:-}"
  local channel="${4:-}"
  local current_version="${5:-}"

  local is_java=false
  [[ "${candidate}" == "java" ]] && is_java=true

  if [[ "${is_java}" == "true" ]]; then
    _gs_eu_sdkman_select_best_java_version "${response}" "${major_constraint}" "${current_version}" "${channel}"
    return
  fi

  # Extract all version-like tokens from the response
  local all_versions=()
  while IFS= read -r ver; do
    [[ -z "${ver}" ]] && continue
    # Apply major constraint filter if specified
    if [[ -n "${major_constraint}" ]]; then
      [[ "${ver}" == "${major_constraint}."* ]] || continue
    fi
    all_versions+=("${ver}")
  done < <(
    printf '%s' "${response}" | \
      grep -oE '[0-9]+\.[0-9]+[.0-9]*(-[a-zA-Z0-9_]+)*' | \
      grep -v '^[[:space:]]*$' | \
      sort -V | \
      uniq \
      2>/dev/null || true
  )

  if [[ ${#all_versions[@]} -eq 0 ]]; then
    return 0
  fi

  local all_version_tokens
  all_version_tokens="$(printf '%s\n' "${all_versions[@]}")"
  local proposed
  proposed="$(_gs_eu_channel_select_best "${all_version_tokens}" "${channel}")"
  [[ -n "${proposed}" ]] && echo "${proposed}"
}

# Select best Java version from SDKMAN list output.
# Java versions look like: "21.0.7-tem", "21.0.7-zulu", "17.0.11-tem"
# Preference order: same distribution as current_version > -tem (Temurin) > others.
# Note: distribution suffixes (-tem, -zulu, etc.) are NOT pre-release markers.
# Only versions with actual RC/beta/alpha qualifiers in the numeric part are pre-releases.
_gs_eu_sdkman_select_best_java_version() {
  local response="${1}"
  local major_constraint="${2}"
  local current_version="${3:-}"
  local channel="${4:-}"

  # Determine stable vs channel mode
  local is_stable_mode=true
  if [[ -n "${channel}" && "${channel}" != "stable" ]]; then
    is_stable_mode=false
  fi

  # Extract distribution suffix from current_version (e.g. "zulu" from "11.0.30-zulu")
  # Used to prefer the same distribution the user is already tracking
  local preferred_dist=""
  if [[ "${current_version}" == *"-"* ]]; then
    preferred_dist="${current_version##*-}"
  fi

  local preferred_dist_versions=() tem_versions=() other_versions=()
  local ver

  while IFS= read -r ver; do
    [[ -z "${ver}" ]] && continue
    # Apply major constraint — strip suffix first
    local ver_base="${ver%%-*}"
    if [[ -n "${major_constraint}" ]]; then
      [[ "${ver_base}" == "${major_constraint}."* ]] || continue
    fi
    # For Java, a pre-release is indicated by rc/beta/alpha in the NUMERIC base part
    # Distribution suffixes like -tem, -zulu are not pre-releases
    local is_java_pre=false
    if [[ "${ver_base,,}" =~ (rc|beta|alpha|ea) ]]; then
      is_java_pre=true
    fi

    if [[ "${is_stable_mode}" == "true" ]] && [[ "${is_java_pre}" == "true" ]]; then
      continue  # Skip pre-releases in stable mode
    fi
    if [[ "${is_stable_mode}" == "false" ]] && [[ "${is_java_pre}" == "false" ]]; then
      # In channel mode, only track pre-releases (skip stable Java versions here;
      # stable gets written as alt hint separately)
      continue
    fi

    local ver_dist="${ver##*-}"
    if [[ -n "${preferred_dist}" && "${ver_dist}" == "${preferred_dist}" ]]; then
      preferred_dist_versions+=("${ver}")
    elif [[ "${ver}" == *"-tem" && "${preferred_dist}" != "tem" ]]; then
      tem_versions+=("${ver}")
    else
      other_versions+=("${ver}")
    fi
  done < <(
    printf '%s' "${response}" | \
      grep -oE '[0-9]+\.[0-9]+[.0-9]*-[a-zA-Z]+' | \
      grep -E '^[0-9]+\.[0-9]+[.0-9]*-[a-zA-Z]+$' | \
      grep -v '^[[:space:]]*$' | \
      sort -t- -k1,1V | \
      uniq \
      2>/dev/null || true
  )

  # For channel mode: also collect stable versions for the alt hint
  if [[ "${is_stable_mode}" == "false" ]]; then
    local stable_preferred=() stable_tem=() stable_other=()
    while IFS= read -r ver; do
      [[ -z "${ver}" ]] && continue
      local ver_base="${ver%%-*}"
      if [[ -n "${major_constraint}" ]]; then
        [[ "${ver_base}" == "${major_constraint}."* ]] || continue
      fi
      local is_java_pre=false
      if [[ "${ver_base,,}" =~ (rc|beta|alpha|ea) ]]; then
        is_java_pre=true
      fi
      [[ "${is_java_pre}" == "true" ]] && continue
      local ver_dist="${ver##*-}"
      if [[ -n "${preferred_dist}" && "${ver_dist}" == "${preferred_dist}" ]]; then
        stable_preferred+=("${ver}")
      elif [[ "${ver}" == *"-tem" && "${preferred_dist}" != "tem" ]]; then
        stable_tem+=("${ver}")
      else
        stable_other+=("${ver}")
      fi
    done < <(
      printf '%s' "${response}" | \
        grep -oE '[0-9]+\.[0-9]+[.0-9]*-[a-zA-Z]+' | \
        grep -E '^[0-9]+\.[0-9]+[.0-9]*-[a-zA-Z]+$' | \
        grep -v '^[[:space:]]*$' | \
        sort -t- -k1,1V | \
        uniq \
        2>/dev/null || true
    )

    local highest_stable_java=""
    if [[ ${#stable_preferred[@]} -gt 0 ]]; then
      highest_stable_java="$(printf '%s\n' "${stable_preferred[@]}" | sort -t- -k1,1V | tail -1)"
    elif [[ ${#stable_tem[@]} -gt 0 ]]; then
      highest_stable_java="$(printf '%s\n' "${stable_tem[@]}" | sort -t- -k1,1V | tail -1)"
    elif [[ ${#stable_other[@]} -gt 0 ]]; then
      highest_stable_java="$(printf '%s\n' "${stable_other[@]}" | sort -t- -k1,1V | tail -1)"
    fi
    [[ -n "${highest_stable_java}" ]] && _gs_eu_write_alt_version "stable" "${highest_stable_java}"
  fi

  if [[ ${#preferred_dist_versions[@]} -gt 0 ]]; then
    # Sort by base version (before dash) and return highest preferred-dist version
    printf '%s\n' "${preferred_dist_versions[@]}" | \
      sort -t- -k1,1V | tail -1
    return 0
  fi

  if [[ ${#tem_versions[@]} -gt 0 ]]; then
    # Sort by base version (before dash) and return highest -tem
    printf '%s\n' "${tem_versions[@]}" | \
      sort -t- -k1,1V | tail -1
    return 0
  fi

  if [[ ${#other_versions[@]} -gt 0 ]]; then
    printf '%s\n' "${other_versions[@]}" | \
      sort -t- -k1,1V | tail -1
    return 0
  fi

  return 0
}
