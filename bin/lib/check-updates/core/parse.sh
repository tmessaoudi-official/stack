#!/bin/bash
# .env annotation parser — state machine reading line by line.
# Produces structured records from @todo check-updates annotations.
#
# Record fields (all stored in parallel arrays indexed by CU_RECORD_COUNT):
#   CU_RECORDS_ENV_VAR[]        env variable name
#   CU_RECORDS_CURRENT_VERSION[]  current value from .env
#   CU_RECORDS_TYPE[]           fetcher type (dockerhub, github, npm, ...)
#   CU_RECORDS_IDENTIFIER[]     type-specific identifier
#   CU_RECORDS_HINT[]           hint text (e.g. "php >= 8.5.0")
#   CU_RECORDS_FLAGS[]          space-separated flags: override skip manual
#   CU_RECORDS_GIT_FALLBACK_URL[]   from "could be a repo url" lines
#   CU_RECORDS_GIT_FALLBACK_SHA[]   the SHA from same line
#   CU_RECORDS_LINE_NUMBER[]    line number of annotation in .env
#   CU_RECORDS_RAW_ANNOTATION[] the raw annotation comment text

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_CU_PARSE_LOADED:-}" ]] && return 0
readonly _CU_PARSE_LOADED=1

# shellcheck source=../config/type_map.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/type_map.sh"

# Global record arrays
declare -a CU_RECORDS_ENV_VAR=()
declare -a CU_RECORDS_CURRENT_VERSION=()
declare -a CU_RECORDS_TYPE=()
declare -a CU_RECORDS_IDENTIFIER=()
declare -a CU_RECORDS_HINT=()
declare -a CU_RECORDS_FLAGS=()
declare -a CU_RECORDS_GIT_FALLBACK_URL=()
declare -a CU_RECORDS_GIT_FALLBACK_SHA=()
declare -a CU_RECORDS_LINE_NUMBER=()
declare -a CU_RECORDS_RAW_ANNOTATION=()
CU_RECORD_COUNT=0

# Regex patterns stored in variables to avoid bash ERE backslash issues
# Matches: (flagword) rest
readonly _RE_FLAG_PREFIX='^[(]([^)]+)[)][[:space:]]*(.*)'
# Matches: text_before(hint_text) at end of string
readonly _RE_HINT_SUFFIX='^([^(]*)[[]?)[(]([^)]+)[)][[:space:]]*$'
# Simpler hint: text_before (hint) end
readonly _RE_HINT_SIMPLE='^(.*)[[:space:]][(]([^)]+)[)][[:space:]]*$'

