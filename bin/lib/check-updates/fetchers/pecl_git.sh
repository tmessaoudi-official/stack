#!/bin/bash
# PECL git SHA resolution fetcher.
# For packages installed from GitHub commits (git-SHA track).
# Checks if a stable PECL release now exists for the extension,
# suggesting promotion from git-SHA to semver.

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_CU_PECL_GIT_SH_LOADED:-}" ]] && return 0
readonly _GS_CU_PECL_GIT_SH_LOADED=1

# Fetch latest commit SHA and check if PECL stable is available.
# Usage: _gs_cu_pecl_git_fetch_latest "https://github.com/Imagick/imagick" "abc123def456"
# Usage: _gs_cu_pecl_git_fetch_latest "https://github.com/m6w6/ext-raphf" "abc123" "false" "false" "raphf"
# Returns: echoes proposed SHA or PECL version, or empty on failure
_gs_cu_pecl_git_fetch_latest() {
  local identifier="${1}"    # "https://github.com/owner/repo"
  local current_sha="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"
  local pecl_ref_override="${5:-}"

  # Extract owner/repo from URL
  local repo_path=""
  if [[ "${identifier}" =~ github\.com/([^/]+)/([^/[:space:]]+) ]]; then
    repo_path="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  else
    _gs_cu_log_debug "pecl_git: Cannot extract repo from identifier: ${identifier}"
    return 1
  fi

  local cache_key="pecl-git:${repo_path}"

  if [[ "${no_cache}" != "true" ]]; then
    local cached
    if cached="$(_gs_cu_cache_read "${cache_key}" 2>/dev/null)"; then
      echo "${cached}"
      return 0
    fi
  fi

  if [[ "${offline}" == "true" ]]; then
    return 1
  fi

  # Determine extension name
  local ext_name
  if [[ -n "${pecl_ref_override:-}" ]]; then
    ext_name="${pecl_ref_override}"
  else
    ext_name="${repo_path##*/}"
    ext_name="${ext_name#ext-}"  # strip "ext-" prefix (fixes ext-raphf → raphf)
    ext_name="${ext_name,,}"
  fi

  # Try PECL first
  local pecl_version=""
  if pecl_version="$(_gs_cu_pecl_fetch_latest "${ext_name}" "" "false" "${no_cache}" 2>/dev/null)"; then
    if [[ -n "${pecl_version}" ]]; then
      # PECL stable found — suggest promotion
      local result="__pecl_promotion__:${ext_name}:${pecl_version}"
      _gs_cu_cache_write "${cache_key}" "${result}"
      echo "${result}"
      return 0
    fi
  fi

  # No PECL release — fetch latest commit SHA from GitHub
  local latest_sha
  if ! latest_sha="$(_gs_cu_github_fetch_latest_sha "${repo_path}" "master" 2>/dev/null)"; then
    # Try main branch
    latest_sha="$(_gs_cu_github_fetch_latest_sha "${repo_path}" "main" 2>/dev/null || echo "")"
  fi

  if [[ -n "${latest_sha}" ]]; then
    # Return short SHA (12 chars) to match typical format
    local short_sha="${latest_sha:0:12}"
    _gs_cu_cache_write "${cache_key}" "${short_sha}"
    echo "${short_sha}"
  fi
}
