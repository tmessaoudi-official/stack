#!/bin/bash
# Ubuntu codename alignment logic.
# Handles GLOBAL_STACK_IMAGE_UBUNTU_VERSION and any version string containing
# an Ubuntu codename that may need upgrading to the env's target codename.

set -eEuo pipefail

# shellcheck source=../config/codename_map.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/codename_map.sh"
# shellcheck source=../fetchers/dockerhub.sh
source "$(dirname "${BASH_SOURCE[0]}")/../fetchers/dockerhub.sh"

# The env's authoritative Ubuntu codename (read from GLOBAL_STACK_IMAGE_UBUNTU_VERSION)
CU_UBUNTU_ENV_CODENAME=""
CU_UBUNTU_ENV_VERSION=""

# Initialize by reading GLOBAL_STACK_IMAGE_UBUNTU_VERSION from the parsed records
_ubuntu_init() {
  local env_file="${1}"
  local ubuntu_line
  ubuntu_line="$(grep -m1 '^GLOBAL_STACK_IMAGE_UBUNTU_VERSION=' "${env_file}" 2>/dev/null || echo "")"
  if [[ -n "${ubuntu_line}" ]]; then
    CU_UBUNTU_ENV_VERSION="${ubuntu_line#*=}"
    CU_UBUNTU_ENV_CODENAME="$(_extract_codename_from_version "${CU_UBUNTU_ENV_VERSION}")"
  fi
  _log_debug "Ubuntu env codename: ${CU_UBUNTU_ENV_CODENAME} (from ${CU_UBUNTU_ENV_VERSION})"
}

# Check if a Docker Hub tag exists for the given image+tag.
# Returns 0 if it exists, 1 if not.
_ubuntu_tag_exists_on_dockerhub() {
  local namespace="${1}"  # e.g. "_" or "axllent"
  local image="${2}"
  local tag="${3}"

  local api_ns
  if [[ "${namespace}" == "_" ]]; then
    api_ns="library"
  else
    api_ns="${namespace}"
  fi

  local url="https://hub.docker.com/v2/repositories/${api_ns}/${image}/tags/${tag}"
  local response
  response="$(curl --silent --max-time 10 --retry 1 -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null || echo "000")"
  [[ "${response}" == "200" ]]
}

# Process GLOBAL_STACK_IMAGE_UBUNTU_VERSION specifically:
# Fetch the latest resolute-YYYYMMDD tag from Docker Hub _/ubuntu and propose update.
# Returns: echoes proposed version or empty string on failure
_ubuntu_fetch_latest_ubuntu_image() {
  local current_version="${1}"
  local env_codename="${2}"

  # Fetch all tags for _/ubuntu matching the env codename
  local tags_json
  if ! tags_json="$(_dockerhub_fetch_tags "_" "ubuntu" 2>/dev/null)"; then
    return 1
  fi

  # Filter tags matching <codename>-YYYYMMDD pattern
  local matching_tag
  matching_tag="$(printf '%s' "${tags_json}" | jq -r \
    --arg codename "${env_codename}" \
    '[.[] | select(test("^" + $codename + "-[0-9]{8}$"))] | sort | last // empty' \
    2>/dev/null || echo "")"

  if [[ -z "${matching_tag}" ]]; then
    _log_debug "No dated tag found for ubuntu:${env_codename}-YYYYMMDD"
    return 1
  fi

  echo "${matching_tag}"
}

# For a version string containing an Ubuntu codename, replace old codename
# with env_codename, then verify tag exists on Docker Hub.
# Usage: _ubuntu_align_codename_in_version "8.2.6-rc0-noble" "namespace" "image"
# Returns: echoes proposed version or original if no change needed
_ubuntu_align_codename_in_version() {
  local version="${1}"
  local namespace="${2}"
  local image="${3}"

  if [[ -z "${CU_UBUNTU_ENV_CODENAME}" ]]; then
    echo "${version}"
    return 0
  fi

  # Extract codename from version
  local ver_codename
  ver_codename="$(_extract_codename_from_version "${version}")"

  if [[ -z "${ver_codename}" ]]; then
    echo "${version}"
    return 0
  fi

  # If already at env codename, no change
  if [[ "${ver_codename}" == "${CU_UBUNTU_ENV_CODENAME}" ]]; then
    echo "${version}"
    return 0
  fi

  # Check if env codename is actually newer than ver_codename
  if ! _codename_is_older "${ver_codename}" "${CU_UBUNTU_ENV_CODENAME}"; then
    echo "${version}"
    return 0
  fi

  # Build proposed version with env codename
  local proposed_version="${version//${ver_codename}/${CU_UBUNTU_ENV_CODENAME}}"

  # Check if this tag exists on Docker Hub
  if _ubuntu_tag_exists_on_dockerhub "${namespace}" "${image}" "${proposed_version}"; then
    echo "${proposed_version}"
  else
    # Special case: wkhtmltopdf frozen at jammy
    echo "__codename_mismatch__:${proposed_version}"
  fi
}

# Process a record that contains a Ubuntu codename in its version.
# Outputs: decision AUTO | MANUAL | SKIP
_ubuntu_process_record() {
  local env_var="${1}"
  local current_version="${2}"
  local type_id="${3}"
  local namespace="${4}"
  local image="${5}"
  local no_auto_apply="${6:-false}"
  local dry_run="${7:-false}"

  if [[ -z "${CU_UBUNTU_ENV_CODENAME}" ]]; then
    echo "SKIP:no-env-codename"
    return 0
  fi

  local ver_codename
  ver_codename="$(_extract_codename_from_version "${current_version}")"

  if [[ -z "${ver_codename}" ]]; then
    echo "SKIP:no-codename-in-version"
    return 0
  fi

  if [[ "${ver_codename}" == "${CU_UBUNTU_ENV_CODENAME}" ]]; then
    echo "SKIP:codename-current"
    return 0
  fi

  local proposed_version="${current_version//${ver_codename}/${CU_UBUNTU_ENV_CODENAME}}"

  # Check tag availability
  local available
  if _ubuntu_tag_exists_on_dockerhub "${namespace}" "${image}" "${proposed_version}"; then
    available="true"
  else
    available="false"
  fi

  if [[ "${available}" == "false" ]]; then
    echo "MANUAL:codename-mismatch-no-tag-available"
    return 0
  fi

  # Tag confirmed → AUTO unless no_auto_apply
  if [[ "${no_auto_apply}" == "true" ]]; then
    echo "MANUAL:ubuntu-codename-alignment"
  else
    echo "AUTO"
  fi
}
