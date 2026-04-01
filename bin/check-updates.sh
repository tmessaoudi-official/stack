#!/bin/bash
# check-updates.sh — Automated version update checker for Global Stack.
#
# Reads @todo check-updates annotations from .env, fetches latest versions
# from upstream APIs, and optionally auto-applies updates to .env and Dockerfiles.
#
# Usage:
#   bin/check-updates.sh [OPTIONS]
#
# Options:
#   --dry-run              Write patch only, no files modified
#   --offline              Cache only, no network
#   --no-cache             Bypass cache reads (still writes)
#   --cache-ttl=<seconds>  Default: 3600
#   --filter=<pattern>     Only process vars matching pattern
#   --type=<types>         Comma-separated fetcher types to run
#   --no-auto-apply        Report all, apply nothing
#   --patch-file=<path>    Override patch output path
#   --report-file=<path>   Override JSON report path
#   --github-token=<token> Override GITHUB_TOKEN env var
#   --help

set -eEuo pipefail

# --------------------------------------------------------------------------
# Script location & library root
# --------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly STACK_DIR
LIB_DIR="${SCRIPT_DIR}/lib/check-updates"
readonly LIB_DIR

# --------------------------------------------------------------------------
# Source all library modules
# --------------------------------------------------------------------------
# shellcheck source=lib/check-updates/core/report.sh
source "${LIB_DIR}/core/report.sh"
# shellcheck source=lib/check-updates/core/cache.sh
source "${LIB_DIR}/core/cache.sh"
# shellcheck source=lib/check-updates/core/parse.sh
source "${LIB_DIR}/core/parse.sh"
# shellcheck source=lib/check-updates/core/diff.sh
source "${LIB_DIR}/core/diff.sh"
# shellcheck source=lib/check-updates/core/dockerfile.sh
source "${LIB_DIR}/core/dockerfile.sh"
# shellcheck source=lib/check-updates/config/codename_map.sh
source "${LIB_DIR}/config/codename_map.sh"
# shellcheck source=lib/check-updates/config/type_map.sh
source "${LIB_DIR}/config/type_map.sh"

# Fetchers
# shellcheck source=lib/check-updates/fetchers/dockerhub.sh
source "${LIB_DIR}/fetchers/dockerhub.sh"
# shellcheck source=lib/check-updates/fetchers/github.sh
source "${LIB_DIR}/fetchers/github.sh"
# shellcheck source=lib/check-updates/fetchers/npm.sh
source "${LIB_DIR}/fetchers/npm.sh"
# shellcheck source=lib/check-updates/fetchers/pecl.sh
source "${LIB_DIR}/fetchers/pecl.sh"
# shellcheck source=lib/check-updates/fetchers/pecl_git.sh
source "${LIB_DIR}/fetchers/pecl_git.sh"
# shellcheck source=lib/check-updates/fetchers/sdkman.sh
source "${LIB_DIR}/fetchers/sdkman.sh"
# shellcheck source=lib/check-updates/fetchers/sdkmanager.sh
source "${LIB_DIR}/fetchers/sdkmanager.sh"
# shellcheck source=lib/check-updates/fetchers/pypi.sh
source "${LIB_DIR}/fetchers/pypi.sh"
# shellcheck source=lib/check-updates/fetchers/quay.sh
source "${LIB_DIR}/fetchers/quay.sh"
# shellcheck source=lib/check-updates/fetchers/url.sh
source "${LIB_DIR}/fetchers/url.sh"

# Ubuntu alignment (depends on dockerhub fetcher)
# shellcheck source=lib/check-updates/core/ubuntu.sh
source "${LIB_DIR}/core/ubuntu.sh"

