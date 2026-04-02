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
#   --no-override          Skip override-flagged records entirely
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
readonly _GS_CU_ENV_FILE="${STACK_DIR}/.env"
_GS_CU_DRY_RUN="false"
export _GS_CU_OFFLINE="false"
export _GS_CU_NO_CACHE="false"
export _GS_CU_CACHE_TTL="${_GS_CU_CACHE_TTL:-3600}"
_GS_CU_FILTER=""
_GS_CU_TYPE_FILTER=""
_GS_CU_NO_AUTO_APPLY="false"
_GS_CU_NO_OVERRIDE="false"
_GS_CU_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly _GS_CU_TIMESTAMP
_GS_CU_PATCH_FILE="/tmp/check-updates-${_GS_CU_TIMESTAMP}.patch"
_GS_CU_REPORT_FILE="/tmp/check-updates-${_GS_CU_TIMESTAMP}.json"
export _GS_CU_DEBUG="${_GS_CU_DEBUG:-false}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
_gs_cu_show_help() {
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
  --no-override          Skip override-flagged records entirely
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

_gs_cu_parse_args() {
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --dry-run)         _GS_CU_DRY_RUN="true" ;;
      --offline)         _GS_CU_OFFLINE="true" ;;
      --no-cache)        _GS_CU_NO_CACHE="true" ;;
      --cache-ttl=*)     _GS_CU_CACHE_TTL="${arg#*=}" ;;
      --filter=*)        _GS_CU_FILTER="${arg#*=}" ;;
      --type=*)          _GS_CU_TYPE_FILTER="${arg#*=}" ;;
      --no-auto-apply)   _GS_CU_NO_AUTO_APPLY="true" ;;
      --no-override)     _GS_CU_NO_OVERRIDE="true" ;;
      --patch-file=*)    _GS_CU_PATCH_FILE="${arg#*=}" ;;
      --report-file=*)   _GS_CU_REPORT_FILE="${arg#*=}" ;;
      --github-token=*)  GITHUB_TOKEN="${arg#*=}" ;;
      --debug)           _GS_CU_DEBUG="true" ;;
      --help)            _gs_cu_show_help; exit 0 ;;
      *)
        printf 'Unknown option: %s\n' "${arg}" >&2
        _gs_cu_show_help >&2
        exit 1
        ;;
    esac
  done
  export GITHUB_TOKEN
}

# --------------------------------------------------------------------------
# Type filter check
# --------------------------------------------------------------------------
_gs_cu_type_is_enabled() {
  local type="${1}"
  if [[ -z "${_GS_CU_TYPE_FILTER}" ]]; then
    return 0
  fi
  local enabled_type
  local enabled_types=()
  IFS=',' read -ra enabled_types <<< "${_GS_CU_TYPE_FILTER}"
  for enabled_type in "${enabled_types[@]}"; do
    [[ "${enabled_type}" == "${type}" ]] && return 0
  done
  return 1
}

# --------------------------------------------------------------------------
# Dispatch to the appropriate fetcher
# --------------------------------------------------------------------------
_gs_cu_fetch_latest_version() {
  local type="${1}"
  local identifier="${2}"
  local current_version="${3}"
  local pecl_ref="${4:-}"

  case "${type}" in
    dockerhub)
      _gs_cu_dockerhub_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_CU_OFFLINE}" "${_GS_CU_NO_CACHE}"
      ;;
    quay)
      _gs_cu_quay_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_CU_OFFLINE}" "${_GS_CU_NO_CACHE}"
      ;;
    github)
      local gh_id="${identifier}" gh_pin=""
      if [[ "${identifier}" =~ ^([^:]+):([0-9]+\.[0-9]+)$ ]]; then
        gh_id="${BASH_REMATCH[1]}"; gh_pin="${BASH_REMATCH[2]}"
      fi
      _gs_cu_github_fetch_latest "${gh_id}" "${current_version}" \
        "${_GS_CU_OFFLINE}" "${_GS_CU_NO_CACHE}" "${gh_pin}"
      ;;
    npm)
      _gs_cu_npm_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_CU_OFFLINE}" "${_GS_CU_NO_CACHE}"
      ;;
    pecl)
      _gs_cu_pecl_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_CU_OFFLINE}" "${_GS_CU_NO_CACHE}"
      ;;
    pecl-git)
      _gs_cu_pecl_git_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_CU_OFFLINE}" "${_GS_CU_NO_CACHE}" "${pecl_ref:-}"
      ;;
    sdkman)
      _gs_cu_sdkman_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_CU_OFFLINE}" "${_GS_CU_NO_CACHE}"
      ;;
    sdkmanager)
      _gs_cu_sdkmanager_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_CU_OFFLINE}" "${_GS_CU_NO_CACHE}"
      ;;
    pypi)
      _gs_cu_pypi_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_CU_OFFLINE}" "${_GS_CU_NO_CACHE}"
      ;;
    url)
      _gs_cu_url_fetch_latest "${identifier}" "${current_version}" \
        "${_GS_CU_OFFLINE}" "${_GS_CU_NO_CACHE}"
      ;;
    *)
      _gs_cu_log_debug "Unknown fetcher type: ${type}"
      echo ""
      ;;
  esac
}

