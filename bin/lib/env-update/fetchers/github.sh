#!/bin/bash
# github.sh — GitHub fetcher using the record-index contract
#
# Input:  record index — reads type/identifier/channel/tag_*/major_hint etc.
# Output: writes proposed_version + decision + error_message + alt_version back into record
#
# Strategy (tried in order until a non-empty candidate list is found):
#   1. Releases API  — GET /repos/{owner}/{repo}/releases?per_page=100
#                      Filters out drafts; splits stable vs pre-release.
#   2. Tags API      — GET /repos/{owner}/{repo}/tags?per_page=100&page=N
#                      Paginated (max 10 pages); stops early when page < 100 results.
#   3. git ls-remote — last resort, only when tags pagination exhausts 10 pages
#                      without finding a major_hint match; testable via
#                      _GS_EU2_GIT_LS_REMOTE_FIXTURE env var override.
#
# Authentication: GITHUB_TOKEN env var injected as Bearer token on all API calls.
# Rate-limit hint: included in error_message on HTTP failure when token is absent.
#
# Exported helpers used by the pecl-git fetcher:
#   _gs_eu2_github_get_commit_sha  repo_id ref   → SHA string (7+ hex chars)
#   _gs_eu2_github_get_commit_date repo_id sha   → YYYY-MM-DD

