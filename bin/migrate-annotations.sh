#!/bin/bash
# migrate-annotations.sh — One-shot migration of legacy @todo check-updates
# annotations in .env to the new unified type:identifier format.
#
# Usage:
#   bin/migrate-annotations.sh [OPTIONS]
#
# Options:
#   --dry-run    Show what would change, don't modify
#   --no-backup  Skip creating .env.bak (default: backup is created)
#   --help

set -eEuo pipefail

# --------------------------------------------------------------------------
# Script location
# --------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly STACK_DIR
LIB_DIR="${SCRIPT_DIR}/lib/check-updates"
readonly LIB_DIR
ENV_FILE="${STACK_DIR}/.env"
readonly ENV_FILE

# --------------------------------------------------------------------------
# Source required libraries
# --------------------------------------------------------------------------
# shellcheck source=lib/check-updates/core/report.sh
source "${LIB_DIR}/core/report.sh"
# shellcheck source=lib/check-updates/config/type_map.sh
source "${LIB_DIR}/config/type_map.sh"
# shellcheck source=lib/check-updates/config/codename_map.sh
source "${LIB_DIR}/config/codename_map.sh"

# --------------------------------------------------------------------------
# Defaults
# --------------------------------------------------------------------------
MIGRATE_DRY_RUN="false"
MIGRATE_BACKUP="true"

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
_show_help() {
  cat <<'EOF'
bin/migrate-annotations.sh — Migrate legacy .env annotations to new format

Usage:
  bin/migrate-annotations.sh [OPTIONS]

Options:
  --dry-run    Show what would change, don't modify .env
  --no-backup  Skip creating .env.bak (default: backup is created)
  --help       Show this help

This script rewrites all @todo check-updates annotations in .env from the
legacy URL-based format to the new structured type:identifier format.

Example transformations:
  Before: # @todo check-updates axllent/mailpit https://hub.docker.com/r/axllent/mailpit/tags v1.29.3
  After:  # @todo check-updates dockerhub:axllent/mailpit v1.29.3

  Before: # @todo check-updates https://github.com/golang/go/tags 1.26.1
  After:  # @todo check-updates github:golang/go 1.26.1

  Before: # @todo (override) check-updates dpage/pgadmin4 https://hub.docker.com/r/dpage/pgadmin4/tags 9.13.0
  After:  # @todo check-updates (override) dockerhub:dpage/pgadmin4 9.13.0
EOF
}

_parse_args() {
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --dry-run)   MIGRATE_DRY_RUN="true" ;;
      --no-backup) MIGRATE_BACKUP="false" ;;
      --help)      _show_help; exit 0 ;;
      *)
        printf 'Unknown option: %s\n' "${arg}" >&2
        _show_help >&2
        exit 1
        ;;
    esac
  done
}

# --------------------------------------------------------------------------
# Migration transformation functions
# --------------------------------------------------------------------------

