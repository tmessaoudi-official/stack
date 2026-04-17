#!/bin/bash
# Terminal/JSON/patch output renderer.
# Provides logging functions for all env-update output.
# shellcheck disable=SC2034  # Some vars used by callers

set -eEuo pipefail

# --------------------------------------------------------------------------
# Color support (disabled by NO_COLOR env var per https://no-color.org)
# --------------------------------------------------------------------------
_gs_eu_init_colors() {
  if [[ -z "${NO_COLOR:-}" && -t 1 ]]; then
    readonly _GS_EU_CLR_RESET='\033[0m'
    readonly _GS_EU_CLR_GREEN='\033[0;32m'
    readonly _GS_EU_CLR_YELLOW='\033[0;33m'
    readonly _GS_EU_CLR_CYAN='\033[0;36m'
    readonly _GS_EU_CLR_RED='\033[0;31m'
    readonly _GS_EU_CLR_MAGENTA='\033[0;35m'
    readonly _GS_EU_CLR_BOLD='\033[1m'
    readonly _GS_EU_CLR_DIM='\033[2m'
  else
    readonly _GS_EU_CLR_RESET=''
    readonly _GS_EU_CLR_GREEN=''
    readonly _GS_EU_CLR_YELLOW=''
    readonly _GS_EU_CLR_CYAN=''
    readonly _GS_EU_CLR_RED=''
    readonly _GS_EU_CLR_MAGENTA=''
    readonly _GS_EU_CLR_BOLD=''
    readonly _GS_EU_CLR_DIM=''
  fi
}

_gs_eu_init_colors

# --------------------------------------------------------------------------
# Report accumulators (global arrays — populated during the run)
# --------------------------------------------------------------------------
_GS_EU_REPORT_AUTO=()      # "env_var|type:id|old|new|location"
_GS_EU_REPORT_MANUAL=()    # "env_var|type:id|old|new|reason"
_GS_EU_REPORT_SKIPPED=()   # "env_var|type:id|reason"
_GS_EU_REPORT_ERRORS=()    # "env_var|type:id|msg"
_GS_EU_REPORT_NORES=()     # "env_var|type:id|detail"
_GS_EU_REPORT_UBUNTU=()    # "env_var|old|new|display"
_GS_EU_REPORT_OVERRIDE=()  # "env_var|type:id|old|new|reason"
_GS_EU_REPORT_FLOAT=()     # "env_var|type:id|ref|detail"
_GS_EU_REPORT_PREONLY=()   # "env_var|type:id|old|new"
_GS_EU_REPORT_OK=()        # "env_var|type:id|version"  (up-to-date entries)

# --------------------------------------------------------------------------
# Per-record logging
# --------------------------------------------------------------------------

# Print a pre-release hint line for a given env_var if one was recorded.
# Reads from _GS_EU_PRERELEASE_HINT_FILE (format: VARNAME:hint text).
_gs_eu_print_prerelease_hint() {
  local env_var="${1}"
  if [[ -z "${_GS_EU_PRERELEASE_HINT_FILE:-}" || ! -f "${_GS_EU_PRERELEASE_HINT_FILE}" ]]; then
    return 0
  fi
  local hint_line
  hint_line="$(grep "^${env_var}:" "${_GS_EU_PRERELEASE_HINT_FILE}" 2>/dev/null | head -1 || true)"
  if [[ -n "${hint_line}" ]]; then
    local hint_text="${hint_line#*:}"
    printf '%b\n' "        ${_GS_EU_CLR_DIM}↳ ${hint_text}${_GS_EU_CLR_RESET}"
  fi
}

# [AUTO ] — version was auto-applied
# Usage: _gs_eu_log_auto "env_var" "type:id" "old" "new" "file:line"
_gs_eu_log_auto() {
  local env_var="${1}"
  local type_id="${2}"
  local old_v="${3}"
  local new_v="${4}"
  local location="${5:-}"
  local msg
  printf -v msg "${_GS_EU_CLR_GREEN}[AUTO ]${_GS_EU_CLR_RESET} %-60s %s → %s" \
    "${type_id}" "${old_v}" "${new_v}"
  if [[ -n "${location}" ]]; then
    msg+="  ${_GS_EU_CLR_DIM}(${location})${_GS_EU_CLR_RESET}"
  fi
  printf '%b\n' "${msg}"
  _gs_eu_print_prerelease_hint "${env_var}"
  _GS_EU_REPORT_AUTO+=("${env_var}|${type_id}|${old_v}|${new_v}|${location}")
}

