#!/bin/bash
# PECL REST API fetcher.
# PECL uses an XML-based REST API at https://pecl.php.net/rest/

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_EU_PECL_SH_LOADED:-}" ]] && return 0
readonly _GS_EU_PECL_SH_LOADED=1

# Fetch latest stable version of a PECL extension
# Usage: _gs_eu_pecl_fetch_latest "imagick" "3.8.1"
# Extended: _gs_eu_pecl_fetch_latest "imagick" "3.8.1" "false" "false" "beta"
_gs_eu_pecl_fetch_latest() {
  local identifier="${1}"    # extension name, e.g. "imagick"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"
  local channel="${5:-}"

  local cache_key="pecl:${identifier}:${channel}"

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

  # PECL REST API: https://pecl.php.net/rest/r/<extension>/allreleases.xml
  local url="https://pecl.php.net/rest/r/${identifier}/allreleases.xml"
  local response
  if ! response="$(curl --silent --location --fail --max-time 10 --retry 2 "${url}" 2>/dev/null)"; then
    return 1
  fi

  # Parse XML with grep/sed (xmllint may not be available on host)
  local proposed
  proposed="$(_gs_eu_pecl_parse_channel "${response}" "${channel}")"

  if [[ -n "${proposed}" ]]; then
    _gs_eu_cache_write "${cache_key}" "${proposed}"
    echo "${proposed}"
  fi
}

# Fetch rich metadata for a PECL extension.
# Returns colon-separated: VERSION:STABILITY:PHP_MIN:RELEASE_DATE
# Usage: _gs_eu_pecl_fetch_full "imagick"
_gs_eu_pecl_fetch_full() {
  local identifier="${1}"    # extension name, e.g. "imagick"
  local offline="${2:-false}"
  local no_cache="${3:-false}"

  local cache_key="pecl-full:${identifier}"

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

  # Fetch allreleases.xml
  local allreleases_url="https://pecl.php.net/rest/r/${identifier}/allreleases.xml"
  local allreleases_xml
  if ! allreleases_xml="$(curl --silent --location --fail --max-time 10 --retry 2 "${allreleases_url}" 2>/dev/null)"; then
    return 1
  fi

  # Parse version/stability pairs — prefer first stable entry (highest stable)
  local best_ver="" best_stab=""

  local pair ver stab
  while IFS= read -r pair; do
    ver="${pair%%:*}"
    stab="${pair##*:}"
    if [[ "${stab,,}" == "stable" ]]; then
      if [[ -z "${best_ver}" ]]; then
        best_ver="${ver}"
        best_stab="stable"
      fi
    fi
  done < <(
    printf '%s' "${allreleases_xml}" | \
      grep -oE '<v>[^<]+</v><s>[^<]+</s>' | \
      sed 's|<v>\([^<]*\)</v><s>\([^<]*\)</s>|\1:\2|g' \
      2>/dev/null || true
  )

  # If no stable, take first non-stable (highest available)
  if [[ -z "${best_ver}" ]]; then
    while IFS= read -r pair; do
      ver="${pair%%:*}"
      stab="${pair##*:}"
      if [[ -z "${best_ver}" ]]; then
        best_ver="${ver}"
        best_stab="${stab,,}"
      fi
    done < <(
      printf '%s' "${allreleases_xml}" | \
        grep -oE '<v>[^<]+</v><s>[^<]+</s>' | \
        sed 's|<v>\([^<]*\)</v><s>\([^<]*\)</s>|\1:\2|g' \
        2>/dev/null || true
    )
  fi

  if [[ -z "${best_ver}" ]]; then
    return 1
  fi

  # Fetch per-version XML for date and PHP min
  local ver_url="https://pecl.php.net/rest/r/${identifier}/${best_ver}.xml"
  local ver_xml=""
  ver_xml="$(curl --silent --location --fail --max-time 10 --retry 2 "${ver_url}" 2>/dev/null || true)"

  local release_date="" php_min=""
  if [[ -n "${ver_xml}" ]]; then
    release_date="$(printf '%s' "${ver_xml}" | grep -oE '<da>[^<]+</da>' | head -1 | sed 's|<da>\([^<]*\)</da>|\1|' | cut -c1-10 || true)"
    # PHP min from <dep><name>php</name>...<min>VERSION</min>
    php_min="$(printf '%s' "${ver_xml}" | grep -oE '<min>[^<]+</min>' | head -1 | sed 's|<min>\([^<]*\)</min>|\1|' || true)"
  fi

  local result="${best_ver}:${best_stab:-stable}:${php_min:-}:${release_date:-}"
  _gs_eu_cache_write "${cache_key}" "${result}"
  echo "${result}"
}

