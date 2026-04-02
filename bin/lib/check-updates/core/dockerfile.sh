#!/bin/bash
# Dockerfile ARG discovery and update logic.
# Scans docker/images/*/Dockerfile for ARG <VAR_NAME>= defaults and updates them.

set -eEuo pipefail

# Map: env_var → array of dockerfile paths (populated lazily)
# We use a global associative array for this.
declare -A _GS_CU_DOCKERFILE_MAP=()
_GS_CU_DOCKERFILE_MAP_BUILT="false"

# Build the env_var → dockerfile path map by scanning all Dockerfiles
# Only needs to run once per execution.
_gs_cu_dockerfile_build_map() {
  if [[ "${_GS_CU_DOCKERFILE_MAP_BUILT}" == "true" ]]; then
    return 0
  fi

  local stack_dir="${1:-/stack}"
  local dockerfiles
  # shellcheck disable=SC2207
  dockerfiles=($(find "${stack_dir}/docker/images" -name "Dockerfile" -type f 2>/dev/null | sort))

  local dockerfile
  for dockerfile in "${dockerfiles[@]}"; do
    # Extract all ARG VAR_NAME=... lines
    local line
    while IFS= read -r line; do
      # Match: ARG GLOBAL_STACK_..._VERSION=...  or  ARG GLOBAL_STACK_..._VERSION
      if [[ "${line}" =~ ^ARG[[:space:]]+(GLOBAL_STACK_[A-Za-z0-9_]+)(=.*)?$ ]]; then
        local var_name="${BASH_REMATCH[1]}"
        # Append dockerfile to map entry (pipe-separated)
        if [[ -n "${_GS_CU_DOCKERFILE_MAP[${var_name}]+x}" ]]; then
          _GS_CU_DOCKERFILE_MAP[${var_name}]+="${dockerfile}|"
        else
          _GS_CU_DOCKERFILE_MAP[${var_name}]="${dockerfile}|"
        fi
      fi
    done < "${dockerfile}"
  done

  _GS_CU_DOCKERFILE_MAP_BUILT="true"
  _gs_cu_log_debug "Dockerfile map built: ${#_GS_CU_DOCKERFILE_MAP[@]} unique vars"
}

# Get list of Dockerfiles that reference a given env var as an ARG
# Usage: _gs_cu_dockerfile_get_files "GLOBAL_STACK_IMAGE_UBUNTU_VERSION"
# Returns: newline-separated list of paths
_gs_cu_dockerfile_get_files() {
  local var_name="${1}"

  if [[ -z "${_GS_CU_DOCKERFILE_MAP[${var_name}]+x}" ]]; then
    return 0
  fi

  local entries="${_GS_CU_DOCKERFILE_MAP[${var_name}]}"
  # Split by pipe
  local IFS='|'
  local path
  for path in ${entries}; do
    [[ -n "${path}" ]] && echo "${path}"
  done
}

# Update a Dockerfile ARG default value in-place
# Usage: _gs_cu_dockerfile_update_arg "/stack/docker/images/00base/Dockerfile" \
#           "GLOBAL_STACK_IMAGE_UBUNTU_VERSION" "resolute-20260108" "resolute-20260115"
# Returns: 0 on success, 1 on failure
_gs_cu_dockerfile_update_arg() {
  local dockerfile="${1}"
  local var_name="${2}"
  local old_value="${3}"
  local new_value="${4}"
  local dry_run="${5:-false}"

  if [[ ! -f "${dockerfile}" ]]; then
    _gs_cu_log_debug "Dockerfile not found: ${dockerfile}"
    return 1
  fi

  # Check if the ARG line with this exact value exists
  if ! grep -q "^ARG ${var_name}=${old_value}$" "${dockerfile}" 2>/dev/null; then
    # The ARG might exist but with a different value, or no default
    # Try updating by matching the variable name regardless of value
    if grep -q "^ARG ${var_name}=" "${dockerfile}" 2>/dev/null; then
      if [[ "${dry_run}" != "true" ]]; then
        sed -i "s|^ARG ${var_name}=.*$|ARG ${var_name}=${new_value}|g" "${dockerfile}"
        _gs_cu_log_debug "Updated ARG ${var_name} in ${dockerfile} (value was different from expected)"
      fi
      return 0
    fi
    _gs_cu_log_debug "ARG ${var_name}=${old_value} not found in ${dockerfile}"
    return 1
  fi

  if [[ "${dry_run}" != "true" ]]; then
    sed -i "s|^ARG ${var_name}=${old_value}$|ARG ${var_name}=${new_value}|g" "${dockerfile}"
    _gs_cu_log_debug "Updated ARG ${var_name}=${old_value} → ${new_value} in ${dockerfile}"
  else
    _gs_cu_log_debug "[DRY-RUN] Would update ARG ${var_name}=${old_value} → ${new_value} in ${dockerfile}"
  fi
  return 0
}