# --------------------------------------------------------------------------
# Parse a single structured annotation line
# Format: # @todo check-updates [FLAGS] <TYPE>:<IDENTIFIER> [HINT] <VERSION>
# --------------------------------------------------------------------------
_parse_annotation_new_format() {
  local line="${1}"
  # Strip leading comment and whitespace
  local content
  content="${line#*@todo check-updates}"
  content="${content#"${content%%[! ]*}"}"  # ltrim

  local flags=""
  local type_id=""
  local hint=""
  local version=""

  # Extract flags: parenthesized words before type:id
  # e.g. "(override)" or "(skip)" or "(manual)"
  local remaining="${content}"
  while [[ "${remaining}" =~ ${_RE_FLAG_PREFIX} ]]; do
    local flag_word="${BASH_REMATCH[1]}"
    remaining="${BASH_REMATCH[2]}"
    flag_word="${flag_word%"${flag_word##*[! ]}"}"
    flags+="${flag_word} "
  done
  flags="${flags% }"  # rtrim

  # The next token should be type:identifier
  if [[ "${remaining}" =~ ^([a-z_-]+:[^[:space:]]+)[[:space:]]+(.*) ]]; then
    type_id="${BASH_REMATCH[1]}"
    remaining="${BASH_REMATCH[2]}"
  elif [[ "${remaining}" =~ ^([a-z_-]+:[^[:space:]]+)$ ]]; then
    type_id="${BASH_REMATCH[1]}"
    remaining=""
  else
    return 1
  fi

  # Extract hint: text in parentheses at end of remaining
  # e.g. "3.8.1 (php >= 8.2.0)"
  local hint_match=""
  if [[ "${remaining}" =~ ${_RE_HINT_SIMPLE} ]]; then
    local before_hint="${BASH_REMATCH[1]}"
    hint_match="${BASH_REMATCH[2]}"
    remaining="${before_hint}"
  fi

  # Trim whitespace from version
  remaining="${remaining#"${remaining%%[! ]*}"}"
  remaining="${remaining%"${remaining##*[! ]}"}"
  version="${remaining}"
  hint="${hint_match}"

  local type="${type_id%%:*}"
  local identifier="${type_id#*:}"

  printf '%s\t%s\t%s\t%s\t%s\t%s' \
    "${flags}" "${type}" "${identifier}" "${hint}" "${version}" ""
  return 0
}

# --------------------------------------------------------------------------
# Parse a legacy annotation line (URL-based format)
# Format: # @todo [FLAGS] check-updates <NAME> <URL> [<URL2>...] <VERSION>
# --------------------------------------------------------------------------
_parse_annotation_legacy_format() {
  local line="${1}"
  local content
  content="${line#*@todo}"
  content="${content#"${content%%[! ]*}"}"

  local flags=""
  local remaining="${content}"

  # Extract flags in parentheses using variable pattern
  while [[ "${remaining}" =~ ${_RE_FLAG_PREFIX} ]]; do
    flags+="${BASH_REMATCH[1]} "
    remaining="${BASH_REMATCH[2]}"
  done
  flags="${flags% }"

  # Strip "check-updates" keyword
  remaining="${remaining#check-updates}"
  remaining="${remaining#"${remaining%%[! ]*}"}"

  # Tokenize
  local tokens=()
  read -ra tokens <<< "${remaining}"

  if [[ ${#tokens[@]} -lt 2 ]]; then
    return 1
  fi

  local version="${tokens[${#tokens[@]}-1]}"

  # Find URLs from middle tokens
  local urls=()
  local name_token=""
  local i
  for (( i=0; i<${#tokens[@]}-1; i++ )); do
    local tok="${tokens[${i}]}"
    if [[ "${tok}" =~ ^https?:// ]]; then
      urls+=("${tok}")
    elif [[ ${i} -eq 0 && ! "${tok}" =~ ^https?:// ]]; then
      name_token="${tok}"
    fi
  done

  # Determine type:id from URL or name
  local type_id=""

  if [[ ${#urls[@]} -gt 0 ]]; then
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
  elif [[ -n "${name_token}" ]]; then
    if [[ "${name_token}" =~ ^GLOBAL_STACK_ ]]; then
      type_id="sdkman_var:${name_token}"
    else
      type_id="sdkman:${name_token}"
    fi
  else
    return 1
  fi

  local type="${type_id%%:*}"
  local identifier="${type_id#*:}"

  printf '%s\t%s\t%s\t%s\t%s\t%s' \
    "${flags}" "${type}" "${identifier}" "" "${version}" ""
  return 0
}

# --------------------------------------------------------------------------
# Main parser: reads .env file and populates CU_RECORDS_* arrays
# --------------------------------------------------------------------------
_parse_env_file() {
  local env_file="${1}"
  local filter_pattern="${2:-}"

  local state="IDLE"
  local pending_flags=""
  local pending_type=""
  local pending_identifier=""
  local pending_hint=""
  local pending_version=""
  local pending_line_number=0
  local pending_raw_annotation=""
  local pending_git_fallback_url=""
  local pending_git_fallback_sha=""

  local line_number=0

  # Pattern for git fallback lines
  local _re_git_fallback
  _re_git_fallback='^[[:space:]]*#[[:space:]]*@todo[[:space:]]+could[[:space:]]+be[[:space:]]+a[[:space:]]+repo[[:space:]]+url[[:space:]]+(https://[^[:space:]]+)[[:space:]]+(branch[[:space:]]+or[[:space:]]+commit[[:space:]]+)?([a-f0-9]+)'

  while IFS= read -r line || [[ -n "${line}" ]]; do
    (( line_number++ )) || true

    # git fallback URL lines
    if [[ "${line}" =~ ${_re_git_fallback} ]]; then
      pending_git_fallback_url="${BASH_REMATCH[1]}"
      pending_git_fallback_sha="${BASH_REMATCH[3]}"
      _log_debug "Git fallback URL: ${pending_git_fallback_url} SHA: ${pending_git_fallback_sha}"
      continue
    fi

    # annotation lines
    if [[ "${line}" =~ ^[[:space:]]*#[[:space:]]*@todo.*check-updates ]]; then
      state="AWAITING_VARIABLE"
      pending_line_number="${line_number}"
      pending_raw_annotation="${line}"
      pending_flags=""
      pending_type=""
      pending_identifier=""
      pending_hint=""
      pending_version=""

      local parsed_result=""
      # Detect new format by presence of type:identifier pattern
      if [[ "${line}" =~ check-updates.*[[:space:]](dockerhub|quay|github|npm|pecl|pecl-git|sdkman|sdkmanager|pypi|url): ]]; then
        if parsed_result="$(_parse_annotation_new_format "${line}" 2>/dev/null)"; then
          IFS=$'\t' read -r pending_flags pending_type pending_identifier \
            pending_hint pending_version _unused <<< "${parsed_result}"
        else
          parsed_result=""
        fi
      fi

      if [[ -z "${parsed_result}" ]]; then
        if parsed_result="$(_parse_annotation_legacy_format "${line}" 2>/dev/null)"; then
          IFS=$'\t' read -r pending_flags pending_type pending_identifier \
            pending_hint pending_version _unused <<< "${parsed_result}"
        else
          _log_debug "Could not parse annotation at line ${line_number}: ${line}"
          state="IDLE"
        fi
      fi
      continue
    fi

    # variable assignment lines
    if [[ "${state}" == "AWAITING_VARIABLE" ]]; then
      if [[ "${line}" =~ ^[[:space:]]*# ]]; then
        continue
      fi
      if [[ -z "${line}" ]]; then
        state="IDLE"
        pending_git_fallback_url=""
        pending_git_fallback_sha=""
        continue
      fi
      if [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        local var_name="${BASH_REMATCH[1]}"
        local var_value="${BASH_REMATCH[2]}"

        # Apply filter
        if [[ -n "${filter_pattern}" && ! "${var_name}" =~ ${filter_pattern} ]]; then
          state="IDLE"
          pending_git_fallback_url=""
          pending_git_fallback_sha=""
          continue
        fi

        # Handle sdkman_var type
        if [[ "${pending_type}" == "sdkman_var" ]]; then
          local sdkman_result
          sdkman_result="$(_infer_sdkman_candidate "${var_name}" "${var_value}")"
          if [[ -n "${sdkman_result}" ]]; then
            pending_type="${sdkman_result%%:*}"
            pending_identifier="${sdkman_result#*:}"
            pending_version="${var_value}"
          else
            state="IDLE"
            pending_git_fallback_url=""
            pending_git_fallback_sha=""
            continue
          fi
        fi

        # If version was empty in annotation, use the variable value
        if [[ -z "${pending_version}" ]]; then
          pending_version="${var_value}"
        fi

        # Store record
        local idx="${CU_RECORD_COUNT}"
        CU_RECORDS_ENV_VAR[${idx}]="${var_name}"
        CU_RECORDS_CURRENT_VERSION[${idx}]="${pending_version}"
        CU_RECORDS_TYPE[${idx}]="${pending_type}"
        CU_RECORDS_IDENTIFIER[${idx}]="${pending_identifier}"
        CU_RECORDS_HINT[${idx}]="${pending_hint}"
        CU_RECORDS_FLAGS[${idx}]="${pending_flags}"
        CU_RECORDS_GIT_FALLBACK_URL[${idx}]="${pending_git_fallback_url}"
        CU_RECORDS_GIT_FALLBACK_SHA[${idx}]="${pending_git_fallback_sha}"
        CU_RECORDS_LINE_NUMBER[${idx}]="${pending_line_number}"
        CU_RECORDS_RAW_ANNOTATION[${idx}]="${pending_raw_annotation}"
        (( CU_RECORD_COUNT++ )) || true

        _log_debug "Record #${idx}: ${var_name} [${pending_type}:${pending_identifier}] = ${pending_version}"

        state="IDLE"
        pending_git_fallback_url=""
        pending_git_fallback_sha=""
      fi
    fi

  done < "${env_file}"

  _log_debug "Total records parsed: ${CU_RECORD_COUNT}"
}
