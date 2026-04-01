#!/bin/bash
# Terminal/JSON/patch output renderer.
# Provides logging functions for all check-updates output.
# shellcheck disable=SC2034  # Some vars used by callers

set -eEuo pipefail

# --------------------------------------------------------------------------
# Color support (disabled by NO_COLOR env var per https://no-color.org)
# --------------------------------------------------------------------------
_init_colors() {
  if [[ -z "${NO_COLOR:-}" && -t 1 ]]; then
    readonly CU_CLR_RESET='\033[0m'
    readonly CU_CLR_GREEN='\033[0;32m'
    readonly CU_CLR_YELLOW='\033[0;33m'
    readonly CU_CLR_CYAN='\033[0;36m'
    readonly CU_CLR_RED='\033[0;31m'
    readonly CU_CLR_MAGENTA='\033[0;35m'
    readonly CU_CLR_BOLD='\033[1m'
    readonly CU_CLR_DIM='\033[2m'
  else
    readonly CU_CLR_RESET=''
    readonly CU_CLR_GREEN=''
    readonly CU_CLR_YELLOW=''
    readonly CU_CLR_CYAN=''
    readonly CU_CLR_RED=''
    readonly CU_CLR_MAGENTA=''
    readonly CU_CLR_BOLD=''
    readonly CU_CLR_DIM=''
  fi
}

_init_colors

# --------------------------------------------------------------------------
# Report accumulators (global arrays — populated during the run)
# --------------------------------------------------------------------------
CU_REPORT_AUTO=()      # "[env_var] type:id old → new"
CU_REPORT_MANUAL=()    # "[env_var] type:id old → new  (reason)"
CU_REPORT_SKIPPED=()   # "[env_var] type:id  (reason)"
CU_REPORT_ERRORS=()    # "[env_var] type:id  API error: ..."
CU_REPORT_UBUNTU=()    # "[env_var] codename alignment ..."

# --------------------------------------------------------------------------
# Per-record logging
# --------------------------------------------------------------------------

# [AUTO ] — version was auto-applied
# Usage: _log_auto "env_var" "type:id" "old" "new" "file:line"
_log_auto() {
  local env_var="${1}"
  local type_id="${2}"
  local old_v="${3}"
  local new_v="${4}"
  local location="${5:-}"
  local msg
  printf -v msg "${CU_CLR_GREEN}[AUTO ]${CU_CLR_RESET} %-60s %s → %s" \
    "${type_id}" "${old_v}" "${new_v}"
  if [[ -n "${location}" ]]; then
    msg+="  ${CU_CLR_DIM}(${location})${CU_CLR_RESET}"
  fi
  printf '%b\n' "${msg}"
  CU_REPORT_AUTO+=("${env_var}|${type_id}|${old_v}|${new_v}|${location}")
}

# [SKIP ] — unversioned/nightly/latest/edge — no check possible
# Usage: _log_skip "env_var" "type:id" "reason"
_log_skip() {
  local env_var="${1}"
  local type_id="${2}"
  local reason="${3:-unversioned}"
  local msg
  printf -v msg "${CU_CLR_DIM}[SKIP ]${CU_CLR_RESET} %-60s ${CU_CLR_DIM}(%s)${CU_CLR_RESET}" \
    "${type_id}" "${reason}"
  printf '%b\n' "${msg}"
  CU_REPORT_SKIPPED+=("${env_var}|${type_id}|${reason}")
}

# [MANUAL] — update found but requires manual review
# Usage: _log_manual "env_var" "type:id" "old" "new" "reason"
_log_manual() {
  local env_var="${1}"
  local type_id="${2}"
  local old_v="${3}"
  local new_v="${4}"
  local reason="${5:-review required}"
  local msg
  printf -v msg "${CU_CLR_CYAN}[MANUAL]${CU_CLR_RESET} %-60s %s → %s  ${CU_CLR_DIM}(%s)${CU_CLR_RESET}" \
    "${type_id}" "${old_v}" "${new_v}" "${reason}"
  printf '%b\n' "${msg}"
  CU_REPORT_MANUAL+=("${env_var}|${type_id}|${old_v}|${new_v}|${reason}")
}

# [HOLD ] — pre-release proposed vs stable current
# Usage: _log_hold "env_var" "type:id" "old" "new" "reason"
_log_hold() {
  local env_var="${1}"
  local type_id="${2}"
  local old_v="${3}"
  local new_v="${4}"
  local reason="${5:-pre-release: review}"
  local msg
  printf -v msg "${CU_CLR_YELLOW}[HOLD ]${CU_CLR_RESET} %-60s %s → %s  ${CU_CLR_DIM}(%s)${CU_CLR_RESET}" \
    "${type_id}" "${old_v}" "${new_v}" "${reason}"
  printf '%b\n' "${msg}"
  CU_REPORT_MANUAL+=("${env_var}|${type_id}|${old_v}|${new_v}|${reason}")
}

