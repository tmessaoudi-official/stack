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
# Exported helpers used by the pecl fetcher (git:owner/repo flag):
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
# Exported for use by the pecl fetcher (git:owner/repo flag).
_gs_eu2_github_get_commit_sha() {
  local _repo="${1}" _ref="${2:-main}"
  local _url="https://api.github.com/repos/${_repo}/commits?sha=${_ref}&per_page=1"
  local _resp
  _resp="$(_gs_eu2_github_api_get "${_url}" 2>/dev/null)" || return 1
  printf '%s' "${_resp}" | jq -r '.[0].sha // empty' 2>/dev/null || true
}

# _gs_eu2_github_get_commit_date REPO_ID SHA
# Returns the commit date (YYYY-MM-DD) for a given SHA.
# Exported for use by the pecl fetcher (git:owner/repo flag).
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

  local _identifier _channel _major_hint _no_cache _manual _tcp
  _identifier="$(_gs_eu2_record_get "${_idx}" identifier)"
  _channel="$(_gs_eu2_record_get "${_idx}" channel)"
  _major_hint="$(_gs_eu2_record_get "${_idx}" major_hint)"
  _no_cache="${_GS_EU2_CFG[no_cache]:-false}"
  _manual="$(_gs_eu2_record_get "${_idx}" manual)"
  _tcp="$(_gs_eu2_record_get "${_idx}" tag_channel_prefix)"

  # ── Check-tags merge mode (per-annotation flag or --with-tags CLI flag) ────
  local _check_tags _with_tags _merge_mode
  _check_tags="$(_gs_eu2_record_get "${_idx}" check_tags)"
  _with_tags="${_GS_EU2_CFG[with_tags]:-false}"
  _merge_mode="false"
  [[ "${_check_tags}" == "true" || "${_with_tags}" == "true" ]] && _merge_mode="true"

  local _tok="${GITHUB_TOKEN:-${GLOBAL_STACK_GITHUB_TOKEN:-}}"

  # watch_major_depth read early for cache key: watch-major runs must not share
  # a cache entry with non-watch-major runs (cache-hit returns before latest_unconstrained
  # is populated, so a shared entry would silently suppress WATCH on subsequent runs).
  local _wm_depth_ck
  _wm_depth_ck="$(_gs_eu2_record_get "${_idx}" watch_major_depth)"

  # Build cache key — include merge_mode, watch depth, and channel prefix to avoid
  # poisoning a non-tcp cache entry with tcp-stripped results (or vice versa).
  local _cache_key="github:${_identifier}:${_major_hint}:${_channel}:${_wm_depth_ck}"
  [[ -n "${_tcp}" ]] && _cache_key="${_cache_key}:tcp_${_tcp}"
  [[ "${_merge_mode}" == "true" ]] && _cache_key="${_cache_key}:tags"

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

  # ── Strategy 2: Tags API ──────────────────────────────────────────────────
  # Triggered when releases returned nothing, or all-prerelease for stable.
  # Also triggered unconditionally in merge mode (check-tags / --with-tags):
  # in merge mode the tags pool is combined with releases rather than replacing it.
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
  if [[ "${_s2_trigger}" == "true" || "${_merge_mode}" == "true" ]]; then
    local _tags_out
    _tags_out="$(_gs_eu2_github_fetch_tags_paginated "${_identifier}" "${_tok}" 10 2>/dev/null)"
    if [[ "${_merge_mode}" == "true" ]]; then
      # Merge mode: combine releases + tags into one candidate pool
      _raw_tags="${_raw_tags}"$'\n'"${_tags_out}"
    else
      # Replace: releases were empty/all-prerelease, use tags only
      _raw_tags="${_tags_out}"
    fi
  fi

  # ── Strategy 3: git ls-remote (when tags pagination exhausted) ─────────────
  # Only triggered when major_hint is set and nothing matched in pagination
  # (checked after applying filters below — see post-filter fallback)

  if [[ -z "$(printf '%s\n' "${_raw_tags}" | grep -v '^$' || true)" ]]; then
    local _hint=""
    [[ -z "${_tok}" ]] && _hint=" (set GITHUB_TOKEN or GLOBAL_STACK_GITHUB_TOKEN to avoid rate limits)"
    # (manual) repos with no releases/tags are expected (e.g. code-dump repos with no versioned
    # releases). Skip rather than error — the annotation is human-managed.
    if [[ "${_manual}" == "true" ]]; then
      _gs_eu2_record_set "${_idx}" decision "SKIP"
      return 0
    fi
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "no tags or releases found for github:${_identifier}${_hint}"
    return 0
  fi

  # ── (tag-channel-prefix) — round-trip strip before pipeline ─────────────────
  # The round-trip: tag-with-prefix → strip → compare → re-prepend on output.
  # WHY: some repos use a prefix to distinguish channel releases (e.g. "dev-1.2.3")
  # from stable releases ("1.2.3").  Stripping the prefix before comparison lets
  # SemVer comparison and tag-filter/tag-strip-prefix logic work on bare version
  # strings without knowing the prefix.  Re-prepending at output ensures the full
  # original tag name is written to proposed_version (not a stripped artefact).
  # Stable tags (no prefix) are never re-prepended — only pre-release ones are.
  #
  # Capture the original (raw) tags BEFORE stripping so we can conditionally
  # re-prepend the prefix on the winner (only when the winning raw tag had it).
  # Also strips _tcp from _releases_out so the version-gap fix block (which reads
  # _releases_out directly) operates on already-stripped data.
  local _orig_tags="${_raw_tags}"
  if [[ -n "${_tcp}" ]]; then
    _raw_tags="$(printf '%s\n' "${_raw_tags}" | sed "s/^${_tcp}//")"
    _releases_out="$(printf '%s\n' "${_releases_out}" | sed "s/^${_tcp}//")"
  fi

  # ── Apply tag_flags pipeline ───────────────────────────────────────────────
  local _tags
  _tags="$(printf '%s\n' "${_raw_tags}" | _gs_eu2_apply_tag_flags_from_record "${_idx}")"

  # (watch-major) — capture unconstrained best from full tag set (post-tag_flags, pre-major-pin).
  # Inherits all tag_flags (already applied to _tags). Auto-detects variant suffix from
  # current_version when no explicit tag-filter is present.
  local _wm_depth
  _wm_depth="$(_gs_eu2_record_get "${_idx}" watch_major_depth)"
  if [[ -n "${_wm_depth}" && -n "${_major_hint}" ]]; then
    local _wm_tags="${_tags}"
    local _wm_tag_filter
    _wm_tag_filter="$(_gs_eu2_record_get "${_idx}" tag_filter)"
    if [[ -z "${_wm_tag_filter}" ]]; then
      local _wm_cur _wm_suffix
      _wm_cur="$(_gs_eu2_record_get "${_idx}" current_version)"
      _wm_suffix="$(_gs_eu2_version_tag_suffix "${_wm_cur}")"
      if [[ -n "${_wm_suffix}" ]]; then
        local _wm_suffix_esc
        _wm_suffix_esc="$(printf '%s' "${_wm_suffix}" | sed 's/[.[\*^$()+?{}|]/\\&/g')"
        _wm_tags="$(printf '%s\n' "${_wm_tags}" | grep -E "${_wm_suffix_esc}"'$' || true)"
      fi
    fi
    local _unconstrained_best
    _unconstrained_best="$(_gs_eu2_channel_select_best "${_wm_tags}" "stable")"
    if [[ -n "${_unconstrained_best}" ]]; then
      # Conditional re-prepend: only if the original raw tag had the channel prefix
      if [[ -n "${_tcp}" ]] && \
         printf '%s\n' "${_orig_tags}" | grep -qxF "${_tcp}${_unconstrained_best}"; then
        _unconstrained_best="${_tcp}${_unconstrained_best}"
      fi
      local _vp_wm
      _vp_wm="$(_gs_eu2_record_get "${_idx}" version_prefix)"
      [[ -n "${_vp_wm}" ]] && _unconstrained_best="${_vp_wm}${_unconstrained_best}"
      _gs_eu2_record_set "${_idx}" latest_unconstrained "${_unconstrained_best}"
    fi
  fi

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

  # ── Version-gap fix: if proposed is older than current, also check tags ───
  # Fires only when merge_mode is not already active (avoids a redundant fetch).
  # Scenario: releases API returns 0.14.0 but current is 0.15.2 (tag-only release)
  # → we auto-fetch tags, merge with releases pool, re-run pipeline, take the max.
  if [[ "${_merge_mode}" != "true" && -n "${_proposed}" ]]; then
    local _cur_vg
    _cur_vg="$(_gs_eu2_record_get "${_idx}" current_version)"
    if [[ -n "${_cur_vg}" ]] && ! _gs_eu2_is_unversioned "${_cur_vg}"; then
      # Strip _tcp from both sides before comparing (current may carry the prefix)
      local _cur_vg_cmp="${_cur_vg#v}" _proposed_cmp="${_proposed#v}"
      [[ -n "${_tcp}" ]] && _cur_vg_cmp="${_cur_vg_cmp#"${_tcp}"}"
      [[ -n "${_tcp}" ]] && _proposed_cmp="${_proposed_cmp#"${_tcp}"}"
      local _oldest_vg
      _oldest_vg="$(printf '%s\n%s\n' "${_cur_vg_cmp}" "${_proposed_cmp}" | sort -V | head -1)"
      if [[ "${_oldest_vg}" == "${_proposed_cmp}" && "${_oldest_vg}" != "${_cur_vg_cmp}" ]]; then
        local _gap_raw
        _gap_raw="$(_gs_eu2_github_fetch_tags_paginated "${_identifier}" "${_tok}" 10 2>/dev/null)"
        if [[ -n "$(printf '%s\n' "${_gap_raw}" | grep -v '^$' || true)" ]]; then
          # Strip _tcp from gap raw tags before merging with already-stripped _releases_out
          local _gap_raw_stripped="${_gap_raw}"
          [[ -n "${_tcp}" ]] && \
            _gap_raw_stripped="$(printf '%s\n' "${_gap_raw}" | sed "s/^${_tcp}//")"
          local _merged_raw="${_releases_out}"$'\n'"${_gap_raw_stripped}"
          local _merged_filtered
          _merged_filtered="$(printf '%s\n' "${_merged_raw}" | _gs_eu2_apply_tag_flags_from_record "${_idx}")"
          if [[ -n "${_major_hint}" ]]; then
            _merged_filtered="$(printf '%s\n' "${_merged_filtered}" \
              | grep -E "^v?${_major_hint}([.^_-]|\$)" 2>/dev/null || true)"
          fi
          if [[ -n "$(printf '%s\n' "${_merged_filtered}" | grep -v '^$' || true)" ]]; then
            local _gap_proposed
            _gap_proposed="$(_gs_eu2_channel_select_best "${_merged_filtered}" "${_channel}")"
            if [[ -n "${_gap_proposed}" ]]; then
              local _oldest2
              _oldest2="$(printf '%s\n%s\n' "${_proposed_cmp}" "${_gap_proposed#v}" | sort -V | head -1)"
              if [[ "${_oldest2}" == "${_proposed_cmp}" && "${_oldest2}" != "${_gap_proposed#v}" ]]; then
                # Conditional re-prepend for gap winner
                if [[ -n "${_tcp}" ]] && \
                   printf '%s\n' "${_orig_tags}" | grep -qxF "${_tcp}${_gap_proposed}"; then
                  _gap_proposed="${_tcp}${_gap_proposed}"
                fi
                _proposed="${_gap_proposed}"
              fi
            fi
          fi
        fi
      fi
    fi
  fi

  # ── alt_version: hint when a newer pre-release exists beyond the stable pick ─
  if [[ -z "${_channel}" || "${_channel}" == "stable" ]]; then
    local _best_pre
    _best_pre="$(_gs_eu2_channel_select_best "${_tags}" "unstable")"
    if [[ -n "${_best_pre}" ]]; then
      # Conditional re-prepend before comparison — _tags is already stripped,
      # so re-prepend if the original raw tag had the channel prefix
      local _best_pre_display="${_best_pre}"
      if [[ -n "${_tcp}" ]] && \
         printf '%s\n' "${_orig_tags}" | grep -qxF "${_tcp}${_best_pre}"; then
        _best_pre_display="${_tcp}${_best_pre}"
      fi
      # Compare stripped versions; _proposed may carry _tcp if it was re-prepended above
      local _proposed_stripped="${_proposed#v}"
      [[ -n "${_tcp}" ]] && _proposed_stripped="${_proposed_stripped#"${_tcp}"}"
      if [[ "${_best_pre_display}" != "${_proposed}" ]]; then
        local _cmp
        _cmp="$(_gs_eu2_semver_compare "${_best_pre}" "${_proposed_stripped}" "${_tcp}")"
        if [[ "${_cmp}" == "newer" ]]; then
          _gs_eu2_record_set "${_idx}" alt_version "pre-release also available: ${_best_pre_display}"
        fi
      fi
    fi
  fi

  # ── Conditional re-prepend of tag-channel-prefix ─────────────────────────
  # Re-prepend ONLY when the original raw tag had the channel prefix.
  # This preserves stable releases (no prefix) and round-trips pre-release tags.
  if [[ -n "${_tcp}" ]] && \
     printf '%s\n' "${_orig_tags}" | grep -qxF "${_tcp}${_proposed}"; then
    _proposed="${_tcp}${_proposed}"
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