# --------------------------------------------------------------------------
# Defaults
# --------------------------------------------------------------------------
readonly ENV_FILE="${STACK_DIR}/.env"
CU_DRY_RUN="false"
export CU_OFFLINE="false"
export CU_NO_CACHE="false"
export CU_CACHE_TTL="${CU_CACHE_TTL:-3600}"
CU_FILTER=""
CU_TYPE_FILTER=""
CU_NO_AUTO_APPLY="false"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly TIMESTAMP
CU_PATCH_FILE="/tmp/check-updates-${TIMESTAMP}.patch"
CU_REPORT_FILE="/tmp/check-updates-${TIMESTAMP}.json"
export CU_DEBUG="${CU_DEBUG:-false}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
_show_help() {
  cat <<'EOF'
bin/check-updates.sh — Global Stack version update checker

Usage:
  bin/check-updates.sh [OPTIONS]

Options:
  --dry-run              Write patch only, no files modified
  --offline              Use cache only, no network requests
  --no-cache             Bypass cache reads (still writes on fetch)
  --cache-ttl=<seconds>  Cache TTL in seconds (default: 3600)
  --filter=<pattern>     Only process .env vars matching bash regex
  --type=<types>         Comma-separated list of fetcher types to run
                         Types: dockerhub quay github npm pecl pecl-git
                                sdkman sdkmanager pypi url
  --no-auto-apply        Report all changes, apply nothing automatically
  --patch-file=<path>    Path for patch output file
  --report-file=<path>   Path for JSON report file
  --github-token=<token> GitHub API token (overrides GITHUB_TOKEN env var)
  --debug                Enable debug output
  --help                 Show this help

Examples:
  bin/check-updates.sh
  bin/check-updates.sh --dry-run --filter=NODE22
  bin/check-updates.sh --type=dockerhub,github --no-auto-apply
  bin/check-updates.sh --offline  # use cached results only
EOF
}

_parse_args() {
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --dry-run)         CU_DRY_RUN="true" ;;
      --offline)         CU_OFFLINE="true" ;;
      --no-cache)        CU_NO_CACHE="true" ;;
      --cache-ttl=*)     CU_CACHE_TTL="${arg#*=}" ;;
      --filter=*)        CU_FILTER="${arg#*=}" ;;
      --type=*)          CU_TYPE_FILTER="${arg#*=}" ;;
      --no-auto-apply)   CU_NO_AUTO_APPLY="true" ;;
      --patch-file=*)    CU_PATCH_FILE="${arg#*=}" ;;
      --report-file=*)   CU_REPORT_FILE="${arg#*=}" ;;
      --github-token=*)  GITHUB_TOKEN="${arg#*=}" ;;
      --debug)           CU_DEBUG="true" ;;
      --help)            _show_help; exit 0 ;;
      *)
        printf 'Unknown option: %s\n' "${arg}" >&2
        _show_help >&2
        exit 1
        ;;
    esac
  done
  export GITHUB_TOKEN
}

# --------------------------------------------------------------------------
# Type filter check
# --------------------------------------------------------------------------
_type_is_enabled() {
  local type="${1}"
  if [[ -z "${CU_TYPE_FILTER}" ]]; then
    return 0
  fi
  local enabled_type
  IFS=',' read -ra enabled_types <<< "${CU_TYPE_FILTER}"
  for enabled_type in "${enabled_types[@]}"; do
    [[ "${enabled_type}" == "${type}" ]] && return 0
  done
  return 1
}

# --------------------------------------------------------------------------
# Dispatch to the appropriate fetcher
# --------------------------------------------------------------------------
_fetch_latest_version() {
  local type="${1}"
  local identifier="${2}"
  local current_version="${3}"

  case "${type}" in
    dockerhub)
      _dockerhub_fetch_latest "${identifier}" "${current_version}" \
        "${CU_OFFLINE}" "${CU_NO_CACHE}"
      ;;
    quay)
      _quay_fetch_latest "${identifier}" "${current_version}" \
        "${CU_OFFLINE}" "${CU_NO_CACHE}"
      ;;
    github)
      _github_fetch_latest "${identifier}" "${current_version}" \
        "${CU_OFFLINE}" "${CU_NO_CACHE}"
      ;;
    npm)
      _npm_fetch_latest "${identifier}" "${current_version}" \
        "${CU_OFFLINE}" "${CU_NO_CACHE}"
      ;;
    pecl)
      _pecl_fetch_latest "${identifier}" "${current_version}" \
        "${CU_OFFLINE}" "${CU_NO_CACHE}"
      ;;
    pecl-git)
      _pecl_git_fetch_latest "${identifier}" "${current_version}" \
        "${CU_OFFLINE}" "${CU_NO_CACHE}"
      ;;
    sdkman)
      _sdkman_fetch_latest "${identifier}" "${current_version}" \
        "${CU_OFFLINE}" "${CU_NO_CACHE}"
      ;;
    sdkmanager)
      _sdkmanager_fetch_latest "${identifier}" "${current_version}" \
        "${CU_OFFLINE}" "${CU_NO_CACHE}"
      ;;
    pypi)
      _pypi_fetch_latest "${identifier}" "${current_version}" \
        "${CU_OFFLINE}" "${CU_NO_CACHE}"
      ;;
    url)
      _url_fetch_latest "${identifier}" "${current_version}" \
        "${CU_OFFLINE}" "${CU_NO_CACHE}"
      ;;
    *)
      _log_debug "Unknown fetcher type: ${type}"
      echo ""
      ;;
  esac
}