# [SKIP ] — unversioned/nightly/latest/edge — no check possible
# Usage: _gs_eu_log_skip "env_var" "type:id" "reason"
_gs_eu_log_skip() {
  local env_var="${1}"
  local type_id="${2}"
  local reason="${3:-unversioned}"
  local msg
  printf -v msg "${_GS_EU_CLR_DIM}[SKIP ]${_GS_EU_CLR_RESET} %-60s ${_GS_EU_CLR_DIM}(%s)${_GS_EU_CLR_RESET}" \
    "${type_id}" "${reason}"
  printf '%b\n' "${msg}"
  _gs_eu_print_prerelease_hint "${env_var}"
  _GS_EU_REPORT_SKIPPED+=("${env_var}|${type_id}|${reason}")
}

# [OK    ] — version is up to date (silent inline; shown in summary with --show-ok)
# Usage: _gs_eu_log_ok "env_var" "type:id" "version"
_gs_eu_log_ok() {
  local env_var="${1}"
  local type_id="${2}"
  local version="${3}"
  _GS_EU_REPORT_OK+=("${env_var}|${type_id}|${version}")
}

# [MANUAL] — update found but requires manual review
# Usage: _gs_eu_log_manual "env_var" "type:id" "old" "new" "reason"
_gs_eu_log_manual() {
  local env_var="${1}"
  local type_id="${2}"
  local old_v="${3}"
  local new_v="${4}"
  local reason="${5:-review required}"
  local msg
  printf -v msg "${_GS_EU_CLR_CYAN}[MANUAL]${_GS_EU_CLR_RESET} %-60s %s → %s  ${_GS_EU_CLR_DIM}(%s)${_GS_EU_CLR_RESET}" \
    "${type_id}" "${old_v}" "${new_v}" "${reason}"
  printf '%b\n' "${msg}"
  _gs_eu_print_prerelease_hint "${env_var}"
  _GS_EU_REPORT_MANUAL+=("${env_var}|${type_id}|${old_v}|${new_v}|${reason}")
}

# [HOLD ] — pre-release proposed vs stable current
# Usage: _gs_eu_log_hold "env_var" "type:id" "old" "new" "reason"
_gs_eu_log_hold() {
  local env_var="${1}"
  local type_id="${2}"
  local old_v="${3}"
  local new_v="${4}"
  local reason="${5:-pre-release: review}"
  local msg
  printf -v msg "${_GS_EU_CLR_YELLOW}[HOLD ]${_GS_EU_CLR_RESET} %-60s %s → %s  ${_GS_EU_CLR_DIM}(%s)${_GS_EU_CLR_RESET}" \
    "${type_id}" "${old_v}" "${new_v}" "${reason}"
  printf '%b\n' "${msg}"
  _gs_eu_print_prerelease_hint "${env_var}"
  _GS_EU_REPORT_MANUAL+=("${env_var}|${type_id}|${old_v}|${new_v}|${reason}")
}

# [WARN ] — API error, stale cache used
# Usage: _gs_eu_log_warn "env_var" "type:id" "message"
_gs_eu_log_warn() {
  local env_var="${1}"
  local type_id="${2}"
  local message="${3}"
  local msg
  printf -v msg "${_GS_EU_CLR_YELLOW}[WARN ]${_GS_EU_CLR_RESET} %-60s %s" \
    "${type_id}" "${message}"
  printf '%b\n' "${msg}"
  _gs_eu_print_prerelease_hint "${env_var}"
  _GS_EU_REPORT_ERRORS+=("${env_var}|${type_id}|${message}")
}

# [ERROR] — hard failure
# Usage: _gs_eu_log_error "env_var" "type:id" "message"
_gs_eu_log_error() {
  local env_var="${1}"
  local type_id="${2}"
  local message="${3}"
  local msg
  printf -v msg "${_GS_EU_CLR_RED}[ERROR]${_GS_EU_CLR_RESET} %-60s %s" \
    "${type_id}" "${message}"
  printf '%b\n' "${msg}" >&2
  _GS_EU_REPORT_ERRORS+=("${env_var}|${type_id}|${message}")
}

