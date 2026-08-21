#!/bin/bash
# dockerhub.sh — Docker Hub tag fetcher using the record-index contract.
#
# Exports:   _gs_eu2_fetch_dockerhub  _gs_eu2_dh_namespace  _gs_eu2_dh_fetch_tags
# Sources:   core/records.sh  core/semver.sh  core/channel.sh
#            core/tag_flags.sh  core/cache.sh  http/curl.sh
# Deps:      curl, jq
# Env:       _GS_EU2_CFG[no_cache]
#
# Input:  record index — reads identifier/channel/tag_*/major_hint/prefer_specific etc.
# Output: writes proposed_version + decision + error_message + latest_unconstrained
#         + using_fallback_major back into record

[[ -n "${_GS_EU2_DOCKERHUB_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_DOCKERHUB_SH_LOADED=1

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

# _gs_eu2_dh_namespace — normalise Docker Hub image identifier.
#
# Args:    $1 identifier — raw identifier (e.g. "_/nginx", "user/image")
# Prints:  normalised identifier ("library/nginx", "user/image")
# Returns: 0 always
#
# Docker Hub special convention: "_/name" means "library/name" (official images).
_gs_eu2_dh_namespace() {
  local _id="${1}"
  if [[ "${_id}" == _/* ]]; then
    printf 'library/%s' "${_id#_/}"
  else
    printf '%s' "${_id}"
  fi
}

# _gs_eu2_dh_fetch_tags — fetch all tags for a Docker Hub namespace/image.
#
# Args:    $1 ns   — "namespace/image" string (already normalised by _gs_eu2_dh_namespace)
#          $2 sink — optional diagnostics sink from _gs_eu2_http_diag_new. This
#                    function runs inside a command substitution, so the URL and
#                    status of the failing page cannot be returned to the caller
#                    any other way — they die with the subshell.
# Reads:   _GS_EU2_DH_ANON_PAGE_CAP (test seam — first page Docker Hub refuses to
#          serve anonymously; defaults to 11, i.e. offset 1000 at page_size=100)
# Prints:  newline-separated tag names
# Returns: 0 on success (including a walk ended early by the anonymous page cap);
#          1 on HTTP failure; 2 on a JSON parse failure. The two failure codes are
#          distinct because the caller reads the sink for an HTTP status, and on a
#          parse failure that status belongs to a request that SUCCEEDED.
# Side fx: may read/write cache (via _gs_eu2_http_get); writes to the sink
#
# C1: follows the "next" pagination link until null, accumulating all tag pages.
_gs_eu2_dh_fetch_tags() {
  local _ns="${1}" _sink="${2:-}"
  local _url="https://registry.hub.docker.com/v2/repositories/${_ns}/tags?page_size=100&ordering=last_updated"
  local _all_tags="" _resp _page_tags _next_url _fail_st _fail_pg

  while [[ -n "${_url}" ]]; do
    if ! _resp="$(_gs_eu2_http_get "${_url}" "${_sink}")"; then
      # Docker Hub refuses anonymous callers past offset 1000 with HTTP 403 —
      # page 11 at page_size=100. That is an upstream BOUNDARY, not a fetch
      # failure: this URL orders by last_updated, so the pages already collected
      # are the most recently updated tags and the newest version is necessarily
      # among them. End the walk successfully with what we have instead of
      # discarding 1000 good tags, which is what made library/mongo,
      # library/postgres and library/redis permanently ERROR.
      #
      # The gate is deliberately narrow. Below the cap a 403 means something
      # else entirely (rate limit, repo turned private, auth), and pages 2-10 are
      # offsets 100-900 — arithmetically not the cap. Those must still fail, or
      # the walk would silently truncate on a real error.
      #
      # last_updated is PUSH order, not version order, so "the newest version is
      # in the first 1000" is an assumption, not a tautology. It was validated
      # 2026-08-21 against COMPLETE tag lists (fetched via the ?name= filter,
      # which reaches past the cap) for every image that actually reaches the cap
      # — mongo 3607 tags, postgres 1421, redis 1176 — and all three proposals
      # were correct. It holds because the newest branch is itself rebuilt in
      # every wave, so its tags keep re-surfacing near the top. It would break
      # only if upstream pushed 1000+ other tags after the newest release.
      # See templates/tips/env-update.md § "Why keeping a truncated list is safe"
      # for the numbers, the verification runbook, and the known residual: a
      # cap-hit is now silent.
      _fail_st=""
      _fail_pg=""
      if [[ -n "${_sink}" ]]; then
        _fail_st="$(_gs_eu2_http_diag_status "${_sink}")" || _fail_st=""
        _fail_pg="$(_gs_eu2_http_url_page "$(_gs_eu2_http_diag_url "${_sink}")")" || _fail_pg=""
      fi
      if [[ -n "${_all_tags}" && "${_fail_st}" == "403" && -n "${_fail_pg}" ]] \
        && [[ "${_fail_pg}" -ge "${_GS_EU2_DH_ANON_PAGE_CAP:-11}" ]]; then
        break
      fi
      return 1
    fi
    if ! _page_tags="$(printf '%s\n' "${_resp}" | jq -r '.results[].name' 2>/dev/null)"; then
      # rc 2, not 1: the HTTP request SUCCEEDED, so the sink holds its status
      # (200). Collapsing a parse failure into rc 1 made the caller read that 200
      # as the failure cause and report "(HTTP 200)" for a malformed body.
      return 2
    fi
    _all_tags="${_all_tags}${_page_tags}"$'\n'
    _next_url="$(printf '%s\n' "${_resp}" | jq -r '.next // empty' 2>/dev/null)"
    if [[ -n "${_next_url}" ]] \
      && [[ "${_next_url}" != https://registry.hub.docker.com/* ]] \
      && [[ "${_next_url}" != https://hub.docker.com/* ]]; then
      _next_url=""
    fi
    _url="${_next_url}"
  done

  printf '%s' "${_all_tags}"
}

# _gs_eu2_fetch_dockerhub — main entry point for the dockerhub: fetcher type.
#
# Args:    $1 record_index — 0-based record index
# Reads:   record fields: identifier, channel, major_hint, major_hint_min,
#          prefer_specific, tag_filter, tag_exclude, tag_strip_prefix,
#          tag_strip_suffix, tag_extract, tag_replace_from, tag_replace_to,
#          version_prefix, tag_channel_prefix, watch_major_depth, current_version
# Sets:    record fields: proposed_version, decision (ERROR only), error_message,
#          latest_unconstrained, using_fallback_major
# Prints:  nothing
# Returns: 0 always
_gs_eu2_fetch_dockerhub() {
  local _idx="${1}"

  local _identifier _channel _major_hint _major_hint_min _current _no_cache
  _identifier="$(_gs_eu2_record_get "${_idx}" identifier)"
  _channel="$(_gs_eu2_record_get "${_idx}" channel)"
  _major_hint="$(_gs_eu2_record_get "${_idx}" major_hint)"
  _major_hint_min="$(_gs_eu2_record_get "${_idx}" major_hint_min)"
  _current="$(_gs_eu2_record_get "${_idx}" current_version)"
  _no_cache="${_GS_EU2_CFG[no_cache]:-false}"

  local _ns
  _ns="$(_gs_eu2_dh_namespace "${_identifier}")"

  # tag_suffix: if set, must be the record's tag_suffix field — used for cache key + filter
  local _tag_suffix
  _tag_suffix="$(_gs_eu2_record_get "${_idx}" tag_suffix)"

  # prefer_specific: read early so it's available for cache key construction
  local _prefer_specific
  _prefer_specific="$(_gs_eu2_record_get "${_idx}" prefer_specific)"

  # watch_major_depth read early for cache key: watch-major runs must not share
  # a cache entry with non-watch-major runs (cache-hit returns before latest_unconstrained
  # is populated, so a shared entry would silently suppress WATCH on subsequent runs).
  local _wm_depth_ck
  _wm_depth_ck="$(_gs_eu2_record_get "${_idx}" watch_major_depth)"

  # Build cache key — include prefer_specific, watch depth, and major_hint_min so range
  # annotations (:LOW-HIGH) don't collide with plain major-pin annotations (:HIGH).
  local _cache_key="dockerhub:${_ns}:${_tag_suffix}:${_major_hint}:${_major_hint_min}:${_channel}:${_prefer_specific}:${_wm_depth_ck}"

  # Cache read
  _gs_eu2_cache_try_load "${_idx}" "${_cache_key}" "${_major_hint:-}" "${_major_hint_min:-}" && return 0

  # Fetch tags.
  #
  # The sink is created HERE, in the frame that reads it back: _gs_eu2_dh_fetch_tags
  # runs in a command substitution and (under --jobs>1) inside a worker subshell,
  # so nothing it sets can propagate upward. One mktemp -d per record makes the
  # path unique by construction — no shared global, no collision between workers.
  #
  # The 2>/dev/null is pre-existing and stays: for a 403 curl --silent writes
  # nothing to stderr, so it suppresses nothing here, and removing it would
  # interleave worker stderr with the parent's progress line during fan-out
  # (core/parallel.sh:50,56 — the parent owns stderr during fan-out).
  # "|| _dh_diag=''" is a deliberate degradation, not error suppression: under
  # 'set -eEuo pipefail' a failing mktemp (full /tmp, unset TMPDIR in a stripped
  # worker env) would otherwise abort the whole check run. A diagnostics feature
  # must never be able to fail the operation it exists to explain. An empty sink
  # is a no-op for every _gs_eu2_http_diag_* function, so the message ladder
  # below simply falls through to the original wording — exactly the pre-change
  # behaviour, which is the correct thing to degrade to.
  #
  # Note the sink is no longer only a message concern: _gs_eu2_dh_fetch_tags
  # reads it to recognise the anonymous page cap, so an empty sink also loses the
  # cap-is-a-boundary behaviour and a >1000-tag image goes back to ERROR. That is
  # still the correct degradation — the floor is exactly the pre-fix behaviour,
  # never something worse — but it is a bigger floor than "the old wording".
  local _dh_diag _raw_tags _dh_rc=0
  _dh_diag="$(_gs_eu2_http_diag_new)" || _dh_diag=""
  _raw_tags="$(_gs_eu2_dh_fetch_tags "${_ns}" "${_dh_diag}" 2>/dev/null)" || _dh_rc=$?
  if [[ "${_dh_rc}" -ne 0 ]]; then
    local _dh_status _dh_page _dh_msg
    _dh_status="$(_gs_eu2_http_diag_status "${_dh_diag}")"
    _dh_page="$(_gs_eu2_http_url_page "$(_gs_eu2_http_diag_url "${_dh_diag}")")"
    _gs_eu2_http_diag_free "${_dh_diag}"

    # Message ladder, most specific first. The statusless branch keeps the
    # original wording verbatim: a transport failure (DNS, connection refused)
    # really does yield no status, and inventing one would be a regression.
    #
    # rc 2 is checked FIRST and never consults _dh_status: on a parse failure the
    # last HTTP call succeeded, so the sink holds 200. Reporting that turned a
    # correct generic message into a confidently wrong one.
    #
    # There is deliberately no offset-cap branch any more. Reaching the cap is no
    # longer an error — _gs_eu2_dh_fetch_tags ends the walk successfully — so a
    # 403 that still arrives here is NOT the cap and must not be described as it.
    # The page number is kept because it is useful diagnostics; the causal claim
    # is dropped because it was false for pages 2-10.
    if [[ "${_dh_rc}" -eq 2 ]]; then
      _dh_msg="fetch failed for ${_ns} (malformed JSON response)"
    elif [[ -n "${_dh_status}" && -n "${_dh_page}" && "${_dh_page}" -gt 1 ]]; then
      _dh_msg="fetch failed for ${_ns} (HTTP ${_dh_status} at page ${_dh_page})"
    elif [[ -n "${_dh_status}" ]]; then
      _dh_msg="fetch failed for ${_ns} (HTTP ${_dh_status})"
    else
      _dh_msg="fetch failed for ${_ns}"
    fi

    _gs_eu2_record_set "${_idx}" decision "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "${_dh_msg}"
    return 0
  fi
  _gs_eu2_http_diag_free "${_dh_diag}"

  if [[ -z "${_raw_tags}" ]]; then
    _gs_eu2_record_set "${_idx}" decision "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "no tags returned for ${_ns}"
    return 0
  fi

  # Apply tag-suffix filter first (before full tag_flags pipeline)
  local _tags="${_raw_tags}"
  if [[ -n "${_tag_suffix}" ]]; then
    _tags="$(printf '%s\n' "${_tags}" | grep -E -- "$(printf '%s' "${_tag_suffix}" | sed 's/[.[\*^$()+?{}|]/\\&/g')\$" || true)"
  fi

  # Apply full tag flags pipeline
  _tags="$(printf '%s\n' "${_tags}" | _gs_eu2_apply_tag_flags_from_record "${_idx}")"

  # (watch-major) — capture unconstrained best from full tag set (post-tag_flags, pre-major-pin).
  # Inherits all tag_flags (already applied to _tags). Auto-detects variant suffix from
  # current_version when no explicit tag-filter is present, so zulu/alpine/fpm variants
  # stay within their family even without a repeated (tag-filter:...) flag.
  local _wm_depth
  _wm_depth="$(_gs_eu2_record_get "${_idx}" watch_major_depth)"
  if [[ -n "${_wm_depth}" && -n "${_major_hint}" ]]; then
    local _wm_tags="${_tags}"
    local _wm_tag_filter
    _wm_tag_filter="$(_gs_eu2_record_get "${_idx}" tag_filter)"
    if [[ -z "${_wm_tag_filter}" ]]; then
      local _wm_suffix
      _wm_suffix="$(_gs_eu2_version_tag_suffix "${_current}")"
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

  # C3: Major-pin filter — anchor end of major component with ([.^-]|$) to prevent
  # major_hint="18" from matching "180.0" (the | was missing the $ end-of-string case).
  if [[ -n "${_major_hint}" ]]; then
    _tags="$(printf '%s\n' "${_tags}" | grep -E "^${_major_hint}([.^-]|\$)" 2>/dev/null \
      || printf '%s\n' "${_tags}" | awk -F'[.-]' -v m="${_major_hint}" '$1 == m' || true)"
  fi

  if [[ -z "${_tags}" ]]; then
    if [[ -n "${_major_hint_min}" ]]; then
      local _fallback_tags
      _fallback_tags="$(printf '%s\n' "${_tags_premajor}" \
        | grep -E "^${_major_hint_min}([.^-]|\$)" 2>/dev/null \
        || printf '%s\n' "${_tags_premajor}" \
           | awk -F'[.-]' -v m="${_major_hint_min}" '$1 == m' \
        || true)"
      if [[ -n "${_fallback_tags}" ]]; then
        _tags="${_fallback_tags}"
        _gs_eu2_record_set "${_idx}" using_fallback_major "true"
      fi
    fi
    if [[ -z "${_tags}" ]]; then
      _gs_eu2_record_set "${_idx}" decision "SKIP"
      _gs_eu2_record_set "${_idx}" error_message "no tags matched filters for ${_ns}"
      return 0
    fi
  fi

  # prefer-specific: drop floating tags (X or X.Y form) when flag is set.
  # This prevents X.Y tags (which silently re-point when patches ship) from
  # winning over X.Y.Z pinnable tags.  Flag is opt-in to avoid breaking images
  # like Postgres where X.Y *is* the specific version (no X.Y.Z exists).
  # Note: _prefer_specific already read above (before cache key) — reuse it here.
  if [[ "${_prefer_specific}" == "true" ]]; then
    local _specific_tags
    _specific_tags="$(printf '%s\n' "${_tags}" | _gs_eu2_filter_specific_tags)"
    if [[ -n "${_specific_tags}" ]]; then
      _tags="${_specific_tags}"
    else
      _gs_eu2_record_set "${_idx}" decision "SKIP"
      _gs_eu2_record_set "${_idx}" error_message "no specific (X.Y.Z) tags found for ${_ns} after prefer-specific filter"
      return 0
    fi
  fi

  # Detect all-unversioned tag set (e.g. oracle-xe image has only "latest")
  local _has_versioned=false _utag
  while IFS= read -r _utag; do
    [[ -z "${_utag}" ]] && continue
    if ! _gs_eu2_is_unversioned "${_utag}"; then
      _has_versioned=true
      break
    fi
  done <<<"${_tags}"
  if [[ "${_has_versioned}" == "false" ]]; then
    _gs_eu2_record_set "${_idx}" decision "SKIP"
    _gs_eu2_record_set "${_idx}" error_message "no versioned tags available for ${_ns}"
    return 0
  fi

  # Channel selection → proposed
  local _proposed
  _proposed="$(_gs_eu2_channel_select_best "${_tags}" "${_channel}")"

  if [[ -z "${_proposed}" ]]; then
    _gs_eu2_record_set "${_idx}" decision "SKIP"
    _gs_eu2_record_set "${_idx}" error_message "channel selection returned nothing for ${_ns}"
    return 0
  fi

  # B3: re-prepend version_prefix stripped by tag-strip-prefix (e.g. "v" for moby/buildkit)
  local _vp
  _vp="$(_gs_eu2_record_get "${_idx}" version_prefix)"
  [[ -n "${_vp}" ]] && _proposed="${_vp}${_proposed}"

  # Write result — proposed_version only; decision left empty for decide.sh (via main.sh)
  _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"

  # Cache the result
  [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"

  return 0
}
