#!/bin/bash
# Channel selection engine — shared by all fetchers.
# Provides version-channel matching and the canonical stable/unstable selection algorithm.
#
# Depends on: diff.sh (_gs_eu_is_prerelease, _gs_eu_semver_compare)
#             env-update.sh (_gs_eu_write_alt_version) — available at call time

set -eEuo pipefail

[[ -n "${_GS_EU_CHANNEL_SH_LOADED:-}" ]] && return 0
readonly _GS_EU_CHANNEL_SH_LOADED=1

# Check if a version string matches a specific channel qualifier.
#
# A qualifier like "rc" should match all of these forms:
#   1.0.0-rc    1.0.0rc    1.0.0-rc2    1.0.0rc2    1.0.0-rc.2    1.0.0.rc2
#
# Strategy: the qualifier keyword must appear as a word-boundary-like token
# in the version string (case-insensitive). We look for the keyword optionally
# preceded by a separator (-, ., nothing) and optionally followed by digits,
# dots, or another separator. This avoids false positives (e.g. "secret"
# matching "rc") while handling all real-world pre-release formats.
#
# channel:unstable   → any pre-release (delegates to _gs_eu_is_prerelease)
# channel:rc         → rc, rc2, rc.2, -rc2, .rc, etc.
# channel:beta       → beta, beta1, beta.1, -beta2, etc.
# channel:alpha      → alpha, alpha1, alpha.1, -alpha2, etc.
# channel:preview    → preview, preview1, preview.1, -preview2, etc.
# channel:rc,beta    → rc OR beta (comma-separated = OR logic)
# Returns 0 if version matches, 1 if not.
_gs_eu_version_matches_channel() {
  local version="${1}"
  local channel="${2}"
  local lower="${version,,}"

  if [[ "${channel}" == "unstable" ]]; then
    _gs_eu_is_prerelease "${version}"
    return
  fi

  # Build a regex that matches the qualifier keyword as a distinct token:
  #   (^|[-._[:digit:]])KEYWORD([0-9._-]|$)
  # This means: at start-of-string or after a separator or digit, the keyword,
  # then digits/separators or end-of-string. Handles:
  #   rc, -rc, .rc, rc2, -rc2, rc.2, rc-2, 1.0.0rc (keyword at end after digit run)
  # For the last case (e.g. "1.0.0rc") the preceding char is a digit, not a
  # separator — so we also allow a digit before the keyword:
  #   (^|[-._[:digit:]])KEYWORD([[:digit:]._-]|$)
  local qualifier
  local IFS=','
  for qualifier in ${channel}; do
    qualifier="${qualifier,,}"
    # Pattern: optional separator/digit before keyword, keyword itself,
    # then optional digits/separator/end after.
    local pattern="(^|[-._[:digit:]])${qualifier}([[:digit:]._-]|$)"
    if [[ "${lower}" =~ ${pattern} ]]; then
      return 0
    fi
  done
  return 1
}

# Filter a newline-separated list of version strings by channel qualifier.
# Uses _gs_eu_version_matches_channel to keep only versions that match.
# When channel is empty or "nightly", returns all versions unchanged.
# Usage: _gs_eu_filter_versions_by_channel "${versions_text}" "${channel}"
_gs_eu_filter_versions_by_channel() {
  local versions_text="${1}"
  local channel="${2:-}"

  # Empty or nightly channel: no filtering
  if [[ -z "${channel}" || "${channel}" == "nightly" ]]; then
    printf '%s\n' "${versions_text}"
    return 0
  fi

  local version
  while IFS= read -r version; do
    [[ -z "${version}" ]] && continue
    if _gs_eu_version_matches_channel "${version}" "${channel}"; then
      printf '%s\n' "${version}"
    fi
  done <<< "${versions_text}"
}