# --------------------------------------------------------------------------
# Handle pecl-git promotion suggestion
# --------------------------------------------------------------------------
_handle_pecl_git_promotion() {
  local env_var="${1}"
  local identifier="${2}"
  local current_sha="${3}"
  local proposed="${4}"
  local hint="${5:-}"
  local line_number="${6:-}"

  # proposed looks like "__pecl_promotion__:imagick:3.9.0"
  if [[ "${proposed}" =~ ^__pecl_promotion__:([^:]+):(.+)$ ]]; then
    local ext_name="${BASH_REMATCH[1]}"
    local pecl_version="${BASH_REMATCH[2]}"

    # Determine the _NAME variable (same prefix, _NAME suffix)
    local name_var="${env_var/_VERSION/_NAME}"

    printf '\n%b\n' "${CU_CLR_CYAN}[PROMOTE]${CU_CLR_RESET} pecl-git → pecl stable detected for ${ext_name}:"
    printf '  Suggested changes (MANUAL — both lines must be updated together):\n'
    printf '  %s=%s  →  %s=%s\n' "${name_var}" "${identifier}" "${name_var}" "${ext_name}"
    printf '  %s=%s  →  %s=%s\n' "${env_var}" "${current_sha}" "${env_var}" "${pecl_version}"
    printf '  Annotation should change to:\n'
    printf '    # @todo check-updates pecl:%s %s\n' "${ext_name}" "${pecl_version}"
    if [[ -n "${hint}" ]]; then
      printf '    (hint: %s)\n' "${hint}"
    fi

    _log_manual "${env_var}" "pecl-git:${identifier}" \
      "${current_sha}" "${pecl_version}" \
      "PROMOTE: pecl stable available — update _NAME and _VERSION together"
  fi
}

