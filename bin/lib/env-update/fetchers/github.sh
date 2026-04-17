#!/bin/bash
# GitHub Releases/Tags API fetcher.
# Handles both releases and tags endpoints.

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_EU_GITHUB_SH_LOADED:-}" ]] && return 0
readonly _GS_EU_GITHUB_SH_LOADED=1

# Write a fetch error message to the error file (works across subshell boundaries)
# Usage: _gs_eu_set_fetch_error "HTTP 403 — rate-limited"
_gs_eu_set_fetch_error() {
  printf '%s' "${1}" > "${_GS_EU_FETCH_ERROR_FILE:-/tmp/gs-fetch-error}" 2>/dev/null || true
}

# Write a pre-release hint for a variable to the shared hint file.
# Called by the dispatch layer in env-update.sh after reading _GS_EU_ALT_VERSION_FILE.
# Usage (stable mode — hint toward newer pre-release):
#   _gs_eu_set_prerelease_hint "GLOBAL_STACK_FOO" "3.15.0a7" "also"
# Usage (unstable mode — hint toward stable):
#   _gs_eu_set_prerelease_hint "GLOBAL_STACK_FOO" "3.14.2" "stable"
_gs_eu_set_prerelease_hint() {
  local var_name="${1}"
  local hint_version="${2}"
  local hint_direction="${3:-also}"  # "also" = stable→pre, "stable" = unstable→stable
  if [[ -n "${_GS_EU_PRERELEASE_HINT_FILE:-}" ]]; then
    if [[ "${hint_direction}" == "stable" ]]; then
      printf '%s:stable: %s\n' "${var_name}" "${hint_version}" \
        >> "${_GS_EU_PRERELEASE_HINT_FILE}" 2>/dev/null || true
    else
      printf '%s:also: %s (pre-release available — use channel:unstable/rc/beta/etc to track)\n' \
        "${var_name}" "${hint_version}" \
        >> "${_GS_EU_PRERELEASE_HINT_FILE}" 2>/dev/null || true
    fi
  fi
}

# Apply tag-filter, tag-exclude, tag-strip-prefix, tag-strip-suffix, tag-extract,
# tag-replace-from/to to a newline-separated list of tag strings.
# Returns filtered/transformed tags, one per line.
# This is a thin wrapper over _gs_eu_apply_tag_flags (from tag_flags.sh).
_gs_eu_github_apply_tag_flags() {
  local tags_text="${1}"      # newline-separated tag names
  local tag_filter="${2:-}"
  local tag_exclude="${3:-}"
  local tag_strip_prefix="${4:-}"
  local tag_strip_suffix="${5:-}"
  local tag_extract="${6:-}"
  local tag_replace_from="${7:-}"
  local tag_replace_to="${8:-}"

  printf '%s\n' "${tags_text}" | _gs_eu_apply_tag_flags \
    "${tag_filter}" "${tag_exclude}" "${tag_strip_prefix}" "${tag_strip_suffix}" \
    "${tag_extract}" "${tag_replace_from}" "${tag_replace_to}"
}

# Select highest semver from a newline-separated list of version strings
_gs_eu_github_select_highest_semver() {
  local versions_text="${1}"
  printf '%s\n' "${versions_text}" | \
    grep -E '^[0-9]' | \
    sort -V | \
    tail -1 2>/dev/null || true
}

