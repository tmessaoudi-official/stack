#!/bin/bash
# url.sh — URL fetcher — tiered strategy for arbitrary URL-based version sources.
#
# Input:  record index — reads type/identifier/fetch_extract/fetch_json/channel/
#                        urls/url_probe/url_probe_depth/version_prefix etc.
# Output: writes proposed_version + error_message + alt_version back into record.
#         NEVER writes decision (except ERROR on hard fetch failure) — that is
#         owned exclusively by core/decide.sh.
#
# 5-tier strategy (tried in order, stop at first successful extraction):
#   Tier 1: fetch-extract — fetch URL body, run perl regex capture-group-1
#   Tier 2: fetch-json    — fetch URL as JSON, run jq path extraction
#   Tier 3: GitHub redirect — use urls: field to call GitHub releases/tags API
#   Tier 4: directory listing — Apache/SVN/GNU/nodejs HTML directory index;
#                                channel:nightly sub-mode included here
#   Tier 5: url-probe — probe Ubuntu-codename-qualified paths for availability
#
# When no tier matches: set error_message "no extraction strategy matched for <url>"
# and return 0 (not ERROR — decide.sh will classify as SKIP since proposed is empty).

[[ -n "${_GS_EU2_URL_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_URL_SH_LOADED=1

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
# shellcheck source=../core/ubuntu.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/ubuntu.sh"
# shellcheck source=../http/curl.sh
source "$(dirname "${BASH_SOURCE[0]}")/../http/curl.sh"
# shellcheck source=./github.sh
source "$(dirname "${BASH_SOURCE[0]}")/github.sh"

# _gs_eu2_fetch_url INDEX
# Main fetcher entry point — takes one argument: record index.
_gs_eu2_fetch_url() {
  local _idx="${1}"

  local _identifier _channel _fetch_extract _fetch_json _urls
  local _url_probe _url_probe_depth _version_prefix _no_cache
  _identifier="$(_gs_eu2_record_get "${_idx}" identifier)"
  _channel="$(_gs_eu2_record_get "${_idx}" channel)"
  _fetch_extract="$(_gs_eu2_record_get "${_idx}" fetch_extract)"
  _fetch_json="$(_gs_eu2_record_get "${_idx}" fetch_json)"
  _urls="$(_gs_eu2_record_get "${_idx}" urls)"
  _url_probe="$(_gs_eu2_record_get "${_idx}" url_probe)"
  _url_probe_depth="$(_gs_eu2_record_get "${_idx}" url_probe_depth)"
  _version_prefix="$(_gs_eu2_record_get "${_idx}" version_prefix)"
  _no_cache="${_GS_EU2_CFG[no_cache]:-false}"

  # Build a stable cache key covering all discriminating fields
  local _cache_key
  _cache_key="url:${_identifier}:${_fetch_extract:+fe}:${_fetch_json:+fj}:${_url_probe:+up}:${_channel}"

  # Cache read (skip when no_cache=true)
  if [[ "${_no_cache}" != "true" ]]; then
    local _cached
    if _cached="$(_gs_eu2_cache_read "${_cache_key}")" && [[ -n "${_cached}" ]]; then
      _gs_eu2_record_set "${_idx}" proposed_version "${_cached}"
      return 0
    fi
  fi

  local _proposed=""

  # ────────────────────────────────────────────────────────────────────────
  # Tier 1 — fetch-extract
  # Fetch URL body; run perl regex, capture group 1; sort -V; take highest.
  # ────────────────────────────────────────────────────────────────────────
  if [[ -n "${_fetch_extract}" ]]; then
    local _body _fetch_ok=false
    if _body="$(_gs_eu2_http_get "${_identifier}" 2>/dev/null)"; then
      _fetch_ok=true
      _proposed="$(printf '%s' "${_body}" | \
        perl -ne "if (/${_fetch_extract}/) { print \"\$1\n\" }" 2>/dev/null | \
        sort -V | tail -1 || true)"
    fi

    if [[ -n "${_proposed}" ]]; then
      [[ -n "${_version_prefix}" ]] && _proposed="${_version_prefix}${_proposed}"
      _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"
      [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"
      return 0
    fi

    # Distinguish HTTP fetch failure from a regex that matched nothing
    if [[ "${_fetch_ok}" != "true" ]]; then
      _gs_eu2_record_set "${_idx}" error_message \
        "url: fetch failed for ${_identifier}"
    else
      _gs_eu2_record_set "${_idx}" error_message \
        "url: fetch-extract pattern '${_fetch_extract}' matched nothing from ${_identifier}"
    fi
    return 0
  fi

  # ────────────────────────────────────────────────────────────────────────
  # Tier 2 — fetch-json
  # Fetch URL as JSON; extract via jq path.
  # ────────────────────────────────────────────────────────────────────────
  if [[ -n "${_fetch_json}" ]]; then
    local _json
    if _json="$(_gs_eu2_http_get "${_identifier}" 2>/dev/null)"; then
      _proposed="$(printf '%s' "${_json}" | jq -r "${_fetch_json}" 2>/dev/null || true)"
      # Discard the literal string "null" (jq output when key is JSON null).
      # Use exact-match only — substring replacement would corrupt versions like "null-rc1".
      [[ "${_proposed}" == "null" ]] && _proposed=""
      _proposed="${_proposed//$'\n'/}"
    fi

    if [[ -n "${_proposed}" ]]; then
      [[ -n "${_version_prefix}" ]] && _proposed="${_version_prefix}${_proposed}"
      _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"
      [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"
      return 0
    fi

    _gs_eu2_record_set "${_idx}" error_message \
      "url: fetch-json jq path '${_fetch_json}' returned empty from ${_identifier}"
    return 0
  fi

  # ────────────────────────────────────────────────────────────────────────
  # Tier 3 — GitHub redirect via urls: field
  # When a urls: annotation includes a github.com URL, extract owner/repo
  # and use the GitHub releases/tags API directly (avoids HTML scraping).
  # Reuses github.sh exported helpers — does NOT call _gs_eu2_fetch_github
  # to avoid double-writing the record.
  # ────────────────────────────────────────────────────────────────────────
  if [[ -n "${_urls}" ]]; then
    local _tok="${GITHUB_TOKEN:-${GLOBAL_STACK_GITHUB_TOKEN:-}}"
    local _ref_url
    for _ref_url in ${_urls}; do
      if [[ "${_ref_url}" =~ github\.com/([^/]+)/([^/[:space:]]+) ]]; then
        local _gh_owner="${BASH_REMATCH[1]}"
        local _gh_repo="${BASH_REMATCH[2]}"
        # Strip trailing path segments (e.g. /releases, /tags) and .git suffix
        _gh_repo="${_gh_repo%%/*}"
        _gh_repo="${_gh_repo%.git}"
        local _gh_id="${_gh_owner}/${_gh_repo}"

        # Strategy 1: Releases API
        local _raw_tags=""
        local _releases_out
        if _releases_out="$(_gs_eu2_github_fetch_releases "${_gh_id}" "${_tok}" 2>/dev/null)"; then
          _raw_tags="${_releases_out}"
        fi

        # Strategy 2: Tags API when releases returned nothing
        if [[ -z "$(printf '%s\n' "${_raw_tags}" | grep -v '^$' || true)" ]]; then
          _raw_tags="$(_gs_eu2_github_fetch_tags_paginated "${_gh_id}" "${_tok}" 3 2>/dev/null)"
        fi

        if [[ -n "$(printf '%s\n' "${_raw_tags}" | grep -v '^$' || true)" ]]; then
          # Apply tag_flags pipeline from record
          local _filtered_tags
          _filtered_tags="$(printf '%s\n' "${_raw_tags}" | _gs_eu2_apply_tag_flags_from_record "${_idx}")"

          _proposed="$(_gs_eu2_channel_select_best "${_filtered_tags}" "${_channel}")"

          if [[ -n "${_proposed}" ]]; then
            [[ -n "${_version_prefix}" ]] && _proposed="${_version_prefix}${_proposed}"
            _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"
            [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"
            return 0
          fi
        fi
        # This GitHub URL didn't yield a result — try next urls: entry
      fi
    done
  fi

  # ────────────────────────────────────────────────────────────────────────
  # Tier 4 — Directory listing (Apache SVN, GNU mirrors, Node.js nightly)
  #
  # Two sub-modes:
  #   a) channel:nightly  — parse href entries that look like nightly version dirs
  #   b) otherwise        — detect Apache/SVN/GNU directory index by URL pattern;
  #                         extract numeric version hrefs, apply channel selection
  # ────────────────────────────────────────────────────────────────────────

  # Sub-mode a: channel:nightly — directory listing of version dirs
  if [[ "${_channel}" == "nightly" ]]; then
    local _nightly_html
    if _nightly_html="$(_gs_eu2_http_get "${_identifier}" 2>/dev/null)"; then
      local _entries
      _entries="$(printf '%s' "${_nightly_html}" | \
        perl -ne 'while (/href="([^"\/][^"]*\/?)"/g) { print "$1\n" }' 2>/dev/null | \
        grep -v '^[.?#]' | \
        sed 's|/$||' | \
        grep -E '[0-9]' | \
        grep -v '^$' || true)"

      _proposed="$(printf '%s\n' "${_entries}" | \
        perl -ne '
          # Normalize sort key: strip hex SHA that follows a YYYYMMDD date.
          # Applies to any channel format (nightly, canary, dev, ...) — the
          # channel name is irrelevant; only the date+sha suffix causes sort-V
          # to mis-order entries. Non-matching entries pass through unchanged.
          chomp; $orig = $_;
          (my $key = $orig) =~ s/(\d{8})[0-9a-fA-F]+$/$1/;
          print "$key\t$orig\n";
        ' | sort -V -k1,1 | tail -1 | cut -f2 || true)"
      _proposed="${_proposed%/}"
    fi

    if [[ -n "${_proposed}" ]]; then
      [[ -n "${_version_prefix}" ]] && _proposed="${_version_prefix}${_proposed}"
      _gs_eu2_record_set "${_idx}" proposed_version "${_proposed}"
      [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_proposed}"
      return 0
    fi

    _gs_eu2_record_set "${_idx}" error_message \
      "url: channel:nightly — no version entries found at ${_identifier}"
    return 0
  fi

  # Sub-mode b: Apache/SVN/GNU directory listing detection by URL pattern
  local _is_dir_listing=false
  if [[ "${_identifier}" =~ svn\.apache\.org/repos/asf/ ]] || \
     [[ "${_identifier}" =~ /pub/gnu/ ]] || \
     [[ "${_identifier}" =~ apache\.org.*tags/ ]]; then
    _is_dir_listing=true
  fi

  if [[ "${_is_dir_listing}" == "true" ]]; then
    local _dir_html
    if _dir_html="$(_gs_eu2_http_get "${_identifier}" 2>/dev/null)"; then
      # Extract href values that look like versioned paths.
      # Handles both bare version numbers and paths like "tags/1.6.3/" from SVN.
      local _raw_candidates
      _raw_candidates="$(printf '%s' "${_dir_html}" | \
        grep -oE 'href="[^"]*"' | \
        sed 's|href="||;s|"$||' | \
        grep -E '[0-9]+\.[0-9]' | \
        sed 's|/$||' | \
        grep -v '^$' || true)"

      # Two extraction paths:
      #   1. version_prefix set → keep the full href value (e.g. "tags/1.6.3") and
      #      strip only the prefix so channel_select_best works on a bare number,
      #      then re-prepend the prefix.
      #   2. No prefix → extract bare version numbers from hrefs.
      local _dir_versions=""
      if [[ -n "${_version_prefix}" ]]; then
        # Keep only hrefs that start with the version_prefix (e.g. "tags/")
        local _pfx_hrefs
        _pfx_hrefs="$(printf '%s\n' "${_raw_candidates}" | \
          grep "^${_version_prefix}" | \
          sed "s|^${_version_prefix}||" | \
          grep -v '^$' || true)"
        _dir_versions="${_pfx_hrefs}"
      else
        # Extract numeric version-looking substrings from hrefs
        _dir_versions="$(printf '%s\n' "${_raw_candidates}" | \
          grep -oE '[0-9]+\.[0-9][0-9a-zA-Z._-]*' | \
          grep -v '^$' || true)"
      fi

      if [[ -n "${_dir_versions}" ]]; then
        local _best
        _best="$(_gs_eu2_channel_select_best "${_dir_versions}" "${_channel}")"
        if [[ -n "${_best}" ]]; then
          [[ -n "${_version_prefix}" ]] && _best="${_version_prefix}${_best}"
          _gs_eu2_record_set "${_idx}" proposed_version "${_best}"
          [[ "${_no_cache}" != "true" ]] && _gs_eu2_cache_write "${_cache_key}" "${_best}"
          return 0
        fi
      fi
    fi
    # Dir-listing fetch failed or no versions found — fall through to error
    _gs_eu2_record_set "${_idx}" error_message \
      "url: directory listing — no version entries found at ${_identifier}"
    return 0
  fi

  # ────────────────────────────────────────────────────────────────────────
  # Tier 5 — url-probe
  # Probe Ubuntu-codename-qualified paths for the first that returns 2xx/3xx.
  # Derives the "current" codename from the current_version field by parsing
  # the xUbuntu_XX.XX suffix (e.g. "unstable/xUbuntu_24.04" → "noble").
  # Returns the raw path form (e.g. "stable/xUbuntu_24.04") so that decide.sh
  # can compare it directly against the current_version string.
  # ────────────────────────────────────────────────────────────────────────
  if [[ -n "${_url_probe}" ]]; then
    local _probe_result
    _probe_result="$(_gs_eu2_url_probe_check \
      "${_identifier}" \
      "${_url_probe}" \
      "${_url_probe_depth:-6}" \
      "${_cache_key}")"

    if [[ -n "${_probe_result}" ]]; then
      _gs_eu2_record_set "${_idx}" proposed_version "${_probe_result}"
      # Note: _gs_eu2_url_probe_check already writes cache internally
      return 0
    fi

    _gs_eu2_record_set "${_idx}" error_message \
      "url: url-probe — no accessible path found at ${_identifier}"
    return 0
  fi

  # ────────────────────────────────────────────────────────────────────────
  # No tier matched — set error message, leave proposed_version empty.
  # decide.sh will classify as SKIP when proposed is empty.
  # ────────────────────────────────────────────────────────────────────────
  _gs_eu2_record_set "${_idx}" error_message \
    "url: no extraction strategy matched for ${_identifier}"
  return 0
}

# _gs_eu2_url_probe_check BASE_URL PROBE_PATHS DEPTH CACHE_KEY
#
# Probes path templates for each Ubuntu codename going from current → older,
# testing each path in the order listed in PROBE_PATHS.  Returns the first
# path (raw form, e.g. "stable/xUbuntu_24.04") that responds with 2xx/3xx.
#
# Template variables in PROBE_PATHS:
#   {codename}         → Ubuntu codename (e.g. "noble")
#   {codename-version} → Ubuntu version number (e.g. "24.04")
#
# The starting codename is derived from the current_version field in the
# record (e.g. "unstable/xUbuntu_24.04" → version "24.04" → codename "noble").
# If derivation fails, starts from the newest known codename.
#
# Probes newest first (current codename, then older ones) so we always
# propose the most recent available path.
_gs_eu2_url_probe_check() {
  local _base_url="${1}"
  local _probe_paths_str="${2}"
  local _depth="${3:-6}"
  local _cache_key="${4:-url-probe:${_base_url}}"

  # Split probe paths on comma into an array
  local _paths=()
  local _old_ifs="${IFS}"
  IFS=',' read -ra _paths <<< "${_probe_paths_str}"
  IFS="${_old_ifs}"

  if [[ ${#_paths[@]} -eq 0 ]]; then
    return 0
  fi

  # Build ordered codename list (oldest → newest); we'll probe newest first
  local _all_codenames=()
  local _cn_line
  while IFS= read -r _cn_line; do
    [[ -z "${_cn_line}" ]] && continue
    _all_codenames+=("${_cn_line}")
  done < <(_gs_eu2_ubuntu_codename_list)

  # Reverse to get newest-first order for probing
  local _ordered=()
  local _i
  for (( _i = ${#_all_codenames[@]} - 1; _i >= 0; _i-- )); do
    _ordered+=("${_all_codenames[${_i}]}")
  done

  local _end=$(( _depth - 1 ))
  if [[ "${_end}" -ge "${#_ordered[@]}" ]]; then
    _end=$(( ${#_ordered[@]} - 1 ))
  fi

  # Probe from newest codename, going back up to _depth codenames
  local _probe_cn
  for (( _i = 0; _i <= _end; _i++ )); do
    _probe_cn="${_ordered[${_i}]}"
    local _probe_cn_ver
    _probe_cn_ver="$(_gs_eu2_ubuntu_codename_to_version "${_probe_cn}")"

    local _probe_path
    for _probe_path in "${_paths[@]}"; do
      # Substitute template variables
      local _resolved="${_probe_path}"
      _resolved="${_resolved//\{codename\}/${_probe_cn}}"
      _resolved="${_resolved//\{codename-version\}/${_probe_cn_ver}}"

      local _full_url="${_base_url%/}/${_resolved}/"
      local _http_code
      _http_code="$(_gs_eu2_url_probe_http_check "${_full_url}")"

      # Accept 2xx or 3xx (resource exists, possibly redirected)
      if [[ "${_http_code:0:1}" == "2" || "${_http_code:0:1}" == "3" ]]; then
        # Reconstruct the raw path form (e.g. "stable/xUbuntu_24.04")
        local _result_path="${_probe_path}"
        _result_path="${_result_path//\{codename\}/${_probe_cn}}"
        _result_path="${_result_path//\{codename-version\}/${_probe_cn_ver}}"

        _gs_eu2_cache_write "${_cache_key}" "${_result_path}"
        printf '%s' "${_result_path}"
        return 0
      fi
    done
  done

  # Nothing found
  return 0
}

# _gs_eu2_url_probe_http_check URL
# Returns the HTTP status code for a HEAD/GET to URL.
# Uses fixture injection when _GS_EU2_HTTP_FIXTURE_DIR is set —
# presence of the fixture file = 200; absence = 404.
_gs_eu2_url_probe_http_check() {
  local _url="${1}"

  if [[ -n "${_GS_EU2_HTTP_FIXTURE_DIR:-}" ]]; then
    local _safe
    _safe="$(_gs_eu2_fixture_path "${_url}")"
    local _fixture_path="${_GS_EU2_HTTP_FIXTURE_DIR}/${_safe}"
    if [[ -f "${_fixture_path}" ]]; then
      printf '200'
    else
      printf '404'
    fi
    return 0
  fi

  # Real HTTP probe: use curl HEAD first (faster), fallback to GET for servers
  # that don't support HEAD (some Apache directory listings return 405 on HEAD).
  local _code
  _code="$(curl --silent --max-time 10 --retry 1 \
    --head \
    -o /dev/null -w '%{http_code}' \
    "${_url}" 2>/dev/null || printf '0')"

  # If HEAD returned 405 (Method Not Allowed), retry with GET
  if [[ "${_code}" == "405" ]]; then
    _code="$(curl --silent --max-time 10 --retry 1 \
      -o /dev/null -w '%{http_code}' \
      "${_url}" 2>/dev/null || printf '0')"
  fi

  printf '%s' "${_code}"
}