# [WARN ] — API error, stale cache used
# Usage: _log_warn "env_var" "type:id" "message"
_log_warn() {
  local env_var="${1}"
  local type_id="${2}"
  local message="${3}"
  local msg
  printf -v msg "${CU_CLR_YELLOW}[WARN ]${CU_CLR_RESET} %-60s %s" \
    "${type_id}" "${message}"
  printf '%b\n' "${msg}"
  CU_REPORT_ERRORS+=("${env_var}|${type_id}|${message}")
}

# [ERROR] — hard failure
# Usage: _log_error "env_var" "type:id" "message"
_log_error() {
  local env_var="${1}"
  local type_id="${2}"
  local message="${3}"
  local msg
  printf -v msg "${CU_CLR_RED}[ERROR]${CU_CLR_RESET} %-60s %s" \
    "${type_id}" "${message}"
  printf '%b\n' "${msg}" >&2
  CU_REPORT_ERRORS+=("${env_var}|${type_id}|${message}")
}

# [UBUNTU] — Ubuntu codename alignment
# Usage: _log_ubuntu "env_var" "old_version" "new_version" "applied|manual"
_log_ubuntu() {
  local env_var="${1}"
  local old_v="${2}"
  local new_v="${3}"
  local disposition="${4:-applied}"
  local msg
  printf -v msg "${CU_CLR_MAGENTA}[UBUNTU]${CU_CLR_RESET} %-60s %s → %s  ${CU_CLR_DIM}(%s)${CU_CLR_RESET}" \
    "${env_var}" "${old_v}" "${new_v}" "${disposition}"
  printf '%b\n' "${msg}"
  CU_REPORT_UBUNTU+=("${env_var}|${old_v}|${new_v}|${disposition}")
}

# [INFO ] — general informational message
_log_info() {
  local message="${1}"
  local msg
  printf -v msg "${CU_CLR_BOLD}[INFO ]${CU_CLR_RESET} %s" "${message}"
  printf '%b\n' "${msg}"
}

# [DEBUG] — only when CU_DEBUG=true
_log_debug() {
  if [[ "${CU_DEBUG:-false}" == "true" ]]; then
    local msg
    printf -v msg "${CU_CLR_DIM}[DEBUG]${CU_CLR_RESET} %s" "${*}"
    printf '%b\n' "${msg}" >&2
  fi
}