# Canonical stable/unstable/channel selection algorithm.
# Centralizes ALL stable/unstable/channel selection logic.
#
# Usage: _gs_eu_channel_select_best "${all_versions}" "${channel}"
#
# Inputs:
#   $1 — all_versions: newline-separated list of version strings
#         (may include both stable and pre-release)
#   $2 — channel: value from annotation (empty/"stable", "unstable", "rc", "beta", etc.)
#
# Output:
#   echoes the selected version (or empty string if nothing found)
#
# Side effects:
#   Calls _gs_eu_write_alt_version "also" VERSION  — when stable selected, hint at newer pre-release
#   Calls _gs_eu_write_alt_version "stable" VERSION — when channel selected, hint at stable
_gs_eu_channel_select_best() {
  local all_versions="${1}"
  local channel="${2:-}"

  # Empty input → nothing to do
  if [[ -z "${all_versions}" ]]; then
    return 0
  fi

  # Step 1: Split into stable and pre-release lists
  local stable_versions=()
  local pre_versions=()
  local ver
  while IFS= read -r ver; do
    [[ -z "${ver}" ]] && continue
    # Reject non-digit-prefixed versions (e.g. "release-0.13.8") — sort -V ranks
    # these incorrectly above numeric versions via ASCII ordering.
    [[ "${ver}" =~ ^[0-9] ]] || continue
    if _gs_eu_is_prerelease "${ver}"; then
      pre_versions+=("${ver}")
    else
      stable_versions+=("${ver}")
    fi
  done <<< "${all_versions}"

  # Step 2: Sort both via sort -V, get highest of each
  local highest_stable=""
  local highest_pre=""

  if [[ ${#stable_versions[@]} -gt 0 ]]; then
    highest_stable="$(printf '%s\n' "${stable_versions[@]}" | sort -V | tail -1)" || true
  fi
  if [[ ${#pre_versions[@]} -gt 0 ]]; then
    highest_pre="$(printf '%s\n' "${pre_versions[@]}" | sort -V | tail -1)" || true
  fi

  # Step 3: If channel is empty or "stable"
  if [[ -z "${channel}" || "${channel}" == "stable" ]]; then
    local proposed="${highest_stable}"
    # Fall back to highest pre if no stable exists
    if [[ -z "${proposed}" ]]; then
      proposed="${highest_pre}"
    fi
    if [[ -z "${proposed}" ]]; then
      return 0
    fi
    # If any pre > proposed → write_alt_version "also" highest_pre
    if [[ -n "${highest_pre}" && -n "${highest_stable}" ]]; then
      if [[ "$(_gs_eu_semver_compare "${highest_pre}" "${proposed}")" == "newer" ]]; then
        _gs_eu_write_alt_version "also" "${highest_pre}"
      fi
    fi
    echo "${proposed}"
    return 0
  fi

  # Step 4 & 5: channel-specific selection
  local channel_match=""

  if [[ "${channel}" == "unstable" ]]; then
    # highest pre (any prerelease)
    channel_match="${highest_pre}"
  else
    # Specific channel like "rc", "beta", comma-separated
    local filtered
    filtered="$(_gs_eu_filter_versions_by_channel "${all_versions}" "${channel}")"
    if [[ -n "${filtered}" ]]; then
      channel_match="$(printf '%s\n' "${filtered}" | sort -V | tail -1)" || true
    fi
    # Fallback: if no channel_match found but pre_versions exist, use highest pre
    if [[ -z "${channel_match}" && -n "${highest_pre}" ]]; then
      channel_match="${highest_pre}"
    fi
  fi

  # No channel match and no stable → nothing
  if [[ -z "${channel_match}" && -z "${highest_stable}" ]]; then
    return 0
  fi

  # If channel_match is empty but stable exists, fall through to promotion check
  if [[ -z "${channel_match}" ]]; then
    echo "${highest_stable}"
    return 0
  fi

  # Step 6 & 7: PROMOTION check
  if [[ -n "${highest_stable}" ]]; then
    local cmp
    cmp="$(_gs_eu_semver_compare "${highest_stable}" "${channel_match}")"
    if [[ "${cmp}" == "newer" ]]; then
      # Stable has surpassed the tracked pre-release — promote
      echo "${highest_stable}"
      # do NOT write any alt-version hint (pre-release is obsolete)
      return 0
    fi
  fi

  # Step 8: echo channel_match + hint toward stable
  echo "${channel_match}"
  if [[ -n "${highest_stable}" ]]; then
    _gs_eu_write_alt_version "stable" "${highest_stable}"
  fi
  return 0
}

# Variant of _gs_eu_channel_select_best for fetchers that already split
# versions into stable/pre-release before selection.
#
# Usage: _gs_eu_channel_select_best_split "${stable_versions}" "${pre_versions}" "${channel}"
#
# Inputs:
#   $1 — stable_versions: newline-separated list of stable version strings
#   $2 — pre_versions: newline-separated list of pre-release version strings
#   $3 — channel: value from annotation
#
# Output/Side effects: same as _gs_eu_channel_select_best
_gs_eu_channel_select_best_split() {
  local stable_versions_text="${1}"
  local pre_versions_text="${2}"
  local channel="${3:-}"

  # Get highest stable and pre
  local highest_stable=""
  local highest_pre=""

  if [[ -n "${stable_versions_text}" ]]; then
    highest_stable="$(printf '%s\n' "${stable_versions_text}" | grep -v '^$' | sort -V | tail -1)" || true
  fi
  if [[ -n "${pre_versions_text}" ]]; then
    highest_pre="$(printf '%s\n' "${pre_versions_text}" | grep -v '^$' | sort -V | tail -1)" || true
  fi

  # Nothing at all
  if [[ -z "${highest_stable}" && -z "${highest_pre}" ]]; then
    return 0
  fi

  # Step 3: stable/default channel
  if [[ -z "${channel}" || "${channel}" == "stable" ]]; then
    local proposed="${highest_stable}"
    if [[ -z "${proposed}" ]]; then
      proposed="${highest_pre}"
    fi
    if [[ -z "${proposed}" ]]; then
      return 0
    fi
    if [[ -n "${highest_pre}" && -n "${highest_stable}" ]]; then
      if [[ "$(_gs_eu_semver_compare "${highest_pre}" "${proposed}")" == "newer" ]]; then
        _gs_eu_write_alt_version "also" "${highest_pre}"
      fi
    fi
    echo "${proposed}"
    return 0
  fi

  # Step 4 & 5: channel-specific selection
  local channel_match=""

  if [[ "${channel}" == "unstable" ]]; then
    channel_match="${highest_pre}"
  else
    # Filter from combined list
    local all_versions=""
    if [[ -n "${stable_versions_text}" && -n "${pre_versions_text}" ]]; then
      all_versions="${stable_versions_text}"$'\n'"${pre_versions_text}"
    elif [[ -n "${stable_versions_text}" ]]; then
      all_versions="${stable_versions_text}"
    else
      all_versions="${pre_versions_text}"
    fi
    local filtered
    filtered="$(_gs_eu_filter_versions_by_channel "${all_versions}" "${channel}")"
    if [[ -n "${filtered}" ]]; then
      channel_match="$(printf '%s\n' "${filtered}" | grep -v '^$' | sort -V | tail -1)" || true
    fi
    # Fallback to highest pre
    if [[ -z "${channel_match}" && -n "${highest_pre}" ]]; then
      channel_match="${highest_pre}"
    fi
  fi

  # No channel match and no stable → nothing
  if [[ -z "${channel_match}" && -z "${highest_stable}" ]]; then
    return 0
  fi

  if [[ -z "${channel_match}" ]]; then
    echo "${highest_stable}"
    return 0
  fi

  # Promotion check
  if [[ -n "${highest_stable}" ]]; then
    local cmp
    cmp="$(_gs_eu_semver_compare "${highest_stable}" "${channel_match}")"
    if [[ "${cmp}" == "newer" ]]; then
      echo "${highest_stable}"
      return 0
    fi
  fi

  # Echo channel_match + hint toward stable
  echo "${channel_match}"
  if [[ -n "${highest_stable}" ]]; then
    _gs_eu_write_alt_version "stable" "${highest_stable}"
  fi
  return 0
}
