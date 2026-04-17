#!/bin/bash
# Version comparison and auto-apply decision logic.
# Determines whether a proposed version update should be:
#   - AUTO: automatically applied
#   - MANUAL: reported only, requires human review
#   - SKIP: no action (unversioned/nightly/etc.)

set -eEuo pipefail

# --------------------------------------------------------------------------
# Version qualifier detection helpers
# --------------------------------------------------------------------------

# Returns "major", "minor", "patch", or "unknown" for version change type
_gs_eu_semver_delta_type() {
  local old="${1#v}" new="${2#v}"
  [[ -z "${old}" || -z "${new}" ]] && echo "unknown" && return
  local old_major="${old%%.*}" new_major="${new%%.*}"
  if [[ "${old_major}" != "${new_major}" ]]; then echo "major"; return; fi
  local old_rest="${old#*.}" new_rest="${new#*.}"
  local old_minor="${old_rest%%.*}" new_minor="${new_rest%%.*}"
  if [[ "${old_minor}" != "${new_minor}" ]]; then echo "minor"; return; fi
  echo "patch"
}

# Returns 0 if version looks like a pre-release
_gs_eu_is_prerelease() {
  local version="${1}"
  local lower="${version,,}"
  [[ "${lower}" =~ (${_GS_EU_PRERELEASE_REGEX}) ]]
}

# Returns 0 if version is unversioned (nightly/latest/edge/next/master)
_gs_eu_is_unversioned() {
  local version="${1}"
  local lower="${version,,}"
  [[ "${lower}" =~ ^(nightly|latest|edge|master|next|head|main)$ ]]
}

# Returns 0 if version contains a git SHA (40 or 12 hex chars)
_gs_eu_is_git_sha() {
  local version="${1}"
  [[ "${version}" =~ ^[a-f0-9]{12,40}$ ]]
}

# Returns 0 if version contains a Debian/Ubuntu codename
_gs_eu_has_distro_codename() {
  local version="${1}"
  local lower="${version,,}"
  [[ "${lower}" =~ (focal|jammy|kinetic|lunar|mantic|noble|oracular|plucky|questing|resolute|oraclelinux|alpine|bullseye|bookworm|buster|stretch|bionic|xenial) ]]
}

# Returns 0 if version has alpine suffix (e.g. 18.3-alpine3.23)
_gs_eu_has_alpine_suffix() {
  local version="${1}"
  [[ "${version}" =~ -alpine[0-9] ]]
}

