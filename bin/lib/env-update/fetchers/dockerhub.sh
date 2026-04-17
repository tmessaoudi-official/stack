#!/bin/bash
# Docker Hub API v2 fetcher.
# Handles both official images (_/image) and user images (namespace/image).
#
# Supports:
#   E1. (tag-suffix:VALUE) flag — filter to tags ending with -VALUE
#   E2. Major pin via identifier:MAJOR — HOLD when newer major exists
#   E3. Alpine auto-detect — filter to -alpine tags when current has -alpine
#   E4. Ubuntu codename auto-detect — same-codename comparison + upgrade hint
#   Tag flags: tag-filter, tag-exclude, tag-strip-prefix, tag-strip-suffix, tag-extract

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_EU_DOCKERHUB_SH_LOADED:-}" ]] && return 0
readonly _GS_EU_DOCKERHUB_SH_LOADED=1

# Fetch all tags for a Docker Hub image, returns JSON array of tag names
# Usage: _gs_eu_dockerhub_fetch_tags "_" "ubuntu"
# Usage: _gs_eu_dockerhub_fetch_tags "axllent" "mailpit"
_gs_eu_dockerhub_fetch_tags() {
  local namespace="${1}"
  local image="${2}"

  local api_ns
  if [[ "${namespace}" == "_" ]]; then
    api_ns="library"
  else
    api_ns="${namespace}"
  fi

  # Fetch up to 100 tags, sorted by most recent
  local url="https://hub.docker.com/v2/repositories/${api_ns}/${image}/tags?page_size=100&ordering=last_updated"

  local response
  if ! response="$(curl --silent --location --fail --max-time 10 --retry 2 "${url}" 2>/dev/null)"; then
    return 1
  fi

  # Extract just the tag names as a JSON array
  local tags
  tags="$(printf '%s' "${response}" | jq -r '[.results[].name]' 2>/dev/null || echo "[]")"
  echo "${tags}"
}

# Fetch the latest stable tag from Docker Hub matching a version prefix pattern.
# Usage: _gs_eu_dockerhub_fetch_latest "axllent/mailpit" "v1.29.3"
# Extended: _gs_eu_dockerhub_fetch_latest "identifier" "current" "offline" "no_cache" "tag_suffix" "major_pin" \
#             "tag_filter" "tag_exclude" "tag_strip_prefix" "tag_strip_suffix" "tag_extract"
# Returns: proposed version string (echoed) or empty on failure
_gs_eu_dockerhub_fetch_latest() {
  local identifier="${1}"    # "namespace/image" or "_/image"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"
  local tag_suffix="${5:-}"          # E1: filter tags ending with this suffix (e.g. "developer")
  local major_pin="${6:-}"           # E2: pin to this major version (e.g. "18")
  local tag_filter="${7:-}"          # keep only tags matching REGEX
  local tag_exclude="${8:-}"         # drop tags matching REGEX
  local tag_strip_prefix="${9:-}"    # strip literal prefix from tags before comparison
  local tag_strip_suffix="${10:-}"   # strip literal suffix from tags before comparison
  local tag_extract="${11:-}"        # extract capture group 1 from tags via perl
  local tag_replace_from="${12:-}"   # replace FROM literal in tags
  local tag_replace_to="${13:-}"     # replacement string
  local channel="${14:-}"            # channel (nightly, stable, beta)
  local version_prefix="${15:-}"     # prepend to proposed version

  # E2: parse major_pin from identifier if present (identifier:MAJOR format)
  local raw_identifier="${identifier}"
  if [[ "${identifier}" =~ ^([^:]+):([0-9]+)$ ]]; then
    raw_identifier="${BASH_REMATCH[1]}"
    major_pin="${BASH_REMATCH[2]}"
  fi

  local namespace="${raw_identifier%%/*}"
  local image="${raw_identifier##*/}"

  # Build a cache key that accounts for all discriminators
  local cache_key="dockerhub:${raw_identifier}:${tag_suffix}:${major_pin}:${tag_filter}:${tag_exclude}:${tag_extract}:${tag_replace_from}:${channel}"

  # Cache check
  if [[ "${offline}" != "true" && "${no_cache}" != "true" ]]; then
    local cached
    if cached="$(_gs_eu_cache_read "${cache_key}" 2>/dev/null)"; then
      echo "${cached}"
      return 0
    fi
  fi

  if [[ "${offline}" == "true" ]]; then
    return 1
  fi

  # Fetch tags
  local tags_json
  if ! tags_json="$(_gs_eu_dockerhub_fetch_tags "${namespace}" "${image}")"; then
    _gs_eu_set_fetch_error "dockerhub: failed to fetch tags for ${raw_identifier}"
    return 1
  fi

  # Determine version filter strategy based on current_version
  local proposed
  proposed="$(_gs_eu_dockerhub_select_best_tag "${tags_json}" "${current_version}" \
    "${tag_suffix}" "${major_pin}" "${raw_identifier}" \
    "${tag_filter}" "${tag_exclude}" "${tag_strip_prefix}" "${tag_strip_suffix}" "${tag_extract}" \
    "${tag_replace_from}" "${tag_replace_to}" "${channel}")"

  if [[ -n "${proposed}" ]]; then
    # Apply version_prefix if set
    if [[ -n "${version_prefix}" ]]; then
      proposed="${version_prefix}${proposed}"
    fi
    _gs_eu_cache_write "${cache_key}" "${proposed}"
    echo "${proposed}"
  fi
}

