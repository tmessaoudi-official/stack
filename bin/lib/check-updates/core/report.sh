#!/bin/bash
# Terminal/JSON/patch output renderer.
# Provides logging functions for all check-updates output.
# shellcheck disable=SC2034  # Some vars used by callers

set -eEuo pipefail

# --------------------------------------------------------------------------
# Color support (disabled by NO_COLOR env var per https://no-color.org)
# --------------------------------------------------------------------------
_gs_cu_init_colors() {
  if [[ -z "${NO_COLOR:-}" && -t 1 ]]; then
    readonly _GS_CU_CLR_RESET='\033[0m'
    readonly _GS_CU_CLR_GREEN='\033[0;32m'
    readonly _GS_CU_CLR_YELLOW='\033[0;33m'
    readonly _GS_CU_CLR_CYAN='\033[0;36m'
    readonly _GS_CU_CLR_RED='\033[0;31m'
    readonly _GS_CU_CLR_MAGENTA='\033[0;35m'
    readonly _GS_CU_CLR_BOLD='\033[1m'
    readonly _GS_CU_CLR_DIM='\033[2m'
  else
    readonly _GS_CU_CLR_RESET=''
    readonly _GS_CU_CLR_GREEN=''
    readonly _GS_CU_CLR_YELLOW=''
    readonly _GS_CU_CLR_CYAN=''
    readonly _GS_CU_CLR_RED=''
    readonly _GS_CU_CLR_MAGENTA=''
    readonly _GS_CU_CLR_BOLD=''
    readonly _GS_CU_CLR_DIM=''
  fi
}

_gs_cu_init_colors

# --------------------------------------------------------------------------
# Report accumulators (global arrays — populated during the run)
# --------------------------------------------------------------------------
_GS_CU_REPORT_AUTO=()      # "[env_var] type:id old → new"
_GS_CU_REPORT_MANUAL=()    # "[env_var] type:id old → new  (reason)"
_GS_CU_REPORT_SKIPPED=()   # "[env_var] type:id  (reason)"
_GS_CU_REPORT_ERRORS=()    # "[env_var] type:id  API error: ..."
_GS_CU_REPORT_UBUNTU=()    # "[env_var] codename alignment ..."
_GS_CU_REPORT_OVERRIDE=()  # "[env_var] type:id old → new  (pinned reason)"

# --------------------------------------------------------------------------
# Per-record logging
# --------------------------------------------------------------------------

# [AUTO ] — version was auto-applied
# Usage: _gs_cu_log_auto "env_var" "type:id" "old" "new" "file:line"
_gs_cu_log_auto() {
  local env_var="${1}"
  local type_id="${2}"
  local old_v="${3}"
  local new_v="${4}"
  local location="${5:-}"
  local msg
  printf -v msg "${_GS_CU_CLR_GREEN}[AUTO ]${_GS_CU_CLR_RESET} %-60s %s → %s" \
    "${type_id}" "${old_v}" "${new_v}"
  if [[ -n "${location}" ]]; then
    msg+="  ${_GS_CU_CLR_DIM}(${location})${_GS_CU_CLR_RESET}"
  fi
  printf '%b\n' "${msg}"
  _GS_CU_REPORT_AUTO+=("${env_var}|${type_id}|${old_v}|${new_v}|${location}")
}

# [SKIP ] — unversioned/nightly/latest/edge — no check possible
# Usage: _gs_cu_log_skip "env_var" "type:id" "reason"
_gs_cu_log_skip() {
  local env_var="${1}"
  local type_id="${2}"
  local reason="${3:-unversioned}"
  local msg
  printf -v msg "${_GS_CU_CLR_DIM}[SKIP ]${_GS_CU_CLR_RESET} %-60s ${_GS_CU_CLR_DIM}(%s)${_GS_CU_CLR_RESET}" \
    "${type_id}" "${reason}"
  printf '%b\n' "${msg}"
  _GS_CU_REPORT_SKIPPED+=("${env_var}|${type_id}|${reason}")
}

