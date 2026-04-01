#!/bin/bash
# GitHub Releases/Tags API fetcher.
# Handles both releases and tags endpoints.

set -eEuo pipefail

# Fetch latest release from GitHub
# Usage: _github_fetch_latest "golang/go" "1.26.1"
# Returns: echoed version string or empty on failure
_github_fetch_latest() {
  local identifier="${1}"    # "owner/repo"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"

  local cache_key="github:${identifier}"

  # Cache check
  if [[ "${no_cache}" != "true" ]]; then
    local cached
    if cached="$(_cache_read "${cache_key}" 2>/dev/null)"; then
      echo "${cached}"
      return 0
    fi
  fi

  if [[ "${offline}" == "true" ]]; then
    return 1
  fi

  # Build auth header if GITHUB_TOKEN is set
  local auth_args=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth_args=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  # Try releases API first
  local releases_url="https://api.github.com/repos/${identifier}/releases"
  local response
  if response="$(curl --silent --fail --max-time 10 --retry 2 \
    "${auth_args[@]}" \
    -H "Accept: application/vnd.github+json" \
    "${releases_url}" 2>/dev/null)"; then

    local proposed
    proposed="$(_github_select_best_release "${response}" "${current_version}")"
    if [[ -n "${proposed}" ]]; then
      _cache_write "${cache_key}" "${proposed}"
      echo "${proposed}"
      return 0
    fi
  fi

  # Fall back to tags API
  local tags_url="https://api.github.com/repos/${identifier}/tags?per_page=50"
  if response="$(curl --silent --fail --max-time 10 --retry 2 \
    "${auth_args[@]}" \
    -H "Accept: application/vnd.github+json" \
    "${tags_url}" 2>/dev/null)"; then

    local proposed
    proposed="$(_github_select_best_tag "${response}" "${current_version}")"
    if [[ -n "${proposed}" ]]; then
      _cache_write "${cache_key}" "${proposed}"
      echo "${proposed}"
      return 0
    fi
  fi

  return 1
}

# Select best release from GitHub releases API JSON
_github_select_best_release() {
  local releases_json="${1}"
  local current_version="${2}"

  local is_pre=false
  if [[ "${current_version,,}" =~ (alpha|beta|rc[0-9]*|preview) ]]; then
    is_pre=true
  fi

  # Prefer non-prerelease unless current is pre
  if [[ "${is_pre}" == "false" ]]; then
    local proposed
    proposed="$(printf '%s' "${releases_json}" | jq -r \
      '[.[] | select(.prerelease == false and .draft == false)] | sort_by(.tag_name) | last | .tag_name // empty' \
      2>/dev/null || echo "")"
    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
  fi

  # Include pre-releases
  local proposed
  proposed="$(printf '%s' "${releases_json}" | jq -r \
    '[.[] | select(.draft == false)] | sort_by(.tag_name) | last | .tag_name // empty' \
    2>/dev/null || echo "")"
  echo "${proposed}"
}

# Select best tag from GitHub tags API JSON
_github_select_best_tag() {
  local tags_json="${1}"
  local current_version="${2}"

  local is_pre=false
  if [[ "${current_version,,}" =~ (alpha|beta|rc[0-9]*|preview|-nightly) ]]; then
    is_pre=true
  fi

  # For node nightly, we need special handling
  if [[ "${current_version}" =~ nightly ]]; then
    # Get latest nightly tag
    local proposed
    proposed="$(printf '%s' "${tags_json}" | jq -r \
      '[.[] | select(.name | test("nightly"))] | sort_by(.name) | last | .name // empty' \
      2>/dev/null || echo "")"
    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
  fi

  # For go tags: golang/go uses "go1.26.1" format
  if [[ "${current_version}" =~ ^[0-9]+\.[0-9]+ ]] || [[ "${current_version}" =~ ^go[0-9]+ ]]; then
    local proposed
    proposed="$(printf '%s' "${tags_json}" | jq -r \
      '[.[] | .name | select(test("^(v|go)?[0-9]+\\.[0-9]"))] | sort | last // empty' \
      2>/dev/null || echo "")"
    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
  fi

  if [[ "${is_pre}" == "false" ]]; then
    local proposed
    proposed="$(printf '%s' "${tags_json}" | jq -r \
      '[.[] | .name | select(test("^v?[0-9]+\\.[0-9]+(\\.[0-9]+)?$"))] | sort | last // empty' \
      2>/dev/null || echo "")"
    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
  fi

  local proposed
  proposed="$(printf '%s' "${tags_json}" | jq -r \
    '[.[] | .name | select(test("^v?[0-9]+\\.[0-9]"))] | sort | last // empty' \
    2>/dev/null || echo "")"
  echo "${proposed}"
}

# Fetch the latest commit SHA from a GitHub repo branch
# Usage: _github_fetch_latest_sha "Imagick/imagick" "master"
_github_fetch_latest_sha() {
  local identifier="${1}"   # "owner/repo"
  local branch="${2:-master}"

  local auth_args=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth_args=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  local url="https://api.github.com/repos/${identifier}/commits/${branch}"
  local response
  if response="$(curl --silent --fail --max-time 10 --retry 2 \
    "${auth_args[@]}" \
    -H "Accept: application/vnd.github+json" \
    "${url}" 2>/dev/null)"; then
    printf '%s' "${response}" | jq -r '.sha // empty' 2>/dev/null || echo ""
  fi
}