# --------------------------------------------------------------------------
# Process a single record
# --------------------------------------------------------------------------
_process_record() {
  local idx="${1}"

  local env_var="${CU_RECORDS_ENV_VAR[${idx}]}"
  local current_version="${CU_RECORDS_CURRENT_VERSION[${idx}]}"
  local type="${CU_RECORDS_TYPE[${idx}]}"
  local identifier="${CU_RECORDS_IDENTIFIER[${idx}]}"
  local hint="${CU_RECORDS_HINT[${idx}]:-}"
  local flags="${CU_RECORDS_FLAGS[${idx}]:-}"
  local line_number="${CU_RECORDS_LINE_NUMBER[${idx}]:-}"
  local type_id="${type}:${identifier}"

  _log_debug "Processing record #${idx}: ${env_var} [${type_id}] current=${current_version}"

  # Type filter
  if ! _type_is_enabled "${type}"; then
    _log_debug "Type ${type} not in filter — skipping ${env_var}"
    return 0
  fi

  # Skip unversioned
  if _is_unversioned "${current_version}"; then
    _log_skip "${env_var}" "${type_id}" "unversioned (${current_version})"
    return 0
  fi

  # Manual/skip flags
  if [[ "${flags}" =~ skip ]]; then
    _log_skip "${env_var}" "${type_id}" "flagged-skip"
    return 0
  fi

  # URL type is always manual
  if [[ "${type}" == "url" ]]; then
    _log_manual "${env_var}" "${type_id}" "${current_version}" "?" "manual-url — check ${identifier}"
    return 0
  fi

  # Fetch latest
  local proposed=""
  local fetch_error=""
  if proposed="$(_fetch_latest_version "${type}" "${identifier}" "${current_version}" 2>/dev/null)"; then
    _log_debug "Fetched: ${proposed}"
  else
    fetch_error="fetch failed"
    _log_warn "${env_var}" "${type_id}" "API error — check ${identifier} manually"
    return 0
  fi

  if [[ -z "${proposed}" ]]; then
    _log_debug "No proposed version returned for ${env_var}"
    # URL type returns empty intentionally
    if [[ "${type}" != "url" ]]; then
      _log_manual "${env_var}" "${type_id}" "${current_version}" "?" "no-result — check ${identifier} manually"
    fi
    return 0
  fi

  # Handle pecl-git promotion
  if [[ "${proposed}" == __pecl_promotion__* ]]; then
    _handle_pecl_git_promotion "${env_var}" "${identifier}" "${current_version}" \
      "${proposed}" "${hint}" "${line_number}"
    return 0
  fi

  # Ubuntu-tagged versions: delegate to ubuntu module
  if [[ "${type}" == "dockerhub" ]] && _has_distro_codename "${current_version}" && \
     ! _has_non_ubuntu_distro "${current_version}"; then
    # Check codename alignment
    local namespace="${identifier%%/*}"
    local image="${identifier##*/}"
    local ubuntu_decision
    ubuntu_decision="$(_ubuntu_process_record \
      "${env_var}" "${current_version}" "${type_id}" \
      "${namespace}" "${image}" \
      "${CU_NO_AUTO_APPLY}" "${CU_DRY_RUN}")"

    local ubuntu_action="${ubuntu_decision%%:*}"
    local ubuntu_reason="${ubuntu_decision#*:}"

    if [[ "${ubuntu_action}" == "SKIP" ]]; then
      if [[ "${ubuntu_reason}" != "codename-current" && "${ubuntu_reason}" != "no-change" ]]; then
        _log_debug "Ubuntu SKIP for ${env_var}: ${ubuntu_reason}"
      fi
    elif [[ "${ubuntu_action}" == "MANUAL" ]]; then
      if [[ "${ubuntu_reason}" == "codename-mismatch-no-tag-available" ]]; then
        # wkhtmltopdf-style: always report
        printf '%b\n' "${CU_CLR_YELLOW}[UBUNTU]${CU_CLR_RESET} %-60s codename mismatch — no new-codename tag available  ${CU_CLR_DIM}(check ${identifier} manually)${CU_CLR_RESET}" "${type_id}"
        _log_ubuntu "${env_var}" "${current_version}" "${proposed}" "manual: no-tag-for-new-codename"
      else
        _log_ubuntu "${env_var}" "${current_version}" "${proposed}" "manual"
        _log_manual "${env_var}" "${type_id}" "${current_version}" "${proposed}" "${ubuntu_reason}"
      fi
    elif [[ "${ubuntu_action}" == "AUTO" ]]; then
      _log_ubuntu "${env_var}" "${current_version}" "${proposed}" "applied"
      _apply_update "${STACK_DIR}" "${ENV_FILE}" \
        "${env_var}" "${current_version}" "${proposed}" "${CU_DRY_RUN}"
      _log_auto "${env_var}" "${type_id}" "${current_version}" "${proposed}" ".env:${line_number}"
    fi

    # Also check if the fetched version (proposed) is different from current for non-codename changes
    # (e.g. same codename but newer version number: 8.2.6-rc0-noble → 8.2.7-noble)
    if [[ "${proposed}" != "${current_version}" && \
          "${ubuntu_action}" != "AUTO" ]]; then
      local diff_decision
      diff_decision="$(_decide_action "${type}" "${identifier}" "${flags}" \
        "${current_version}" "${proposed}" "${hint}")"
      local diff_action="${diff_decision%%:*}"
      if [[ "${diff_action}" != "SKIP" && "${diff_action}" != "MANUAL" ]]; then
        # The ubuntu module already handled it
        true
      fi
    fi
    return 0
  fi

  # Special handling for GLOBAL_STACK_IMAGE_UBUNTU_VERSION (the base image itself)
  if [[ "${env_var}" == "GLOBAL_STACK_IMAGE_UBUNTU_VERSION" && "${type}" == "dockerhub" ]]; then
    # Fetch latest dated tag
    local latest_ubuntu
    if latest_ubuntu="$(_ubuntu_fetch_latest_ubuntu_image "${current_version}" "${CU_UBUNTU_ENV_CODENAME}" 2>/dev/null)"; then
      if [[ -n "${latest_ubuntu}" && "${latest_ubuntu}" != "${current_version}" ]]; then
        if [[ "${CU_NO_AUTO_APPLY}" == "true" || "${CU_DRY_RUN}" == "true" ]]; then
          _log_manual "${env_var}" "${type_id}" "${current_version}" "${latest_ubuntu}" "ubuntu-base-image"
        else
          _apply_update "${STACK_DIR}" "${ENV_FILE}" \
            "${env_var}" "${current_version}" "${latest_ubuntu}" "${CU_DRY_RUN}"
          _log_auto "${env_var}" "${type_id}" "${current_version}" "${latest_ubuntu}" ".env:${line_number}"
        fi
      fi
    fi
    return 0
  fi

  # Standard decision
  local decision
  decision="$(_decide_action "${type}" "${identifier}" "${flags}" \
    "${current_version}" "${proposed}" "${hint}")"
  local action="${decision%%:*}"
  local reason="${decision#*:}"

  case "${action}" in
    AUTO)
      if [[ "${CU_NO_AUTO_APPLY}" == "true" || "${CU_DRY_RUN}" == "true" ]]; then
        _log_manual "${env_var}" "${type_id}" "${current_version}" "${proposed}" "no-auto-apply-mode"
      else
        _apply_update "${STACK_DIR}" "${ENV_FILE}" \
          "${env_var}" "${current_version}" "${proposed}" "${CU_DRY_RUN}"
        _log_auto "${env_var}" "${type_id}" "${current_version}" "${proposed}" ".env:${line_number}"
      fi
      ;;
    HOLD)
      _log_hold "${env_var}" "${type_id}" "${current_version}" "${proposed}" "${reason}"
      ;;
    MANUAL)
      _log_manual "${env_var}" "${type_id}" "${current_version}" "${proposed}" "${reason}"
      ;;
    SKIP)
      # Only log if reason is not "no-change"
      if [[ "${reason}" != "no-change" ]]; then
        _log_skip "${env_var}" "${type_id}" "${reason}"
      fi
      ;;
  esac
}

