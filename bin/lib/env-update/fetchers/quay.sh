#!/bin/bash
# Quay.io API fetcher.
# Used for keycloak and other Quay-hosted images.

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_EU_QUAY_SH_LOADED:-}" ]] && return 0
readonly _GS_EU_QUAY_SH_LOADED=1

# Fetch latest tag from Quay.io
# Usage: _gs_eu_quay_fetch_latest "keycloak/keycloak" "26.5.5-0"
# Extended: tag flag parameters for filtering/transforming tags
_gs_eu_quay_fetch_latest() {
  local identifier="${1}"    # "org/image"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"
  local tag_filter="${5:-}"
  local tag_exclude="${6:-}"
  local tag_strip_prefix="${7:-}"
  local tag_strip_suffix="${8:-}"
  local tag_extract="${9:-}"
  local tag_replace_from="${10:-}"
  local tag_replace_to="${11:-}"
  local channel="${12:-}"
  local version_prefix="${13:-}"

  local cache_key="quay:${identifier}:${tag_filter}:${tag_exclude}:${tag_extract}:${tag_replace_from}:${channel}"

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

  # Quay.io API v1
  local url="https://quay.io/api/v1/repository/${identifier}/tag/?limit=50&onlyActiveTags=true"
  local response
  if ! response="$(curl --silent --location --fail --max-time 10 --retry 2 \
    -H "Accept: application/json" \
    "${url}" 2>/dev/null)"; then
    return 1
  fi

  local proposed
  proposed="$(_gs_eu_quay_select_best_tag "${response}" "${current_version}" \
    "${tag_filter}" "${tag_exclude}" "${tag_strip_prefix}" "${tag_strip_suffix}" "${tag_extract}" \
    "${tag_replace_from}" "${tag_replace_to}" "${channel}")"

  if [[ -n "${proposed}" ]]; then
    # Apply version_prefix if set
    if [[ -n "${version_prefix}" ]]; then
      proposed="${version_prefix}${proposed}"
    fi
    _gs_eu_cache_write "${cache_key}" "${proposed}"
    echo "${proposed}"
  fi
}

# Select best tag from Quay.io API response
# Args: response current_version [tag_filter tag_exclude tag_strip_prefix tag_strip_suffix tag_extract tag_replace_from tag_replace_to] [channel]
_gs_eu_quay_select_best_tag() {
  local response="${1}"
  local current_version="${2}"
  local tag_filter="${3:-}"
  local tag_exclude="${4:-}"
  local tag_strip_prefix="${5:-}"
  local tag_strip_suffix="${6:-}"
  local tag_extract="${7:-}"
  local tag_replace_from="${8:-}"
  local tag_replace_to="${9:-}"
  local channel="${10:-}"

  # ------------------------------------------------------------------
  # Tag flags: when any are set, apply them and return highest result
  # ------------------------------------------------------------------
  local _has_tag_flags=false
  if [[ -n "${tag_filter}${tag_exclude}${tag_strip_prefix}${tag_strip_suffix}${tag_extract}${tag_replace_from}" ]]; then
    _has_tag_flags=true
  fi

  if [[ "${_has_tag_flags}" == "true" ]]; then
    local all_tag_names
    all_tag_names="$(printf '%s' "${response}" | jq -r '[.tags[].name] | .[]' 2>/dev/null || echo "")"
    local filtered_tags
    filtered_tags="$(printf '%s\n' "${all_tag_names}" | _gs_eu_apply_tag_flags \
      "${tag_filter}" "${tag_exclude}" "${tag_strip_prefix}" "${tag_strip_suffix}" "${tag_extract}" \
      "${tag_replace_from}" "${tag_replace_to}")"

    local proposed
    proposed="$(_gs_eu_channel_select_best "${filtered_tags}" "${channel}")"
    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
    return 0
  fi

  # ------------------------------------------------------------------
  # Non-tag-flags path: collect all semver-like tags, delegate to channel selector
  # ------------------------------------------------------------------

  # Prefer strict semver-build tags (e.g. 26.5.7-0) first; collect stable candidates
  local strict_stable_tags
  strict_stable_tags="$(printf '%s' "${response}" | jq -r \
    '[.tags[].name | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+-[0-9]+$"))] | .[]' \
    2>/dev/null || echo "")"

  # All semver-like tags (excluding bare latest/nightly)
  local all_semver_tags
  all_semver_tags="$(printf '%s' "${response}" | jq -r \
    '[.tags[].name | select(test("^[0-9]+\\.[0-9]") and (test("latest|nightly") | not))] | .[]' \
    2>/dev/null || echo "")"

  # For the stable/default path, prefer the strict-semver-build set if it yields a result;
  # otherwise fall through to the full semver set.
  # We achieve this by trying strict_stable_tags first, then falling back.
  local proposed=""
  if [[ -n "${strict_stable_tags}" ]]; then
    proposed="$(_gs_eu_channel_select_best "${strict_stable_tags}" "${channel}")"
  fi
  if [[ -z "${proposed}" && -n "${all_semver_tags}" ]]; then
    proposed="$(_gs_eu_channel_select_best "${all_semver_tags}" "${channel}")"
  fi
  echo "${proposed}"
}