[[ -n "${_GS_EU2_GITHUB_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_GITHUB_SH_LOADED=1

# shellcheck source=../core/records.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/records.sh"
# shellcheck source=../core/semver.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/semver.sh"
# shellcheck source=../core/channel.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/channel.sh"
# shellcheck source=../core/tag_flags.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/tag_flags.sh"
# shellcheck source=../core/cache.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/cache.sh"
# shellcheck source=../http/curl.sh
source "$(dirname "${BASH_SOURCE[0]}")/../http/curl.sh"

# _gs_eu2_github_api_get URL [token]
# Authenticated GET helper (falls through to unauthenticated when token is empty).
_gs_eu2_github_api_get() {
  local _url="${1}" _tok="${2:-${GITHUB_TOKEN:-${GLOBAL_STACK_GITHUB_TOKEN:-}}}"
  if [[ -n "${_tok}" ]]; then
    _gs_eu2_http_get_auth "${_url}" "${_tok}"
  else
    _gs_eu2_http_get "${_url}"
  fi
}

# _gs_eu2_github_ls_remote REPO_ID
# Runs git ls-remote to list all refs for a GitHub repo.
# When _GS_EU2_GIT_LS_REMOTE_FIXTURE is set, cats that file instead (test seam).
# Outputs newline-separated "SHA\tREF" lines.
_gs_eu2_github_ls_remote() {
  local _repo="${1}"
  if [[ -n "${_GS_EU2_GIT_LS_REMOTE_FIXTURE:-}" ]]; then
    cat "${_GS_EU2_GIT_LS_REMOTE_FIXTURE}"
    return
  fi
  local _tok="${GITHUB_TOKEN:-${GLOBAL_STACK_GITHUB_TOKEN:-}}"
  local _url="https://github.com/${_repo}.git"
  if [[ -n "${_tok}" ]]; then
    # Use GIT_ASKPASS to supply the token out-of-band — avoids token in process
    # list (ps auxww), shell history, and CI logs.
    local _askpass
    _askpass="$(mktemp)"
    printf '#!/bin/sh\necho "%s"\n' "${_tok}" > "${_askpass}"
    chmod 700 "${_askpass}"
    GIT_ASKPASS="${_askpass}" git ls-remote \
      "https://x-access-token@github.com/${_repo}.git" 'refs/tags/*' 2>/dev/null || true
    rm -f "${_askpass}"
  else
    git ls-remote "${_url}" 'refs/tags/*' 2>/dev/null || true
  fi
}

# _gs_eu2_github_get_commit_sha REPO_ID REF
# Returns the commit SHA (full or short) for REF (branch name, tag, or SHA).
# Exported for use by the pecl-git fetcher.
_gs_eu2_github_get_commit_sha() {
  local _repo="${1}" _ref="${2:-main}"
  local _url="https://api.github.com/repos/${_repo}/commits?sha=${_ref}&per_page=1"
  local _resp
  _resp="$(_gs_eu2_github_api_get "${_url}" 2>/dev/null)" || return 1
  printf '%s' "${_resp}" | jq -r '.[0].sha // empty' 2>/dev/null || true
}

# _gs_eu2_github_get_commit_date REPO_ID SHA
# Returns the commit date (YYYY-MM-DD) for a given SHA.
# Exported for use by the pecl-git fetcher.
_gs_eu2_github_get_commit_date() {
  local _repo="${1}" _sha="${2}"
  local _url="https://api.github.com/repos/${_repo}/commits/${_sha}"
  local _resp
  _resp="$(_gs_eu2_github_api_get "${_url}" 2>/dev/null)" || return 1
  local _raw
  _raw="$(printf '%s' "${_resp}" | jq -r '.commit.author.date // empty' 2>/dev/null || true)"
  # Trim to YYYY-MM-DD
  printf '%s' "${_raw:0:10}"
}

# _gs_eu2_github_fetch_releases REPO_ID TOKEN
# Fetches all non-draft releases; outputs raw tag_names (one per line).
_gs_eu2_github_fetch_releases() {
  local _repo="${1}" _tok="${2:-}"
  local _url="https://api.github.com/repos/${_repo}/releases?per_page=100"
  local _resp
  _resp="$(_gs_eu2_github_api_get "${_url}" "${_tok}" 2>/dev/null)" || return 1
  printf '%s' "${_resp}" | jq -r '.[] | select(.draft == false) | .tag_name' 2>/dev/null || true
}

# _gs_eu2_github_fetch_tags_paginated REPO_ID TOKEN MAX_PAGES
# Fetches tags via pagination (up to MAX_PAGES pages).
# Stops early when a page returns fewer than 100 items.
# Outputs raw tag names (one per line).
_gs_eu2_github_fetch_tags_paginated() {
  local _repo="${1}" _tok="${2:-}" _max="${3:-10}"
  local _page=1 _tags="" _page_tags _count
  while (( _page <= _max )); do
    local _url="https://api.github.com/repos/${_repo}/tags?per_page=100&page=${_page}"
    local _resp
    if ! _resp="$(_gs_eu2_github_api_get "${_url}" "${_tok}" 2>/dev/null)"; then
      break
    fi
    _page_tags="$(printf '%s' "${_resp}" | jq -r '.[].name' 2>/dev/null || true)"
    [[ -z "${_page_tags}" ]] && break
    _tags="${_tags}${_page_tags}"$'\n'
    _count="$(printf '%s\n' "${_page_tags}" | grep -c . || true)"
    (( _count < 100 )) && break
    (( _page++ ))
  done
  printf '%s' "${_tags}"
}

# Main fetcher entry point — takes one argument: record index.
_gs_eu2_fetch_github() {
  local _idx="${1}"

  local _identifier _channel _major_hint _no_cache
  _identifier="$(_gs_eu2_record_get "${_idx}" identifier)"
  _channel="$(_gs_eu2_record_get "${_idx}" channel)"
  _major_hint="$(_gs_eu2_record_get "${_idx}" major_hint)"
  _no_cache="${_GS_EU2_CFG[no_cache]:-false}"

  local _tok="${GITHUB_TOKEN:-${GLOBAL_STACK_GITHUB_TOKEN:-}}"

  # Build cache key
  local _cache_key="github:${_identifier}:${_major_hint}:${_channel}"

  # Cache read
  if [[ "${_no_cache}" != "true" ]]; then
    local _cached
    if _cached="$(_gs_eu2_cache_read "${_cache_key}")" && [[ -n "${_cached}" ]]; then
      _gs_eu2_record_set "${_idx}" proposed_version "${_cached}"
      return 0
    fi
  fi

  # ── Strategy 1: Releases API ──────────────────────────────────────────────
  local _raw_tags=""
  local _releases_out
  if _releases_out="$(_gs_eu2_github_fetch_releases "${_identifier}" "${_tok}" 2>/dev/null)"; then
    _raw_tags="${_releases_out}"
  else
    # Releases API failed entirely (HTTP error, auth, etc.)
    local _hint=""
    [[ -z "${_tok}" ]] && _hint=" (set GITHUB_TOKEN or GLOBAL_STACK_GITHUB_TOKEN to avoid rate limits)"
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "fetch failed for github:${_identifier}${_hint}"
    return 0
  fi

  # ── Strategy 2: Tags API (when releases returned nothing, or all-prerelease for stable) ──
  # Also triggered when the releases API returned only pre-releases and the channel is stable.
  # Repos like Flutter publish GitHub Releases only for pre-releases; stable versions are
  # tag-only.  Without this check, channel_select_best would see only pre-releases and
  # return empty for the stable channel, causing a spurious SKIP.
  local _s2_trigger="false"
  if [[ -z "$(printf '%s\n' "${_raw_tags}" | grep -v '^$' || true)" ]]; then
    _s2_trigger="true"
  elif [[ -z "${_channel}" || "${_channel}" == "stable" ]]; then
    # Check if ALL non-empty releases entries are pre-releases
    local _has_stable="false"
    local _v
    while IFS= read -r _v; do
      [[ -z "${_v}" ]] && continue
      if ! _gs_eu2_is_prerelease "${_v}"; then
        _has_stable="true"
        break
      fi
    done <<< "${_raw_tags}"
    [[ "${_has_stable}" == "false" ]] && _s2_trigger="true"
  fi
  if [[ "${_s2_trigger}" == "true" ]]; then
    local _tags_out
    _tags_out="$(_gs_eu2_github_fetch_tags_paginated "${_identifier}" "${_tok}" 10 2>/dev/null)"
    _raw_tags="${_tags_out}"
  fi

  # ── Strategy 3: git ls-remote (when tags pagination exhausted) ─────────────
  # Only triggered when major_hint is set and nothing matched in pagination
  # (checked after applying filters below — see post-filter fallback)

  if [[ -z "$(printf '%s\n' "${_raw_tags}" | grep -v '^$' || true)" ]]; then
    local _hint=""
    [[ -z "${_tok}" ]] && _hint=" (set GITHUB_TOKEN or GLOBAL_STACK_GITHUB_TOKEN to avoid rate limits)"
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "no tags or releases found for github:${_identifier}${_hint}"
    return 0
  fi

  # ── Apply tag_flags pipeline ───────────────────────────────────────────────
  local _tags
  _tags="$(printf '%s\n' "${_raw_tags}" | _gs_eu2_apply_tag_flags_from_record "${_idx}")"

  # ── Major-pin filter ───────────────────────────────────────────────────────
  if [[ -n "${_major_hint}" ]]; then
    local _filtered_major
    _filtered_major="$(printf '%s\n' "${_tags}" \
      | grep -E "^v?${_major_hint}([.^_-]|\$)" 2>/dev/null || true)"

    # Strategy 3: git ls-remote fallback when pagination exhausted and major_hint yielded nothing
    if [[ -z "$(printf '%s\n' "${_filtered_major}" | grep -v '^$' || true)" ]]; then
      local _lsr_out
      _lsr_out="$(_gs_eu2_github_ls_remote "${_identifier}" 2>/dev/null)"
      if [[ -n "${_lsr_out}" ]]; then
        # Extract tag names from ls-remote output (strip refs/tags/ prefix and ^{} deref lines)
        local _lsr_tags
        _lsr_tags="$(printf '%s\n' "${_lsr_out}" \
          | awk '{print $2}' \
          | grep '^refs/tags/' \
          | grep -v '\^{}$' \
          | sed 's|refs/tags/||' || true)"
        local _lsr_filtered
        _lsr_filtered="$(printf '%s\n' "${_lsr_tags}" \
          | _gs_eu2_apply_tag_flags_from_record "${_idx}" \
          | grep -E "^v?${_major_hint}([.^_-]|\$)" 2>/dev/null || true)"
        [[ -n "$(printf '%s\n' "${_lsr_filtered}" | grep -v '^$' || true)" ]] \
          && _filtered_major="${_lsr_filtered}"
      fi
    fi

    _tags="${_filtered_major}"
  fi

  if [[ -z "$(printf '%s\n' "${_tags}" | grep -v '^$' || true)" ]]; then
    # Heuristic: stable current + no tags found = fetcher failure, not a legitimate no-stable case.
    local _cur0 _decision0="SKIP"
    _cur0="$(_gs_eu2_record_get "${_idx}" current_version)"
    if [[ -n "${_cur0}" ]] && ! _gs_eu2_is_prerelease "${_cur0}"; then
      _decision0="ERROR"
    fi
    _gs_eu2_record_set "${_idx}" decision      "${_decision0}"
    _gs_eu2_record_set "${_idx}" error_message "no tags matched filters for github:${_identifier}"
    return 0
  fi

  # ── Channel selection → proposed ──────────────────────────────────────────
  local _proposed
  _proposed="$(_gs_eu2_channel_select_best "${_tags}" "${_channel}")"

  if [[ -z "${_proposed}" ]]; then
    # Heuristic: if the current version is stable, stable releases must exist for this project —
    # finding none is a fetcher failure, not a legitimate "no stable releases" case.
    local _cur _decision="SKIP"
    _cur="$(_gs_eu2_record_get "${_idx}" current_version)"
    if [[ -n "${_cur}" ]] && ! _gs_eu2_is_prerelease "${_cur}"; then
      _decision="ERROR"
    fi
    _gs_eu2_record_set "${_idx}" decision      "${_decision}"
    _gs_eu2_record_set "${_idx}" error_message "channel selection returned nothing for github:${_identifier}"
    return 0
  fi

  # ── alt_version: hint when a newer pre-release exists beyond the stable pick ─
  if [[ -z "${_channel}" || "${_channel}" == "stable" ]]; then
    local _best_pre
    _best_pre="$(_gs_eu2_channel_select_best "${_tags}" "unstable")"
    if [[ -n "${_best_pre}" && "${_best_pre}" != "${_proposed}" ]]; then
      local _cmp
      _cmp="$(_gs_eu2_semver_compare "${_best_pre}" "${_proposed}")"
      if [[ "${_cmp}" == "newer" ]]; then
        _gs_eu2_record_set "${_idx}" alt_version "pre-release also available: ${_best_pre}"
      fi
    fi
  fi

  # ── Re-prepend version_prefix stripped by tag-strip-prefix ────────────────
  local _vp
  _vp="$(_gs_eu2_record_get "${_idx}" version_prefix)"
  [[ -n "${_vp}" ]] && _proposed="${_vp}${_proposed}"

  # ── Write result — proposed_version only; decision left empty for decide.sh ─
  _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"

  # ── Cache the result ───────────────────────────────────────────────────────
  [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"

  return 0
}
