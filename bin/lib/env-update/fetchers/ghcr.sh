#!/bin/bash
# ghcr.sh — GitHub Container Registry (ghcr.io) tag fetcher using the record-index contract.
#
# Exports:   _gs_eu2_ghcr_get_token  _gs_eu2_ghcr_fetch_tags  _gs_eu2_fetch_ghcr
# Sources:   core/records.sh  core/semver.sh  core/channel.sh
#            core/tag_flags.sh  core/cache.sh  http/curl.sh
# Deps:      curl, jq
# Env:       GITHUB_TOKEN or GLOBAL_STACK_GITHUB_TOKEN (optional; used as Bearer when set,
#            bypassing anonymous token acquisition); _GS_EU2_CFG[no_cache]
#
# Input:  record index — reads identifier/channel/tag_*/major_hint/major_hint_min/
#                        watch_major_depth/current_version/version_prefix
# Output: writes proposed_version + decision + error_message + latest_unconstrained
#         + using_fallback_major back into record
#
# Authentication strategy:
#   1. If GITHUB_TOKEN or GLOBAL_STACK_GITHUB_TOKEN is set → use it directly as Bearer.
#      This also works for private images accessible by the token.
#   2. Otherwise → fetch an anonymous Bearer token from the GHCR token endpoint.
#      Public images support anonymous pull via scope=repository:<owner>/<image>:pull.
#      Token endpoint: https://ghcr.io/token?service=ghcr.io&scope=repository:<id>:pull
#
# Pagination: requests up to n=1000 tags in one call. The OCI distribution API paginates
#   via a Link response header (not a body field), which the current HTTP layer does not
#   capture. n=1000 covers the vast majority of registries in practice; repositories with
#   more than 1000 tags are not supported.
#
# Annotation syntax: # @todo env-update ghcr:<owner>/<image> [MAJOR_HINT] CURRENT_VERSION
# Example:           # @todo env-update ghcr:sooperset/mcp-atlassian 0.21.1