# --------------------------------------------------------------------------
# Parallel execution helpers
# --------------------------------------------------------------------------
# Run a batch of record indices in parallel, up to N jobs at a time
_run_parallel() {
  local max_jobs="${1}"
  shift
  local indices=("$@")

  local pids=()
  local pid_idx=()
  local job_count=0

  local idx
  for idx in "${indices[@]}"; do
    # Process record in a subshell
    (
      _process_record "${idx}"
    ) &
    pids+=("$!")
    pid_idx+=("${idx}")
    (( job_count++ )) || true

    # Throttle
    if [[ ${job_count} -ge ${max_jobs} ]]; then
      # Wait for all current batch
      local pid
      for pid in "${pids[@]}"; do
        wait "${pid}" || true
      done
      pids=()
      pid_idx=()
      job_count=0
    fi
  done

  # Wait for remaining
  local pid
  for pid in "${pids[@]}"; do
    wait "${pid}" || true
  done
}

# --------------------------------------------------------------------------
# Group records by type for parallel execution per type
# --------------------------------------------------------------------------
_group_records_by_type() {
  declare -A type_groups

  local i
  for (( i=0; i<CU_RECORD_COUNT; i++ )); do
    local t="${CU_RECORDS_TYPE[${i}]}"
    if [[ -n "${type_groups[${t}]+x}" ]]; then
      type_groups[${t}]+=" ${i}"
    else
      type_groups[${t}]="${i}"
    fi
  done

  declare -p type_groups
}