# [UBUNTU] — Ubuntu codename alignment
# Usage: _gs_eu_log_ubuntu "env_var" "old_version" "new_version" "applied|manual"
_gs_eu_log_ubuntu() {
  local env_var="${1}"
  local old_v="${2}"
  local new_v="${3}"
  local disposition="${4:-applied}"
  local msg
  printf -v msg "${_GS_EU_CLR_MAGENTA}[UBUNTU]${_GS_EU_CLR_RESET} %-60s %s → %s  ${_GS_EU_CLR_DIM}(%s)${_GS_EU_CLR_RESET}" \
    "${env_var}" "${old_v}" "${new_v}" "${disposition}"
  printf '%b\n' "${msg}"
  _GS_EU_REPORT_UBUNTU+=("${env_var}|${old_v}|${new_v}|${disposition}")
}

# [INFO ] — general informational message
_gs_eu_log_info() {
  local message="${1}"
  local msg
  printf -v msg "${_GS_EU_CLR_BOLD}[INFO ]${_GS_EU_CLR_RESET} %s" "${message}"
  printf '%b\n' "${msg}"
}

# [DEBUG] — only when _GS_EU_DEBUG=true
_gs_eu_log_debug() {
  if [[ "${_GS_EU_DEBUG:-false}" == "true" ]]; then
    local msg
    printf -v msg "${_GS_EU_CLR_DIM}[DEBUG]${_GS_EU_CLR_RESET} %s" "${*}"
    printf '%b\n' "${msg}" >&2
  fi
}

# [NORES] — fetch returned empty with no error (no result available)
# Usage: _gs_eu_log_nores "env_var" "type:id" "detail"
_gs_eu_log_nores() {
  local env_var="${1}"
  local type_id="${2}"
  local detail="${3:-no result from upstream}"
  local msg
  printf -v msg "${_GS_EU_CLR_YELLOW}[NORES]${_GS_EU_CLR_RESET} %-60s ${_GS_EU_CLR_DIM}(%s)${_GS_EU_CLR_RESET}" \
    "${type_id}" "${detail}"
  printf '%b\n' "${msg}"
  _gs_eu_print_prerelease_hint "${env_var}"
  _GS_EU_REPORT_NORES+=("${env_var}|${type_id}|${detail}")
}

# [PREONLY] — no stable found; newest pre-release shown for awareness
# Usage: _gs_eu_log_preonly "env_var" "type:id" "current" "pre_release_ver"
_gs_eu_log_preonly() {
  local env_var="${1}"
  local type_id="${2}"
  local old_v="${3}"
  local new_v="${4}"
  local msg
  printf -v msg "${_GS_EU_CLR_YELLOW}[PREONLY]${_GS_EU_CLR_RESET} %-58s %s → %s  ${_GS_EU_CLR_DIM}(no stable found — pre-release only)${_GS_EU_CLR_RESET}" \
    "${type_id}" "${old_v}" "${new_v}"
  printf '%b\n' "${msg}"
  _gs_eu_print_prerelease_hint "${env_var}"
  _GS_EU_REPORT_PREONLY+=("${env_var}|${type_id}|${old_v}|${new_v}")
}

# [FLOAT] — floating version ref (master/latest/nightly/next/main/HEAD) — always current by definition
# Usage: _gs_eu_log_float "env_var" "type:id" "floating_ref" "detail"
_gs_eu_log_float() {
  local env_var="${1}"
  local type_id="${2}"
  local ref="${3}"
  local detail="${4:-floating ref — always latest}"
  local msg
  printf -v msg "${_GS_EU_CLR_DIM}[FLOAT]${_GS_EU_CLR_RESET} %-60s ${_GS_EU_CLR_DIM}tracks '%s' (%s)${_GS_EU_CLR_RESET}" \
    "${type_id}" "${ref}" "${detail}"
  printf '%b\n' "${msg}"
  _GS_EU_REPORT_FLOAT+=("${env_var}|${type_id}|${ref}|${detail}")
}

