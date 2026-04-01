#!/bin/bash
# PECL git SHA resolution fetcher.
# For packages installed from GitHub commits (git-SHA track).
# Checks if a stable PECL release now exists for the extension,
# suggesting promotion from git-SHA to semver.

set -eEuo pipefail

# Fetch latest commit SHA and check if PECL stable is available.
# Usage: _pecl_git_fetch_latest "https://github.com/Imagick/imagick" "abc123def456"
# Returns: echoes proposed SHA or PECL version, or empty on failure
_pecl_git_fetch_latest() {
  local identifier="${1}"    # "https://github.com/owner/repo"
  local current_sha="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"

  # Extract owner/repo from URL
  local repo_path=""
  if [[ "${identifier}" =~ github\.com/([^/]+)/([^/[:space:]]+) ]]; then
    repo_path="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  else
    _log_debug "pecl_git: Cannot extract repo from identifier: ${identifier}"
    return 1
  fi

  local cache_key="pecl-git:${repo_path}"

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

  # First check if a stable PECL release exists for this extension
  # The extension name is typically the repo name (lowercase)
  local ext_name
  ext_name="${repo_path##*/}"
  ext_name="${ext_name,,}"

  # Try PECL first
  local pecl_version=""
  if pecl_version="$(_pecl_fetch_latest "${ext_name}" "" "false" "${no_cache}" 2>/dev/null)"; then
    if [[ -n "${pecl_version}" ]]; then
      # PECL stable found — suggest promotion
      # Return special marker so diff.sh knows this is a promotion
      local result="__pecl_promotion__:${ext_name}:${pecl_version}"
      _cache_write "${cache_key}" "${result}"
      echo "${result}"
      return 0
    fi
  fi

  # No PECL release — fetch latest commit SHA from GitHub
  local latest_sha
  if ! latest_sha="$(_github_fetch_latest_sha "${repo_path}" "master" 2>/dev/null)"; then
    # Try main branch
    latest_sha="$(_github_fetch_latest_sha "${repo_path}" "main" 2>/dev/null || echo "")"
  fi

  if [[ -n "${latest_sha}" ]]; then
    # Return short SHA (12 chars) to match typical format
    local short_sha="${latest_sha:0:12}"
    _cache_write "${cache_key}" "${short_sha}"
    echo "${short_sha}"
  fi
}