# --------------------------------------------------------------------------
# Patch file generation
# --------------------------------------------------------------------------
_generate_patch_file() {
  local patch_file="${1}"

  # Create empty patch file
  : > "${patch_file}"

  local entry
  for entry in "${CU_REPORT_AUTO[@]:-}"; do
    [[ -z "${entry}" ]] && continue
    IFS='|' read -r ev ti ov nv _loc <<< "${entry}"

    # Generate diff for .env change
    local tmpfile
    tmpfile="$(mktemp)"
    cp "${ENV_FILE}" "${tmpfile}"
    local escaped_old escaped_new
    # shellcheck disable=SC2001
    escaped_old="$(printf '%s' "${ov}" | sed 's|[.[\*^$()+?{|]|\\&|g')"
    # shellcheck disable=SC2001
    escaped_new="$(printf '%s' "${nv}" | sed 's|[&/\]|\\&|g')"
    sed -i "s|^${ev}=${escaped_old}$|${ev}=${escaped_new}|g" "${tmpfile}" 2>/dev/null || true
    diff -u "${ENV_FILE}" "${tmpfile}" >> "${patch_file}" 2>/dev/null || true
    rm -f "${tmpfile}"
  done
}

# --------------------------------------------------------------------------
# Main execution
# --------------------------------------------------------------------------
main() {
  _parse_args "$@"

  _log_info "Global Stack check-updates starting..."
  _log_info "Stack dir: ${STACK_DIR}"
  _log_info "Env file:  ${ENV_FILE}"

  if [[ ! -f "${ENV_FILE}" ]]; then
    printf 'ERROR: .env file not found at %s\n' "${ENV_FILE}" >&2
    exit 1
  fi

  # Initialize cache
  _cache_init

  # Initialize Ubuntu codename context
  _ubuntu_init "${ENV_FILE}"
  if [[ -n "${CU_UBUNTU_ENV_CODENAME}" ]]; then
    _log_info "Ubuntu target codename: ${CU_UBUNTU_ENV_CODENAME} (from ${CU_UBUNTU_ENV_VERSION})"
  fi

  # Build Dockerfile map
  _dockerfile_build_map "${STACK_DIR}"

  # Parse .env file
  _log_info "Parsing .env annotations..."
  _parse_env_file "${ENV_FILE}" "${CU_FILTER}"
  _log_info "Found ${CU_RECORD_COUNT} annotated variables"

  if [[ "${CU_RECORD_COUNT}" -eq 0 ]]; then
    _log_info "No annotated variables found. Run bin/migrate-annotations.sh first."
    exit 0
  fi

  # Process all records — parallel per type group to avoid rate limits
  _log_info "Checking for updates..."

  # Collect records by type
  declare -A type_to_indices=()
  local i
  for (( i=0; i<CU_RECORD_COUNT; i++ )); do
    local t="${CU_RECORDS_TYPE[${i}]}"
    if [[ -n "${type_to_indices[${t}]+x}" ]]; then
      type_to_indices[${t}]+=" ${i}"
    else
      type_to_indices[${t}]="${i}"
    fi
  done

  # Process each type group in parallel (max 8 concurrent per type)
  # But types themselves run sequentially to avoid mixing output
  local type
  for type in "${!type_to_indices[@]}"; do
    if ! _type_is_enabled "${type}"; then
      continue
    fi

    local indices_str="${type_to_indices[${type}]}"
    local indices=()
    # shellcheck disable=SC2207
    IFS=' ' read -ra indices <<< "${indices_str}"

    _log_debug "Processing type ${type}: ${#indices[@]} records"

    # For each index in this type, run sequentially (output ordering matters)
    # Parallel would intermix _log_ output lines
    local idx
    for idx in "${indices[@]}"; do
      [[ -z "${idx}" ]] && continue
      _process_record "${idx}" || true
    done
  done

  # Generate patch file
  if [[ ${#CU_REPORT_AUTO[@]} -gt 0 ]]; then
    _generate_patch_file "${CU_PATCH_FILE}"
  fi

  # Write JSON report
  _write_json_report "${CU_REPORT_FILE}"

  # Print summary
  _print_summary "${CU_PATCH_FILE}" "${CU_REPORT_FILE}"
}

main "$@"