# [MANUAL] — update found but requires manual review
# Usage: _gs_cu_log_manual "env_var" "type:id" "old" "new" "reason"
_gs_cu_log_manual() {
  local env_var="${1}"
  local type_id="${2}"
  local old_v="${3}"
  local new_v="${4}"
  local reason="${5:-review required}"
  local msg
  printf -v msg "${_GS_CU_CLR_CYAN}[MANUAL]${_GS_CU_CLR_RESET} %-60s %s → %s  ${_GS_CU_CLR_DIM}(%s)${_GS_CU_CLR_RESET}" \
    "${type_id}" "${old_v}" "${new_v}" "${reason}"
  printf '%b\n' "${msg}"
  _GS_CU_REPORT_MANUAL+=("${env_var}|${type_id}|${old_v}|${new_v}|${reason}")
}

# [HOLD ] — pre-release proposed vs stable current
# Usage: _gs_cu_log_hold "env_var" "type:id" "old" "new" "reason"
_gs_cu_log_hold() {
  local env_var="${1}"
  local type_id="${2}"
  local old_v="${3}"
  local new_v="${4}"
  local reason="${5:-pre-release: review}"
  local msg
  printf -v msg "${_GS_CU_CLR_YELLOW}[HOLD ]${_GS_CU_CLR_RESET} %-60s %s → %s  ${_GS_CU_CLR_DIM}(%s)${_GS_CU_CLR_RESET}" \
    "${type_id}" "${old_v}" "${new_v}" "${reason}"
  printf '%b\n' "${msg}"
  _GS_CU_REPORT_MANUAL+=("${env_var}|${type_id}|${old_v}|${new_v}|${reason}")
}

# [WARN ] — API error, stale cache used
# Usage: _gs_cu_log_warn "env_var" "type:id" "message"
_gs_cu_log_warn() {
  local env_var="${1}"
  local type_id="${2}"
  local message="${3}"
  local msg
  printf -v msg "${_GS_CU_CLR_YELLOW}[WARN ]${_GS_CU_CLR_RESET} %-60s %s" \
    "${type_id}" "${message}"
  printf '%b\n' "${msg}"
  _GS_CU_REPORT_ERRORS+=("${env_var}|${type_id}|${message}")
}

# [ERROR] — hard failure
# Usage: _gs_cu_log_error "env_var" "type:id" "message"
_gs_cu_log_error() {
  local env_var="${1}"
  local type_id="${2}"
  local message="${3}"
  local msg
  printf -v msg "${_GS_CU_CLR_RED}[ERROR]${_GS_CU_CLR_RESET} %-60s %s" \
    "${type_id}" "${message}"
  printf '%b\n' "${msg}" >&2
  _GS_CU_REPORT_ERRORS+=("${env_var}|${type_id}|${message}")
}

# [UBUNTU] — Ubuntu codename alignment
# Usage: _gs_cu_log_ubuntu "env_var" "old_version" "new_version" "applied|manual"
_gs_cu_log_ubuntu() {
  local env_var="${1}"
  local old_v="${2}"
  local new_v="${3}"
  local disposition="${4:-applied}"
  local msg
  printf -v msg "${_GS_CU_CLR_MAGENTA}[UBUNTU]${_GS_CU_CLR_RESET} %-60s %s → %s  ${_GS_CU_CLR_DIM}(%s)${_GS_CU_CLR_RESET}" \
    "${env_var}" "${old_v}" "${new_v}" "${disposition}"
  printf '%b\n' "${msg}"
  _GS_CU_REPORT_UBUNTU+=("${env_var}|${old_v}|${new_v}|${disposition}")
}

# [INFO ] — general informational message
_gs_cu_log_info() {
  local message="${1}"
  local msg
  printf -v msg "${_GS_CU_CLR_BOLD}[INFO ]${_GS_CU_CLR_RESET} %s" "${message}"
  printf '%b\n' "${msg}"
}

# [DEBUG] — only when _GS_CU_DEBUG=true
_gs_cu_log_debug() {
  if [[ "${_GS_CU_DEBUG:-false}" == "true" ]]; then
    local msg
    printf -v msg "${_GS_CU_CLR_DIM}[DEBUG]${_GS_CU_CLR_RESET} %s" "${*}"
    printf '%b\n' "${msg}" >&2
  fi
}