# --------------------------------------------------------------------------
# Handle pecl-git promotion suggestion
# --------------------------------------------------------------------------
_gs_cu_handle_pecl_git_promotion() {
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

    printf '\n%b\n' "${_GS_CU_CLR_CYAN}[PROMOTE]${_GS_CU_CLR_RESET} pecl-git → pecl stable detected for ${ext_name}:"
    printf '  Suggested changes (MANUAL — both lines must be updated together):\n'
    printf '  %s=%s  →  %s=%s\n' "${name_var}" "${identifier}" "${name_var}" "${ext_name}"
    printf '  %s=%s  →  %s=%s\n' "${env_var}" "${current_sha}" "${env_var}" "${pecl_version}"
    printf '  Annotation should change to:\n'
    printf '    # @todo check-updates pecl:%s %s\n' "${ext_name}" "${pecl_version}"
    if [[ -n "${hint}" ]]; then
      printf '    (hint: %s)\n' "${hint}"
    fi

    _gs_cu_log_manual "${env_var}" "pecl-git:${identifier}" \
      "${current_sha}" "${pecl_version}" \
      "PROMOTE: pecl stable available — update _NAME and _VERSION together"
  fi
}

# --------------------------------------------------------------------------
# Process a single record
# --------------------------------------------------------------------------
_gs_cu_process_record() {
  local idx="${1}"

  local env_var="${_GS_CU_RECORDS_ENV_VAR[${idx}]}"
  local current_version="${_GS_CU_RECORDS_CURRENT_VERSION[${idx}]}"
  local type="${_GS_CU_RECORDS_TYPE[${idx}]}"
  local identifier="${_GS_CU_RECORDS_IDENTIFIER[${idx}]}"
  local hint="${_GS_CU_RECORDS_HINT[${idx}]:-}"
  local flags="${_GS_CU_RECORDS_FLAGS[${idx}]:-}"
  local line_number="${_GS_CU_RECORDS_LINE_NUMBER[${idx}]:-}"
  local depends_on="${_GS_CU_RECORDS_DEPENDS_ON[${idx}]:-}"
  local pecl_ref="${_GS_CU_RECORDS_PECL_REF[${idx}]:-}"
  local type_id="${type}:${identifier}"

  _gs_cu_log_debug "Processing record #${idx}: ${env_var} [${type_id}] current=${current_version}"

  # Type filter
  if ! _gs_cu_type_is_enabled "${type}"; then
    _gs_cu_log_debug "Type ${type} not in filter — skipping ${env_var}"
    return 0
  fi

  # Skip unversioned
  if _gs_cu_is_unversioned "${current_version}"; then
    _gs_cu_log_skip "${env_var}" "${type_id}" "unversioned (${current_version})"
    return 0
  fi

  # Manual/skip flags
  if [[ "${flags}" =~ skip ]]; then
    _gs_cu_log_skip "${env_var}" "${type_id}" "flagged-skip"
    return 0
  fi

  # Override flag — fetch for reporting but hold for manual review
  if [[ "${flags}" =~ override ]]; then
    if [[ "${_GS_CU_NO_OVERRIDE}" == "true" ]]; then
      _gs_cu_log_skip "${env_var}" "${type_id}" "override-suppressed (--no-override)"
      return 0
    fi
    local proposed=""
    if _gs_cu_type_is_enabled "${type}" && ! _gs_cu_is_unversioned "${current_version}"; then
      proposed="$(_gs_cu_fetch_latest_version "${type}" "${identifier}" "${current_version}" "${pecl_ref:-}" 2>/dev/null || echo "?")"
    fi
    _gs_cu_log_override "${env_var}" "${type_id}" "${current_version}" "${proposed:-?}" \
      "pinned-override (check manually before upgrading)"
    return 0
  fi

  # URL type is always manual
  if [[ "${type}" == "url" ]]; then
    _gs_cu_log_manual "${env_var}" "${type_id}" "${current_version}" "?" "manual-url — check ${identifier}"
    return 0
  fi

  # Fetch latest
  local proposed=""
  if proposed="$(_gs_cu_fetch_latest_version "${type}" "${identifier}" "${current_version}" "${pecl_ref:-}" 2>/dev/null)"; then
    _gs_cu_log_debug "Fetched: ${proposed}"
  else
    _gs_cu_log_warn "${env_var}" "${type_id}" "API error — check ${identifier} manually"
    return 0
  fi

  if [[ -z "${proposed}" ]]; then
    _gs_cu_log_debug "No proposed version returned for ${env_var}"
    if [[ "${type}" != "url" ]]; then
      _gs_cu_log_manual "${env_var}" "${type_id}" "${current_version}" "?" "no-result — check ${identifier} manually"
    fi
    return 0
  fi

  # Handle pecl-git promotion
  if [[ "${proposed}" == __pecl_promotion__* ]]; then
    _gs_cu_handle_pecl_git_promotion "${env_var}" "${identifier}" "${current_version}" \
      "${proposed}" "${hint}" "${line_number}"
    return 0
  fi

  # depends-on hold logic
  if [[ -n "${depends_on}" && -n "${proposed}" ]]; then
    local dep_var="${depends_on%%:*}"
    local dep_constraint="${depends_on##*:}"
    local dep_version=""
    local j
    for (( j=0; j<_GS_CU_RECORD_COUNT; j++ )); do
      if [[ "${_GS_CU_RECORDS_ENV_VAR[${j}]}" == "${dep_var}" ]]; then
        dep_version="${_GS_CU_RECORDS_CURRENT_VERSION[${j}]}"
        break
      fi
    done
    if [[ -n "${dep_version}" && "${dep_constraint}" == "major" ]]; then
      local proposed_major="${proposed%%.*}"
      local dep_major="${dep_version%%.*}"
      if [[ "${proposed_major}" != "${dep_major}" ]]; then
        _gs_cu_log_manual "${env_var}" "${type_id}" "${current_version}" "${proposed}" \
          "depends-on:${dep_var}:major — upgrade ${dep_var} first"
        return 0
      fi
    fi
  fi

  # Ubuntu-tagged versions: delegate to ubuntu module
  if [[ "${type}" == "dockerhub" ]] && _gs_cu_has_distro_codename "${current_version}" && \
     ! _gs_cu_has_non_ubuntu_distro "${current_version}"; then
    local namespace="${identifier%%/*}"
    local image="${identifier##*/}"
    local ubuntu_decision
    ubuntu_decision="$(_gs_cu_ubuntu_process_record \
      "${env_var}" "${current_version}" "${type_id}" \
      "${namespace}" "${image}" \
      "${_GS_CU_NO_AUTO_APPLY}" "${_GS_CU_DRY_RUN}")"

    local ubuntu_action="${ubuntu_decision%%:*}"
    local ubuntu_reason="${ubuntu_decision#*:}"

    if [[ "${ubuntu_action}" == "SKIP" ]]; then
      if [[ "${ubuntu_reason}" != "codename-current" && "${ubuntu_reason}" != "no-change" ]]; then
        _gs_cu_log_debug "Ubuntu SKIP for ${env_var}: ${ubuntu_reason}"
      fi
    elif [[ "${ubuntu_action}" == "MANUAL" ]]; then
      if [[ "${ubuntu_reason}" == "codename-mismatch-no-tag-available" ]]; then
        printf '%b\n' "${_GS_CU_CLR_YELLOW}[UBUNTU]${_GS_CU_CLR_RESET} %-60s codename mismatch — no new-codename tag available  ${_GS_CU_CLR_DIM}(check ${identifier} manually)${_GS_CU_CLR_RESET}" "${type_id}"
        _gs_cu_log_ubuntu "${env_var}" "${current_version}" "${proposed}" "manual: no-tag-for-new-codename"
      else
        _gs_cu_log_ubuntu "${env_var}" "${current_version}" "${proposed}" "manual"
        _gs_cu_log_manual "${env_var}" "${type_id}" "${current_version}" "${proposed}" "${ubuntu_reason}"
      fi
    elif [[ "${ubuntu_action}" == "AUTO" ]]; then
      _gs_cu_log_ubuntu "${env_var}" "${current_version}" "${proposed}" "applied"
      _gs_cu_apply_update "${STACK_DIR}" "${_GS_CU_ENV_FILE}" \
        "${env_var}" "${current_version}" "${proposed}" "${_GS_CU_DRY_RUN}"
      _gs_cu_log_auto "${env_var}" "${type_id}" "${current_version}" "${proposed}" ".env:${line_number}"
    fi
    return 0
  fi

  # Special handling for GLOBAL_STACK_IMAGE_UBUNTU_VERSION (the base image itself)
  if [[ "${env_var}" == "GLOBAL_STACK_IMAGE_UBUNTU_VERSION" && "${type}" == "dockerhub" ]]; then
    local latest_ubuntu
    if latest_ubuntu="$(_gs_cu_ubuntu_fetch_latest_ubuntu_image "${current_version}" "${_GS_CU_UBUNTU_ENV_CODENAME}" 2>/dev/null)"; then
      if [[ -n "${latest_ubuntu}" && "${latest_ubuntu}" != "${current_version}" ]]; then
        if [[ "${_GS_CU_NO_AUTO_APPLY}" == "true" || "${_GS_CU_DRY_RUN}" == "true" ]]; then
          _gs_cu_log_manual "${env_var}" "${type_id}" "${current_version}" "${latest_ubuntu}" "ubuntu-base-image"
        else
          _gs_cu_apply_update "${STACK_DIR}" "${_GS_CU_ENV_FILE}" \
            "${env_var}" "${current_version}" "${latest_ubuntu}" "${_GS_CU_DRY_RUN}"
          _gs_cu_log_auto "${env_var}" "${type_id}" "${current_version}" "${latest_ubuntu}" ".env:${line_number}"
        fi
      fi
    fi
    return 0
  fi

  # Standard decision
  local decision
  decision="$(_gs_cu_decide_action "${type}" "${identifier}" "${flags}" \
    "${current_version}" "${proposed}" "${hint}")"
  local action="${decision%%:*}"
  local reason="${decision#*:}"

  case "${action}" in
    AUTO)
      if [[ "${_GS_CU_NO_AUTO_APPLY}" == "true" || "${_GS_CU_DRY_RUN}" == "true" ]]; then
        _gs_cu_log_manual "${env_var}" "${type_id}" "${current_version}" "${proposed}" "no-auto-apply-mode"
      else
        _gs_cu_apply_update "${STACK_DIR}" "${_GS_CU_ENV_FILE}" \
          "${env_var}" "${current_version}" "${proposed}" "${_GS_CU_DRY_RUN}"
        _gs_cu_log_auto "${env_var}" "${type_id}" "${current_version}" "${proposed}" ".env:${line_number}"
      fi
      ;;
    HOLD)
      _gs_cu_log_hold "${env_var}" "${type_id}" "${current_version}" "${proposed}" "${reason}"
      ;;
    MANUAL)
      _gs_cu_log_manual "${env_var}" "${type_id}" "${current_version}" "${proposed}" "${reason}"
      ;;
    SKIP)
      if [[ "${reason}" != "no-change" ]]; then
        _gs_cu_log_skip "${env_var}" "${type_id}" "${reason}"
      fi
      ;;
  esac
}

