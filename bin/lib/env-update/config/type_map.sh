#!/bin/bash
# Infer TYPE from legacy annotation URL patterns.
# Called by parse.sh when the annotation is in the old URL format.
# shellcheck disable=SC2034  # Variables used by sourcing scripts

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_EU_TYPE_MAP_SH_LOADED:-}" ]] && return 0
readonly _GS_EU_TYPE_MAP_SH_LOADED=1

# Given a raw URL from a legacy annotation, return the structured type:identifier
# Usage: _gs_eu_infer_type_from_url "https://hub.docker.com/r/axllent/mailpit/tags" "v1.29.3"
# Output format: "<type>:<identifier>" echoed to stdout
_gs_eu_infer_type_from_url() {
  local url="${1}"
  local current_version="${2:-}"

  # Docker Hub official: https://hub.docker.com/_/mongo/tags
  if [[ "${url}" =~ hub\.docker\.com/_/([^/]+) ]]; then
    local image="${BASH_REMATCH[1]}"
    # Remove trailing /tags or similar
    image="${image%%/*}"
    echo "dockerhub:_/${image}"
    return 0
  fi

  # Docker Hub user: https://hub.docker.com/r/namespace/image/tags
  if [[ "${url}" =~ hub\.docker\.com/r/([^/]+)/([^/]+) ]]; then
    local ns="${BASH_REMATCH[1]}"
    local img="${BASH_REMATCH[2]}"
    echo "dockerhub:${ns}/${img}"
    return 0
  fi

  # Quay.io: https://quay.io/repository/keycloak/keycloak?tab=tags
  if [[ "${url}" =~ quay\.io/repository/([^/?]+)/([^/?]+) ]]; then
    local org="${BASH_REMATCH[1]}"
    local img="${BASH_REMATCH[2]}"
    echo "quay:${org}/${img}"
    return 0
  fi

  # PECL: https://pecl.php.net/package/imagick
  if [[ "${url}" =~ pecl\.php\.net/package/([^[:space:]]+) ]]; then
    local ext="${BASH_REMATCH[1]}"
    echo "pecl:${ext}"
    return 0
  fi

  # PyPI: https://pypi.org/project/Django/
  if [[ "${url}" =~ pypi\.org/project/([^/[:space:]]+) ]]; then
    local pkg="${BASH_REMATCH[1]}"
    echo "pypi:${pkg}"
    return 0
  fi

  # npmjs: https://www.npmjs.com/package/@angular/cli
  if [[ "${url}" =~ npmjs\.com/package/([^[:space:]]+) ]]; then
    local pkg="${BASH_REMATCH[1]}"
    echo "npm:${pkg}"
    return 0
  fi

  # RubyGems: https://rubygems.org/gems/fastlane
  if [[ "${url}" =~ rubygems\.org/gems/([^/[:space:]]+) ]]; then
    local gem="${BASH_REMATCH[1]}"
    echo "rubygems:${gem}"
    return 0
  fi

  # GitHub releases/tags/commits: https://github.com/owner/repo/releases
  if [[ "${url}" =~ github\.com/([^/]+)/([^/[:space:]]+) ]]; then
    local owner="${BASH_REMATCH[1]}"
    local repo="${BASH_REMATCH[2]}"
    # Strip any trailing path components
    repo="${repo%%/*}"
    echo "github:${owner}/${repo}"
    return 0
  fi

  # Codeberg: https://codeberg.org/mergiraf/mergiraf/tags
  if [[ "${url}" =~ codeberg\.org/([^/]+)/([^/[:space:]]+) ]]; then
    local owner="${BASH_REMATCH[1]}"
    local repo="${BASH_REMATCH[2]}"
    repo="${repo%%/*}"
    echo "codeberg:${owner}/${repo}"
    return 0
  fi

  # SVN/Apache repos: https://svn.apache.org/repos/asf/...
  if [[ "${url}" =~ svn\.apache\.org ]]; then
    echo "url:${url}"
    return 0
  fi

  # Fallback: manual URL
  echo "url:${url}"
}

# Infer SDKMAN candidate from variable name pattern
# e.g. "GLOBAL_STACK_JAVA11_INSTALL_PACKAGE_GRADLE_VX1_VERSION" → "gradle" with major from current_version
# Usage: _gs_eu_infer_sdkman_candidate "GLOBAL_STACK_JAVA11_INSTALL_PACKAGE_GRADLE_VX1_VERSION" "9.4.0"
# Output: "sdkman:gradle:9"
_gs_eu_infer_sdkman_candidate() {
  local var_name="${1}"
  local current_version="${2}"

  # Pattern: ..._INSTALL_PACKAGE_<CANDIDATE>_VX[0-9]_VERSION
  if [[ "${var_name}" =~ _INSTALL_PACKAGE_([A-Z_]+)_VX[0-9]+_VERSION$ ]]; then
    local candidate_upper="${BASH_REMATCH[1]}"
    local candidate
    candidate="${candidate_upper,,}"  # lowercase
    # Extract major version
    local major
    major="${current_version%%.*}"
    echo "sdkman:${candidate}:${major}"
    return 0
  fi

  # Pattern: ..._INSTALL_PACKAGE_<CANDIDATE>_VERSION (no VX suffix)
  if [[ "${var_name}" =~ _INSTALL_PACKAGE_([A-Z_]+)_VERSION$ ]]; then
    local candidate_upper="${BASH_REMATCH[1]}"
    local candidate
    candidate="${candidate_upper,,}"
    echo "sdkman:${candidate}"
    return 0
  fi

  echo ""
}
