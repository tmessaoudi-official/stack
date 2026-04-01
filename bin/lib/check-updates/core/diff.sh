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

# Returns 0 if version looks like a pre-release
_is_prerelease() {
  local version="${1}"
  # Indicators: alpha, beta, rc, preview, nightly, edge, dev, next, snapshot
  # Also: -rc0, -rc1, -beta, -alpha, -preview
  local lower="${version,,}"
  [[ "${lower}" =~ (alpha|beta|rc[0-9]*|preview|nightly|edge|\.dev|snapshot|-dev) ]]
}

# Returns 0 if version is unversioned (nightly/latest/edge/next/master)
_is_unversioned() {
  local version="${1}"
  local lower="${version,,}"
  [[ "${lower}" =~ ^(nightly|latest|edge|master|next|head|main)$ ]]
}

# Returns 0 if version contains a git SHA (40 or 12 hex chars)
_is_git_sha() {
  local version="${1}"
  [[ "${version}" =~ ^[a-f0-9]{12,40}$ ]]
}

# Returns 0 if version contains a Debian/Ubuntu codename
_has_distro_codename() {
  local version="${1}"
  local lower="${version,,}"
  [[ "${lower}" =~ (focal|jammy|kinetic|lunar|mantic|noble|oracular|plucky|questing|resolute|oraclelinux|alpine|bullseye|bookworm|buster|stretch|bionic|xenial) ]]
}

# Returns 0 if version has alpine suffix (e.g. 18.3-alpine3.23)
_has_alpine_suffix() {
  local version="${1}"
  [[ "${version}" =~ -alpine[0-9] ]]
}

# Extract alpine suffix from version
_get_alpine_suffix() {
  local version="${1}"
  if [[ "${version}" =~ (-alpine[0-9.]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo ""
  fi
}

# Strip alpine suffix from version for numeric comparison
_strip_alpine_suffix() {
  local version="${1}"
  echo "${version%%-alpine*}"
}

# Returns 0 if the version has non-ubuntu distro codename (oraclelinux, etc.)
_has_non_ubuntu_distro() {
  local version="${1}"
  local lower="${version,,}"
  [[ "${lower}" =~ (oraclelinux|centos|fedora|debian|bullseye|bookworm|buster|stretch|bionic|xenial|wheezy) ]]
}

# --------------------------------------------------------------------------
# Semantic version comparison
# Returns: 0 if a == b, 1 if a > b, 2 if a < b
# Handles: v prefix, pre-release qualifiers
# --------------------------------------------------------------------------
_semver_compare() {
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
# Outputs: echoes one of: AUTO | MANUAL:<reason> | SKIP:<reason>
# --------------------------------------------------------------------------
_decide_action() {
  local type="${1}"
  local identifier="${2}"
  local flags="${3}"
  local current="${4}"
  local proposed="${5}"
  local hint="${6:-}"

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

  # Unversioned current (nightly, latest, edge, etc.) → SKIP
  if _is_unversioned "${current}"; then
    echo "SKIP:unversioned"
    return 0
  fi

  # git SHA track → MANUAL (promotion suggestion)
  if _is_git_sha "${current}"; then
    echo "MANUAL:git-sha-track"
    return 0
  fi

  # sdkmanager → always MANUAL
  if [[ "${type}" == "sdkmanager" ]]; then
    echo "MANUAL:sdkmanager"
    return 0
  fi

  # SDKMAN multi-major: the major constraint is in identifier (e.g. gradle:8)
  # Cross-major updates are filtered by fetcher; any proposal here is within-major
  # But still MANUAL (per spec)
  if [[ "${type}" == "sdkman" && "${identifier}" =~ :[0-9]+$ ]]; then
    echo "MANUAL:sdkman-multi-major"
    return 0
  fi

  # Ubuntu codename in version → special handling
  if _has_distro_codename "${current}" && ! _has_non_ubuntu_distro "${current}"; then
    # Ubuntu-tagged versions are handled by ubuntu.sh separately
    # The diff.sh AUTO decision for ubuntu is made after tag confirmation
    echo "MANUAL:ubuntu-codename"
    return 0
  fi

  # Non-ubuntu distro in version (oraclelinux etc.) → MANUAL
  if _has_non_ubuntu_distro "${current}"; then
    echo "MANUAL:distro-suffix"
    return 0
  fi

  # Alpine suffix handling
  if _has_alpine_suffix "${current}" && _has_alpine_suffix "${proposed}"; then
    local cur_alpine cur_base
    local prop_alpine prop_base
    cur_alpine="$(_get_alpine_suffix "${current}")"
    prop_alpine="$(_get_alpine_suffix "${proposed}")"
    cur_base="$(_strip_alpine_suffix "${current}")"
    prop_base="$(_strip_alpine_suffix "${proposed}")"

    if [[ "${cur_alpine}" != "${prop_alpine}" ]]; then
      # Alpine suffix changed → MANUAL
      echo "MANUAL:alpine-suffix-change"
      return 0
    fi

    # Same alpine suffix — check if base version changed
    local cmp
    cmp="$(_semver_compare "${cur_base}" "${prop_base}")"
    if [[ "${cmp}" == "older" ]]; then
      # proposed is newer, same alpine suffix → AUTO
      if _is_prerelease "${proposed}" && ! _is_prerelease "${current}"; then
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
  if _is_prerelease "${proposed}" && ! _is_prerelease "${current}"; then
    echo "HOLD:pre-release-proposed"
    return 0
  fi

  # Pre-release proposed AND current is same qualifier → AUTO
  if _is_prerelease "${proposed}" && _is_prerelease "${current}"; then
    local cmp
    cmp="$(_semver_compare "${current}" "${proposed}")"
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
  cmp="$(_semver_compare "${current}" "${proposed}")"
  if [[ "${cmp}" == "older" ]]; then
    echo "AUTO"
  elif [[ "${cmp}" == "equal" ]]; then
    echo "SKIP:no-change"
  else
    # proposed is older than current? Shouldn't happen unless we fetched wrong
    echo "SKIP:proposed-older"
  fi
}
