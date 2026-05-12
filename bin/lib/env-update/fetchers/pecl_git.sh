#!/bin/bash
# pecl_git.sh — PECL-git fetcher using the record-index contract
#
# Tracks PHP extensions available only as GitHub release tags (or tags API),
# or where the git releases are ahead of the latest PECL stable release.
#
# Input:  record index — reads type/identifier/channel/pecl_ref etc.
# Output: writes proposed_version + proposed_sha + commit_date + error_message
#         + alt_version back into record
#
# Identifier format:   pecl-git:owner/repo
# proposed_version:    semver release tag (e.g. 6.3.0), with v-prefix stripped
# proposed_sha:        full commit SHA for the release tag
# annotation_sha:      SHA stored in the annotation (read from record, not fetched)
# commit_date:         YYYY-MM-DD date of the release commit (hint only, never stored)
# use_sha:             when true, apply writes proposed_sha to VAR= instead of proposed_version
#
# Strategy:
#   1. Fetch latest release tag via releases API
#   2. Fallback to tags API (3 pages) if releases empty
#   3. If still empty → ERROR with (use-sha) hint
#   4. Strip v-prefix; apply tag_strip_prefix from record if set
#   5. Filter by major_hint if set
#   6. Sort descending via sort -V → take best
#   7. Fetch SHA for the version tag
#   8. Fetch commit date for SHA (hint only)
#   9. Check for PECL promotion
#
# Cache key: pecl-git4:OWNER/REPO (bumped from pecl-git3: HEAD SHA instead of tag SHA)
#
# Depends on: github.sh (provides _gs_eu2_github_fetch_releases,
#             _gs_eu2_github_fetch_tags_paginated, _gs_eu2_github_get_commit_sha,
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
# Strip in order: php-, php_, ext-
# (using parameter expansion for each; stop after first match)
_gs_eu2_pecl_git_derive_ext_name() {
  local _repo_name="${1,,}"   # lowercase
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

  local _identifier _channel _major_hint _tag_strip_prefix _no_cache
  _identifier="$(_gs_eu2_record_get "${_idx}" identifier)"
  _channel="$(_gs_eu2_record_get "${_idx}" channel)"
  _major_hint="$(_gs_eu2_record_get "${_idx}" major_hint)"
  _tag_strip_prefix="$(_gs_eu2_record_get "${_idx}" tag_strip_prefix)"
  _no_cache="${_GS_EU2_CFG[no_cache]:-false}"

  # ── Check-tags merge mode ─────────────────────────────────────────────────
  local _check_tags _with_tags _merge_mode
  _check_tags="$(_gs_eu2_record_get "${_idx}" check_tags)"
  _with_tags="${_GS_EU2_CFG[with_tags]:-false}"
  _merge_mode="false"
  [[ "${_check_tags}" == "true" || "${_with_tags}" == "true" ]] && _merge_mode="true"

  # ── Extract owner/repo — accept shorthand or full URL (legacy fallback) ──
  local _owner_repo=""
  if [[ "${_identifier}" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
    # New canonical form: owner/repo
    _owner_repo="${_identifier}"
  elif [[ "${_identifier}" =~ github\.com/([^/[:space:]]+/[^/[:space:]]+) ]]; then
    # Legacy full-URL form — kept for any cached/old annotations
    _owner_repo="${BASH_REMATCH[1]}"
    _owner_repo="${_owner_repo%.git}"
  else
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "pecl-git: cannot extract owner/repo from '${_identifier}'"
    return 0
  fi

  # ── Determine ext_name for PECL lookup ───────────────────────────────────
  local _ext_name
  local _repo_name="${_owner_repo##*/}"
  _ext_name="$(_gs_eu2_pecl_git_derive_ext_name "${_repo_name}")"

  # ── Cache key (pecl-git4: HEAD SHA instead of tag SHA) ───────────────────
  local _cache_key="pecl-git4:${_owner_repo}"
  [[ "${_merge_mode}" == "true" ]] && _cache_key="${_cache_key}:tags"

  if [[ "${_no_cache}" != "true" ]]; then
    local _cached
    if _cached="$(_gs_eu2_cache_read "${_cache_key}" 2>/dev/null)" && [[ -n "${_cached}" ]]; then
      # Cached value format: PROPOSED_VER|PROPOSED_SHA (SHA may be empty)
      local _cached_ver="${_cached%%|*}"
      local _cached_sha="${_cached#*|}"
      [[ "${_cached_sha}" == "${_cached_ver}" ]] && _cached_sha=""
      _gs_eu2_record_set "${_idx}" proposed_version "${_cached_ver}"
      _gs_eu2_record_set "${_idx}" proposed_sha     "${_cached_sha}"
      return 0
    fi
  fi

  # ── Step 1: Fetch latest release tags ────────────────────────────────────
  local _tok="${GITHUB_TOKEN:-${GLOBAL_STACK_GITHUB_TOKEN:-}}"
  local _raw_tags="" _releases_out=""
  if _releases_out="$(_gs_eu2_github_fetch_releases "${_owner_repo}" "${_tok}" 2>/dev/null)"; then
    _raw_tags="${_releases_out}"
  fi

  # Fallback: tags API (3 pages max); in merge mode, always fetch and combine
  if [[ -z "$(printf '%s\n' "${_raw_tags}" | grep -v '^$' || true)" || "${_merge_mode}" == "true" ]]; then
    local _tags_out
    _tags_out="$(_gs_eu2_github_fetch_tags_paginated "${_owner_repo}" "${_tok}" 3 2>/dev/null)" || true
    if [[ "${_merge_mode}" == "true" ]]; then
      # Merge: combine releases + tags into one candidate pool
      _raw_tags="${_raw_tags}"$'\n'"${_tags_out}"
    else
      _raw_tags="${_tags_out}"
    fi
  fi

  if [[ -z "$(printf '%s\n' "${_raw_tags}" | grep -v '^$' || true)" ]]; then
    local _rate_hint=""
    [[ -z "${_tok}" ]] && _rate_hint=" (set GITHUB_TOKEN or GLOBAL_STACK_GITHUB_TOKEN to avoid rate limits)"
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message \
      "pecl-git: no release tags found for '${_owner_repo}'; pin manually with (use-sha)${_rate_hint}"
    return 0
  fi

  # ── Step 2: Strip v-prefix and apply tag_strip_prefix ────────────────────
  local _candidates=()
  local _t
  while IFS= read -r _t; do
    [[ -z "${_t}" ]] && continue
    # Strip v-prefix
    _t="${_t#v}"
    # Apply record's tag_strip_prefix if set
    [[ -n "${_tag_strip_prefix}" ]] && _t="${_t#"${_tag_strip_prefix}"}"
    [[ -n "${_t}" ]] && _candidates+=("${_t}")
  done <<< "${_raw_tags}"

  # ── Step 2b: Prefer stable releases when current version is stable ───────
  # Prevents sort -V from picking a prerelease (e.g. 6.3.0RC1) over stable.
  local _cur_v
  _cur_v="$(_gs_eu2_record_get "${_idx}" current_version)"
  if ! _gs_eu2_is_prerelease "${_cur_v}"; then
    local _stable_cs=() _c
    for _c in "${_candidates[@]}"; do
      _gs_eu2_is_prerelease "${_c}" || _stable_cs+=("${_c}")
    done
    [[ ${#_stable_cs[@]} -gt 0 ]] && _candidates=("${_stable_cs[@]}")
  fi

  # ── Step 3: Filter by major_hint ─────────────────────────────────────────
  if [[ -n "${_major_hint}" ]]; then
    local _maj_filtered=()
    local _c
    for _c in "${_candidates[@]}"; do
      [[ "${_c%%.*}" == "${_major_hint}" ]] && _maj_filtered+=("${_c}")
    done
    _candidates=("${_maj_filtered[@]+"${_maj_filtered[@]}"}")
  fi

  if [[ ${#_candidates[@]} -eq 0 ]]; then
    local _rate_hint2=""
    [[ -z "${_tok}" ]] && _rate_hint2=" (set GITHUB_TOKEN or GLOBAL_STACK_GITHUB_TOKEN to avoid rate limits)"
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message \
      "pecl-git: no release tags found for '${_owner_repo}'; pin manually with (use-sha)${_rate_hint2}"
    return 0
  fi

  # ── Step 4: Digit-preference filter + sort descending, take best ─────────
  # GNU sort -V places letter-prefixed strings (PHP_ZIP-1.12.1, RELEASE_3_3_0)
  # AFTER digit-starting strings, so tail -1 would pick them over clean semver.
  # Partition: digit-starting candidates win outright; fall back only when zero.
  local _dig_candidates=() _let_candidates=() _c4
  for _c4 in "${_candidates[@]}"; do
    if [[ "${_c4}" =~ ^[0-9] ]]; then
      _dig_candidates+=("${_c4}")
    else
      _let_candidates+=("${_c4}")
    fi
  done
  if [[ ${#_dig_candidates[@]} -gt 0 ]]; then
    _candidates=("${_dig_candidates[@]}")
  else
    _candidates=("${_let_candidates[@]+"${_let_candidates[@]}"}")
  fi
  local _best_ver
  _best_ver="$(printf '%s\n' "${_candidates[@]}" | sort -V | tail -1)"

  # ── Step 4b: Version-gap fix — if best_ver < current, also check tags ────
  # Fires only when merge_mode is not already active (avoids a redundant fetch).
  if [[ "${_merge_mode}" != "true" && -n "${_best_ver}" ]]; then
    local _cur_vg
    _cur_vg="$(_gs_eu2_record_get "${_idx}" current_version)"
    if [[ -n "${_cur_vg}" ]] && ! _gs_eu2_is_unversioned "${_cur_vg}"; then
      local _oldest_vg
      _oldest_vg="$(printf '%s\n%s\n' "${_cur_vg#v}" "${_best_ver#v}" | sort -V | head -1)"
      if [[ "${_oldest_vg}" == "${_best_ver#v}" && "${_oldest_vg}" != "${_cur_vg#v}" ]]; then
        local _gap_tags_raw
        _gap_tags_raw="$(_gs_eu2_github_fetch_tags_paginated "${_owner_repo}" "${_tok}" 3 2>/dev/null)" || true
        if [[ -n "$(printf '%s\n' "${_gap_tags_raw}" | grep -v '^$' || true)" ]]; then
          local _merged_raw="${_releases_out}"$'\n'"${_gap_tags_raw}"
          local _gap_candidates=()
          local _gt
          while IFS= read -r _gt; do
            [[ -z "${_gt}" ]] && continue
            _gt="${_gt#v}"
            [[ -n "${_tag_strip_prefix}" ]] && _gt="${_gt#"${_tag_strip_prefix}"}"
            [[ -n "${_gt}" ]] && _gap_candidates+=("${_gt}")
          done <<< "${_merged_raw}"
          if ! _gs_eu2_is_prerelease "${_cur_vg}"; then
            local _stable_gap=() _gc
            for _gc in "${_gap_candidates[@]}"; do
              _gs_eu2_is_prerelease "${_gc}" || _stable_gap+=("${_gc}")
            done
            [[ ${#_stable_gap[@]} -gt 0 ]] && _gap_candidates=("${_stable_gap[@]}")
          fi
          if [[ -n "${_major_hint}" ]]; then
            local _maj_gap=() _gc2
            for _gc2 in "${_gap_candidates[@]}"; do
              [[ "${_gc2%%.*}" == "${_major_hint}" ]] && _maj_gap+=("${_gc2}")
            done
            _gap_candidates=("${_maj_gap[@]+"${_maj_gap[@]}"}")
          fi
          if [[ ${#_gap_candidates[@]} -gt 0 ]]; then
            # Same digit-preference filter as Step 4 — letter-prefixed tags must not win.
            local _gdg=() _glt=() _gc3
            for _gc3 in "${_gap_candidates[@]}"; do
              if [[ "${_gc3}" =~ ^[0-9] ]]; then
                _gdg+=("${_gc3}")
              else
                _glt+=("${_gc3}")
              fi
            done
            [[ ${#_gdg[@]} -gt 0 ]] && _gap_candidates=("${_gdg[@]}") \
              || _gap_candidates=("${_glt[@]+"${_glt[@]}"}")
            local _gap_best
            _gap_best="$(printf '%s\n' "${_gap_candidates[@]}" | sort -V | tail -1)"
            local _oldest2
            _oldest2="$(printf '%s\n%s\n' "${_best_ver#v}" "${_gap_best#v}" | sort -V | head -1)"
            if [[ "${_oldest2}" == "${_best_ver#v}" && "${_oldest2}" != "${_gap_best#v}" ]]; then
              _best_ver="${_gap_best}"
            fi
          fi
        fi
      fi
    fi
  fi

  # ── Step 5: Get HEAD SHA — always prefer HEAD over a tagged SHA ──────────
  # HEAD is the freshest commit; the user builds extensions against PHP master
  # so a tag SHA may lag behind fixes needed for unreleased PHP versions.
  local _proposed_sha=""
  _proposed_sha="$(_gs_eu2_github_get_commit_sha "${_owner_repo}" "HEAD" 2>/dev/null)" || true

  # ── Step 6: Get commit date for HEAD (hint for PECL promotion check) ─────
  local _commit_date="" _proposed_sha_date=""
  if [[ -n "${_proposed_sha}" ]]; then
    _commit_date="$(_gs_eu2_github_get_commit_date "${_owner_repo}" "${_proposed_sha}" 2>/dev/null)" || true
    _proposed_sha_date="${_commit_date}"
  fi

  # ── Step 7: Check for PECL promotion ─────────────────────────────────────
  if [[ -n "${_commit_date}" ]]; then
    local _promotion_ver
    _promotion_ver="$(_gs_eu2_pecl_check_promotion "${_ext_name}" "${_commit_date}" 2>/dev/null)" || true
    if [[ -n "${_promotion_ver}" ]]; then
      _gs_eu2_record_set "${_idx}" alt_version \
        "PECL stable available: ${_promotion_ver} — consider switching to pecl:${_ext_name}"
    fi
  fi

  # ── Step 8: Write results ─────────────────────────────────────────────────
  _gs_eu2_record_set "${_idx}" proposed_version  "${_best_ver}"
  _gs_eu2_record_set "${_idx}" proposed_sha      "${_proposed_sha}"
  _gs_eu2_record_set "${_idx}" proposed_sha_date "${_proposed_sha_date}"
  _gs_eu2_record_set "${_idx}" commit_date       "${_commit_date}"

  # Cache: pipe-separated VER|SHA
  if [[ "${_no_cache}" != "true" ]]; then
    _gs_eu2_cache_write "${_cache_key}" "${_best_ver}|${_proposed_sha}"
  fi

  return 0
}