# Parse PECL allreleases XML and return best version based on channel.
# channel: empty or "stable" → stable-first with pre-release alt hint
# channel: "beta", "alpha", "unstable", "rc" → propose pre-release, write stable as alt
_gs_eu_pecl_parse_channel() {
  local xml="${1}"
  local channel="${2:-}"

  # Determine mode
  local is_stable_mode=true
  if [[ -n "${channel}" && "${channel}" != "stable" ]]; then
    is_stable_mode=false
  fi

  # Extract ALL version/stability pairs from XML
  # XML format: <v>X.Y.Z</v><s>stable|beta|alpha|...</s>
  local stable_versions=() pre_versions=()

  local pair
  while IFS= read -r pair; do
    local ver="${pair%%:*}"
    local stab="${pair##*:}"
    local stab_lower="${stab,,}"
    if [[ "${stab_lower}" == "stable" ]]; then
      stable_versions+=("${ver}")
    elif [[ "${stab_lower}" =~ (beta|alpha|rc|devel) ]]; then
      pre_versions+=("${ver}")
    fi
  done < <(
    printf '%s' "${xml}" | \
      grep -oE '<v>[^<]+</v><s>[^<]+</s>' | \
      sed 's|<v>\([^<]*\)</v><s>\([^<]*\)</s>|\1:\2|g' \
      2>/dev/null || true
  )

  if [[ "${is_stable_mode}" == "true" ]]; then
    # Stable mode: propose highest stable; write highest pre-release as "also" hint
    local proposed=""
    if [[ ${#stable_versions[@]} -gt 0 ]]; then
      proposed="$(printf '%s\n' "${stable_versions[@]}" | sort -V | tail -1)"
    fi

    # Write pre-release alt hint if a pre-release exists
    if [[ ${#pre_versions[@]} -gt 0 ]]; then
      local highest_pre
      highest_pre="$(printf '%s\n' "${pre_versions[@]}" | sort -V | tail -1)"
      [[ -n "${highest_pre}" ]] && _gs_eu_write_alt_version "also" "${highest_pre}"
    fi

    if [[ -n "${proposed}" ]]; then
      echo "${proposed}"
      return 0
    fi

    # Fallback: no stable found — propose highest pre-release (same as before)
    if [[ ${#pre_versions[@]} -gt 0 ]]; then
      printf '%s\n' "${pre_versions[@]}" | sort -V | tail -1
    fi
    return 0
  else
    # Channel/pre-release mode: propose highest pre-release matching the qualifier (or any pre-release)
    # Write highest stable as "stable" alt hint
    local proposed=""

    if [[ "${channel}" == "unstable" ]]; then
      # Any pre-release
      if [[ ${#pre_versions[@]} -gt 0 ]]; then
        proposed="$(printf '%s\n' "${pre_versions[@]}" | sort -V | tail -1)"
      fi
    else
      # Filter pre-releases by specific qualifier (beta, alpha, rc)
      local matched_versions=()
      local pv
      for pv in "${pre_versions[@]}"; do
        local pv_lower="${pv,,}"
        if [[ "${pv_lower}" =~ ${channel} ]]; then
          matched_versions+=("${pv}")
        fi
      done
      if [[ ${#matched_versions[@]} -gt 0 ]]; then
        proposed="$(printf '%s\n' "${matched_versions[@]}" | sort -V | tail -1)"
      else
        # Fall back to any pre-release if no specific qualifier match
        if [[ ${#pre_versions[@]} -gt 0 ]]; then
          proposed="$(printf '%s\n' "${pre_versions[@]}" | sort -V | tail -1)"
        fi
      fi
    fi

    # Write stable as alt hint
    if [[ ${#stable_versions[@]} -gt 0 ]]; then
      local highest_stable
      highest_stable="$(printf '%s\n' "${stable_versions[@]}" | sort -V | tail -1)"
      [[ -n "${highest_stable}" ]] && _gs_eu_write_alt_version "stable" "${highest_stable}"
    fi

    [[ -n "${proposed}" ]] && echo "${proposed}"
    return 0
  fi
}

# Parse PECL allreleases XML and return highest stable version
# (legacy wrapper — kept for backward compatibility)
_gs_eu_pecl_parse_latest_stable() {
  local xml="${1}"
  _gs_eu_pecl_parse_channel "${xml}" "stable"
}