[[ -n "${_GS_EU2_GHCR_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_GHCR_SH_LOADED=1

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

# _gs_eu2_ghcr_get_token — obtain a Bearer token for a GHCR image pull.
#
# Args:    $1 identifier — "owner/image" string (e.g. "sooperset/mcp-atlassian")
# Reads:   GITHUB_TOKEN or GLOBAL_STACK_GITHUB_TOKEN
# Prints:  Bearer token string (non-empty on success)
# Returns: 0 on success; 1 on failure (token endpoint unreachable or response invalid)
#
# If GITHUB_TOKEN or GLOBAL_STACK_GITHUB_TOKEN is set, returns it directly without
# contacting the token endpoint — GitHub tokens are valid GHCR Bearer tokens.
# Otherwise fetches an anonymous token scoped to the specific repository pull permission.
_gs_eu2_ghcr_get_token() {
  local _id="${1}"
  local _pat="${GITHUB_TOKEN:-${GLOBAL_STACK_GITHUB_TOKEN:-}}"

  # Fast path: use the existing GitHub PAT directly.
  if [[ -n "${_pat}" ]]; then
    printf '%s' "${_pat}"
    return 0
  fi

  # Anonymous path: fetch a short-lived registry token from the GHCR token service.
  # The token is scoped to a single repository pull and is safe to use in tests via
  # the fixture seam (fixture file: ghcr.io_token — query string is stripped by fixture_path).
  local _token_url="https://ghcr.io/token?service=ghcr.io&scope=repository:${_id}:pull"
  local _resp
  if ! _resp="$(_gs_eu2_http_get "${_token_url}" 2>/dev/null)"; then
    return 1
  fi

  local _tok
  _tok="$(printf '%s' "${_resp}" | jq -r '.token // empty' 2>/dev/null || true)"
  if [[ -z "${_tok}" ]]; then
    return 1
  fi

  printf '%s' "${_tok}"
}

# _gs_eu2_ghcr_fetch_tags — fetch all tags for a ghcr.io image.
#
# Args:    $1 identifier — "owner/image" string
#          $2 token      — Bearer token (from _gs_eu2_ghcr_get_token)
# Prints:  newline-separated tag names
# Returns: 0 on success; non-zero on HTTP failure
# Side fx: may read/write cache (via _gs_eu2_http_get_auth)
#
# Requests up to n=1000 tags in a single OCI distribution API call.
# The OCI Link-header pagination mechanism is not supported; n=1000 covers
# the vast majority of real-world repositories in a single request.
_gs_eu2_ghcr_fetch_tags() {
  local _identifier="${1}" _tok="${2}"
  local _url="https://ghcr.io/v2/${_identifier}/tags/list?n=1000"
  local _resp

  if ! _resp="$(_gs_eu2_http_get_auth "${_url}" "${_tok}" 2>/dev/null)"; then
    return 1
  fi

  printf '%s\n' "${_resp}" | jq -r '.tags[]?' 2>/dev/null || true
}

# _gs_eu2_fetch_ghcr — main entry point for the ghcr: fetcher type.
#
# Args:    $1 record_index — 0-based record index
# Reads:   record fields: identifier, channel, major_hint, major_hint_min,
#          tag_filter, tag_exclude, tag_strip_prefix, tag_strip_suffix,
#          tag_extract, tag_replace_from, tag_replace_to,
#          watch_major_depth, current_version, version_prefix
# Sets:    record fields: proposed_version, decision (ERROR/SKIP only),
#          error_message, latest_unconstrained, using_fallback_major
# Prints:  nothing
# Returns: 0 always (errors stored in record, not propagated as exit codes)
_gs_eu2_fetch_ghcr() {
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
  local _cache_key="ghcr:${_identifier}:${_major_hint}:${_major_hint_min}:${_channel}:${_wm_depth_ck}"

  # Cache read
  if [[ "${_no_cache}" != "true" ]]; then
    local _cached
    if _cached="$(_gs_eu2_cache_read "${_cache_key}")" && [[ -n "${_cached}" ]]; then
      if [[ -n "${_major_hint_min}" && -n "${_cached}" \
            && "${_cached}" =~ ^v?"${_major_hint_min}"([.^_-]|$) \
            && ! "${_cached}" =~ ^v?"${_major_hint}"([.^_-]|$) ]]; then
        _gs_eu2_record_set "${_idx}" using_fallback_major "true"
      fi
      _gs_eu2_record_set "${_idx}" proposed_version "${_cached}"
      return 0
    fi
  fi

  # Obtain Bearer token (PAT fast-path or anonymous token acquisition).
  local _tok
  if ! _tok="$(_gs_eu2_ghcr_get_token "${_identifier}" 2>/dev/null)"; then
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "failed to acquire authentication token for ghcr:${_identifier} — set GITHUB_TOKEN for private images"
    return 0
  fi

  if [[ -z "${_tok}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "empty authentication token for ghcr:${_identifier} — set GITHUB_TOKEN for private images"
    return 0
  fi

  # Fetch tags
  local _raw_tags
  if ! _raw_tags="$(_gs_eu2_ghcr_fetch_tags "${_identifier}" "${_tok}")"; then
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "fetch failed for ghcr:${_identifier}"
    return 0
  fi

  if [[ -z "${_raw_tags}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "ERROR"
    _gs_eu2_record_set "${_idx}" error_message "no tags returned for ghcr:${_identifier}"
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
    _unconstrained_best="$(_gs_eu2_channel_select_best "${_wm_tags}" "stable")"
    if [[ -n "${_unconstrained_best}" ]]; then
      local _vp_wm
      _vp_wm="$(_gs_eu2_record_get "${_idx}" version_prefix)"
      [[ -n "${_vp_wm}" ]] && _unconstrained_best="${_vp_wm}${_unconstrained_best}"
      _gs_eu2_record_set "${_idx}" latest_unconstrained "${_unconstrained_best}"
    fi
  fi

  # Save pre-filter tag list for fallback-major retry below.
  local _tags_premajor="${_tags}"

  # Major-pin filter — anchor prevents "2" matching "20.x"
  if [[ -n "${_major_hint}" ]]; then
    _tags="$(printf '%s\n' "${_tags}" | grep -E "^v?${_major_hint}([.^-]|\$)" 2>/dev/null \
      || printf '%s\n' "${_tags}" | awk -F'[v.-]' -v m="${_major_hint}" \
           '{ v=$0; sub(/^v/,"",v); split(v,a,"[.-]"); if(a[1]==m) print $0 }' || true)"
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
      _gs_eu2_record_set "${_idx}" error_message "no tags matched filters for ghcr:${_identifier}"
      return 0
    fi
  fi

  # Detect all-unversioned tag set (e.g. image has only "latest", "edge", "sha-*" tags)
  local _has_versioned=false _utag
  while IFS= read -r _utag; do
    [[ -z "${_utag}" ]] && continue
    if ! _gs_eu2_is_unversioned "${_utag}"; then _has_versioned=true; break; fi
  done <<< "${_tags}"
  if [[ "${_has_versioned}" == "false" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "SKIP"
    _gs_eu2_record_set "${_idx}" error_message "no versioned tags available for ghcr:${_identifier}"
    return 0
  fi

  # Channel selection → proposed
  local _proposed
  _proposed="$(_gs_eu2_channel_select_best "${_tags}" "${_channel}")"

  if [[ -z "${_proposed}" ]]; then
    _gs_eu2_record_set "${_idx}" decision      "SKIP"
    _gs_eu2_record_set "${_idx}" error_message "channel selection returned nothing for ghcr:${_identifier}"
    return 0
  fi

  # Re-prepend version_prefix stripped by tag-strip-prefix (mirrors quay/dockerhub B3)
  local _vp
  _vp="$(_gs_eu2_record_get "${_idx}" version_prefix)"
  [[ -n "${_vp}" ]] && _proposed="${_vp}${_proposed}"

  # Write result — proposed_version only; decision left empty for decide.sh
  _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"

  # Cache the result
  [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"

  return 0
}