# [OVRRD] — version is pinned override — fetched for visibility but never applied
# Usage: _gs_eu_log_override "env_var" "type:id" "current" "latest" "reason"
# Suppresses output entirely when current==proposed AND no hint exists (nothing useful to show).
_gs_eu_log_override() {
  local env_var="${1}" type_id="${2}" old_v="${3}" new_v="${4}" reason="${5:-overridden — not applied}"

  # Check for hint before deciding to suppress
  local _hint_line=""
  if [[ -n "${_GS_EU_PRERELEASE_HINT_FILE:-}" && -f "${_GS_EU_PRERELEASE_HINT_FILE}" ]]; then
    _hint_line="$(grep "^${env_var}:" "${_GS_EU_PRERELEASE_HINT_FILE}" 2>/dev/null | head -1 || true)"
  fi

  # Suppress: no change in version AND no hint to show
  if [[ "${old_v}" == "${new_v}" && -z "${_hint_line}" ]]; then
    return 0
  fi

  local msg
  printf -v msg "${_GS_EU_CLR_BOLD}${_GS_EU_CLR_RED}[OVRRD]${_GS_EU_CLR_RESET} %-60s current=%-20s latest=%-20s  ${_GS_EU_CLR_DIM}(%s)${_GS_EU_CLR_RESET}" \
    "${type_id}" "${old_v}" "${new_v}" "${reason}"
  printf '%b\n' "${msg}"
  _gs_eu_print_prerelease_hint "${env_var}"
  _GS_EU_REPORT_OVERRIDE+=("${env_var}|${type_id}|${old_v}|${new_v}|${reason}")
}

# --------------------------------------------------------------------------
# Delta label helper: returns colored "[major]" / "[minor]" / "[patch]"
# --------------------------------------------------------------------------
_gs_eu_delta_label() {
  local old="${1}" new="${2}"
  local delta
  delta="$(_gs_eu_semver_delta_type "${old}" "${new}" 2>/dev/null || echo "unknown")"
  case "${delta}" in
    major) printf '%b' "  ${_GS_EU_CLR_RED}[major]${_GS_EU_CLR_RESET}" ;;
    minor) printf '%b' "  ${_GS_EU_CLR_YELLOW}[minor]${_GS_EU_CLR_RESET}" ;;
    patch) printf '%b' "  ${_GS_EU_CLR_DIM}[patch]${_GS_EU_CLR_RESET}" ;;
  esac
}

