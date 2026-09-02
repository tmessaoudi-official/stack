#!/bin/bash
# codeberg.sh — Codeberg (Gitea) releases/tags fetcher using the record-index contract.
#
# Exports:   _gs_eu2_fetch_codeberg  _gs_eu2_cb_fetch_tags
# Sources:   core/records.sh  core/semver.sh  core/channel.sh
#            core/tag_flags.sh  core/cache.sh  http/curl.sh
# Deps:      curl, jq
# Env:       _GS_EU2_CFG[no_cache]
#
# Input:  record index — reads identifier/channel/tag_*/major_hint/major_hint_min
# Output: writes proposed_version + decision + error_message back into record
#
# API: https://codeberg.org/api/v1/repos/{owner}/{repo}/releases?limit=50&page=1
# Falls back to the tags endpoint when the releases array is empty or the request
# fails, and additionally consults it when the releases pool cannot represent the
# requested channel (all pre-release on stable / no pre-release on a non-stable
# channel) — see the channel-representation fallthrough in _gs_eu2_fetch_codeberg.

[[ -n "${_GS_EU2_CODEBERG_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_CODEBERG_SH_LOADED=1

# shellcheck source=./../core/records.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/records.sh"
# shellcheck source=./../core/semver.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/semver.sh"
# shellcheck source=./../core/channel.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/channel.sh"
# shellcheck source=./../core/tag_flags.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/tag_flags.sh"
# shellcheck source=./../core/cache.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/cache.sh"
# shellcheck source=./../http/curl.sh
source "$(dirname "${BASH_SOURCE[0]}")/../http/curl.sh"

# _gs_eu2_cb_token — resolve the optional Codeberg auth token.
#
# Reads:   CODEBERG_TOKEN, then GLOBAL_STACK_CODEBERG_TOKEN (both optional)
# Prints:  the token string, or empty if neither is set
# Returns: 0 always
#
# Optional: absent → unauthenticated (default). Present → sent with the Gitea/Forgejo
# canonical "Authorization: token <TOKEN>" scheme (NOT Bearer). Mirrors GITHUB_TOKEN
# parity for github/ghcr. The token raises Codeberg's API rate limit; it does NOT
# work around upstream list-endpoint timeouts/504s (a server-side condition).
_gs_eu2_cb_token() {
  printf '%s' "${CODEBERG_TOKEN:-${GLOBAL_STACK_CODEBERG_TOKEN:-}}"
}

# _gs_eu2_cb_fetch_tags — fetch tag list from Codeberg tags endpoint.
#
# Args:    $1 identifier — "owner/repo" string
# Prints:  newline-separated tag names
# Returns: 0 on success; non-zero on HTTP failure
# Side fx: may read/write cache (via _gs_eu2_http_get_auth)
# Auth:    optional CODEBERG_TOKEN via "token" scheme (Gitea/Forgejo)
_gs_eu2_cb_fetch_tags() {
  local _identifier="${1}"
  local _url="https://codeberg.org/api/v1/repos/${_identifier}/tags?limit=50"
  local _resp _tok
  _tok="$(_gs_eu2_cb_token)"

  if ! _resp="$(_gs_eu2_http_get_auth "${_url}" "${_tok}" "token" 2>/dev/null)"; then
    return 1
  fi

  printf '%s\n' "${_resp}" | jq -r '.[].name' 2>/dev/null || true
}

# _gs_eu2_fetch_codeberg — main entry point for the codeberg: fetcher type.
#
# Args:    $1 record_index — 0-based record index
# Reads:   record fields: identifier, channel, major_hint, major_hint_min,
#          tag_filter, tag_exclude, tag_strip_prefix, tag_strip_suffix,
#          tag_extract, tag_replace_from, tag_replace_to
# Sets:    record fields: proposed_version, decision (ERROR only), error_message,
#          latest_unconstrained, using_fallback_major
# Prints:  nothing
# Returns: 0 always (errors stored in record, not propagated as exit codes)
_gs_eu2_fetch_codeberg() {
  local _idx="${1}"

  local _identifier _channel _major_hint _major_hint_min _no_cache
  _identifier="$(_gs_eu2_record_get "${_idx}" identifier)"
  _channel="$(_gs_eu2_record_get "${_idx}" channel)"
  _major_hint="$(_gs_eu2_record_get "${_idx}" major_hint)"
  _major_hint_min="$(_gs_eu2_record_get "${_idx}" major_hint_min)"
  _no_cache="${_GS_EU2_CFG[no_cache]:-false}"

  # watch_major_depth read early for cache key: watch-major runs must not share
  # a cache entry with non-watch-major runs (cache-hit returns before latest_unconstrained
  # is populated, so a shared entry would silently suppress WATCH on subsequent runs).
  local _wm_depth_ck
  _wm_depth_ck="$(_gs_eu2_record_get "${_idx}" watch_major_depth)"

  # Build cache key — include major_hint_min so range annotations don't collide.
  local _cache_key
  _cache_key="codeberg:${_identifier}:${_major_hint}:${_major_hint_min}:${_channel}:${_wm_depth_ck}:$(_gs_eu2_tag_flags_fingerprint "${_idx}")"

  # Cache read
  _gs_eu2_cache_try_load "${_idx}" "${_cache_key}" "${_major_hint:-}" "${_major_hint_min:-}" && return 0

  # Fetch releases endpoint — write JSON to temp file to avoid subshell variable leak.
  # We need to inspect both the return code AND the content (empty array vs real failure).
  local _releases_tmp
  _releases_tmp="$(mktemp)"
  local _releases_ok=false _releases_empty=false
  local _releases_url="https://codeberg.org/api/v1/repos/${_identifier}/releases?limit=50&page=1"
  local _cb_tok
  _cb_tok="$(_gs_eu2_cb_token)"
  if _gs_eu2_http_get_auth "${_releases_url}" "${_cb_tok}" "token" 2>/dev/null > "${_releases_tmp}"; then
    _releases_ok=true
    local _count
    _count="$(jq 'length' "${_releases_tmp}" 2>/dev/null || printf '0')"
    [[ "${_count}" == "0" ]] && _releases_empty=true
  fi

  local _raw_tags=""
  if [[ "${_releases_ok}" == "true" && "${_releases_empty}" == "false" ]]; then
    # Non-empty releases: extract tag_name from non-draft entries (prerelease included)
    _raw_tags="$(jq -r '.[] | select(.draft == false) | .tag_name' "${_releases_tmp}" 2>/dev/null || true)"

    # ── Channel-representation fallthrough (mirrors github.sh Strategy 2) ─────
    # A non-empty releases pool can still fail to represent the channel the
    # annotation asked for, in two symmetric ways. Either way the tags endpoint
    # is the only other place the answer can live, so consult it:
    #
    #   stable channel  + every release is a pre-release → nothing selectable
    #   non-stable chan + no release is a pre-release    → channel unanswerable
    #
    # Only the release NAME survives into the pool (jq takes .tag_name), so the
    # JSON "prerelease" field is not available here — classification is by string,
    # exactly as channel selection does it downstream.
    local _cb_want_tags="false" _cb_merge="false" _v
    if [[ -z "${_channel}" || "${_channel}" == "stable" ]]; then
      local _has_stable="false"
      while IFS= read -r _v; do
        [[ -z "${_v}" ]] && continue
        if ! _gs_eu2_is_prerelease "${_v}"; then
          _has_stable="true"
          break
        fi
      done <<< "${_raw_tags}"
      [[ "${_has_stable}" == "false" ]] && _cb_want_tags="true"
    else
      local _has_pre="false"
      while IFS= read -r _v; do
        [[ -z "${_v}" ]] && continue
        if _gs_eu2_is_prerelease "${_v}"; then
          _has_pre="true"
          break
        fi
      done <<< "${_raw_tags}"
      if [[ "${_has_pre}" == "false" ]]; then
        _cb_want_tags="true"
        # Merge, don't replace: the stable releases stay valid candidates for a
        # non-stable comparison, and the tags endpoint caps at limit=50 — on a
        # tag-heavy repo a replace would drop the pinned major entirely.
        _cb_merge="true"
      fi
    fi
    if [[ "${_cb_want_tags}" == "true" ]]; then
      # Best-effort: a failing or empty tags call keeps the releases pool we
      # already have. Codeberg's list endpoints 504 under load, and turning a
      # working answer into an ERROR would be a strict regression — unlike the
      # empty/failed-releases branch below, where there is no pool to fall back on.
      local _cb_tags_out=""
      if _cb_tags_out="$(_gs_eu2_cb_fetch_tags "${_identifier}" 2>/dev/null)" \
        && [[ -n "${_cb_tags_out}" ]]; then
        if [[ "${_cb_merge}" == "true" ]]; then
          _raw_tags="${_raw_tags}"$'\n'"${_cb_tags_out}"
        else
          _raw_tags="${_cb_tags_out}"
        fi
      fi
    fi
  else
    # Releases failed or empty → fall back to tags endpoint
    if ! _raw_tags="$(_gs_eu2_cb_fetch_tags "${_identifier}")"; then
      rm -f "${_releases_tmp}"
      _gs_eu2_record_set "${_idx}" decision      "ERROR"
      _gs_eu2_record_set "${_idx}" error_message "codeberg API unreachable or timed out for ${_identifier} (try again later)"
      return 0
    fi
  fi
  rm -f "${_releases_tmp}"

  if [[ -z "${_raw_tags}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "no tags returned for codeberg:${_identifier}"
    return 0
  fi

  # Apply full tag flags pipeline
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
    _unconstrained_best="$(_gs_eu2_channel_select_best "${_wm_tags}" "${_channel:-stable}")"
    if [[ -n "${_unconstrained_best}" ]]; then
      local _vp_wm
      _vp_wm="$(_gs_eu2_record_get "${_idx}" version_prefix)"
      [[ -n "${_vp_wm}" ]] && _unconstrained_best="${_vp_wm}${_unconstrained_best}"
      _gs_eu2_record_set "${_idx}" latest_unconstrained "${_unconstrained_best}"
    fi
  fi

  # Save pre-filter tag list for fallback-major retry below.
  local _tags_premajor="${_tags}"

  # Major-pin filter
  if [[ -n "${_major_hint}" ]]; then
    _tags="$(printf '%s\n' "${_tags}" | grep -E "^v?${_major_hint}([.^-]|\$)" 2>/dev/null \
      || printf '%s\n' "${_tags}" | awk -F'[v.-]' -v m="${_major_hint}" '
        { v=$0; sub(/^v/,"",v); split(v,a,"[.-]"); if(a[1]==m) print $0 }' || true)"
  fi

  if [[ -z "${_tags}" ]]; then
    if [[ -n "${_major_hint_min}" ]]; then
      local _fallback_tags
      _fallback_tags="$(printf '%s\n' "${_tags_premajor}" \
        | grep -E "^v?${_major_hint_min}([.^-]|\$)" 2>/dev/null \
        || printf '%s\n' "${_tags_premajor}" \
           | awk -F'[v.-]' -v m="${_major_hint_min}" \
               '{ v=$0; sub(/^v/,"",v); split(v,a,"[.-]"); if(a[1]==m) print $0 }' \
        || true)"
      if [[ -n "${_fallback_tags}" ]]; then
        _tags="${_fallback_tags}"
        _gs_eu2_record_set "${_idx}" using_fallback_major "true"
      fi
    fi
    if [[ -z "${_tags}" ]]; then
      _gs_eu2_record_set "${_idx}" decision      "SKIP"
      _gs_eu2_record_set "${_idx}" error_message "no tags matched filters for codeberg:${_identifier}"
      return 0
    fi
  fi

  # Channel selection → proposed
  local _proposed
  _proposed="$(_gs_eu2_channel_select_best "${_tags}" "${_channel}")"

  if [[ -z "${_proposed}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "SKIP"
    _gs_eu2_record_set "${_idx}" error_message "channel selection returned nothing for codeberg:${_identifier}"
    return 0
  fi

  # Re-prepend version_prefix stripped by tag-strip-prefix (mirrors dockerhub B3)
  local _vp
  _vp="$(_gs_eu2_record_get "${_idx}" version_prefix)"
  [[ -n "${_vp}" ]] && _proposed="${_vp}${_proposed}"

  # Write result — proposed_version only; decision left empty for decide.sh
  _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"

  # Cache the result
  [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"

  return 0
}
