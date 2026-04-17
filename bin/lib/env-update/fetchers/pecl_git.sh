#!/bin/bash
# PECL git SHA resolution fetcher.
# For packages installed from GitHub commits (git-SHA track).
# Checks if a stable PECL release now exists for the extension,
# suggesting promotion from git-SHA to semver.

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_EU_PECL_GIT_SH_LOADED:-}" ]] && return 0
readonly _GS_EU_PECL_GIT_SH_LOADED=1

# Global: rich metadata from the last pecl-git fetch.
# Format: "pecl:VERSION:STABILITY:RELEASE_DATE|git:SHA:COMMIT_DATE"
# or "pecl:none|git:SHA:COMMIT_DATE"
_GS_EU_PECL_GIT_METADATA=""

# Fetch latest commit SHA and check if PECL stable is available.
# Usage: _gs_eu_pecl_git_fetch_latest "https://github.com/Imagick/imagick" "abc123def456"
# Usage: _gs_eu_pecl_git_fetch_latest "https://github.com/m6w6/ext-raphf" "abc123" "false" "false" "raphf"
# Returns: echoes proposed SHA or PECL sentinel, or empty on failure
_gs_eu_pecl_git_fetch_latest() {
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
    _gs_eu_log_debug "pecl_git: Cannot extract repo from identifier: ${identifier}"
    return 1
  fi

  local cache_key="pecl-git:${repo_path}"

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

  # Determine extension name
  local ext_name
  if [[ -n "${pecl_ref_override:-}" ]]; then
    ext_name="${pecl_ref_override}"
  else
    ext_name="${repo_path##*/}"
    ext_name="${ext_name#ext-}"  # strip "ext-" prefix (fixes ext-raphf → raphf)
    ext_name="${ext_name,,}"
  fi

  # Fetch latest commit SHA from GitHub
  local latest_sha=""
  if ! latest_sha="$(_gs_eu_github_fetch_latest_sha "${repo_path}" "master" 2>/dev/null)"; then
    latest_sha="$(_gs_eu_github_fetch_latest_sha "${repo_path}" "main" 2>/dev/null || echo "")"
  fi
  if [[ -z "${latest_sha}" ]]; then
    _gs_eu_set_fetch_error "pecl-git: GitHub SHA fetch failed for '${repo_path}' (both master and main branches returned empty — check repo path)"
  fi

  local short_sha=""
  local commit_date=""
  if [[ -n "${latest_sha}" ]]; then
    short_sha="${latest_sha}"  # full 40-char SHA
    # Fetch commit date
    commit_date="$(_gs_eu_github_fetch_commit_date "${repo_path}" "${latest_sha}" 2>/dev/null || true)"
  fi

  # Try PECL full metadata
  local pecl_metadata=""
  pecl_metadata="$(_gs_eu_pecl_fetch_full "${ext_name}" "false" "${no_cache}" 2>/dev/null || true)"

  local pecl_version="" pecl_stab="" pecl_php_min="" pecl_date=""
  if [[ -n "${pecl_metadata}" ]]; then
    IFS=':' read -r pecl_version pecl_stab pecl_php_min pecl_date <<< "${pecl_metadata}"
  fi

  # Set global metadata string
  if [[ -n "${pecl_version}" ]]; then
    _GS_EU_PECL_GIT_METADATA="pecl:${pecl_version}:${pecl_stab:-}:${pecl_date:-}|git:${short_sha:-}:${commit_date:-}"
  else
    _GS_EU_PECL_GIT_METADATA="pecl:none|git:${short_sha:-}:${commit_date:-}"
  fi

  # Decision: if PECL is exactly stable AND pecl release_date > commit_date → promote
  if [[ "${pecl_stab,,}" == "stable" && -n "${pecl_version}" ]]; then
    if [[ -n "${pecl_date}" && -n "${commit_date}" ]]; then
      # Compare dates lexicographically (YYYY-MM-DD format)
      if [[ "${pecl_date}" > "${commit_date}" ]]; then
        local result="__pecl_promotion__:${ext_name}:${pecl_version}"
        _gs_eu_cache_write "${cache_key}" "${result}"
        echo "${result}"
        return 0
      fi
    else
      # No dates available — still suggest promotion if stable exists
      local result="__pecl_promotion__:${ext_name}:${pecl_version}"
      _gs_eu_cache_write "${cache_key}" "${result}"
      echo "${result}"
      return 0
    fi
  fi

  # No promotion — return git SHA
  if [[ -n "${short_sha}" ]]; then
    _gs_eu_cache_write "${cache_key}" "${short_sha}"
    echo "${short_sha}"
    return 0
  fi

  return 1
}
