#!/bin/bash
# URL fetcher — tiered strategy for arbitrary URLs.
# Tier 0: fetch-extract / fetch-json flags (when set, skip all other tiers)
# Tier 1: GitHub redirect (via urls: annotation)
# Tier 2: (reserved — all hardcoded handlers removed; use fetch-extract/fetch-json/github: instead)
# Tier 3: Apache/SVN/GNU directory listings
# Tier 4: Generic HTML version extraction
# Tier 5: MANUAL fallback
# url-probe: special mechanism for repo-availability probing (CRI-O, kubic)

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_EU_URL_SH_LOADED:-}" ]] && return 0
readonly _GS_EU_URL_SH_LOADED=1

# Fetch latest version for a URL-based identifier.
# Usage: _gs_eu_url_fetch_latest "URL" "current" "offline" "no_cache" "ref_urls" \
#          "fetch_extract" "fetch_json" "url_probe" "url_probe_depth"
_gs_eu_url_fetch_latest() {
  local identifier="${1}"    # the URL itself
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"
  local ref_urls="${5:-}"        # space-separated urls: from annotation
  local fetch_extract="${6:-}"   # regex to extract from response body
  local fetch_json="${7:-}"      # jq path to extract from JSON response
  local url_probe="${8:-}"       # comma-separated probe paths
  local url_probe_depth="${9:-6}" # how many codenames back to probe
  local channel="${10:-}"        # channel (nightly, stable, beta)
  local version_prefix="${11:-}" # prepend to proposed version

  local cache_key="url:${identifier}:${fetch_extract:+fe}:${fetch_json:+fj}:${url_probe:+up}:${channel}"

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

  local proposed=""

  # ------------------------------------------------------------------
  # url-probe mechanism — special availability probing
  # When url_probe is set, probe paths for each codename going back
  # ------------------------------------------------------------------
  if [[ -n "${url_probe}" ]]; then
    local _probe_result
    _probe_result="$(_gs_eu_url_probe_check \
      "${identifier}" "${url_probe}" "${url_probe_depth}" "${cache_key}")"
    if [[ -n "${_probe_result}" ]]; then
      echo "${_probe_result}"
      return 0
    fi
    # Return empty — let caller handle NORES
    return 0
  fi

  # ------------------------------------------------------------------
  # Tier 0 — fetch-extract: fetch URL, extract via regex capture group 1.
  # Takes FULL priority — skips all other tiers when set.
  # ------------------------------------------------------------------
  if [[ -n "${fetch_extract}" ]]; then
    local raw_body
    raw_body="$(curl --silent --location --max-time 20 --retry 2 \
        -H "User-Agent: Mozilla/5.0 (compatible; GlobalStack/1.0)" \
        "${identifier}" 2>/dev/null || true)"
    if [[ -n "${raw_body}" ]]; then
      proposed="$(printf '%s' "${raw_body}" | \
        perl -ne "if (/${fetch_extract}/) { print \"\$1\n\" }" 2>/dev/null | \
        sort -V | tail -1 || true)"
    fi
    if [[ -n "${proposed}" ]]; then
      # Stable mode: if result is a pre-release, write alt hint and return empty
      local _fe_is_stable_mode=true
      if [[ -n "${channel}" && "${channel}" != "stable" && "${channel}" != "nightly" ]]; then
        _fe_is_stable_mode=false
      fi
      if [[ "${_fe_is_stable_mode}" == "true" ]] && _gs_eu_is_prerelease "${proposed}"; then
        _gs_eu_write_alt_version "also" "${proposed}"
        _gs_eu_set_fetch_error "url: fetch-extract returned pre-release '${proposed}' in stable mode"
        return 1
      fi
      if [[ -n "${version_prefix}" ]]; then
        proposed="${version_prefix}${proposed}"
      fi
      _gs_eu_cache_write "${cache_key}" "${proposed}"
      echo "${proposed}"
      return 0
    fi
    _gs_eu_set_fetch_error "url: fetch-extract pattern '${fetch_extract}' matched nothing from ${identifier}"
    return 1
  fi

  # ------------------------------------------------------------------
  # Tier 0 — fetch-json: fetch URL as JSON and extract via jq
  # ------------------------------------------------------------------
  if [[ -n "${fetch_json}" ]]; then
    local json_body
    if json_body="$(curl --silent --location --fail --max-time 15 --retry 2 \
        "${identifier}" 2>/dev/null)"; then
      proposed="$(printf '%s' "${json_body}" | jq -r "${fetch_json}" 2>/dev/null || true)"
      proposed="${proposed//null/}"
      if [[ -n "${proposed}" ]]; then
        # Stable mode: if result is a pre-release, write alt hint and return empty
        local _fj_is_stable_mode=true
        if [[ -n "${channel}" && "${channel}" != "stable" && "${channel}" != "nightly" ]]; then
          _fj_is_stable_mode=false
        fi
        if [[ "${_fj_is_stable_mode}" == "true" ]] && _gs_eu_is_prerelease "${proposed}"; then
          _gs_eu_write_alt_version "also" "${proposed}"
          _gs_eu_set_fetch_error "url: fetch-json returned pre-release '${proposed}' in stable mode"
          return 1
        fi
        if [[ -n "${version_prefix}" ]]; then
          proposed="${version_prefix}${proposed}"
        fi
        _gs_eu_cache_write "${cache_key}" "${proposed}"
        echo "${proposed}"
        return 0
      fi
    fi
    _gs_eu_set_fetch_error "url: fetch-json jq path '${fetch_json}' returned empty from ${identifier}"
    return 1
  fi

  # ------------------------------------------------------------------
  # channel:nightly — directory listing mode
  # Fetch a URL directory listing, extract nightly version entries,
  # apply optional filter prefix parsed from URL (URL:FILTER syntax),
  # sort lexicographically, return latest.
  # ------------------------------------------------------------------
  if [[ "${channel}" == "nightly" ]]; then
    # Parse optional filter from URL: "https://host/path/:FILTER" → URL + filter prefix
    local nightly_url="${identifier}"
    local nightly_filter=""
    if [[ "${identifier}" =~ ^(https?://[^:]+)/:(.+)$ ]]; then
      nightly_url="${BASH_REMATCH[1]}/"
      nightly_filter="${BASH_REMATCH[2]}"
    fi

    local nightly_html
    nightly_html="$(curl --silent --location --max-time 20 --retry 2 \
      -H "User-Agent: Mozilla/5.0 (compatible; GlobalStack/1.0)" \
      "${nightly_url}" 2>/dev/null || true)"

    if [[ -n "${nightly_html}" ]]; then
      # Extract directory hrefs that look like nightly version entries
      local nightly_entries
      nightly_entries="$(printf '%s' "${nightly_html}" | \
        perl -ne 'while (/href="([^"\/][^"]*\/?)"/g) { print "$1\n" }' 2>/dev/null | \
        grep -v '^[.?#]' | \
        sed 's|/$||' | \
        grep -E '[0-9]' | \
        grep -v '^$' || true)"

      if [[ -n "${nightly_filter}" ]]; then
        nightly_entries="$(printf '%s\n' "${nightly_entries}" | grep "^${nightly_filter}" || true)"
      fi

      # Use version-aware sort so v26.x correctly ranks above v6.x or v9.x
      proposed="$(printf '%s\n' "${nightly_entries}" | sort -V | tail -1 || true)"
      proposed="${proposed%/}"
    fi

    if [[ -n "${proposed}" ]]; then
      if [[ -n "${version_prefix}" ]]; then
        proposed="${version_prefix}${proposed}"
      fi
      _gs_eu_cache_write "${cache_key}" "${proposed}"
      echo "${proposed}"
      return 0
    fi
    _gs_eu_set_fetch_error "url: channel:nightly — no entries found at ${nightly_url}"
    return 1
  fi

  # ------------------------------------------------------------------
  # Tier 1 — GitHub redirect via ref_urls annotation
  # ------------------------------------------------------------------
  if [[ -n "${ref_urls}" ]]; then
    local ref_url
    for ref_url in ${ref_urls}; do
      if [[ "${ref_url}" =~ github\.com/([^/]+)/([^/[:space:]]+) ]]; then
        local gh_owner="${BASH_REMATCH[1]}"
        local gh_repo="${BASH_REMATCH[2]}"
        # Strip trailing path segments like /releases or /tags
        gh_repo="${gh_repo%%/*}"
        gh_repo="${gh_repo%.git}"
        local gh_identifier="${gh_owner}/${gh_repo}"
        _gs_eu_log_debug "url: GitHub redirect ${identifier} → ${gh_identifier}"
        if proposed="$(_gs_eu_github_fetch_latest "${gh_identifier}" "${current_version}" \
            "false" "${no_cache}" "" "" "" "" "" "" "" "" "${channel}" 2>/dev/null)"; then
          if [[ -n "${proposed}" ]]; then
            _gs_eu_cache_write "${cache_key}" "${proposed}"
            echo "${proposed}"
            return 0
          fi
        fi
      fi
    done
  fi

  # ------------------------------------------------------------------
  # Tier 3 — Apache/SVN/GNU directory listings
  # ------------------------------------------------------------------

  local is_directory_listing=false
  if [[ "${identifier}" =~ svn\.apache\.org/repos/asf/ ]] || \
     [[ "${identifier}" =~ /pub/gnu/ ]] || \
     [[ "${identifier}" =~ apache\.org.*tags/ ]]; then
    is_directory_listing=true
  fi

  if [[ "${is_directory_listing}" == "true" ]]; then
    local dir_html
    if dir_html="$(curl --silent --location --fail --max-time 15 --retry 2 \
        "${identifier}" 2>/dev/null)"; then
      # Extract href values that look like version directories
      local dir_candidates
      dir_candidates="$(printf '%s' "${dir_html}" | \
        grep -oE 'href="[^"]*"' | \
        sed 's|href="||;s|"$||' | \
        grep -E '[0-9]+\.[0-9]' | \
        sed 's|/$||;s|^.*/||' | \
        grep -oE '[0-9]+\.[0-9][0-9a-zA-Z._-]*' | \
        grep -v '^[[:space:]]*$' | \
        sort -V 2>/dev/null || true)"

      proposed="$(_gs_eu_channel_select_best "${dir_candidates}" "${channel}")"

      if [[ -n "${proposed}" ]]; then
        if [[ -n "${version_prefix}" ]]; then
          proposed="${version_prefix}${proposed}"
        fi
        _gs_eu_cache_write "${cache_key}" "${proposed}"
        echo "${proposed}"
        return 0
      fi
    fi
  fi

  # ------------------------------------------------------------------
  # Tier 4 — Generic HTML version extraction
  # ------------------------------------------------------------------
  local html
  if html="$(curl --silent --location --fail --max-time 15 --retry 2 \
      -H "User-Agent: Mozilla/5.0 (compatible; GlobalStack/1.0)" \
      "${identifier}" 2>/dev/null)"; then

    # Extract version-like strings
    # Filter out date-like patterns (YYYY.MM.DD) and overly long strings
    local candidates
    candidates="$(printf '%s' "${html}" | \
      grep -oE '[0-9]+\.[0-9]+\.[0-9]+[a-zA-Z0-9._-]*' | \
      grep -vE '^20[0-9]{2}\.[0-9]{2}\.[0-9]{2}$' | \
      grep -vE '.{30,}' | \
      sort -V | uniq | tail -20 2>/dev/null || true)"

    if [[ -n "${candidates}" ]]; then
      # Stable mode: check for a keyword-anchored version near "latest/stable/release" first
      local _t4_is_stable_mode=true
      if [[ -n "${channel}" && "${channel}" != "stable" && "${channel}" != "nightly" ]]; then
        _t4_is_stable_mode=false
      fi

      if [[ "${_t4_is_stable_mode}" == "true" ]]; then
        local keyword_ver=""
        keyword_ver="$(printf '%s' "${html}" | \
          grep -iE '(latest|stable|release|download|current)[^0-9]{0,30}[0-9]+\.[0-9]+\.[0-9]+' | \
          grep -oE '[0-9]+\.[0-9]+\.[0-9]+[a-zA-Z0-9._-]*' | \
          grep -vE '^20[0-9]{2}\.[0-9]{2}\.[0-9]{2}$' | \
          sort -V | tail -1 2>/dev/null || true)"
        # Only accept keyword_ver if it's genuinely stable
        if [[ -n "${keyword_ver}" ]] && _gs_eu_is_prerelease "${keyword_ver}"; then
          keyword_ver=""
        fi
        if [[ -n "${keyword_ver}" ]]; then
          proposed="${keyword_ver}"
          # Still write alt hint for pre-releases
          local _kw_pre
          _kw_pre="$(_gs_eu_channel_select_best "${candidates}" "unstable")"
          [[ -n "${_kw_pre}" ]] && _gs_eu_write_alt_version "also" "${_kw_pre}"
        fi
      fi

      if [[ -z "${proposed}" ]]; then
        proposed="$(_gs_eu_channel_select_best "${candidates}" "${channel}")"
      fi

      if [[ -n "${proposed}" ]]; then
        if [[ -n "${version_prefix}" ]]; then
          proposed="${version_prefix}${proposed}"
        fi
        _gs_eu_cache_write "${cache_key}" "${proposed}"
        echo "${proposed}"
        return 0
      fi
    fi
  fi

  # ------------------------------------------------------------------
  # Tier 5 — MANUAL fallback: all tiers exhausted, report what was tried
  # ------------------------------------------------------------------
  local http_code
  http_code="$(curl --silent --location --max-time 10 -o /dev/null -w "%{http_code}" \
    -H "User-Agent: Mozilla/5.0 (compatible; GlobalStack/1.0)" \
    "${identifier}" 2>/dev/null || echo "0")"
  if [[ "${http_code}" == "0" ]]; then
    _gs_eu_set_fetch_error "url: network error reaching ${identifier}"
  elif [[ "${http_code:0:1}" != "2" ]]; then
    _gs_eu_set_fetch_error "url: HTTP ${http_code} from ${identifier}"
  else
    _gs_eu_set_fetch_error "url: HTTP ${http_code} — page reachable but no version pattern found in ${identifier}"
  fi
  return 1
}

# ------------------------------------------------------------------
# url-probe: probe a list of URL paths for each Ubuntu codename
# going back from the current codename by url_probe_depth steps.
#
# Arguments:
#   base_url      — base URL from annotation identifier
#   probe_paths   — comma-separated path templates, e.g.
#                   "stable/xUbuntu_{codename-version},unstable/xUbuntu_{codename-version}"
#   depth         — how many codenames back to try (default 6)
#   cache_key     — cache key to use
#
# Template variables in paths:
#   {codename}         → Ubuntu codename (e.g. "noble")
#   {codename-version} → Ubuntu version number (e.g. "24.04")
#
# Returns: encoded result like "stable", "unstable", "stable:noble", etc.
# ------------------------------------------------------------------
_gs_eu_url_probe_check() {
  local base_url="${1}"
  local probe_paths="${2}"
  local depth="${3:-6}"
  local cache_key="${4:-url-probe:${base_url}}"

  # Split probe paths into array
  local paths=()
  IFS=',' read -ra paths <<< "${probe_paths}"

  if [[ ${#paths[@]} -eq 0 ]]; then
    return 0
  fi

  # Get ordered codename list (newest first) from codename_map
  local ordered_codenames=()
  local _cn_line
  while IFS= read -r _cn_line; do
    [[ -z "${_cn_line}" ]] && continue
    ordered_codenames+=("${_cn_line%%:*}")
  done < <(_gs_eu_codename_ordered_list)

  # Find the index of the current codename
  local current_codename="${_GS_EU_UBUNTU_CODENAME:-}"
  local start_idx=0
  local i
  for (( i=0; i<${#ordered_codenames[@]}; i++ )); do
    if [[ "${ordered_codenames[${i}]}" == "${current_codename}" ]]; then
      start_idx="${i}"
      break
    fi
  done

  local first_path_label
  first_path_label="${paths[0]%%/*}"  # e.g. "stable" from "stable/xUbuntu_..."

  local end_idx=$(( start_idx + depth - 1 ))
  if [[ "${end_idx}" -ge "${#ordered_codenames[@]}" ]]; then
    end_idx=$(( ${#ordered_codenames[@]} - 1 ))
  fi

  # Probe from current codename going back in history (toward older = higher indices)
  for (( i=start_idx; i<=end_idx; i++ )); do
    local probe_codename="${ordered_codenames[${i}]}"
    local probe_cn_ver
    probe_cn_ver="$(_gs_eu_codename_to_version "${probe_codename}")"

    local path_idx=0
    local probe_path
    for probe_path in "${paths[@]}"; do
      local channel_label="${probe_path%%/*}"
      # Substitute template variables
      local resolved_path="${probe_path}"
      resolved_path="${resolved_path//\{codename\}/${probe_codename}}"
      resolved_path="${resolved_path//\{codename-version\}/${probe_cn_ver}}"

      local full_url="${base_url%/}/${resolved_path}"
      local http_code
      http_code="$(curl --silent --max-time 10 --retry 1 \
        -o /dev/null -w "%{http_code}" "${full_url}" 2>/dev/null || echo "0")"

      # Accept 2xx (success) or 3xx (redirect — resource exists at another URL)
      if [[ "${http_code:0:1}" == "2" || "${http_code:0:1}" == "3" ]]; then
        # Found — encode result
        local result
        if [[ "${probe_codename}" == "${current_codename}" ]]; then
          result="${channel_label}"
        else
          result="${channel_label}:${probe_codename}"
        fi
        _gs_eu_cache_write "${cache_key}" "${result}"
        echo "${result}"
        return 0
      fi
      (( path_idx++ )) || true
    done
  done

  # Nothing found
  return 0
}

# Helper: normalize a url-probe current value to encoded form for comparison
# Input: "stable/xUbuntu_24.04" or "unstable/xUbuntu_24.04"
# Output: "stable" (if 24.04=noble=current) or "stable:noble" (if noble!=current codename)
_gs_eu_url_probe_normalize_current() {
  local current_value="${1}"
  local current_codename="${_GS_EU_UBUNTU_CODENAME:-}"

  local channel="${current_value%%/*}"
  local path_rest="${current_value#*/}"

  # Extract version from xUbuntu_X.XX format
  local cn_ver=""
  if [[ "${path_rest}" =~ xUbuntu_([0-9]+\.[0-9]+) ]]; then
    cn_ver="${BASH_REMATCH[1]}"
  fi

  if [[ -z "${cn_ver}" ]]; then
    echo "${channel}"
    return 0
  fi

  local codename
  codename="$(_gs_eu_version_to_codename "${cn_ver}")"

  if [[ -z "${codename}" || "${codename}" == "${current_codename}" ]]; then
    echo "${channel}"
  else
    echo "${channel}:${codename}"
  fi
}