# Extract alpine suffix from version
_gs_eu_get_alpine_suffix() {
  local version="${1}"
  if [[ "${version}" =~ (-alpine[0-9.]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

# Strip alpine suffix from version for numeric comparison
_gs_eu_strip_alpine_suffix() {
  local version="${1}"
  echo "${version%%-alpine*}"
}

# Returns 0 if the version has non-ubuntu distro codename (oraclelinux, etc.)
_gs_eu_has_non_ubuntu_distro() {
  local version="${1}"
  local lower="${version,,}"
  [[ "${lower}" =~ (oraclelinux|centos|fedora|debian|bullseye|bookworm|buster|stretch|bionic|xenial|wheezy) ]]
}

# --------------------------------------------------------------------------
# Semantic version comparison
# Returns: 0 if a == b, 1 if a > b, 2 if a < b
# Handles: v prefix, pre-release qualifiers
# --------------------------------------------------------------------------
_gs_eu_semver_compare() {
  local a="${1}"
  local b="${2}"

  # Strip v prefix
  a="${a#v}"
  b="${b#v}"

  # If identical, equal
  if [[ "${a}" == "${b}" ]]; then
    echo "equal"
    return 0
  fi

  # SemVer pre-release correction: sort -V treats "1.0.0-rc1" as GREATER than
  # "1.0.0", but SemVer §11 says the opposite — a pre-release has lower
  # precedence than its associated normal version.
  # Detect: same numeric base, one has a hyphen-alpha pre-release suffix.
  # Pattern: ^NUMERIC_BASE-ALPHA... (e.g. "0.33.0-rc1", "1.0.0-beta.2")
  # Numeric-only suffixes (e.g. build dates like "20240101") are NOT matched —
  # they fall through to sort -V which handles them correctly.
  local a_base="${a}" b_base="${b}"
  local a_has_pre=false b_has_pre=false
  if [[ "${a}" =~ ^([0-9]+(\.[0-9]+)*)-([a-zA-Z]) ]]; then
    a_base="${BASH_REMATCH[1]}"
    a_has_pre=true
  fi
  if [[ "${b}" =~ ^([0-9]+(\.[0-9]+)*)-([a-zA-Z]) ]]; then
    b_base="${BASH_REMATCH[1]}"
    b_has_pre=true
  fi
  if [[ "${a_base}" == "${b_base}" ]]; then
    if [[ "${a_has_pre}" == "true" && "${b_has_pre}" == "false" ]]; then
      echo "older"   # a is pre-release of same base → a < b
      return 0
    elif [[ "${a_has_pre}" == "false" && "${b_has_pre}" == "true" ]]; then
      echo "newer"   # b is pre-release of same base → a > b
      return 0
    fi
    # Both have pre-release suffix (or neither) → fall through to sort -V
  fi

  # Use sort -V (version sort) — available on GNU coreutils
  local sorted
  sorted="$(printf '%s\n%s\n' "${a}" "${b}" | sort -V)"
  local first
  first="$(echo "${sorted}" | head -1)"

  if [[ "${first}" == "${a}" ]]; then
    echo "older"  # a < b → a is older
  else
    echo "newer"  # a > b → a is newer
  fi
}

# --------------------------------------------------------------------------
# Main decision function
# Inputs:
#   type       - fetcher type
#   identifier - fetcher identifier
#   flags      - space-separated: override skip manual
#   current    - current version string
#   proposed   - proposed new version string
#   hint       - hint text (e.g. "php >= 8.5.0")
#   channel    - tracking channel (e.g. "nightly") — bypasses pre-release/unversioned guards
# Outputs: echoes one of: AUTO | MANUAL:<reason> | SKIP:<reason>
# --------------------------------------------------------------------------
_gs_eu_decide_action() {
  local type="${1}"
  local identifier="${2}"
  local flags="${3}"
  local current="${4}"
  local proposed="${5}"
  local hint="${6:-}"
  local channel="${7:-}"

  # No change
  if [[ "${current}" == "${proposed}" ]]; then
    echo "SKIP:no-change"
    return 0
  fi

  # If proposed is empty (fetch failed or identical), skip
  if [[ -z "${proposed}" ]]; then
    echo "SKIP:no-proposal"
    return 0
  fi

  # Explicit flags take precedence
  if [[ "${flags}" =~ (skip) ]]; then
    echo "SKIP:flagged-skip"
    return 0
  fi
  if [[ "${flags}" =~ (override|manual) ]]; then
    echo "MANUAL:flagged-manual"
    return 0
  fi

  # channel:nightly — use lexicographic comparison (nightly builds are date-suffixed)
  # Bypasses unversioned and pre-release checks entirely.
  if [[ "${channel}" == "nightly" ]]; then
    if [[ "${proposed}" > "${current}" ]]; then
      echo "AUTO"
    else
      echo "SKIP:no-change"
    fi
    return 0
  fi

  # Unversioned current (nightly, latest, edge, etc.) → SKIP
  if _gs_eu_is_unversioned "${current}"; then
    echo "SKIP:unversioned"
    return 0
  fi

  # git SHA track → MANUAL (promotion suggestion)
  if _gs_eu_is_git_sha "${current}"; then
    echo "MANUAL:git-sha-track"
    return 0
  fi

  # sdkmanager → always MANUAL
  if [[ "${type}" == "sdkmanager" ]]; then
    echo "MANUAL:sdkmanager"
    return 0
  fi

  # SDKMAN multi-major: the major constraint is in identifier (e.g. gradle:8)
  if [[ "${type}" == "sdkman" && "${identifier}" =~ :[0-9]+$ ]]; then
    echo "MANUAL:sdkman-multi-major"
    return 0
  fi

  # Ubuntu codename in version → special handling
  if _gs_eu_has_distro_codename "${current}" && ! _gs_eu_has_non_ubuntu_distro "${current}"; then
    # Extract the codename from current version — the alphabetic suffix token
    local _cur_codename="" _prop_codename=""
    local _cn
    local _ubuntu_codenames=(focal jammy kinetic lunar mantic noble oracular plucky questing resolute)
    for _cn in "${_ubuntu_codenames[@]}"; do
      if [[ "${current,,}" == *"${_cn}"* ]]; then
        _cur_codename="${_cn}"
      fi
      if [[ "${proposed,,}" == *"${_cn}"* ]]; then
        _prop_codename="${_cn}"
      fi
    done

    # Same codename in both: strip it and do normal semver comparison → AUTO is possible
    if [[ -n "${_cur_codename}" && "${_cur_codename}" == "${_prop_codename}" ]]; then
      local _cur_num _prop_num
      _cur_num="${current//-${_cur_codename}/}"
      _cur_num="${_cur_num//${_cur_codename}-/}"
      _prop_num="${proposed//-${_prop_codename}/}"
      _prop_num="${_prop_num//${_prop_codename}-/}"
      # Pre-release guard
      if _gs_eu_is_prerelease "${proposed}" && ! _gs_eu_is_prerelease "${current}"; then
        echo "HOLD:pre-release-proposed"
        return 0
      fi
      local _cmp
      _cmp="$(_gs_eu_semver_compare "${_cur_num}" "${_prop_num}")"
      if [[ "${_cmp}" == "older" ]]; then
        echo "AUTO"
      elif [[ "${_cmp}" == "equal" ]]; then
        echo "SKIP:no-change"
      else
        echo "SKIP:proposed-older:${proposed}"
      fi
      return 0
    fi

    # Different codename → always MANUAL
    echo "MANUAL:ubuntu-codename-change"
    return 0
  fi

  # Non-ubuntu distro in version (oraclelinux etc.) → MANUAL
  if _gs_eu_has_non_ubuntu_distro "${current}"; then
    echo "MANUAL:distro-suffix"
    return 0
  fi

  # Alpine suffix handling
  if _gs_eu_has_alpine_suffix "${current}" && _gs_eu_has_alpine_suffix "${proposed}"; then
    local cur_alpine cur_base
    local prop_alpine prop_base
    cur_alpine="$(_gs_eu_get_alpine_suffix "${current}")"
    prop_alpine="$(_gs_eu_get_alpine_suffix "${proposed}")"
    cur_base="$(_gs_eu_strip_alpine_suffix "${current}")"
    prop_base="$(_gs_eu_strip_alpine_suffix "${proposed}")"

    if [[ "${cur_alpine}" != "${prop_alpine}" ]]; then
      # Alpine suffix changed → MANUAL
      echo "MANUAL:alpine-suffix-change"
      return 0
    fi

    # Same alpine suffix — check if base version changed
    local cmp
    cmp="$(_gs_eu_semver_compare "${cur_base}" "${prop_base}")"
    if [[ "${cmp}" == "older" ]]; then
      # proposed is newer, same alpine suffix → AUTO
      if _gs_eu_is_prerelease "${proposed}" && ! _gs_eu_is_prerelease "${current}"; then
        echo "HOLD:pre-release-proposed"
        return 0
      fi
      echo "AUTO"
      return 0
    else
      echo "SKIP:no-change"
      return 0
    fi
  fi

  # Pre-release proposed vs stable current → HOLD (manual review)
  if _gs_eu_is_prerelease "${proposed}" && ! _gs_eu_is_prerelease "${current}"; then
    echo "HOLD:pre-release-proposed"
    return 0
  fi

  # Pre-release proposed AND current is same qualifier → AUTO
  if _gs_eu_is_prerelease "${proposed}" && _gs_eu_is_prerelease "${current}"; then
    local cmp
    cmp="$(_gs_eu_semver_compare "${current}" "${proposed}")"
    if [[ "${cmp}" == "older" ]]; then
      echo "AUTO"
      return 0
    else
      echo "SKIP:no-change"
      return 0
    fi
  fi

  # Normal semver comparison
  local cmp
  cmp="$(_gs_eu_semver_compare "${current}" "${proposed}")"
  if [[ "${cmp}" == "older" ]]; then
    echo "AUTO"
  elif [[ "${cmp}" == "equal" ]]; then
    echo "SKIP:no-change"
  else
    # proposed is older than current — include both versions for visibility
    echo "SKIP:proposed-older:${proposed}"
  fi
}
