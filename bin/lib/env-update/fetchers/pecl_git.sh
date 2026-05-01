#!/bin/bash
# pecl_git.sh — PECL-git fetcher using the record-index contract
#
# Tracks PHP extensions available only as GitHub commits (no stable PECL release yet),
# or where the git HEAD is ahead of the latest PECL stable release.
#
# Input:  record index — reads type/identifier/channel/pecl_ref etc.
# Output: writes proposed_version + error_message + alt_version back into record
#
# Identifier format:   pecl-git:https://github.com/owner/repo
# proposed_version:    YYYYMMDD-<sha8>  (8-char SHA prefix)
# alt_version:         "PECL stable available: VERSION — consider switching to pecl:EXT"
#                      when a stable PECL release postdates the latest git commit.
#
# channel field: repurposed as branch name (default: master with main fallback)
# pecl_ref field: overrides the auto-derived extension name for PECL lookup
#
# Rate-limit note: 2 GitHub API calls per record (commits list + commit detail).
# With GITHUB_TOKEN: 5000 req/hr. Without: 60 req/hr.
#
# ext_name derivation (when pecl_ref is not set):
#   repo name (last URL segment), then strip these prefixes (order matters):
#   1. "php-"   (e.g. php-redis → redis, php-amqp → amqp)
#   2. "php_"   (e.g. php_zip → zip)
#   3. "ext-"   (e.g. ext-raphf → raphf, ext-http → http)
#   The "pecl-" prefix is intentionally NOT stripped — repos like
#   pecl-networking-uuid have their PECL name managed via pecl_ref.
#
# Depends on: github.sh (provides _gs_eu2_github_get_commit_sha and
#             _gs_eu2_github_get_commit_date), pecl.sh (provides
#             _gs_eu2_pecl_check_promotion)

[[ -n "${_GS_EU2_PECL_GIT_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_PECL_GIT_SH_LOADED=1

# shellcheck source=./github.sh
source "$(dirname "${BASH_SOURCE[0]}")/github.sh"
# shellcheck source=./pecl.sh
source "$(dirname "${BASH_SOURCE[0]}")/pecl.sh"

# _gs_eu2_pecl_git_derive_ext_name REPO_NAME
# Derives the PECL extension name from a GitHub repository name.
# See ext_name derivation comment above.
_gs_eu2_pecl_git_derive_ext_name() {
  local _repo_name="${1,,}"   # lowercase
  # Strip in order: php-, php_, ext-
  # (using parameter expansion for each; stop after first match)
  local _ext="${_repo_name#php-}"
  [[ "${_ext}" != "${_repo_name}" ]] && { printf '%s' "${_ext}"; return; }
  _ext="${_repo_name#php_}"
  [[ "${_ext}" != "${_repo_name}" ]] && { printf '%s' "${_ext}"; return; }
  _ext="${_repo_name#ext-}"
  printf '%s' "${_ext}"
}

# Main fetcher entry point — takes one argument: record index.
_gs_eu2_fetch_pecl_git() {
  local _idx="${1}"

  local _identifier _channel _pecl_ref _no_cache
  _identifier="$(_gs_eu2_record_get "${_idx}" identifier)"
  _channel="$(_gs_eu2_record_get "${_idx}" channel)"
  _pecl_ref="$(_gs_eu2_record_get "${_idx}" pecl_ref)"
  _no_cache="${_GS_EU2_CFG[no_cache]:-false}"

  # Extract owner/repo from full GitHub URL
  local _owner_repo=""
  if [[ "${_identifier}" =~ github\.com/([^/[:space:]]+/[^/[:space:]]+) ]]; then
    _owner_repo="${BASH_REMATCH[1]}"
    # Strip trailing .git if present
    _owner_repo="${_owner_repo%.git}"
  else
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "pecl-git: cannot extract owner/repo from '${_identifier}'"
    return 0
  fi

  # Determine ext_name for PECL lookup
  local _ext_name
  if [[ -n "${_pecl_ref}" ]]; then
    _ext_name="${_pecl_ref}"
  else
    local _repo_name="${_owner_repo##*/}"
    _ext_name="$(_gs_eu2_pecl_git_derive_ext_name "${_repo_name}")"
  fi

  # Determine branch: channel field doubles as branch name; default master
  local _branch="${_channel:-master}"

  # Cache key
  local _cache_key="pecl-git2:${_owner_repo}:${_branch}"

  if [[ "${_no_cache}" != "true" ]]; then
    local _cached
    if _cached="$(_gs_eu2_cache_read "${_cache_key}" 2>/dev/null)" && [[ -n "${_cached}" ]]; then
      _gs_eu2_record_set "${_idx}" proposed_version "${_cached}"
      return 0
    fi
  fi

  # ── Step 1: Fetch latest commit SHA ──────────────────────────────────────
  local _sha=""
  _sha="$(_gs_eu2_github_get_commit_sha "${_owner_repo}" "${_branch}" 2>/dev/null)" || true

  # Fallback: try main when master returned nothing
  if [[ -z "${_sha}" && "${_branch}" == "master" ]]; then
    _sha="$(_gs_eu2_github_get_commit_sha "${_owner_repo}" "main" 2>/dev/null)" || true
  fi

  if [[ -z "${_sha}" ]]; then
    local _hint=""
    [[ -z "${GITHUB_TOKEN:-${GLOBAL_STACK_GITHUB_TOKEN:-}}" ]] && _hint=" (set GITHUB_TOKEN or GLOBAL_STACK_GITHUB_TOKEN to avoid rate limits)"
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "pecl-git: GitHub SHA fetch failed for '${_owner_repo}'${_hint}"
    return 0
  fi

  # ── Step 2: Fetch commit date ─────────────────────────────────────────────
  local _commit_date=""
  _commit_date="$(_gs_eu2_github_get_commit_date "${_owner_repo}" "${_sha}" 2>/dev/null)" || true

  # ── Step 3: Build proposed_version = YYYYMMDD-sha8 ───────────────────────
  local _sha8="${_sha:0:8}"
  local _date_compact="${_commit_date//-/}"   # YYYY-MM-DD → YYYYMMDD
  local _proposed="${_date_compact}-${_sha8}"

  # ── Step 4: Check for PECL promotion ─────────────────────────────────────
  if [[ -n "${_commit_date}" ]]; then
    local _promotion_ver
    _promotion_ver="$(_gs_eu2_pecl_check_promotion "${_ext_name}" "${_commit_date}" 2>/dev/null)" || true
    if [[ -n "${_promotion_ver}" ]]; then
      _gs_eu2_record_set "${_idx}" alt_version \
        "PECL stable available: ${_promotion_ver} — consider switching to pecl:${_ext_name}"
    fi
  fi

  # ── Write result ──────────────────────────────────────────────────────────
  _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"
  [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"

  return 0
}