# Fetch latest release from GitHub
# Usage: _gs_eu_github_fetch_latest "golang/go" "1.26.1"
# Usage: _gs_eu_github_fetch_latest "php/php-src" "8.2.30" "false" "false" "8.2"
# Extended: _gs_eu_github_fetch_latest "owner/repo" "ver" "offline" "no_cache" "major_pin" \
#             "tag_filter" "tag_exclude" "tag_strip_prefix" "tag_strip_suffix" "tag_extract" \
#             "tag_replace_from" "tag_replace_to" "channel" "version_prefix"
# Returns: echoed version string or empty on failure
_gs_eu_github_fetch_latest() {
  local identifier="${1}"    # "owner/repo"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"
  local major_pin="${5:-}"
  local tag_filter="${6:-}"
  local tag_exclude="${7:-}"
  local tag_strip_prefix="${8:-}"
  local tag_strip_suffix="${9:-}"
  local tag_extract="${10:-}"
  local tag_replace_from="${11:-}"
  local tag_replace_to="${12:-}"
  local channel="${13:-}"
  local version_prefix="${14:-}"

  # Derive mode from channel
  local stable_only="true"
  local pre_release="false"
  if [[ "${channel}" == "nightly" ]]; then
    stable_only="false"
  elif [[ -n "${channel}" && "${channel}" != "stable" ]]; then
    stable_only="false"
    pre_release="true"
  fi

  local cache_key="github:${identifier}:${major_pin:-all}:${tag_filter}:${tag_exclude}:${tag_extract}:${channel}:${tag_replace_from}"

  # Cache check
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

  # Build auth header if GITHUB_TOKEN is set
  local auth_args=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth_args=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  local proposed=""

  # If major_pin is set, try releases API first (faster, more reliable ordering),
  # then fall back to tags pagination. Repos like flutter/flutter return tags oldest-first
  # so tags pagination (even 10 pages) may not reach recent pinned versions.
  if [[ -n "${major_pin}" ]]; then

    # --- RELEASES-FIRST for major-pin ---
    local _mp_rel_tmp
    _mp_rel_tmp="$(mktemp)"
    local _mp_rel_code
    _mp_rel_code="$(curl --silent --location --max-time 10 --retry 2 \
      "${auth_args[@]}" \
      -H "Accept: application/vnd.github+json" \
      -o "${_mp_rel_tmp}" \
      -w "%{http_code}" \
      "https://api.github.com/repos/${identifier}/releases?per_page=100" 2>/dev/null || echo "0")"
    local _mp_rel_body
    _mp_rel_body="$(cat "${_mp_rel_tmp}" 2>/dev/null || true)"
    rm -f "${_mp_rel_tmp}"

    if [[ "${_mp_rel_code:0:1}" == "2" ]]; then
      local _mp_stable=() _mp_pre=()
      local _mp_rel_tag _mp_rel_pre
      while IFS=$'\t' read -r _mp_rel_tag _mp_rel_pre; do
        [[ -z "${_mp_rel_tag}" ]] && continue
        local _mp_ver="${_mp_rel_tag#v}"
        [[ "${_mp_ver}" =~ ^[0-9] ]] || continue
        # Apply tag flags if present
        if [[ -n "${tag_filter}${tag_exclude}${tag_strip_prefix}${tag_strip_suffix}${tag_extract}${tag_replace_from}" ]]; then
          _mp_ver="$(_gs_eu_github_apply_tag_flags "${_mp_ver}" \
            "${tag_filter}" "${tag_exclude}" "${tag_strip_prefix}" "${tag_strip_suffix}" \
            "${tag_extract}" "${tag_replace_from}" "${tag_replace_to}")"
          [[ -z "${_mp_ver}" ]] && continue
        fi
        # Apply major_pin filter
        [[ "${_mp_ver}" == "${major_pin}."* || "${_mp_ver}" == "${major_pin}" ]] || continue
        if [[ "${_mp_rel_pre}" == "false" ]] && ! _gs_eu_is_prerelease "${_mp_ver}"; then
          _mp_stable+=("${_mp_ver}")
        else
          _gs_eu_version_matches_channel "${_mp_ver}" "${channel}" && _mp_pre+=("${_mp_ver}") || true
        fi
      done < <(printf '%s' "${_mp_rel_body}" | jq -r \
        '.[] | select(.draft == false) | [.tag_name, (.prerelease | tostring)] | @tsv' \
        2>/dev/null || true)

      local _mp_best=""
      if [[ "${stable_only}" == "true" && ${#_mp_stable[@]} -gt 0 ]]; then
        _mp_best="$(printf '%s\n' "${_mp_stable[@]}" | sort -V | tail -1 || true)"
        if [[ ${#_mp_pre[@]} -gt 0 ]]; then
          _gs_eu_write_alt_version "also" "$(printf '%s\n' "${_mp_pre[@]}" | sort -V | tail -1 || true)"
        fi
      elif [[ "${pre_release}" == "true" && ${#_mp_pre[@]} -gt 0 ]]; then
        _mp_best="$(printf '%s\n' "${_mp_pre[@]}" | sort -V | tail -1 || true)"
        if [[ ${#_mp_stable[@]} -gt 0 ]]; then
          _gs_eu_write_alt_version "stable" "$(printf '%s\n' "${_mp_stable[@]}" | sort -V | tail -1 || true)"
        fi
      elif [[ "${stable_only}" != "true" && "${pre_release}" != "true" ]]; then
        # No channel filter — pick highest across stable+pre
        local _mp_all=()
        [[ ${#_mp_stable[@]} -gt 0 ]] && _mp_all+=("${_mp_stable[@]}")
        [[ ${#_mp_pre[@]} -gt 0 ]] && _mp_all+=("${_mp_pre[@]}")
        [[ ${#_mp_all[@]} -gt 0 ]] && _mp_best="$(printf '%s\n' "${_mp_all[@]}" | sort -V | tail -1 || true)"
      fi

      if [[ -n "${_mp_best}" ]]; then
        _gs_eu_cache_write "${cache_key}" "${_mp_best}"
        echo "${_mp_best}"
        return 0
      fi
    fi
    # Releases API didn't yield a pinned result — fall through to tags pagination
    # --- END RELEASES-FIRST ---

    local all_tags_json="[]"
    local page=0
    while (( ++page <= 10 )); do
      local tags_url="https://api.github.com/repos/${identifier}/tags?per_page=100&page=${page}"
      local tmp_file
      tmp_file="$(mktemp)"
      local http_code
      http_code="$(curl --silent --location --max-time 10 --retry 2 \
        "${auth_args[@]}" \
        -H "Accept: application/vnd.github+json" \
        -o "${tmp_file}" \
        -w "%{http_code}" \
        "${tags_url}" 2>/dev/null || echo "0")"
      local page_tags=""
      page_tags="$(cat "${tmp_file}" 2>/dev/null || true)"
      rm -f "${tmp_file}"

      if [[ "${http_code}" == "403" ]]; then
        _gs_eu_set_fetch_error "HTTP 403 — rate-limited (set GITHUB_TOKEN in .env.local)"
        return 1
      elif [[ "${http_code}" == "404" ]]; then
        _gs_eu_set_fetch_error "HTTP 404 — repo not found, verify identifier"
        return 1
      elif [[ "${http_code}" == "0" || "${http_code:0:1}" != "2" ]]; then
        _gs_eu_set_fetch_error "HTTP ${http_code} — network/server error"
        return 1
      fi

      # Merge page into all_tags_json
      all_tags_json="$(printf '%s\n%s\n' "${all_tags_json}" "${page_tags}" | \
        jq -rs '[.[] | .[]]' 2>/dev/null || echo "${all_tags_json}")"

      # Check if this page found a match for the pin — if so stop early
      local page_match
      page_match="$(printf '%s' "${page_tags}" | jq -r \
        --arg pin "${major_pin}" \
        '[.[] | .name | select(test("^[^0-9]*" + ($pin | gsub("\\."; "\\.")) + "[._]"))]
         | length' 2>/dev/null || echo "0")"
      if [[ "${page_match}" -gt 0 ]]; then
        break
      fi

      # Stop if page returned fewer than 100 (last page)
      local page_count
      page_count="$(printf '%s' "${page_tags}" | jq -r 'length' 2>/dev/null || echo "0")"
      if [[ "${page_count}" -lt 100 ]]; then
        break
      fi
    done

    # Extract tag names as newline-separated text
    local all_tag_names
    all_tag_names="$(printf '%s' "${all_tags_json}" | jq -r '.[].name' 2>/dev/null || echo "")"

    # Fallback: if pagination exhausted all 10 pages without finding any tags matching
    # the major pin, use git ls-remote --tags to fetch ALL tags in a single call.
    # This handles repos like flutter/flutter with >1000 tags where GitHub returns
    # oldest-first and the pinned major (e.g. 3.x) is beyond page 10.
    if [[ "${page}" -gt 10 ]]; then
      local _pin_match_count
      _pin_match_count="$(printf '%s\n' "${all_tag_names}" | grep -cE "^v?${major_pin}\." 2>/dev/null || echo "0")"
      if [[ "${_pin_match_count}" -eq 0 ]]; then
        _gs_eu_log_debug "github: tags pagination exhausted 10 pages without finding pin '${major_pin}' — trying git ls-remote"
        local _lsr_tags
        _lsr_tags="$(git ls-remote --tags "https://github.com/${identifier}.git" 2>/dev/null | \
          awk -F/ '{print $NF}' | sed 's/\^{}$//' | sort -u || true)"
        if [[ -n "${_lsr_tags}" ]]; then
          all_tag_names="${_lsr_tags}"
          all_tags_json="$(printf '%s\n' "${_lsr_tags}" | jq -R '.' | jq -s '[.[] | {name: .}]' 2>/dev/null || echo "[]")"
          _gs_eu_log_debug "github: git ls-remote found $(printf '%s\n' "${_lsr_tags}" | wc -l | tr -d ' ') tags"
        fi
      fi
    fi

    # Apply tag flags if any are set
    local _has_tag_flags=false
    if [[ -n "${tag_filter}${tag_exclude}${tag_strip_prefix}${tag_strip_suffix}${tag_extract}${tag_replace_from}" ]]; then
      _has_tag_flags=true
    fi

    if [[ "${_has_tag_flags}" == "true" ]]; then
      local filtered_tags
      filtered_tags="$(_gs_eu_github_apply_tag_flags "${all_tag_names}" \
        "${tag_filter}" "${tag_exclude}" "${tag_strip_prefix}" "${tag_strip_suffix}" "${tag_extract}" \
        "${tag_replace_from}" "${tag_replace_to}")"
      # Apply major_pin constraint (if set) and stable-only filter in bash layer
      local _tf_stable=() _tf_pre=()
      local _tf_v
      while IFS= read -r _tf_v; do
        [[ -z "${_tf_v}" ]] && continue
        # Apply major_pin filter if set
        if [[ -n "${major_pin}" ]]; then
          local _tf_pin_prefix="${major_pin}."
          [[ "${_tf_v}" == "${_tf_pin_prefix}"* || "${_tf_v}" == "${major_pin}" ]] || continue
        fi
        if _gs_eu_is_prerelease "${_tf_v}"; then
          _tf_pre+=("${_tf_v}")
        else
          _tf_stable+=("${_tf_v}")
        fi
      done <<< "${filtered_tags}"

      if [[ "${stable_only}" == "true" ]]; then
        if [[ ${#_tf_pre[@]} -gt 0 ]]; then
          _gs_eu_write_alt_version "also" "$(printf '%s\n' "${_tf_pre[@]}" | sort -V | tail -1 || true)"
        fi
        if [[ ${#_tf_stable[@]} -gt 0 ]]; then
          proposed="$(printf '%s\n' "${_tf_stable[@]}" | sort -V | tail -1 || true)"
        fi
      elif [[ "${pre_release}" == "true" ]]; then
        if [[ ${#_tf_stable[@]} -gt 0 ]]; then
          _gs_eu_write_alt_version "stable" "$(printf '%s\n' "${_tf_stable[@]}" | sort -V | tail -1 || true)"
        fi
        local _tf_ch=()
        local _tf_pv
        for _tf_pv in "${_tf_pre[@]}"; do
          if _gs_eu_version_matches_channel "${_tf_pv}" "${channel}"; then
            _tf_ch+=("${_tf_pv}")
          fi
        done
        if [[ ${#_tf_ch[@]} -gt 0 ]]; then
          proposed="$(printf '%s\n' "${_tf_ch[@]}" | sort -V | tail -1 || true)"
        elif [[ ${#_tf_pre[@]} -gt 0 ]]; then
          proposed="$(printf '%s\n' "${_tf_pre[@]}" | sort -V | tail -1 || true)"
        fi
      else
        # No specific channel — pick highest overall, stable preferred
        proposed="$(_gs_eu_github_select_highest_semver "${filtered_tags}")"
      fi

      if [[ -n "${proposed}" ]]; then
        _gs_eu_cache_write "${cache_key}" "${proposed}"
        echo "${proposed}"
        return 0
      fi
      # No candidates after tag flags + major_pin + stable filter.
      # If we wrote an alt-version hint (pre-release available), return empty
      # cleanly so the caller can surface a PREONLY entry via the hint file.
      # Otherwise, set a descriptive error so the caller shows WARN not NORES.
      if [[ ${#_tf_pre[@]} -eq 0 && ${#_tf_stable[@]} -eq 0 ]]; then
        _gs_eu_set_fetch_error "no tags matched filter '${tag_filter}' for major pin '${major_pin}' in ${identifier}"
        return 1
      fi
      # pre-only: hint was written; return empty cleanly (not an error)
      return 0
    fi

    # Handle Ruby-style underscore tags (v3_4_3 → 3.4.3)
    # Detect if any tags use underscore number format
    local has_underscore_tags
    has_underscore_tags="$(printf '%s' "${all_tags_json}" | jq -r \
      '[.[] | .name | select(test("^v[0-9]+_[0-9]"))] | length' 2>/dev/null || echo "0")"

    # Extract all matching candidates as newline-separated versions for bash-level filtering
    local _pin_candidates=""
    if [[ "${has_underscore_tags}" -gt 0 ]]; then
      # Convert underscore tags to dot-separated for filtering/sorting
      _pin_candidates="$(printf '%s' "${all_tags_json}" | jq -r \
        --arg pin "${major_pin}" \
        '[.[] | .name
          | gsub("_"; ".")
          | ltrimstr("v")
          | select(test("^" + ($pin | gsub("\\."; "\\.")) + "\\."))]
         | sort_by(split(".") | map(tonumber? // 0))
         | .[]' 2>/dev/null || echo "")"
    else
      # Standard dot-separated tags
      _pin_candidates="$(printf '%s' "${all_tags_json}" | jq -r \
        --arg pin "${major_pin}" \
        '[.[] | .name
          | select(test("^[^0-9]*" + ($pin | gsub("\\."; "\\.")) + "\\."))
          | ltrimstr("php-") | ltrimstr("v")]
         | sort_by(split(".") | map(tonumber? // 0))
         | .[]' 2>/dev/null || echo "")"
    fi

    if [[ -n "${_pin_candidates}" ]]; then
      # Apply stable-only filter in bash (jq sort can't call _gs_eu_is_prerelease)
      local _stable_cands=() _pre_cands=()
      local _pc
      while IFS= read -r _pc; do
        [[ -z "${_pc}" ]] && continue
        if _gs_eu_is_prerelease "${_pc}"; then
          _pre_cands+=("${_pc}")
        else
          _stable_cands+=("${_pc}")
        fi
      done <<< "${_pin_candidates}"

      if [[ "${stable_only}" == "true" ]]; then
        # Write highest pre-release as alt hint (for awareness)
        if [[ ${#_pre_cands[@]} -gt 0 ]]; then
          local _highest_pre="${_pre_cands[${#_pre_cands[@]}-1]}"
          _gs_eu_write_alt_version "also" "${_highest_pre}"
        fi
        if [[ ${#_stable_cands[@]} -gt 0 ]]; then
          proposed="${_stable_cands[${#_stable_cands[@]}-1]}"
        fi
      elif [[ "${pre_release}" == "true" ]]; then
        # Pre-release mode: pick highest matching channel
        local _ch_cands=()
        local _pc2
        for _pc2 in "${_pre_cands[@]}"; do
          if _gs_eu_version_matches_channel "${_pc2}" "${channel}"; then
            _ch_cands+=("${_pc2}")
          fi
        done
        if [[ ${#_stable_cands[@]} -gt 0 ]]; then
          _gs_eu_write_alt_version "stable" "${_stable_cands[${#_stable_cands[@]}-1]}"
        fi
        if [[ ${#_ch_cands[@]} -gt 0 ]]; then
          proposed="${_ch_cands[${#_ch_cands[@]}-1]}"
        elif [[ ${#_pre_cands[@]} -gt 0 ]]; then
          proposed="${_pre_cands[${#_pre_cands[@]}-1]}"
        fi
      else
        # No channel constraint — pick highest overall (stable preferred)
        if [[ ${#_stable_cands[@]} -gt 0 ]]; then
          proposed="${_stable_cands[${#_stable_cands[@]}-1]}"
        elif [[ ${#_pre_cands[@]} -gt 0 ]]; then
          proposed="${_pre_cands[${#_pre_cands[@]}-1]}"
        fi
      fi
    fi

    if [[ -n "${proposed}" ]]; then
      _gs_eu_cache_write "${cache_key}" "${proposed}"
      echo "${proposed}"
      return 0
    fi
    _gs_eu_set_fetch_error "no releases/tags matched version filter"
    return 1
  fi

  # If tag flags are set (no major_pin), use tags API directly with flag processing
  local _has_tag_flags_nmp=false
  if [[ -n "${tag_filter}${tag_exclude}${tag_strip_prefix}${tag_strip_suffix}${tag_extract}${tag_replace_from}" ]]; then
    _has_tag_flags_nmp=true
  fi

  if [[ "${_has_tag_flags_nmp}" == "true" ]]; then
    # Paginate tags (up to 10 pages / 1000 tags) — repos like golang/go return tags
    # oldest-first, so the latest version can be many pages deep.
    local all_tags_json_fl="[]"
    local page_fl=0
    while (( ++page_fl <= 10 )); do
      local tags_url_fl="https://api.github.com/repos/${identifier}/tags?per_page=100&page=${page_fl}"
      local tmp_file_fl
      tmp_file_fl="$(mktemp)"
      local http_code_fl
      http_code_fl="$(curl --silent --location --max-time 10 --retry 2 \
        "${auth_args[@]}" \
        -H "Accept: application/vnd.github+json" \
        -o "${tmp_file_fl}" \
        -w "%{http_code}" \
        "${tags_url_fl}" 2>/dev/null || echo "0")"
      local page_tags_fl
      page_tags_fl="$(cat "${tmp_file_fl}" 2>/dev/null || true)"
      rm -f "${tmp_file_fl}"

      if [[ "${http_code_fl}" == "403" ]]; then
        _gs_eu_set_fetch_error "HTTP 403 — rate-limited (set GITHUB_TOKEN in .env.local)"
        return 1
      elif [[ "${http_code_fl}" == "404" ]]; then
        _gs_eu_set_fetch_error "HTTP 404 — repo not found, verify identifier"
        return 1
      elif [[ "${http_code_fl}" == "0" || "${http_code_fl:0:1}" != "2" ]]; then
        _gs_eu_set_fetch_error "HTTP ${http_code_fl} — network/server error"
        return 1
      fi

      # Merge page into accumulated JSON
      all_tags_json_fl="$(printf '%s\n%s\n' "${all_tags_json_fl}" "${page_tags_fl}" | \
        jq -rs '[.[] | .[]]' 2>/dev/null || echo "${all_tags_json_fl}")"

      # Early exit: if tag_filter matches something on this page, stop paginating
      if [[ -n "${tag_filter}" ]]; then
        local page_match_fl
        page_match_fl="$(printf '%s' "${page_tags_fl}" | jq -r \
          --arg filt "${tag_filter}" \
          '[.[] | .name | select(test($filt))] | length' 2>/dev/null || echo "0")"
        if [[ "${page_match_fl}" -gt 0 ]]; then
          break
        fi
      fi

      # Stop if last page (fewer than 100 results)
      local page_count_fl
      page_count_fl="$(printf '%s' "${page_tags_fl}" | jq -r 'length' 2>/dev/null || echo "0")"
      if [[ "${page_count_fl}" -lt 100 ]]; then
        break
      fi
    done

    local all_tag_names_fl
    all_tag_names_fl="$(printf '%s' "${all_tags_json_fl}" | jq -r '.[].name' 2>/dev/null || echo "")"
    local filtered_tags_fl
    filtered_tags_fl="$(_gs_eu_github_apply_tag_flags "${all_tag_names_fl}" \
      "${tag_filter}" "${tag_exclude}" "${tag_strip_prefix}" "${tag_strip_suffix}" "${tag_extract}" \
      "${tag_replace_from}" "${tag_replace_to}")"
    # Apply stable-only filter in bash layer
    local _fl_stable=() _fl_pre=()
    local _fl_v
    while IFS= read -r _fl_v; do
      [[ -z "${_fl_v}" ]] && continue
      if _gs_eu_is_prerelease "${_fl_v}"; then
        _fl_pre+=("${_fl_v}")
      else
        _fl_stable+=("${_fl_v}")
      fi
    done <<< "${filtered_tags_fl}"

    if [[ "${stable_only}" == "true" ]]; then
      if [[ ${#_fl_pre[@]} -gt 0 ]]; then
        _gs_eu_write_alt_version "also" "$(printf '%s\n' "${_fl_pre[@]}" | sort -V | tail -1 || true)"
      fi
      if [[ ${#_fl_stable[@]} -gt 0 ]]; then
        proposed="$(printf '%s\n' "${_fl_stable[@]}" | sort -V | tail -1 || true)"
      fi
    elif [[ "${pre_release}" == "true" ]]; then
      if [[ ${#_fl_stable[@]} -gt 0 ]]; then
        _gs_eu_write_alt_version "stable" "$(printf '%s\n' "${_fl_stable[@]}" | sort -V | tail -1 || true)"
      fi
      local _fl_ch=()
      local _fl_pv
      for _fl_pv in "${_fl_pre[@]}"; do
        if _gs_eu_version_matches_channel "${_fl_pv}" "${channel}"; then
          _fl_ch+=("${_fl_pv}")
        fi
      done
      if [[ ${#_fl_ch[@]} -gt 0 ]]; then
        proposed="$(printf '%s\n' "${_fl_ch[@]}" | sort -V | tail -1 || true)"
      elif [[ ${#_fl_pre[@]} -gt 0 ]]; then
        proposed="$(printf '%s\n' "${_fl_pre[@]}" | sort -V | tail -1 || true)"
      fi
    else
      proposed="$(_gs_eu_github_select_highest_semver "${filtered_tags_fl}")"
    fi

    if [[ -n "${proposed}" ]]; then
      _gs_eu_cache_write "${cache_key}" "${proposed}"
      echo "${proposed}"
      return 0
    fi
    # No candidates after tag flags + stable filter.
    # If pre-releases were found and alt hint was written, return empty cleanly
    # so the caller can surface a PREONLY entry. Otherwise set a real error.
    if [[ ${#_fl_pre[@]} -eq 0 && ${#_fl_stable[@]} -eq 0 ]]; then
      _gs_eu_set_fetch_error "no tags matched filter '${tag_filter}' in ${identifier}"
      return 1
    fi
    # pre-only: hint was written; return empty cleanly (not an error)
    return 0
  fi

  # Try releases API first
  local releases_url="https://api.github.com/repos/${identifier}/releases?per_page=100"
  local tmp_file
  tmp_file="$(mktemp)"
  local http_code
  http_code="$(curl --silent --location --max-time 10 --retry 2 \
    "${auth_args[@]}" \
    -H "Accept: application/vnd.github+json" \
    -o "${tmp_file}" \
    -w "%{http_code}" \
    "${releases_url}" 2>/dev/null || echo "0")"
  local releases_body
  releases_body="$(cat "${tmp_file}" 2>/dev/null || true)"
  rm -f "${tmp_file}"

  if [[ "${http_code}" == "403" ]]; then
    _gs_eu_set_fetch_error "HTTP 403 — rate-limited (set GITHUB_TOKEN in .env.local)"
    return 1
  elif [[ "${http_code}" == "404" ]]; then
    _gs_eu_set_fetch_error "HTTP 404 — repo not found, verify identifier"
    return 1
  elif [[ "${http_code}" == "0" || "${http_code:0:1}" != "2" ]]; then
    _gs_eu_set_fetch_error "HTTP ${http_code} — network/server error"
    return 1
  fi

  # stable-only: find latest stable by BOTH GitHub prerelease flag AND tag name check.
  # GitHub's prerelease flag is unreliable (repo owners often skip it for RCs).
  if [[ "${stable_only}" == "true" ]]; then
    local stable_proposed="" pre_proposed=""
    local _rel_tag _rel_pre
    while IFS=$'\t' read -r _rel_tag _rel_pre; do
      [[ -z "${_rel_tag}" ]] && continue
      local _ver="${_rel_tag#v}"
      # Reject non-digit-prefixed versions (e.g. "release-0.13.8", "App-1.0.0-alpha.1")
      # which sort -V would incorrectly rank above numeric versions via ASCII ordering.
      [[ "${_ver}" =~ ^[0-9] ]] || continue
      if [[ "${_rel_pre}" == "false" ]] && ! _gs_eu_is_prerelease "${_ver}"; then
        # Collect stable candidates
        stable_proposed="${_ver}"$'\n'"${stable_proposed}"
      else
        pre_proposed="${_ver}"$'\n'"${pre_proposed}"
      fi
    done < <(printf '%s' "${releases_body}" | jq -r \
      '.[] | select(.draft == false) | [.tag_name, (.prerelease | tostring)] | @tsv' \
      2>/dev/null || true)

    # Pick highest stable via sort -V
    stable_proposed="$(printf '%s' "${stable_proposed}" | grep -v '^$' | sort -V | tail -1 || true)"
    pre_proposed="$(printf '%s' "${pre_proposed}" | grep -v '^$' | sort -V | tail -1 || true)"

    if [[ -n "${stable_proposed}" ]]; then
      # Regression guard: if current_version is itself a pre-release and the best stable
      # found is NOT newer than the pre-release base version, we're in a "forward
      # pre-release" scenario (e.g., current=1.0.0-beta.44, stable=0.2.28).
      # The stable is from a previous major cycle — fall through to
      # _gs_eu_github_select_best_release which handles mixed stable/pre correctly.
      local _curr_base="${current_version%%-*}"
      local _is_regression=false
      if _gs_eu_is_prerelease "${current_version}"; then
        local _reg_cmp
        _reg_cmp="$(_gs_eu_semver_compare "${stable_proposed}" "${_curr_base}")"
        if [[ "${_reg_cmp}" != "newer" ]]; then
          _is_regression=true
          _gs_eu_log_debug "github: stable_proposed=${stable_proposed} not newer than current base ${_curr_base} — skipping stable-only path"
        fi
      fi

      if [[ "${_is_regression}" == "false" ]]; then
        # Cross-check with tags page 1: some repos (e.g. ziglang/zig) publish tags without
        # a corresponding GitHub release. If tags have a newer strict semver, prefer it.
        local _xc_tmp
        _xc_tmp="$(mktemp)"
        local _xc_code
        _xc_code="$(curl --silent --location --max-time 10 --retry 2 \
          "${auth_args[@]}" \
          -H "Accept: application/vnd.github+json" \
          -o "${_xc_tmp}" \
          -w "%{http_code}" \
          "https://api.github.com/repos/${identifier}/tags?per_page=100" 2>/dev/null || echo "0")"
        local _xc_body
        _xc_body="$(cat "${_xc_tmp}" 2>/dev/null || true)"
        rm -f "${_xc_tmp}"

        if [[ "${_xc_code:0:1}" == "2" ]]; then
          local _xc_best
          _xc_best="$(printf '%s' "${_xc_body}" | jq -r \
            '[.[] | .name | ltrimstr("v") | select(test("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$"))]
             | sort_by(split(".") | map(tonumber? // 0)) | last // empty' \
            2>/dev/null || echo "")"
          if [[ -n "${_xc_best}" ]]; then
            local _xc_cmp
            _xc_cmp="$(_gs_eu_semver_compare "${_xc_best}" "${stable_proposed}")"
            if [[ "${_xc_cmp}" == "newer" ]]; then
              stable_proposed="${_xc_best}"
            fi
          fi
        fi

        if [[ -n "${pre_proposed}" ]]; then
          local _cmp
          _cmp="$(_gs_eu_semver_compare "${pre_proposed}" "${stable_proposed}")"
          [[ "${_cmp}" == "newer" ]] && \
            _gs_eu_write_alt_version "also" "${pre_proposed}"
        fi
        _gs_eu_cache_write "${cache_key}" "${stable_proposed}"
        echo "${stable_proposed}"
        return 0
      fi
      # _is_regression==true: fall through to _gs_eu_github_select_best_release below
    fi
  fi

  # pre-release: find latest matching channel qualifier; hint stable
  if [[ "${pre_release}" == "true" ]]; then
    local pre_proposed="" stable_rel=""
    local _rel_tag _rel_pre
    while IFS=$'\t' read -r _rel_tag _rel_pre; do
      [[ -z "${_rel_tag}" ]] && continue
      local _ver="${_rel_tag#v}"
      [[ "${_ver}" =~ ^[0-9] ]] || continue
      if [[ "${_rel_pre}" == "false" ]] && ! _gs_eu_is_prerelease "${_ver}"; then
        stable_rel="${_ver}"$'\n'"${stable_rel}"
      elif _gs_eu_version_matches_channel "${_ver}" "${channel}"; then
        pre_proposed="${_ver}"$'\n'"${pre_proposed}"
      fi
    done < <(printf '%s' "${releases_body}" | jq -r \
      '.[] | select(.draft == false) | [.tag_name, (.prerelease | tostring)] | @tsv' \
      2>/dev/null || true)

    pre_proposed="$(printf '%s' "${pre_proposed}" | grep -v '^$' | sort -V | tail -1 || true)"
    stable_rel="$(printf '%s' "${stable_rel}" | grep -v '^$' | sort -V | tail -1 || true)"

    if [[ -n "${pre_proposed}" ]]; then
      [[ -n "${stable_rel}" ]] && _gs_eu_write_alt_version "stable" "${stable_rel}"
      _gs_eu_cache_write "${cache_key}" "${pre_proposed}"
      echo "${pre_proposed}"
      return 0
    elif [[ -n "${stable_rel}" ]]; then
      # No pre-release found matching channel, fall back to stable
      _gs_eu_cache_write "${cache_key}" "${stable_rel}"
      echo "${stable_rel}"
      return 0
    fi
  fi

  proposed="$(_gs_eu_github_select_best_release "${releases_body}" "${current_version}")"
  if [[ -n "${proposed}" ]]; then
    _gs_eu_cache_write "${cache_key}" "${proposed}"
    echo "${proposed}"
    return 0
  fi

  # Fall back to tags API
  local tags_url="https://api.github.com/repos/${identifier}/tags?per_page=50"
  tmp_file="$(mktemp)"
  http_code="$(curl --silent --location --max-time 10 --retry 2 \
    "${auth_args[@]}" \
    -H "Accept: application/vnd.github+json" \
    -o "${tmp_file}" \
    -w "%{http_code}" \
    "${tags_url}" 2>/dev/null || echo "0")"
  local tags_body
  tags_body="$(cat "${tmp_file}" 2>/dev/null || true)"
  rm -f "${tmp_file}"

  if [[ "${http_code}" == "403" ]]; then
    _gs_eu_set_fetch_error "HTTP 403 — rate-limited (set GITHUB_TOKEN in .env.local)"
    return 1
  elif [[ "${http_code}" == "404" ]]; then
    _gs_eu_set_fetch_error "HTTP 404 — repo not found, verify identifier"
    return 1
  elif [[ "${http_code}" == "0" || "${http_code:0:1}" != "2" ]]; then
    _gs_eu_set_fetch_error "HTTP ${http_code} — network/server error"
    return 1
  fi

  # stable-only from tags
  if [[ "${stable_only}" == "true" ]]; then
    local stable_tag pre_tag
    stable_tag="$(printf '%s' "${tags_body}" | jq -r \
      '[.[] | .name | select(test("^v?[0-9]+\\.[0-9]+(\\.[0-9]+)?$")) | ltrimstr("v")]
       | sort_by(split(".") | map(tonumber? // 0))
       | last // empty' \
      2>/dev/null || echo "")"
    pre_tag="$(printf '%s' "${tags_body}" | jq -r \
      '[.[] | .name | select(test("^v?[0-9]+\\.[0-9]")) | ltrimstr("v")]
       | sort_by(split(".") | map(tonumber? // 0))
       | last // empty' \
      2>/dev/null || echo "")"
    if [[ -n "${stable_tag}" ]]; then
      if [[ -n "${pre_tag}" && "${pre_tag}" != "${stable_tag}" ]]; then
        _gs_eu_write_alt_version "also" "${pre_tag}"
      fi
      _gs_eu_cache_write "${cache_key}" "${stable_tag}"
      echo "${stable_tag}"
      return 0
    fi
  fi

  # Strict tag filter
  proposed="$(_gs_eu_github_select_best_tag_strict "${tags_body}" "${current_version}")"
  if [[ -n "${proposed}" ]]; then
    _gs_eu_cache_write "${cache_key}" "${proposed}"
    echo "${proposed}"
    return 0
  fi

  # Loose tag filter fallback
  proposed="$(_gs_eu_github_select_best_tag "${tags_body}" "${current_version}")"
  if [[ -n "${proposed}" ]]; then
    _gs_eu_set_fetch_error "no releases/tags matched version filter"
    _gs_eu_cache_write "${cache_key}" "${proposed}"
    echo "${proposed}"
    return 0
  fi

  _gs_eu_set_fetch_error "no releases/tags matched version filter"
  return 1
}

# Select best release from GitHub releases API JSON.
# Uses bash sort -V instead of jq sort_by to correctly handle semver pre-release ordering
# (e.g. "1.0.0-alpha.47" < "1.0.0-beta.44" — jq's tonumber? maps both suffixes to 0).
_gs_eu_github_select_best_release() {
  local releases_json="${1}"
  local current_version="${2}"

  local is_pre=false
  if [[ "${current_version,,}" =~ (alpha|beta|rc[0-9]*|preview) ]]; then
    is_pre=true
  fi

  # Extract all non-draft release tag names, strip v-prefix, reject non-digit-prefixed
  local stable_versions=() pre_versions=()
  local _tag
  while IFS= read -r _tag; do
    [[ -z "${_tag}" ]] && continue
    local _ver="${_tag#v}"
    [[ "${_ver}" =~ ^[0-9] ]] || continue
    if _gs_eu_is_prerelease "${_ver}"; then
      pre_versions+=("${_ver}")
    else
      stable_versions+=("${_ver}")
    fi
  done < <(printf '%s' "${releases_json}" | jq -r \
    '.[] | select(.draft == false) | .tag_name' 2>/dev/null || true)

  # Prefer stable unless current is pre-release
  if [[ "${is_pre}" == "false" && ${#stable_versions[@]} -gt 0 ]]; then
    printf '%s\n' "${stable_versions[@]}" | sort -V | tail -1
    return 0
  fi

  # Include pre-releases: combine all candidates and pick highest
  local all_versions=()
  [[ ${#stable_versions[@]} -gt 0 ]] && all_versions+=("${stable_versions[@]}")
  [[ ${#pre_versions[@]} -gt 0 ]]    && all_versions+=("${pre_versions[@]}")
  if [[ ${#all_versions[@]} -gt 0 ]]; then
    printf '%s\n' "${all_versions[@]}" | sort -V | tail -1
    return 0
  fi

  return 1
}

# Select best tag from GitHub tags API JSON — strict semver filter
_gs_eu_github_select_best_tag_strict() {
  local tags_json="${1}"
  local current_version="${2}"

  local is_pre=false
  if [[ "${current_version,,}" =~ (alpha|beta|rc[0-9]*|preview|-nightly) ]]; then
    is_pre=true
  fi

  # Detect Ruby-style underscore tags (e.g. v3_4_3)
  local has_underscore_tags
  has_underscore_tags="$(printf '%s' "${tags_json}" | jq -r \
    '[.[] | .name | select(test("^v[0-9]+_[0-9]"))] | length' 2>/dev/null || echo "0")"

  if [[ "${has_underscore_tags}" -gt 0 ]]; then
    # Convert underscore tags to dot form for comparison; only stable (no alpha/beta/rc in name)
    local proposed
    proposed="$(printf '%s' "${tags_json}" | jq -r \
      '[.[] | .name
        | select(test("^v[0-9]+_[0-9]+_[0-9]+$"))
        | gsub("_"; ".") | ltrimstr("v")]
       | sort_by(split(".") | map(tonumber? // 0))
       | last // empty' \
      2>/dev/null || echo "")"
    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
  fi

  if [[ "${is_pre}" == "false" ]]; then
    local proposed
    proposed="$(printf '%s' "${tags_json}" | jq -r \
      '[.[] | .name | select(test("^v?[0-9]+\\.[0-9]+(\\.[0-9]+)?$"))]
       | sort_by(ltrimstr("v") | split(".") | map(tonumber? // 0))
       | last // empty' \
      2>/dev/null || echo "")"
    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
  fi

  return 1
}

# Select best tag from GitHub tags API JSON
_gs_eu_github_select_best_tag() {
  local tags_json="${1}"
  local current_version="${2}"

  local is_pre=false
  if [[ "${current_version,,}" =~ (alpha|beta|rc[0-9]*|preview|-nightly) ]]; then
    is_pre=true
  fi

  # For node nightly, we need special handling
  if [[ "${current_version}" =~ nightly ]]; then
    # Get latest nightly tag
    local proposed
    proposed="$(printf '%s' "${tags_json}" | jq -r \
      '[.[] | select(.name | test("nightly")) | .name]
       | sort_by(split(".") | map(tonumber? // 0))
       | last // empty' \
      2>/dev/null || echo "")"
    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
  fi

  # For go tags: golang/go uses "go1.26.1" format
  if [[ "${current_version}" =~ ^[0-9]+\.[0-9]+ ]] || [[ "${current_version}" =~ ^go[0-9]+ ]]; then
    local proposed
    proposed="$(printf '%s' "${tags_json}" | jq -r \
      '[.[] | .name | select(test("^(v|go)?[0-9]+\\.[0-9]"))]
       | sort_by(ltrimstr("v") | ltrimstr("go") | split(".") | map(tonumber? // 0))
       | last // empty' \
      2>/dev/null || echo "")"
    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
  fi

  if [[ "${is_pre}" == "false" ]]; then
    local proposed
    proposed="$(printf '%s' "${tags_json}" | jq -r \
      '[.[] | .name | select(test("^v?[0-9]+\\.[0-9]+(\\.[0-9]+)?$"))]
       | sort_by(ltrimstr("v") | split(".") | map(tonumber? // 0))
       | last // empty' \
      2>/dev/null || echo "")"
    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
  fi

  local proposed
  proposed="$(printf '%s' "${tags_json}" | jq -r \
    '[.[] | .name | select(test("^v?[0-9]+\\.[0-9]"))]
     | sort_by(ltrimstr("v") | split(".") | map(tonumber? // 0))
     | last // empty' \
    2>/dev/null || echo "")"
  echo "${proposed}"
}

# Fetch the latest commit SHA from a GitHub repo branch
# Usage: _gs_eu_github_fetch_latest_sha "Imagick/imagick" "master"
_gs_eu_github_fetch_latest_sha() {
  local identifier="${1}"   # "owner/repo"
  local branch="${2:-master}"

  local auth_args=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth_args=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  local url="https://api.github.com/repos/${identifier}/commits/${branch}"
  local response
  if response="$(curl --silent --location --fail --max-time 10 --retry 2 \
    "${auth_args[@]}" \
    -H "Accept: application/vnd.github+json" \
    "${url}" 2>/dev/null)"; then
    printf '%s' "${response}" | jq -r '.sha // empty' 2>/dev/null || echo ""
  fi
}

# Fetch commit date for a given SHA
# Usage: _gs_eu_github_fetch_commit_date "Imagick/imagick" "abc123def"
# Returns: YYYY-MM-DD string or empty
_gs_eu_github_fetch_commit_date() {
  local identifier="${1}"   # "owner/repo"
  local sha="${2}"

  local auth_args=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    auth_args=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi

  local url="https://api.github.com/repos/${identifier}/commits/${sha}"
  local response
  if response="$(curl --silent --location --fail --max-time 10 --retry 2 \
    "${auth_args[@]}" \
    -H "Accept: application/vnd.github+json" \
    "${url}" 2>/dev/null)"; then
    printf '%s' "${response}" | jq -r '.commit.committer.date // empty' 2>/dev/null | cut -c1-10 || echo ""
  fi
}