# --------------------------------------------------------------------------
# End-of-run summary
# --------------------------------------------------------------------------
_gs_eu_print_summary() {
  local patch_file="${1:-}"
  local report_file="${2:-}"

  printf '\n%b\n' "${_GS_EU_CLR_BOLD}════════════════════════════════════════════════════════════════${_GS_EU_CLR_RESET}"
  printf '%b\n' "${_GS_EU_CLR_BOLD}  ENV-UPDATES SUMMARY${_GS_EU_CLR_RESET}"
  printf '%b\n' "${_GS_EU_CLR_BOLD}════════════════════════════════════════════════════════════════${_GS_EU_CLR_RESET}"

  # OVERRIDES — PINNED MANUAL REVIEW (shown first, in red/bold)
  if [[ ${#_GS_EU_REPORT_OVERRIDE[@]} -gt 0 ]]; then
    printf '\n%b\n' "${_GS_EU_CLR_BOLD}${_GS_EU_CLR_RED}OVERRIDES — PINNED MANUAL REVIEW (${#_GS_EU_REPORT_OVERRIDE[@]}):${_GS_EU_CLR_RESET}"
    printf '%b\n' "${_GS_EU_CLR_DIM}  These versions are intentionally held. Review before unpinning.${_GS_EU_CLR_RESET}"
    local -A _ov_seen=() _ov_first=() _ov_also=()
    local _ov_keys=() entry
    for entry in "${_GS_EU_REPORT_OVERRIDE[@]}"; do
      IFS='|' read -r ev ti ov nv reason <<< "${entry}"
      if [[ -z "${_ov_seen[${ti}]:-}" ]]; then
        _ov_seen["${ti}"]="1"; _ov_first["${ti}"]="${entry}"; _ov_keys+=("${ti}")
      else
        _ov_also["${ti}"]+=" ${ev}"
      fi
    done
    for ti in "${_ov_keys[@]}"; do
      IFS='|' read -r ev ti2 ov nv reason <<< "${_ov_first[${ti}]}"
      printf '  %b%-50s%b  %s → %s%b  (%s)\n' "${_GS_EU_CLR_RED}" "${ti}" "${_GS_EU_CLR_RESET}" \
        "${ov}" "${nv}" "$(_gs_eu_delta_label "${ov}" "${nv}")" "${reason}"
      [[ -n "${_ov_also[${ti}]:-}" ]] && \
        printf '    %b+ also: %s%b\n' "${_GS_EU_CLR_DIM}" "${_ov_also[${ti}]# }" "${_GS_EU_CLR_RESET}"
      _gs_eu_print_prerelease_hint "${ev}"
    done
  fi

  # AUTO-APPLIED
  if [[ ${#_GS_EU_REPORT_AUTO[@]} -gt 0 ]]; then
    printf '\n%b\n' "${_GS_EU_CLR_GREEN}AUTO-APPLIED (${#_GS_EU_REPORT_AUTO[@]}):${_GS_EU_CLR_RESET}"
    local -A _au_seen=() _au_first=() _au_also=()
    local _au_keys=() entry
    for entry in "${_GS_EU_REPORT_AUTO[@]}"; do
      IFS='|' read -r ev ti ov nv loc <<< "${entry}"
      if [[ -z "${_au_seen[${ti}]:-}" ]]; then
        _au_seen["${ti}"]="1"; _au_first["${ti}"]="${entry}"; _au_keys+=("${ti}")
      else
        _au_also["${ti}"]+=" ${ev}"
      fi
    done
    for ti in "${_au_keys[@]}"; do
      IFS='|' read -r ev ti2 ov nv loc <<< "${_au_first[${ti}]}"
      printf '  %b%-50s%b  %s → %s%b\n' "${_GS_EU_CLR_GREEN}" "${ti}" "${_GS_EU_CLR_RESET}" \
        "${ov}" "${nv}" "$(_gs_eu_delta_label "${ov}" "${nv}")"
      [[ -n "${_au_also[${ti}]:-}" ]] && \
        printf '    %b+ also: %s%b\n' "${_GS_EU_CLR_DIM}" "${_au_also[${ti}]# }" "${_GS_EU_CLR_RESET}"
      if [[ "${_GS_EU_SHOW_RUNTIME:-false}" == "true" ]]; then
        local _rt; _rt="$(_gs_eu_derive_runtime "${ev}" 2>/dev/null || true)"
        [[ -n "${_rt}" ]] && printf '        %b↳ env: %s%b\n' "${_GS_EU_CLR_DIM}" "${_rt//:/ }" "${_GS_EU_CLR_RESET}"
      fi
      _gs_eu_print_prerelease_hint "${ev}"
    done
  fi

  # UBUNTU CODENAME ALIGNMENT (no dedup needed — each var has unique codename context)
  if [[ ${#_GS_EU_REPORT_UBUNTU[@]} -gt 0 ]]; then
    printf '\n%b\n' "${_GS_EU_CLR_MAGENTA}UBUNTU CODENAME ALIGNMENT (${#_GS_EU_REPORT_UBUNTU[@]}):${_GS_EU_CLR_RESET}"
    local entry
    for entry in "${_GS_EU_REPORT_UBUNTU[@]}"; do
      IFS='|' read -r ev ov nv disp <<< "${entry}"
      printf '  %b%-50s%b  %s → %s  (%s)\n' "${_GS_EU_CLR_MAGENTA}" "${ev}" "${_GS_EU_CLR_RESET}" "${ov}" "${nv}" "${disp}"
    done
  fi

  # MANUAL REVIEW REQUIRED
  if [[ ${#_GS_EU_REPORT_MANUAL[@]} -gt 0 ]]; then
    printf '\n%b\n' "${_GS_EU_CLR_CYAN}MANUAL REVIEW REQUIRED (${#_GS_EU_REPORT_MANUAL[@]}):${_GS_EU_CLR_RESET}"
    local -A _mn_seen=() _mn_first=() _mn_also=()
    local _mn_keys=() entry
    for entry in "${_GS_EU_REPORT_MANUAL[@]}"; do
      IFS='|' read -r ev ti ov nv reason <<< "${entry}"
      if [[ -z "${_mn_seen[${ti}]:-}" ]]; then
        _mn_seen["${ti}"]="1"; _mn_first["${ti}"]="${entry}"; _mn_keys+=("${ti}")
      else
        _mn_also["${ti}"]+=" ${ev}"
      fi
    done
    for ti in "${_mn_keys[@]}"; do
      IFS='|' read -r ev ti2 ov nv reason <<< "${_mn_first[${ti}]}"
      printf '  %b%-50s%b  %s → %s%b  (%s)\n' "${_GS_EU_CLR_CYAN}" "${ti}" "${_GS_EU_CLR_RESET}" \
        "${ov}" "${nv}" "$(_gs_eu_delta_label "${ov}" "${nv}")" "${reason}"
      [[ -n "${_mn_also[${ti}]:-}" ]] && \
        printf '    %b+ also: %s%b\n' "${_GS_EU_CLR_DIM}" "${_mn_also[${ti}]# }" "${_GS_EU_CLR_RESET}"
      if [[ "${_GS_EU_SHOW_RUNTIME:-false}" == "true" ]]; then
        local _rt; _rt="$(_gs_eu_derive_runtime "${ev}" 2>/dev/null || true)"
        [[ -n "${_rt}" ]] && printf '        %b↳ env: %s%b\n' "${_GS_EU_CLR_DIM}" "${_rt//:/ }" "${_GS_EU_CLR_RESET}"
      fi
      _gs_eu_print_prerelease_hint "${ev}"
    done
  fi

  # SKIPPED
  if [[ ${#_GS_EU_REPORT_SKIPPED[@]} -gt 0 ]]; then
    printf '\n%b\n' "${_GS_EU_CLR_DIM}SKIPPED (${#_GS_EU_REPORT_SKIPPED[@]}):${_GS_EU_CLR_RESET}"
    local -A _sk_seen=() _sk_first=() _sk_also=()
    local _sk_keys=() entry
    for entry in "${_GS_EU_REPORT_SKIPPED[@]}"; do
      IFS='|' read -r ev ti reason <<< "${entry}"
      if [[ -z "${_sk_seen[${ti}]:-}" ]]; then
        _sk_seen["${ti}"]="1"; _sk_first["${ti}"]="${entry}"; _sk_keys+=("${ti}")
      else
        _sk_also["${ti}"]+=" ${ev}"
      fi
    done
    for ti in "${_sk_keys[@]}"; do
      IFS='|' read -r ev ti2 reason <<< "${_sk_first[${ti}]}"
      printf '  %b%-50s%b  (%s)\n' "${_GS_EU_CLR_DIM}" "${ti}" "${_GS_EU_CLR_RESET}" "${reason}"
      [[ -n "${_sk_also[${ti}]:-}" ]] && \
        printf '    %b+ also: %s%b\n' "${_GS_EU_CLR_DIM}" "${_sk_also[${ti}]# }" "${_GS_EU_CLR_RESET}"
      _gs_eu_print_prerelease_hint "${ev}"
    done
  fi

  # FLOATING REFS
  if [[ ${#_GS_EU_REPORT_FLOAT[@]} -gt 0 ]]; then
    printf '\n%b\n' "${_GS_EU_CLR_DIM}FLOATING REFS (${#_GS_EU_REPORT_FLOAT[@]}):${_GS_EU_CLR_RESET}"
    local -A _fl_seen=() _fl_first=() _fl_also=()
    local _fl_keys=() entry
    for entry in "${_GS_EU_REPORT_FLOAT[@]}"; do
      IFS='|' read -r ev ti ref detail <<< "${entry}"
      if [[ -z "${_fl_seen[${ti}]:-}" ]]; then
        _fl_seen["${ti}"]="1"; _fl_first["${ti}"]="${entry}"; _fl_keys+=("${ti}")
      else
        _fl_also["${ti}"]+=" ${ev}"
      fi
    done
    for ti in "${_fl_keys[@]}"; do
      IFS='|' read -r ev ti2 ref detail <<< "${_fl_first[${ti}]}"
      printf '  %b%-50s%b  tracks '"'"'%s'"'"'  (%s)\n' "${_GS_EU_CLR_DIM}" "${ti}" "${_GS_EU_CLR_RESET}" "${ref}" "${detail}"
      [[ -n "${_fl_also[${ti}]:-}" ]] && \
        printf '    %b+ also: %s%b\n' "${_GS_EU_CLR_DIM}" "${_fl_also[${ti}]# }" "${_GS_EU_CLR_RESET}"
      _gs_eu_print_prerelease_hint "${ev}"
    done
  fi

  # PRE-RELEASE ONLY (no stable found — newer pre-release available)
  if [[ ${#_GS_EU_REPORT_PREONLY[@]} -gt 0 ]]; then
    printf '\n%b\n' "${_GS_EU_CLR_YELLOW}── PRE-RELEASE ONLY — no stable found (${#_GS_EU_REPORT_PREONLY[@]}):${_GS_EU_CLR_RESET}"
    printf '%b\n' "${_GS_EU_CLR_DIM}  No stable release available; newer pre-release shown for awareness.${_GS_EU_CLR_RESET}"
    local -A _po_seen=() _po_first=() _po_also=()
    local _po_keys=() entry
    for entry in "${_GS_EU_REPORT_PREONLY[@]}"; do
      IFS='|' read -r ev ti ov nv <<< "${entry}"
      if [[ -z "${_po_seen[${ti}]:-}" ]]; then
        _po_seen["${ti}"]="1"; _po_first["${ti}"]="${entry}"; _po_keys+=("${ti}")
      else
        _po_also["${ti}"]+=" ${ev}"
      fi
    done
    for ti in "${_po_keys[@]}"; do
      IFS='|' read -r ev ti2 ov nv <<< "${_po_first[${ti}]}"
      printf '  %b%-50s%b  %s → %s\n' "${_GS_EU_CLR_YELLOW}" "${ti}" "${_GS_EU_CLR_RESET}" "${ov}" "${nv}"
      [[ -n "${_po_also[${ti}]:-}" ]] && \
        printf '    %b+ also: %s%b\n' "${_GS_EU_CLR_DIM}" "${_po_also[${ti}]# }" "${_GS_EU_CLR_RESET}"
      _gs_eu_print_prerelease_hint "${ev}"
    done
  fi

  # NO RESULT (empty response, no error recorded)
  if [[ ${#_GS_EU_REPORT_NORES[@]} -gt 0 ]]; then
    printf '\n%b\n' "${_GS_EU_CLR_YELLOW}NO RESULT (${#_GS_EU_REPORT_NORES[@]}):${_GS_EU_CLR_RESET}"
    local -A _nr_seen=() _nr_first=() _nr_also=()
    local _nr_keys=() entry
    for entry in "${_GS_EU_REPORT_NORES[@]}"; do
      IFS='|' read -r ev ti detail <<< "${entry}"
      if [[ -z "${_nr_seen[${ti}]:-}" ]]; then
        _nr_seen["${ti}"]="1"; _nr_first["${ti}"]="${entry}"; _nr_keys+=("${ti}")
      else
        _nr_also["${ti}"]+=" ${ev}"
      fi
    done
    for ti in "${_nr_keys[@]}"; do
      IFS='|' read -r ev ti2 detail <<< "${_nr_first[${ti}]}"
      printf '  %b%-50s%b  (%s)\n' "${_GS_EU_CLR_YELLOW}" "${ti}" "${_GS_EU_CLR_RESET}" "${detail}"
      [[ -n "${_nr_also[${ti}]:-}" ]] && \
        printf '    %b+ also: %s%b\n' "${_GS_EU_CLR_DIM}" "${_nr_also[${ti}]# }" "${_GS_EU_CLR_RESET}"
    done
  fi

  # ERRORS
  if [[ ${#_GS_EU_REPORT_ERRORS[@]} -gt 0 ]]; then
    printf '\n%b\n' "${_GS_EU_CLR_RED}ERRORS (${#_GS_EU_REPORT_ERRORS[@]}):${_GS_EU_CLR_RESET}"
    local entry
    for entry in "${_GS_EU_REPORT_ERRORS[@]}"; do
      IFS='|' read -r ev ti msg <<< "${entry}"
      printf '  %b%-50s%b  %s\n' "${_GS_EU_CLR_RED}" "${ti}" "${_GS_EU_CLR_RESET}" "${msg}"
    done
  fi

  # UP TO DATE (only shown with --show-ok)
  if [[ "${_GS_EU_SHOW_OK:-false}" == "true" && ${#_GS_EU_REPORT_OK[@]} -gt 0 ]]; then
    printf '\n%b\n' "${_GS_EU_CLR_DIM}UP TO DATE (${#_GS_EU_REPORT_OK[@]}):${_GS_EU_CLR_RESET}"
    local -A _ok_seen=() _ok_first=() _ok_also=()
    local _ok_keys=() entry
    for entry in "${_GS_EU_REPORT_OK[@]}"; do
      IFS='|' read -r ev ti ver <<< "${entry}"
      if [[ -z "${_ok_seen[${ti}]:-}" ]]; then
        _ok_seen["${ti}"]="1"; _ok_first["${ti}"]="${entry}"; _ok_keys+=("${ti}")
      else
        _ok_also["${ti}"]+=" ${ev}"
      fi
    done
    for ti in "${_ok_keys[@]}"; do
      IFS='|' read -r ev ti2 ver <<< "${_ok_first[${ti}]}"
      printf '  %b✓ %-50s%b  %s\n' "${_GS_EU_CLR_DIM}" "${ti}" "${_GS_EU_CLR_RESET}" "${ver}"
      [[ -n "${_ok_also[${ti}]:-}" ]] && \
        printf '    %b+ also: %s%b\n' "${_GS_EU_CLR_DIM}" "${_ok_also[${ti}]# }" "${_GS_EU_CLR_RESET}"
    done
  fi

  printf '\n'
  if [[ -n "${patch_file}" && -f "${patch_file}" ]]; then
    printf '%b\n' "${_GS_EU_CLR_BOLD}Patch file:${_GS_EU_CLR_RESET}  ${patch_file}"
  fi
  if [[ -n "${report_file}" && -f "${report_file}" ]]; then
    printf '%b\n' "${_GS_EU_CLR_BOLD}JSON report:${_GS_EU_CLR_RESET} ${report_file}"
  fi
  printf '\n'
}

# --------------------------------------------------------------------------
# JSON report builder
# --------------------------------------------------------------------------
_gs_eu_write_json_report() {
  local output_file="${1}"
  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  {
    printf '{\n'
    printf '  "generated_at": "%s",\n' "${timestamp}"

    # overrides
    printf '  "overrides": [\n'
    local i=0
    for entry in "${_GS_EU_REPORT_OVERRIDE[@]:-}"; do
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
    for entry in "${_GS_EU_REPORT_AUTO[@]:-}"; do
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
    for entry in "${_GS_EU_REPORT_MANUAL[@]:-}"; do
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
    for entry in "${_GS_EU_REPORT_SKIPPED[@]:-}"; do
      [[ -z "${entry}" ]] && continue
      IFS='|' read -r ev ti reason <<< "${entry}"
      [[ ${i} -gt 0 ]] && printf ',\n'
      printf '    {"env_var":"%s","type_id":"%s","reason":"%s"}' \
        "${ev}" "${ti}" "${reason}"
      (( i++ )) || true
    done
    printf '\n  ],\n'

    # floating refs
    printf '  "floating_refs": [\n'
    i=0
    for entry in "${_GS_EU_REPORT_FLOAT[@]:-}"; do
      [[ -z "${entry}" ]] && continue
      IFS='|' read -r ev ti ref detail <<< "${entry}"
      [[ ${i} -gt 0 ]] && printf ',\n'
      printf '    {"env_var":"%s","type_id":"%s","ref":"%s","detail":"%s"}' \
        "${ev}" "${ti}" "${ref}" "${detail}"
      (( i++ )) || true
    done
    printf '\n  ],\n'

    # no-result
    printf '  "no_result": [\n'
    i=0
    for entry in "${_GS_EU_REPORT_NORES[@]:-}"; do
      [[ -z "${entry}" ]] && continue
      IFS='|' read -r ev ti detail <<< "${entry}"
      [[ ${i} -gt 0 ]] && printf ',\n'
      printf '    {"env_var":"%s","type_id":"%s","detail":"%s"}' \
        "${ev}" "${ti}" "${detail}"
      (( i++ )) || true
    done
    printf '\n  ],\n'

    # errors
    printf '  "errors": [\n'
    i=0
    for entry in "${_GS_EU_REPORT_ERRORS[@]:-}"; do
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