# Select best matching tag from a JSON array of tags given the current version
# Args: tags_json current_version [tag_suffix] [major_pin] [identifier]
#       [tag_filter] [tag_exclude] [tag_strip_prefix] [tag_strip_suffix] [tag_extract]
#       [tag_replace_from] [tag_replace_to] [channel]
_gs_eu_dockerhub_select_best_tag() {
  local tags_json="${1}"
  local current_version="${2}"
  local tag_suffix="${3:-}"
  local major_pin="${4:-}"
  local identifier="${5:-}"
  local tag_filter="${6:-}"
  local tag_exclude="${7:-}"
  local tag_strip_prefix="${8:-}"
  local tag_strip_suffix="${9:-}"
  local tag_extract="${10:-}"
  local tag_replace_from="${11:-}"
  local tag_replace_to="${12:-}"
  local channel="${13:-}"

  local current_lower="${current_version,,}"
  local is_stable_mode=true
  if [[ -n "${channel}" && "${channel}" != "stable" ]]; then
    is_stable_mode=false
  fi

  # ------------------------------------------------------------------
  # Tag flags: tag-filter, tag-exclude, tag-strip-prefix, tag-strip-suffix, tag-extract, tag-replace
  # When any of these are set, apply them and return the highest result.
  # ------------------------------------------------------------------
  local _has_tag_flags=false
  if [[ -n "${tag_filter}${tag_exclude}${tag_strip_prefix}${tag_strip_suffix}${tag_extract}${tag_replace_from}" ]]; then
    _has_tag_flags=true
  fi

  if [[ "${_has_tag_flags}" == "true" ]]; then
    local all_tag_names
    all_tag_names="$(printf '%s' "${tags_json}" | jq -r '.[]' 2>/dev/null || echo "")"
    local filtered_tags
    filtered_tags="$(printf '%s\n' "${all_tag_names}" | _gs_eu_apply_tag_flags \
      "${tag_filter}" "${tag_exclude}" "${tag_strip_prefix}" "${tag_strip_suffix}" "${tag_extract}" \
      "${tag_replace_from}" "${tag_replace_to}")"

    local proposed
    proposed="$(_gs_eu_channel_select_best "${filtered_tags}" "${channel}")"
    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
    return 0
  fi

  # ------------------------------------------------------------------
  # E1. tag_suffix filter — restrict to tags ending with -SUFFIX
  # Bug fix: extract semver prefix (before -SUFFIX), sort by it, return full tag
  # ------------------------------------------------------------------
  if [[ -n "${tag_suffix}" ]]; then
    local sfx_pattern="-${tag_suffix}"

    if [[ "${is_stable_mode}" == "true" ]]; then
      # Filter tags with suffix, then exclude pre-release ones
      local proposed
      proposed="$(printf '%s' "${tags_json}" | jq -r \
        --arg sfx "${sfx_pattern}" \
        '[.[] | select(endswith($sfx)) | select(test("alpha|beta|rc[0-9]|preview"; "i") | not)]
         | sort_by(
             ltrimstr("v") |
             split("-") | first |
             split(".") | map(tonumber? // 0)
           )
         | last // empty' \
        2>/dev/null || echo "")"

      # Find highest pre-release with same suffix for alt hint
      if [[ -n "${proposed}" ]]; then
        local highest_pre_sfx
        highest_pre_sfx="$(printf '%s' "${tags_json}" | jq -r \
          --arg sfx "${sfx_pattern}" \
          '[.[] | select(endswith($sfx)) | select(test("alpha|beta|rc[0-9]|preview"; "i"))]
           | sort_by(
               ltrimstr("v") |
               split("-") | first |
               split(".") | map(tonumber? // 0)
             )
           | last // empty' \
          2>/dev/null || echo "")"
        [[ -n "${highest_pre_sfx}" ]] && _gs_eu_write_alt_version "also" "${highest_pre_sfx}"
      fi

      [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
      return 0
    else
      # Channel mode with suffix
      local proposed
      proposed="$(printf '%s' "${tags_json}" | jq -r \
        --arg sfx "${sfx_pattern}" \
        '[.[] | select(endswith($sfx))]
         | sort_by(
             ltrimstr("v") |
             split("-") | first |
             split(".") | map(tonumber? // 0)
           )
         | last // empty' \
        2>/dev/null || echo "")"
      [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
      return 0
    fi
  fi

  # ------------------------------------------------------------------
  # E3. Alpine auto-detect — if current has -alpine, filter to alpine tags
  # Fix: only consider tags with -alpineN.NN (with version number), not bare -alpine
  # ------------------------------------------------------------------
  if [[ "${current_version}" =~ -alpine[0-9] ]]; then
    local alpine_ver=""
    [[ "${current_version}" =~ -alpine([0-9.]+)$ ]] && alpine_ver="${BASH_REMATCH[1]}"

    # Apply major pin if set
    if [[ -n "${major_pin}" ]]; then
      local proposed
      # Only include alpine tags with a version number (-alpine3.NN), not bare -alpine
      # In stable mode, exclude pre-release tags
      local pre_filter=""
      if [[ "${is_stable_mode}" == "true" ]]; then
        pre_filter=' | select(test("alpha|beta|rc[0-9]|preview"; "i") | not)'
      fi
      proposed="$(printf '%s' "${tags_json}" | jq -r \
        --arg maj "${major_pin}." \
        --arg pf "${pre_filter}" \
        "[.[] | select(test(\"-alpine[0-9]+\\\\.[0-9]+\")) | select(startswith(\$maj))${pre_filter}]
         | sort_by(ltrimstr(\"v\") | split(\"-\") | first | split(\".\") | map(tonumber? // 0))
         | last // empty" \
        2>/dev/null || echo "")"
      # Check if a newer major exists (HOLD)
      local max_maj
      max_maj="$(printf '%s' "${tags_json}" | jq -r \
        '[.[] | select(test("-alpine[0-9]+\\.[0-9]+")) | split(".")[0] | tonumber? // 0] | max // 0' \
        2>/dev/null || echo "0")"
      if [[ -n "${proposed}" && "${max_maj}" -gt "${major_pin}" ]] 2>/dev/null; then
        # Signal HOLD via special prefix — caller must handle
        echo "__hold_newer_major__:${major_pin}:${max_maj}:${proposed}"
        return 0
      fi
      [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
    fi

    # Same alpine version suffix filter — require versioned alpine (not bare -alpine)
    if [[ -n "${alpine_ver}" ]]; then
      local proposed
      proposed="$(printf '%s' "${tags_json}" | jq -r \
        --arg apv "alpine${alpine_ver}" \
        '[.[] | select(test($apv + "$"))]
         | sort_by(ltrimstr("v") | split("-") | first | split(".") | map(tonumber? // 0))
         | last // empty' \
        2>/dev/null || echo "")"
      [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
    fi

    # Any versioned alpine tag (with version number — exclude bare -alpine)
    # In stable mode, filter out pre-release tags
    local proposed
    if [[ "${is_stable_mode}" == "true" ]]; then
      proposed="$(printf '%s' "${tags_json}" | jq -r \
        '[.[] | select(test("-alpine[0-9]+\\.[0-9]+")) | select(test("alpha|beta|rc[0-9]|preview"; "i") | not)]
         | sort_by(ltrimstr("v") | split("-") | first | split(".") | map(tonumber? // 0))
         | last // empty' \
        2>/dev/null || echo "")"
    else
      proposed="$(printf '%s' "${tags_json}" | jq -r \
        '[.[] | select(test("-alpine[0-9]+\\.[0-9]+"))]
         | sort_by(ltrimstr("v") | split("-") | first | split(".") | map(tonumber? // 0))
         | last // empty' \
        2>/dev/null || echo "")"
    fi
    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
    return 0
  fi

  # ------------------------------------------------------------------
  # E4. Ubuntu codename auto-detect
  # ------------------------------------------------------------------
  local ubuntu_codenames=(focal jammy kinetic lunar mantic noble oracular plucky questing resolute)
  local found_codename=""
  local cn
  for cn in "${ubuntu_codenames[@]}"; do
    if [[ "${current_lower}" == *"${cn}"* ]]; then
      found_codename="${cn}"
      break
    fi
  done

  if [[ -n "${found_codename}" ]]; then
    # Apply major pin if set
    if [[ -n "${major_pin}" ]]; then
      local proposed
      proposed="$(printf '%s' "${tags_json}" | jq -r \
        --arg cn "${found_codename}" \
        --arg maj "${major_pin}." \
        '[.[] | select(test($cn)) | select(startswith($maj))]
         | sort_by(ltrimstr("v") | split("-") | first | split(".") | map(tonumber? // 0))
         | last // empty' \
        2>/dev/null || echo "")"
      [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
    fi

    # Find highest tag matching same codename suffix
    local proposed
    proposed="$(printf '%s' "${tags_json}" | jq -r \
      --arg cn "${found_codename}" \
      '[.[] | select(test($cn))]
       | sort_by(ltrimstr("v") | split("-") | first | split(".") | map(tonumber? // 0))
       | last // empty' \
      2>/dev/null || echo "")"

    # Check if the base Ubuntu codename for this stack has a tag available for a newer app version
    local base_codename="${_GS_EU_UBUNTU_CODENAME:-}"
    if [[ -n "${base_codename}" && "${base_codename}" != "${found_codename}" && -n "${proposed}" ]]; then
      # Numeric part of proposed (strip codename)
      local prop_num="${proposed//-${found_codename}/}"
      prop_num="${prop_num//${found_codename}-/}"
      # Look for the same version with the newer codename
      local codename_upgrade_tag
      codename_upgrade_tag="$(printf '%s' "${tags_json}" | jq -r \
        --arg cn "${base_codename}" \
        --arg ver "${prop_num}-" \
        '[.[] | select(test($cn)) | select(startswith($ver))] | first // empty' \
        2>/dev/null || echo "")"
      if [[ -n "${codename_upgrade_tag}" ]]; then
        # Annotate the result with the codename upgrade info
        echo "__codename_upgrade_hint__:${codename_upgrade_tag}:${proposed}"
        return 0
      fi
    fi

    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
  fi

  # ------------------------------------------------------------------
  # E2. Major pin without suffix qualifiers
  # ------------------------------------------------------------------
  if [[ -n "${major_pin}" ]]; then
    local proposed
    proposed="$(printf '%s' "${tags_json}" | jq -r \
      --arg maj "${major_pin}." \
      '[.[] | select(startswith($maj))
        | select(test("^[0-9]+\\.[0-9]") and (test("alpha|beta|rc|nightly|latest") | not))]
       | sort_by(split(".") | map(tonumber? // 0))
       | last // empty' \
      2>/dev/null || echo "")"

    # Check if a newer major exists → signal HOLD
    local max_maj
    max_maj="$(printf '%s' "${tags_json}" | jq -r \
      '[.[] | select(test("^[0-9]+\\.[0-9]") and (test("alpha|beta|rc|nightly|latest|-") | not))
        | split(".")[0] | tonumber? // 0]
       | if length > 0 then max else 0 end' \
      2>/dev/null || echo "0")"
    if [[ -n "${proposed}" && -n "${max_maj}" ]] && \
       [[ "${max_maj}" -gt "${major_pin}" ]] 2>/dev/null; then
      echo "__hold_newer_major__:${major_pin}:${max_maj}:${proposed}"
      return 0
    fi

    # Write alt hint: scan for pre-release tags under same major for stable mode
    if [[ -n "${proposed}" && "${is_stable_mode}" == "true" ]]; then
      local highest_pre_major
      highest_pre_major="$(printf '%s' "${tags_json}" | jq -r \
        --arg maj "${major_pin}." \
        '[.[] | select(startswith($maj))
          | select(test("alpha|beta|rc"; "i"))]
         | sort_by(split(".") | map(tonumber? // 0))
         | last // empty' \
        2>/dev/null || echo "")"
      [[ -n "${highest_pre_major}" ]] && _gs_eu_write_alt_version "also" "${highest_pre_major}"
    fi

    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
    return 0
  fi

  # oraclelinux suffix
  if [[ "${current_version}" =~ -oraclelinux([0-9]+)$ ]]; then
    local ora_ver="${BASH_REMATCH[1]}"
    local proposed
    proposed="$(printf '%s' "${tags_json}" | jq -r \
      --arg orv "oraclelinux${ora_ver}" \
      '[.[] | select(test($orv + "$"))]
       | sort_by(ltrimstr("v") | split("-") | first | split(".") | map(tonumber? // 0))
       | last // empty' \
      2>/dev/null || echo "")"
    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
  fi

  # ------------------------------------------------------------------
  # Simple semver fallback: collect all semver-like tags, delegate to channel selector
  # ------------------------------------------------------------------
  # Try strict semver first (X.Y.Z only) for a clean stable result
  local strict_semver_tags
  strict_semver_tags="$(printf '%s' "${tags_json}" | jq -r \
    '[.[] | select(test("^v?[0-9]+\\.[0-9]+(\\.[0-9]+)?$")) | ltrimstr("v")] | .[]' \
    2>/dev/null || echo "")"

  local proposed=""
  if [[ -n "${strict_semver_tags}" ]]; then
    proposed="$(_gs_eu_channel_select_best "${strict_semver_tags}" "${channel}")"
  fi

  if [[ -z "${proposed}" ]]; then
    # Broader fallback: any semver-like tag
    local all_semver_tags
    all_semver_tags="$(printf '%s' "${tags_json}" | jq -r \
      '[.[] | select(test("^v?[0-9]+\\.[0-9]")) | ltrimstr("v")] | .[]' \
      2>/dev/null || echo "")"
    proposed="$(_gs_eu_channel_select_best "${all_semver_tags}" "${channel}")"
  fi

  echo "${proposed}"
}