# [OVRRD] — version is pinned override — fetched but held for manual review
# Usage: _gs_cu_log_override "env_var" "type:id" "old" "new" "reason"
_gs_cu_log_override() {
  local env_var="${1}" type_id="${2}" old_v="${3}" new_v="${4}" reason="${5:-pinned override}"
  local msg
  printf -v msg "${_GS_CU_CLR_BOLD}${_GS_CU_CLR_RED}[OVRRD]${_GS_CU_CLR_RESET} %-60s %s → %s  ${_GS_CU_CLR_DIM}(%s)${_GS_CU_CLR_RESET}" \
    "${type_id}" "${old_v}" "${new_v}" "${reason}"
  printf '%b\n' "${msg}"
  _GS_CU_REPORT_OVERRIDE+=("${env_var}|${type_id}|${old_v}|${new_v}|${reason}")
  _GS_CU_REPORT_MANUAL+=("${env_var}|${type_id}|${old_v}|${new_v}|override:${reason}")
}

# --------------------------------------------------------------------------
# End-of-run summary
# --------------------------------------------------------------------------
_gs_cu_print_summary() {
  local patch_file="${1:-}"
  local report_file="${2:-}"

  printf '\n%b\n' "${_GS_CU_CLR_BOLD}════════════════════════════════════════════════════════════════${_GS_CU_CLR_RESET}"
  printf '%b\n' "${_GS_CU_CLR_BOLD}  CHECK-UPDATES SUMMARY${_GS_CU_CLR_RESET}"
  printf '%b\n' "${_GS_CU_CLR_BOLD}════════════════════════════════════════════════════════════════${_GS_CU_CLR_RESET}"

  # OVERRIDES — PINNED MANUAL REVIEW (shown first, in red/bold)
  if [[ ${#_GS_CU_REPORT_OVERRIDE[@]} -gt 0 ]]; then
    printf '\n%b\n' "${_GS_CU_CLR_BOLD}${_GS_CU_CLR_RED}OVERRIDES — PINNED MANUAL REVIEW (${#_GS_CU_REPORT_OVERRIDE[@]}):${_GS_CU_CLR_RESET}"
    printf '%b\n' "${_GS_CU_CLR_DIM}  These versions are intentionally held. Review before unpinning.${_GS_CU_CLR_RESET}"
    local entry
    for entry in "${_GS_CU_REPORT_OVERRIDE[@]}"; do
      IFS='|' read -r ev ti ov nv reason <<< "${entry}"
      printf '  %b%-50s%b  %s → %s  (%s)\n' "${_GS_CU_CLR_RED}" "${ti}" "${_GS_CU_CLR_RESET}" "${ov}" "${nv}" "${reason}"
    done
  fi

  # AUTO-APPLIED
  if [[ ${#_GS_CU_REPORT_AUTO[@]} -gt 0 ]]; then
    printf '\n%b\n' "${_GS_CU_CLR_GREEN}AUTO-APPLIED (${#_GS_CU_REPORT_AUTO[@]}):${_GS_CU_CLR_RESET}"
    local entry
    for entry in "${_GS_CU_REPORT_AUTO[@]}"; do
      IFS='|' read -r ev ti ov nv loc <<< "${entry}"
      printf '  %b%-50s%b  %s → %s\n' "${_GS_CU_CLR_GREEN}" "${ti}" "${_GS_CU_CLR_RESET}" "${ov}" "${nv}"
    done
  fi

  # UBUNTU CODENAME ALIGNMENT
  if [[ ${#_GS_CU_REPORT_UBUNTU[@]} -gt 0 ]]; then
    printf '\n%b\n' "${_GS_CU_CLR_MAGENTA}UBUNTU CODENAME ALIGNMENT (${#_GS_CU_REPORT_UBUNTU[@]}):${_GS_CU_CLR_RESET}"
    local entry
    for entry in "${_GS_CU_REPORT_UBUNTU[@]}"; do
      IFS='|' read -r ev ov nv disp <<< "${entry}"
      printf '  %b%-50s%b  %s → %s  (%s)\n' "${_GS_CU_CLR_MAGENTA}" "${ev}" "${_GS_CU_CLR_RESET}" "${ov}" "${nv}" "${disp}"
    done
  fi

  # MANUAL REVIEW REQUIRED
  if [[ ${#_GS_CU_REPORT_MANUAL[@]} -gt 0 ]]; then
    printf '\n%b\n' "${_GS_CU_CLR_CYAN}MANUAL REVIEW REQUIRED (${#_GS_CU_REPORT_MANUAL[@]}):${_GS_CU_CLR_RESET}"
    local entry
    for entry in "${_GS_CU_REPORT_MANUAL[@]}"; do
      IFS='|' read -r ev ti ov nv reason <<< "${entry}"
      printf '  %b%-50s%b  %s → %s  (%s)\n' "${_GS_CU_CLR_CYAN}" "${ti}" "${_GS_CU_CLR_RESET}" "${ov}" "${nv}" "${reason}"
    done
  fi

  # SKIPPED
  if [[ ${#_GS_CU_REPORT_SKIPPED[@]} -gt 0 ]]; then
    printf '\n%b\n' "${_GS_CU_CLR_DIM}SKIPPED (${#_GS_CU_REPORT_SKIPPED[@]}):${_GS_CU_CLR_RESET}"
    local entry
    for entry in "${_GS_CU_REPORT_SKIPPED[@]}"; do
      IFS='|' read -r ev ti reason <<< "${entry}"
      printf '  %b%-50s%b  (%s)\n' "${_GS_CU_CLR_DIM}" "${ti}" "${_GS_CU_CLR_RESET}" "${reason}"
    done
  fi

  # ERRORS
  if [[ ${#_GS_CU_REPORT_ERRORS[@]} -gt 0 ]]; then
    printf '\n%b\n' "${_GS_CU_CLR_RED}ERRORS (${#_GS_CU_REPORT_ERRORS[@]}):${_GS_CU_CLR_RESET}"
    local entry
    for entry in "${_GS_CU_REPORT_ERRORS[@]}"; do
      IFS='|' read -r ev ti msg <<< "${entry}"
      printf '  %b%-50s%b  %s\n' "${_GS_CU_CLR_RED}" "${ti}" "${_GS_CU_CLR_RESET}" "${msg}"
    done
  fi

  printf '\n'
  if [[ -n "${patch_file}" && -f "${patch_file}" ]]; then
    printf '%b\n' "${_GS_CU_CLR_BOLD}Patch file:${_GS_CU_CLR_RESET}  ${patch_file}"
  fi
  if [[ -n "${report_file}" && -f "${report_file}" ]]; then
    printf '%b\n' "${_GS_CU_CLR_BOLD}JSON report:${_GS_CU_CLR_RESET} ${report_file}"
  fi
  printf '\n'
}

# --------------------------------------------------------------------------
# JSON report builder
# --------------------------------------------------------------------------
_gs_cu_write_json_report() {
  local output_file="${1}"
  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  {
    printf '{\n'
    printf '  "generated_at": "%s",\n' "${timestamp}"

    # overrides
    printf '  "overrides": [\n'
    local i=0
    for entry in "${_GS_CU_REPORT_OVERRIDE[@]:-}"; do
      [[ -z "${entry}" ]] && continue
      IFS='|' read -r ev ti ov nv reason <<< "${entry}"
      [[ ${i} -gt 0 ]] && printf ',\n'
      printf '    {"env_var":"%s","type_id":"%s","old":"%s","new":"%s","reason":"%s"}' \
        "${ev}" "${ti}" "${ov}" "${nv}" "${reason}"
      (( i++ )) || true
    done
    printf '\n  ],\n'

    # auto
    printf '  "auto_applied": [\n'
    i=0
    for entry in "${_GS_CU_REPORT_AUTO[@]:-}"; do
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
    for entry in "${_GS_CU_REPORT_MANUAL[@]:-}"; do
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
    for entry in "${_GS_CU_REPORT_SKIPPED[@]:-}"; do
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
    for entry in "${_GS_CU_REPORT_ERRORS[@]:-}"; do
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
