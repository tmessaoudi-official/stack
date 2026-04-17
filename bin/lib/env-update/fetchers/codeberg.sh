#!/bin/bash
# Codeberg (Gitea) Releases/Tags API fetcher.
# Codeberg runs Gitea — its API schema is compatible with GitHub's for releases and tags.
# API base: https://codeberg.org/api/v1/repos/{owner}/{repo}

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_EU_CODEBERG_SH_LOADED:-}" ]] && return 0
readonly _GS_EU_CODEBERG_SH_LOADED=1

# Fetch latest release from Codeberg
# Usage: _gs_eu_codeberg_fetch_latest "mergiraf/mergiraf" "v0.16.3"
# Extended: _gs_eu_codeberg_fetch_latest "owner/repo" "ver" "offline" "no_cache" "channel"
# Returns: echoed version string or empty on failure
_gs_eu_codeberg_fetch_latest() {
  local identifier="${1}"    # "owner/repo"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"
  local channel="${5:-}"        # channel qualifier (rc, beta, alpha, unstable, ...)

  local cache_key="codeberg:${identifier}:${channel}"

  # Cache check
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
  # Fetch releases (up to 50) and tags (up to 50) from Codeberg API
  # Gitea schema mirrors GitHub: prerelease, draft, tag_name (releases); name (tags)
  # ------------------------------------------------------------------
  local releases_url="https://codeberg.org/api/v1/repos/${identifier}/releases?limit=50"
  local releases_json=""
  releases_json="$(curl --silent --location --fail --max-time 10 --retry 2 \
    -H "Accept: application/json" \
    "${releases_url}" 2>/dev/null || true)"

  local tags_url="https://codeberg.org/api/v1/repos/${identifier}/tags?limit=50"
  local tags_json=""
  tags_json="$(curl --silent --location --fail --max-time 10 --retry 2 \
    -H "Accept: application/json" \
    "${tags_url}" 2>/dev/null || true)"

  if [[ -z "${releases_json}" && -z "${tags_json}" ]]; then
    _gs_eu_set_fetch_error "codeberg: failed to fetch releases and tags for '${identifier}'"
    return 1
  fi

  # Build a unified newline-separated list of all tag names (from both releases + tags)
  local all_tag_names=""
  if [[ -n "${releases_json}" ]]; then
    local rel_tags
    rel_tags="$(printf '%s' "${releases_json}" | \
      jq -r '[.[] | select(.draft == false) | .tag_name | ltrimstr("v")] | .[]' 2>/dev/null || true)"
    all_tag_names+="${rel_tags}"$'\n'
  fi
  if [[ -n "${tags_json}" ]]; then
    local tag_names
    tag_names="$(printf '%s' "${tags_json}" | jq -r '[.[].name | ltrimstr("v")] | .[]' 2>/dev/null || true)"
    all_tag_names+="${tag_names}"$'\n'
  fi
  # Deduplicate
  all_tag_names="$(printf '%s' "${all_tag_names}" | sort -u | grep -v '^$' || true)"

  proposed="$(_gs_eu_channel_select_best "${all_tag_names}" "${channel}")"

  if [[ -z "${proposed}" ]]; then
    _gs_eu_set_fetch_error "codeberg: no matching releases/tags found for '${identifier}'"
    return 1
  fi

  _gs_eu_cache_write "${cache_key}" "${proposed}"
  echo "${proposed}"
}