# --------------------------------------------------------------------------
# Patch file generation
# --------------------------------------------------------------------------
_gs_cu_generate_patch_file() {
  local patch_file="${1}"

  # Create empty patch file
  : > "${patch_file}"

  local entry
  for entry in "${_GS_CU_REPORT_AUTO[@]:-}"; do
    [[ -z "${entry}" ]] && continue
    IFS='|' read -r ev ti ov nv _loc <<< "${entry}"

    # Generate diff for .env change
    local tmpfile
    tmpfile="$(mktemp)"
    cp "${_GS_CU_ENV_FILE}" "${tmpfile}"
    local escaped_old escaped_new
    # shellcheck disable=SC2001
    escaped_old="$(printf '%s' "${ov}" | sed 's|[.[\*^$()+?{|]|\\&|g')"
    # shellcheck disable=SC2001
    escaped_new="$(printf '%s' "${nv}" | sed 's|[&/\]|\\&|g')"
    sed -i "s|^${ev}=${escaped_old}$|${ev}=${escaped_new}|g" "${tmpfile}" 2>/dev/null || true
    diff -u "${_GS_CU_ENV_FILE}" "${tmpfile}" >> "${patch_file}" 2>/dev/null || true
    rm -f "${tmpfile}"
  done
}

# --------------------------------------------------------------------------
# Main execution
# --------------------------------------------------------------------------
main() {
  _gs_cu_parse_args "$@"

  _gs_cu_log_info "Global Stack check-updates starting..."
  _gs_cu_log_info "Stack dir: ${STACK_DIR}"
  _gs_cu_log_info "Env file:  ${_GS_CU_ENV_FILE}"

  if [[ ! -f "${_GS_CU_ENV_FILE}" ]]; then
    printf 'ERROR: .env file not found at %s\n' "${_GS_CU_ENV_FILE}" >&2
    exit 1
  fi

  # Initialize cache
  _gs_cu_cache_init

  # Initialize Ubuntu codename context
  _gs_cu_ubuntu_init "${_GS_CU_ENV_FILE}"
  if [[ -n "${_GS_CU_UBUNTU_ENV_CODENAME}" ]]; then
    _gs_cu_log_info "Ubuntu target codename: ${_GS_CU_UBUNTU_ENV_CODENAME} (from ${_GS_CU_UBUNTU_ENV_VERSION})"
  fi

  # Build Dockerfile map
  _gs_cu_dockerfile_build_map "${STACK_DIR}"

  # Parse .env file
  _gs_cu_log_info "Parsing .env annotations..."
  _gs_cu_parse_env_file "${_GS_CU_ENV_FILE}" "${_GS_CU_FILTER}"
  _gs_cu_log_info "Found ${_GS_CU_RECORD_COUNT} annotated variables"

  if [[ "${_GS_CU_RECORD_COUNT}" -eq 0 ]]; then
    _gs_cu_log_info "No annotated variables found. Run bin/migrate-annotations.sh first."
    exit 0
  fi

  # Process all records — sequential per type group to avoid mixing output
  _gs_cu_log_info "Checking for updates..."

  # Collect records by type
  declare -A _gs_cu_type_to_indices=()
  local i
  for (( i=0; i<_GS_CU_RECORD_COUNT; i++ )); do
    local t="${_GS_CU_RECORDS_TYPE[${i}]}"
    if [[ -n "${_gs_cu_type_to_indices[${t}]+x}" ]]; then
      _gs_cu_type_to_indices[${t}]+=" ${i}"
    else
      _gs_cu_type_to_indices[${t}]="${i}"
    fi
  done

  # Process each type group sequentially (output ordering matters)
  local type
  for type in "${!_gs_cu_type_to_indices[@]}"; do
    if ! _gs_cu_type_is_enabled "${type}"; then
      continue
    fi

    local indices_str="${_gs_cu_type_to_indices[${type}]}"
    local indices=()
    # shellcheck disable=SC2207
    IFS=' ' read -ra indices <<< "${indices_str}"

    _gs_cu_log_debug "Processing type ${type}: ${#indices[@]} records"

    local idx
    for idx in "${indices[@]}"; do
      [[ -z "${idx}" ]] && continue
      _gs_cu_process_record "${idx}" || true
    done
  done

  # Generate patch file
  if [[ ${#_GS_CU_REPORT_AUTO[@]} -gt 0 ]]; then
    _gs_cu_generate_patch_file "${_GS_CU_PATCH_FILE}"
  fi

  # Write JSON report
  _gs_cu_write_json_report "${_GS_CU_REPORT_FILE}"

  # Print summary
  _gs_cu_print_summary "${_GS_CU_PATCH_FILE}" "${_GS_CU_REPORT_FILE}"
}

main "$@"