# Given a raw annotation line, produce the migrated version.
# Returns the new line (echoed) or empty if no migration needed/possible.
_migrate_annotation_line() {
  local line="${1}"
  # Must contain @todo ... check-updates
  if [[ ! "${line}" =~ @todo.*check-updates ]]; then
    echo "${line}"
    return 0
  fi

  # Already in new format? Check for type:identifier pattern after check-updates
  # A new-format annotation has "check-updates" followed (optionally by flags) then type:id
  # Detect by presence of a word like "dockerhub:", "github:", "npm:", etc. after check-updates
  if [[ "${line}" =~ check-updates.*[[:space:]](dockerhub|quay|github|npm|pecl|pecl-git|sdkman|sdkmanager|pypi|url): ]]; then
    _log_debug "Already migrated: ${line}"
    echo "${line}"
    return 0
  fi

  # Extract leading whitespace + comment prefix
  local prefix=""
  if [[ "${line}" =~ ^([[:space:]]*#[[:space:]]*) ]]; then
    prefix="${BASH_REMATCH[1]}"
  fi

  # Extract everything after the comment prefix
  local content="${line#"${prefix}"}"

  # Extract @todo prefix and anything before check-updates
  local todo_prefix=""
  local check_updates_content=""

  if [[ "${content}" =~ ^(@todo[[:space:]]+)(.*)$ ]]; then
    todo_prefix="${BASH_REMATCH[1]}"
    check_updates_content="${BASH_REMATCH[2]}"
  fi

  # Extract flags in parens before or after check-updates
  local flags=""
  local remaining="${check_updates_content}"

  # Pattern stored in variable to avoid bash ERE issues with literal parens
  local _flag_re
  _flag_re='^[(]([^)]+)[)][[:space:]]*(.*)'  
  # Handle flags before check-updates keyword: "@todo (override) check-updates ..."
  while [[ "${remaining}" =~ ${_flag_re} ]]; do
    local flag_val="${BASH_REMATCH[1]}"
    remaining="${BASH_REMATCH[2]}"
    # normalize: lowercase, strip "overriden" → "override"
    flag_val="${flag_val,,}"
    flag_val="${flag_val//overriden/override}"
    flag_val="${flag_val//overridden/override}"
    flags+="(${flag_val}) "
  done

  # Strip "check-updates" keyword
  remaining="${remaining#check-updates}"
  remaining="${remaining# }"

  # Handle flags after check-updates keyword too
  while [[ "${remaining}" =~ ${_flag_re} ]]; do
    local flag_val="${BASH_REMATCH[1]}"
    remaining="${BASH_REMATCH[2]}"
    flag_val="${flag_val,,}"
    flag_val="${flag_val//overriden/override}"
    flag_val="${flag_val//overridden/override}"
    flags+="(${flag_val}) "
  done
  flags="${flags% }"

  # Now remaining is: [optional-name] <url(s)> <version>  OR  <sdkman-ref> <version>
  # Special case: sdkman variable references like "GLOBAL_STACK_JAVA11_INSTALL_PACKAGE_GRADLE_VX1_VERSION 9.4.0"
  # Special case: android sdkmanager references like "sdkmanager --sdk_root=... --list | grep build-tools -- 37.0.0-rc2"

  # Check for sdkmanager pattern first
  if [[ "${remaining}" =~ sdkmanager.*grep[[:space:]]+([^[:space:]|-]+)[[:space:]]*--[[:space:]]*([^[:space:]]+) ]]; then
    local component="${BASH_REMATCH[1]}"
    local version="${BASH_REMATCH[2]}"
    local flags_str=""
    [[ -n "${flags}" ]] && flags_str="${flags} "
    printf '%s%scheck-updates %ssdkmanager:%s %s\n' \
      "${prefix}" "${todo_prefix}" "${flags_str}" "${component}" "${version}"
    return 0
  fi

  # Check for SDKMAN variable reference pattern
  if [[ "${remaining}" =~ ^(GLOBAL_STACK_[A-Z0-9_]+_INSTALL_PACKAGE_([A-Z_]+)_(VX[0-9]+_)?VERSION)[[:space:]]+([^[:space:]]+) ]]; then
    local var_ref="${BASH_REMATCH[1]}"
    local candidate_upper="${BASH_REMATCH[2]}"
    local vx_part="${BASH_REMATCH[3]}"
    local version="${BASH_REMATCH[4]}"
    local candidate="${candidate_upper,,}"
    local major="${version%%.*}"
    local type_id_str="sdkman:${candidate}"
    [[ -n "${vx_part}" ]] && type_id_str="sdkman:${candidate}:${major}"
    local flags_str=""
    [[ -n "${flags}" ]] && flags_str="${flags} "
    printf '%s%scheck-updates %s%s %s\n' \
      "${prefix}" "${todo_prefix}" "${flags_str}" "${type_id_str}" "${version}"
    return 0
  fi

  # Android SDK URL pattern
  if [[ "${remaining}" =~ ^https://developer\.android\.com/studio[[:space:]]+([0-9]+) ]]; then
    local version="${BASH_REMATCH[1]}"
    local flags_str=""
    [[ -n "${flags}" ]] && flags_str="${flags} "
    printf '%s%scheck-updates %surl:https://developer.android.com/studio %s\n' \
      "${prefix}" "${todo_prefix}" "${flags_str}" "${version}"
    return 0
  fi

  # Tokenize remaining into parts
  local tokens=()
  # shellcheck disable=SC2207
  read -ra tokens <<< "${remaining}"

  if [[ ${#tokens[@]} -lt 2 ]]; then
    # Cannot migrate — not enough tokens
    echo "${line}"
    return 0
  fi

  # The last token should be the version
  local version="${tokens[${#tokens[@]}-1]}"

  # Check if version looks like a hint "(php >= 8.5.0)" — if so, second-to-last is version
  local hint=""
  if [[ "${version}" == *")"* || "${version}" == *"("* ]]; then
    # Version is probably embedded in hint text — skip migration of these complex cases
    echo "${line}"
    return 0
  fi

  # Collect URLs from middle tokens
  local urls=()
  local bare_names=()
  local i
  for (( i=0; i<${#tokens[@]}-1; i++ )); do
    local tok="${tokens[${i}]}"
    if [[ "${tok}" =~ ^https?:// ]]; then
      urls+=("${tok}")
    elif [[ "${tok}" =~ ^http:// ]]; then
      urls+=("${tok}")
    else
      bare_names+=("${tok}")
    fi
  done

  # Determine type:id
  local type_id=""

  if [[ ${#urls[@]} -gt 0 ]]; then
    # Use best URL
    local best_url="${urls[0]}"
    local u
    for u in "${urls[@]}"; do
      case "${u}" in
        *hub.docker.com*|*quay.io*|*pecl.php.net*|*pypi.org*|*npmjs.com*)
          best_url="${u}"
          break
          ;;
      esac
    done
    type_id="$(_infer_type_from_url "${best_url}" "${version}")"
  elif [[ ${#bare_names[@]} -gt 0 ]]; then
    # Bare name — try to detect sdkman/sdkmanager from context
    local name="${bare_names[0]}"
    # Check if it looks like an sdkman candidate (lowercase simple name)
    if [[ "${name}" =~ ^[a-z][a-z0-9_-]+$ ]]; then
      type_id="sdkman:${name}"
    else
      type_id="url:${name}"
    fi
  else
    echo "${line}"
    return 0
  fi

  # Handle pecl special case: URLs with multiple URLs — PECL + github
  # e.g. "https://pecl.php.net/package/zmq 1.1.3 beta"
  # The hint part (e.g. "beta") needs to be handled
  # For pecl: type_id = "pecl:ext" but version might have "stable/beta" appended
  # The version is the first numeric-looking token from the end
  local clean_version="${version}"
  local hint_candidate=""
  # If there's one more token after the numeric version that looks like stability info,
  # it's actually part of the annotation text (the .env has those as separate tokens)
  # Example: https://pecl.php.net/package/amqp 2.2.0 stable (php >= php 7.4.0)
  # Here version="2.2.0" is already last (we stopped before "stable")
  # But if stable/beta is the last token, we need to adjust

  if [[ "${#tokens[@]}" -ge 3 ]]; then
    local last_tok="${tokens[${#tokens[@]}-1]}"
    local second_last="${tokens[${#tokens[@]}-2]}"
    if [[ "${last_tok}" =~ ^(stable|beta|alpha)$ && "${second_last}" =~ ^[0-9] ]]; then
      version="${second_last}"
      hint_candidate="${last_tok}"
    fi
  fi

  # Build migrated line
  local flags_str=""
  [[ -n "${flags}" ]] && flags_str="${flags} "

  local hint_str=""
  if [[ -n "${hint_candidate}" ]]; then
    hint_str=" (${hint_candidate})"
  fi

  printf '%s%scheck-updates %s%s %s%s\n' \
    "${prefix}" "${todo_prefix}" "${flags_str}" "${type_id}" "${version}" "${hint_str}"
}

# --------------------------------------------------------------------------
# Main migration logic
# --------------------------------------------------------------------------
_run_migration() {
  local line_number=0
  local changed_count=0
  local unchanged_count=0

  # Arrays to collect changes for dry-run reporting
  local original_lines=()
  local migrated_lines=()
  local change_line_numbers=()

  while IFS= read -r line || [[ -n "${line}" ]]; do
    (( line_number++ )) || true

    # Only process annotation lines
    if [[ "${line}" =~ @todo.*check-updates ]]; then
      local migrated
      migrated="$(_migrate_annotation_line "${line}")"

      if [[ "${migrated}" != "${line}" ]]; then
        original_lines+=("${line}")
        migrated_lines+=("${migrated}")
        change_line_numbers+=("${line_number}")
        (( changed_count++ )) || true
        _log_debug "Line ${line_number} migrated"
      else
        (( unchanged_count++ )) || true
      fi
    fi
  done < "${ENV_FILE}"

  if [[ "${MIGRATE_DRY_RUN}" == "true" ]]; then
    _print_dry_run_report "${#change_line_numbers[@]}" \
      "${original_lines[@]+"${original_lines[@]}"}" \
      "${migrated_lines[@]+"${migrated_lines[@]}"}" \
      "${change_line_numbers[@]+"${change_line_numbers[@]}"}"
    return 0
  fi

  if [[ "${changed_count}" -eq 0 ]]; then
    printf 'No annotations need migration.\n'
    return 0
  fi

  # Create backup
  if [[ "${MIGRATE_BACKUP}" == "true" ]]; then
    cp "${ENV_FILE}" "${ENV_FILE}.bak"
    printf 'Backup created: %s.bak\n' "${ENV_FILE}"
  fi

  # Apply changes in-place using a temp file
  local tmpfile
  tmpfile="$(mktemp)"
  local current_line=0
  local change_idx=0

  while IFS= read -r line || [[ -n "${line}" ]]; do
    (( current_line++ )) || true

    # Check if this line number needs migration
    local needs_change="false"
    local k
    for (( k=0; k<${#change_line_numbers[@]}; k++ )); do
      if [[ "${change_line_numbers[${k}]}" -eq "${current_line}" ]]; then
        printf '%s\n' "${migrated_lines[${k}]}" >> "${tmpfile}"
        needs_change="true"
        break
      fi
    done

    if [[ "${needs_change}" == "false" ]]; then
      printf '%s\n' "${line}" >> "${tmpfile}"
    fi
  done < "${ENV_FILE}"

  mv "${tmpfile}" "${ENV_FILE}"

  printf 'Migration complete: %d annotations updated, %d already in new format.\n' \
    "${changed_count}" "${unchanged_count}"
}

_print_dry_run_report() {
  local count="${1}"
  shift

  printf '%b\n' "${CU_CLR_BOLD}=== DRY-RUN: Migration Preview ===${CU_CLR_RESET}"
  printf '%d annotation(s) would be migrated:\n\n' "${count}"

  if [[ ${count} -eq 0 ]]; then
    printf 'No annotations need migration.\n'
    return 0
  fi

  # We passed arrays in a concatenated form — split them back
  # Since arrays were passed as positional args, they're all flattened
  # We need the three arrays to be passed separately
  # Re-read from file in dry-run mode with proper counting
  local line_number=0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    (( line_number++ )) || true
    if [[ "${line}" =~ @todo.*check-updates ]]; then
      local migrated
      migrated="$(_migrate_annotation_line "${line}")"
      if [[ "${migrated}" != "${line}" ]]; then
        printf '%b  Line %d:\n' "${CU_CLR_DIM}" "${line_number}"
        printf '  %bBEFORE:%b %s\n' "${CU_CLR_RED}" "${CU_CLR_RESET}" "${line}"
        printf '  %bAFTER: %b %s\n' "${CU_CLR_GREEN}" "${CU_CLR_RESET}" "${migrated}"
        printf '\n'
      fi
    fi
  done < "${ENV_FILE}"
}

# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------
main() {
  _parse_args "$@"

  if [[ ! -f "${ENV_FILE}" ]]; then
    printf 'ERROR: .env file not found at %s\n' "${ENV_FILE}" >&2
    exit 1
  fi

  _log_info "Migrating annotations in: ${ENV_FILE}"
  if [[ "${MIGRATE_DRY_RUN}" == "true" ]]; then
    _log_info "DRY-RUN mode — no files will be modified"
  fi

  _run_migration
}

main "$@"
