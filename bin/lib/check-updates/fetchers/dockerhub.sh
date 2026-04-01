#!/bin/bash
# Docker Hub API v2 fetcher.
# Handles both official images (_/image) and user images (namespace/image).

set -eEuo pipefail

# Fetch all tags for a Docker Hub image, returns JSON array of tag names
# Usage: _dockerhub_fetch_tags "_" "ubuntu"
# Usage: _dockerhub_fetch_tags "axllent" "mailpit"
_dockerhub_fetch_tags() {
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
  if ! response="$(curl --silent --fail --max-time 10 --retry 2 "${url}" 2>/dev/null)"; then
    return 1
  fi

  # Extract just the tag names as a JSON array
  local tags
  tags="$(printf '%s' "${response}" | jq -r '[.results[].name]' 2>/dev/null || echo "[]")"
  echo "${tags}"
}

# Fetch the latest stable tag from Docker Hub matching a version prefix pattern.
# For images with Ubuntu codename suffixes, we handle that separately.
# Usage: _dockerhub_fetch_latest "axllent/mailpit" "v1.29.3"
# Returns: proposed version string (echoed) or empty on failure
_dockerhub_fetch_latest() {
  local identifier="${1}"    # "namespace/image" or "_/image"
  local current_version="${2}"
  local offline="${3:-false}"
  local no_cache="${4:-false}"

  local namespace="${identifier%%/*}"
  local image="${identifier##*/}"

  local cache_key="dockerhub:${identifier}"

  # Cache check
  if [[ "${offline}" != "true" && "${no_cache}" != "true" ]]; then
    local cached
    if cached="$(_cache_read "${cache_key}" 2>/dev/null)"; then
      echo "${cached}"
      return 0
    fi
  fi

  if [[ "${offline}" == "true" ]]; then
    return 1
  fi

  # Fetch tags
  local tags_json
  if ! tags_json="$(_dockerhub_fetch_tags "${namespace}" "${image}")"; then
    return 1
  fi

  # Determine version filter strategy based on current_version
  local proposed
  proposed="$(_dockerhub_select_best_tag "${tags_json}" "${current_version}")"

  if [[ -n "${proposed}" ]]; then
    _cache_write "${cache_key}" "${proposed}"
    echo "${proposed}"
  fi
}

# Select best matching tag from a JSON array of tags given the current version
_dockerhub_select_best_tag() {
  local tags_json="${1}"
  local current_version="${2}"

  # Strategy:
  # 1. If current has ubuntu codename suffix, find matching tags and return highest within same codename
  # 2. If current has alpine suffix, find matching tags
  # 3. If current has -oraclelinux suffix, find matching tags
  # 4. For simple semver, find highest matching tag

  local current_lower="${current_version,,}"

  # Check for ubuntu codename in current
  local ubuntu_codenames=(focal jammy kinetic lunar mantic noble oracular plucky questing resolute)
  local found_codename=""
  for cn in "${ubuntu_codenames[@]}"; do
    if [[ "${current_lower}" == *"${cn}"* ]]; then
      found_codename="${cn}"
      break
    fi
  done

  if [[ -n "${found_codename}" ]]; then
    # Find highest tag matching same suffix pattern
    # e.g. current "8.2.6-rc0-noble" → find latest "X.Y.Z-noble" or "X.Y.Z-rcN-noble"
    local proposed
    proposed="$(printf '%s' "${tags_json}" | jq -r \
      --arg cn "${found_codename}" \
      '[.[] | select(test($cn + "$"))] | sort | last // empty' \
      2>/dev/null || echo "")"
    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
  fi

  # Alpine suffix
  if [[ "${current_version}" =~ -alpine([0-9.]+)$ ]]; then
    local alpine_ver="${BASH_REMATCH[1]}"
    # Find highest tag matching same alpine version
    local proposed
    proposed="$(printf '%s' "${tags_json}" | jq -r \
      --arg apv "alpine${alpine_ver}" \
      '[.[] | select(test($apv + "$"))] | sort | last // empty' \
      2>/dev/null || echo "")"
    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
  fi

  # oraclelinux suffix
  if [[ "${current_version}" =~ -oraclelinux([0-9]+)$ ]]; then
    local ora_ver="${BASH_REMATCH[1]}"
    local proposed
    proposed="$(printf '%s' "${tags_json}" | jq -r \
      --arg orv "oraclelinux${ora_ver}" \
      '[.[] | select(test($orv + "$"))] | sort | last // empty' \
      2>/dev/null || echo "")"
    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
  fi

  # Simple semver: find highest pure version tag (no suffix qualifiers)
  # Filter: tag must look like semver (possibly with v prefix and rc/alpha/beta)
  # Prefer stable over pre-release if current is stable
  local is_pre=false
  if [[ "${current_version,,}" =~ (alpha|beta|rc[0-9]*|preview) ]]; then
    is_pre=true
  fi

  if [[ "${is_pre}" == "false" ]]; then
    # Prefer stable
    local proposed
    proposed="$(printf '%s' "${tags_json}" | jq -r \
      '[.[] | select(test("^v?[0-9]+\\.[0-9]+(\\.[0-9]+)?$"))] | sort | last // empty' \
      2>/dev/null || echo "")"
    [[ -n "${proposed}" ]] && echo "${proposed}" && return 0
  fi

  # Fall back: highest semver-like tag
  local proposed
  proposed="$(printf '%s' "${tags_json}" | jq -r \
    '[.[] | select(test("^v?[0-9]+\\.[0-9]"))] | sort | last // empty' \
    2>/dev/null || echo "")"
  echo "${proposed}"
}