# Update .env file in-place for a given variable
# Usage: _gs_cu_env_update_var "/stack/.env" "GLOBAL_STACK_IMAGE_UBUNTU_VERSION" \
#           "resolute-20260108" "resolute-20260115"
_gs_cu_env_update_var() {
  local env_file="${1}"
  local var_name="${2}"
  local old_value="${3}"
  local new_value="${4}"
  local dry_run="${5:-false}"

  if [[ ! -f "${env_file}" ]]; then
    _gs_cu_log_error "" "" ".env file not found: ${env_file}"
    return 1
  fi

  if [[ "${dry_run}" != "true" ]]; then
    # Escape special chars in old_value for sed
    local escaped_old escaped_new
    # shellcheck disable=SC2001
    escaped_old="$(printf '%s' "${old_value}" | sed 's|[.[\*^$()+?{|]|\\&|g')"
    # shellcheck disable=SC2001
    escaped_new="$(printf '%s' "${new_value}" | sed 's|[&/\]|\\&|g')"
    sed -i "s|^${var_name}=${escaped_old}$|${var_name}=${escaped_new}|g" "${env_file}"
    _gs_cu_log_debug "Updated .env: ${var_name}=${old_value} → ${new_value}"
  else
    _gs_cu_log_debug "[DRY-RUN] Would update .env: ${var_name}=${old_value} → ${new_value}"
  fi
}

# Apply an update: update .env and all matching Dockerfiles
# Usage: _gs_cu_apply_update "/stack" "/stack/.env" "GLOBAL_STACK_IMAGE_UBUNTU_VERSION" \
#           "resolute-20260108" "resolute-20260115" false
# Returns: list of modified files (newline-separated)
_gs_cu_apply_update() {
  local stack_dir="${1}"
  local env_file="${2}"
  local var_name="${3}"
  local old_value="${4}"
  local new_value="${5}"
  local dry_run="${6:-false}"

  local modified_files=()

  # Update .env
  _gs_cu_env_update_var "${env_file}" "${var_name}" "${old_value}" "${new_value}" "${dry_run}"
  modified_files+=("${env_file}")

  # Build map if needed
  _gs_cu_dockerfile_build_map "${stack_dir}"

  # Update Dockerfiles
  local dockerfile
  while IFS= read -r dockerfile; do
    [[ -z "${dockerfile}" ]] && continue
    if _gs_cu_dockerfile_update_arg "${dockerfile}" "${var_name}" "${old_value}" "${new_value}" "${dry_run}"; then
      modified_files+=("${dockerfile}")
    fi
  done < <(_gs_cu_dockerfile_get_files "${var_name}")

  printf '%s\n' "${modified_files[@]}"
}

# Generate a unified diff for proposed changes (without applying them)
# Usage: _gs_cu_generate_patch_line "/stack/.env" "GLOBAL_STACK_IMAGE_UBUNTU_VERSION" \
#           "resolute-20260108" "resolute-20260115"
_gs_cu_generate_patch_line() {
  local env_file="${1}"
  local var_name="${2}"
  local old_value="${3}"
  local new_value="${4}"

  # Create temp copy, apply change, diff
  local tmpfile
  tmpfile="$(mktemp)"
  cp "${env_file}" "${tmpfile}"
  local escaped_old escaped_new
  # shellcheck disable=SC2001
  escaped_old="$(printf '%s' "${old_value}" | sed 's|[.[\*^$()+?{|]|\\&|g')"
  # shellcheck disable=SC2001
  escaped_new="$(printf '%s' "${new_value}" | sed 's|[&/\]|\\&|g')"
  sed -i "s|^${var_name}=${escaped_old}$|${var_name}=${escaped_new}|g" "${tmpfile}"
  diff -u "${env_file}" "${tmpfile}" || true
  rm -f "${tmpfile}"
}