# --------------------------------------------------------------------------
# End-of-run summary
# --------------------------------------------------------------------------
_print_summary() {
  local patch_file="${1:-}"
  local report_file="${2:-}"

  printf '\n%b\n' "${CU_CLR_BOLD}════════════════════════════════════════════════════════════════${CU_CLR_RESET}"
  printf '%b\n' "${CU_CLR_BOLD}  CHECK-UPDATES SUMMARY${CU_CLR_RESET}"
  printf '%b\n' "${CU_CLR_BOLD}════════════════════════════════════════════════════════════════${CU_CLR_RESET}"

  # AUTO-APPLIED
  if [[ ${#CU_REPORT_AUTO[@]} -gt 0 ]]; then
    printf '\n%b\n' "${CU_CLR_GREEN}AUTO-APPLIED (${#CU_REPORT_AUTO[@]}):${CU_CLR_RESET}"
    local entry
    for entry in "${CU_REPORT_AUTO[@]}"; do
      IFS='|' read -r ev ti ov nv loc <<< "${entry}"
      printf '  %b%-50s%b  %s → %s\n' "${CU_CLR_GREEN}" "${ti}" "${CU_CLR_RESET}" "${ov}" "${nv}"
    done
  fi

  # UBUNTU CODENAME ALIGNMENT
  if [[ ${#CU_REPORT_UBUNTU[@]} -gt 0 ]]; then
    printf '\n%b\n' "${CU_CLR_MAGENTA}UBUNTU CODENAME ALIGNMENT (${#CU_REPORT_UBUNTU[@]}):${CU_CLR_RESET}"
    local entry
    for entry in "${CU_REPORT_UBUNTU[@]}"; do
      IFS='|' read -r ev ov nv disp <<< "${entry}"
      printf '  %b%-50s%b  %s → %s  (%s)\n' "${CU_CLR_MAGENTA}" "${ev}" "${CU_CLR_RESET}" "${ov}" "${nv}" "${disp}"
    done
  fi

  # MANUAL REVIEW REQUIRED
  if [[ ${#CU_REPORT_MANUAL[@]} -gt 0 ]]; then
    printf '\n%b\n' "${CU_CLR_CYAN}MANUAL REVIEW REQUIRED (${#CU_REPORT_MANUAL[@]}):${CU_CLR_RESET}"
    local entry
    for entry in "${CU_REPORT_MANUAL[@]}"; do
      IFS='|' read -r ev ti ov nv reason <<< "${entry}"
      printf '  %b%-50s%b  %s → %s  (%s)\n' "${CU_CLR_CYAN}" "${ti}" "${CU_CLR_RESET}" "${ov}" "${nv}" "${reason}"
    done
  fi

  # SKIPPED
  if [[ ${#CU_REPORT_SKIPPED[@]} -gt 0 ]]; then
    printf '\n%b\n' "${CU_CLR_DIM}SKIPPED (${#CU_REPORT_SKIPPED[@]}):${CU_CLR_RESET}"
    local entry
    for entry in "${CU_REPORT_SKIPPED[@]}"; do
      IFS='|' read -r ev ti reason <<< "${entry}"
      printf '  %b%-50s%b  (%s)\n' "${CU_CLR_DIM}" "${ti}" "${CU_CLR_RESET}" "${reason}"
    done
  fi

  # ERRORS
  if [[ ${#CU_REPORT_ERRORS[@]} -gt 0 ]]; then
    printf '\n%b\n' "${CU_CLR_RED}ERRORS (${#CU_REPORT_ERRORS[@]}):${CU_CLR_RESET}"
    local entry
    for entry in "${CU_REPORT_ERRORS[@]}"; do
      IFS='|' read -r ev ti msg <<< "${entry}"
      printf '  %b%-50s%b  %s\n' "${CU_CLR_RED}" "${ti}" "${CU_CLR_RESET}" "${msg}"
    done
  fi

  printf '\n'
  if [[ -n "${patch_file}" && -f "${patch_file}" ]]; then
    printf '%b\n' "${CU_CLR_BOLD}Patch file:${CU_CLR_RESET}  ${patch_file}"
  fi
  if [[ -n "${report_file}" && -f "${report_file}" ]]; then
    printf '%b\n' "${CU_CLR_BOLD}JSON report:${CU_CLR_RESET} ${report_file}"
  fi
  printf '\n'
}

# --------------------------------------------------------------------------
# JSON report builder
# --------------------------------------------------------------------------
_write_json_report() {
  local output_file="${1}"
  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  {
    printf '{\n'
    printf '  "generated_at": "%s",\n' "${timestamp}"

    # auto
    printf '  "auto_applied": [\n'
    local i=0
    for entry in "${CU_REPORT_AUTO[@]:-}"; do
      [[ -z "${entry}" ]] && continue
      IFS='|' read -r ev ti ov nv loc <<< "${entry}"
      [[ ${i} -gt 0 ]] && printf ',\n'
      printf '    {"env_var":"%s","type_id":"%s","old":"%s","new":"%s","location":"%s"}' \
        "${ev}" "${ti}" "${ov}" "${nv}" "${loc}"
      (( i++ )) || true
    done
    printf '\n  ],\n'

    # manual
    printf '  "manual_review": [\n'
    i=0
    for entry in "${CU_REPORT_MANUAL[@]:-}"; do
      [[ -z "${entry}" ]] && continue
      IFS='|' read -r ev ti ov nv reason <<< "${entry}"
      [[ ${i} -gt 0 ]] && printf ',\n'
      printf '    {"env_var":"%s","type_id":"%s","old":"%s","new":"%s","reason":"%s"}' \
        "${ev}" "${ti}" "${ov}" "${nv}" "${reason}"
      (( i++ )) || true
    done
    printf '\n  ],\n'

    # skipped
    printf '  "skipped": [\n'
    i=0
    for entry in "${CU_REPORT_SKIPPED[@]:-}"; do
      [[ -z "${entry}" ]] && continue
      IFS='|' read -r ev ti reason <<< "${entry}"
      [[ ${i} -gt 0 ]] && printf ',\n'
      printf '    {"env_var":"%s","type_id":"%s","reason":"%s"}' \
        "${ev}" "${ti}" "${reason}"
      (( i++ )) || true
    done
    printf '\n  ],\n'

    # errors
    printf '  "errors": [\n'
    i=0
    for entry in "${CU_REPORT_ERRORS[@]:-}"; do
      [[ -z "${entry}" ]] && continue
      IFS='|' read -r ev ti msg <<< "${entry}"
      [[ ${i} -gt 0 ]] && printf ',\n'
      printf '    {"env_var":"%s","type_id":"%s","message":"%s"}' \
        "${ev}" "${ti}" "${msg}"
      (( i++ )) || true
    done
    printf '\n  ]\n'

    printf '}\n'
  } > "${output_file}"
}
