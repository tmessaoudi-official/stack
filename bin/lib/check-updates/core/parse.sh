#!/bin/bash
# .env annotation parser — state machine reading line by line.
# Produces structured records from @todo check-updates annotations.
#
# Record fields (all stored in parallel arrays indexed by _GS_CU_RECORD_COUNT):
#   _GS_CU_RECORDS_ENV_VAR[]           env variable name
#   _GS_CU_RECORDS_CURRENT_VERSION[]   current value from .env
#   _GS_CU_RECORDS_TYPE[]              fetcher type (dockerhub, github, npm, ...)
#   _GS_CU_RECORDS_IDENTIFIER[]        type-specific identifier
#   _GS_CU_RECORDS_HINT[]              hint text (e.g. "php >= 8.5.0")
#   _GS_CU_RECORDS_FLAGS[]             space-separated flags: override skip manual
#   _GS_CU_RECORDS_GIT_FALLBACK_URL[]  from "could be a repo url" lines
#   _GS_CU_RECORDS_GIT_FALLBACK_SHA[]  the SHA from same line
#   _GS_CU_RECORDS_LINE_NUMBER[]       line number of annotation in .env
#   _GS_CU_RECORDS_RAW_ANNOTATION[]    the raw annotation comment text
#   _GS_CU_RECORDS_DEPENDS_ON[]        "(depends-on:VAR:constraint)"
#   _GS_CU_RECORDS_URLS[]              space-separated reference URLs from "urls:" section
#   _GS_CU_RECORDS_PECL_REF[]          PECL extension name for pecl-git

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_CU_PARSE_SH_LOADED:-}" ]] && return 0
readonly _GS_CU_PARSE_SH_LOADED=1

# shellcheck source=../config/type_map.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/type_map.sh"

# Global record arrays
declare -a _GS_CU_RECORDS_ENV_VAR=()
declare -a _GS_CU_RECORDS_CURRENT_VERSION=()
declare -a _GS_CU_RECORDS_TYPE=()
declare -a _GS_CU_RECORDS_IDENTIFIER=()
declare -a _GS_CU_RECORDS_HINT=()
declare -a _GS_CU_RECORDS_FLAGS=()
declare -a _GS_CU_RECORDS_GIT_FALLBACK_URL=()
declare -a _GS_CU_RECORDS_GIT_FALLBACK_SHA=()
declare -a _GS_CU_RECORDS_LINE_NUMBER=()
declare -a _GS_CU_RECORDS_RAW_ANNOTATION=()
declare -a _GS_CU_RECORDS_DEPENDS_ON=()   # "(depends-on:VAR:constraint)"
declare -a _GS_CU_RECORDS_URLS=()          # space-separated reference URLs from "urls:" section
declare -a _GS_CU_RECORDS_PECL_REF=()      # PECL extension name for pecl-git
_GS_CU_RECORD_COUNT=0

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
# Returns 8 tab-separated fields:
#   flags TAB type TAB identifier TAB hint TAB version TAB depends_on TAB urls TAB pecl_ref
# --------------------------------------------------------------------------
_gs_cu_parse_annotation_new_format() {
  local line="${1}"
  # Strip leading comment and whitespace
  local content
  content="${line#*@todo check-updates}"
  content="${content#"${content%%[! ]*}"}"  # ltrim

  local flags=""
  local type_id=""
  local hint=""
  local version=""
  local depends_on=""
  local urls=""
  local pecl_ref=""

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

  # Extract (pecl-ref:NAME) token
  local _re_pecl_ref='\(pecl-ref:([^)]+)\)'
  if [[ "${remaining}" =~ ${_re_pecl_ref} ]]; then
    pecl_ref="${BASH_REMATCH[1]}"
    remaining="${remaining//${BASH_REMATCH[0]}/}"
    remaining="${remaining#"${remaining%%[! ]*}"}"
    remaining="${remaining%"${remaining##*[! ]}"}"
  fi

  # Extract (depends-on:VAR:constraint) token
  local _re_depends_on='\(depends-on:[^)]+\)'
  if [[ "${remaining}" =~ ${_re_depends_on} ]]; then
    depends_on="${BASH_REMATCH[0]}"
    # Strip outer parens to get just VAR:constraint
    depends_on="${depends_on#(}"
    depends_on="${depends_on%)}"
    depends_on="${depends_on#depends-on:}"
    remaining="${remaining//${BASH_REMATCH[0]}/}"
    remaining="${remaining#"${remaining%%[! ]*}"}"
    remaining="${remaining%"${remaining##*[! ]}"}"
  fi

  # Extract urls: URL1 URL2 ... keyword
  local _re_urls_section='[[:space:]]urls:[[:space:]]+(.*)'
  if [[ " ${remaining} " =~ [[:space:]]urls:[[:space:]] ]]; then
    # Split on "urls:"
    local before_urls="${remaining%%urls:*}"
    local after_urls="${remaining#*urls:}"
    after_urls="${after_urls#"${after_urls%%[! ]*}"}"
    # URLs are space-separated tokens that start with http
    local url_token
    local remaining_after_urls=""
    for url_token in ${after_urls}; do
      if [[ "${url_token}" =~ ^https?:// ]]; then
        urls+="${url_token} "
      else
        remaining_after_urls+="${url_token} "
      fi
    done
    urls="${urls% }"
    remaining="${before_urls}${remaining_after_urls}"
    remaining="${remaining#"${remaining%%[! ]*}"}"
    remaining="${remaining%"${remaining##*[! ]}"}"
  fi

  # Extract hint: text in parentheses at end of remaining
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

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    "${flags}" "${type}" "${identifier}" "${hint}" "${version}" \
    "${depends_on}" "${urls}" "${pecl_ref}"
  return 0
}

# --------------------------------------------------------------------------
# Parse a legacy annotation line (URL-based format)
# Format: # @todo [FLAGS] check-updates <NAME> <URL> [<URL2>...] <VERSION>
# Returns 8 tab-separated fields (depends_on/urls/pecl_ref will be empty)
# --------------------------------------------------------------------------
_gs_cu_parse_annotation_legacy_format() {
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

  # Strip trailing parenthetical tokens before version extraction
  # e.g. "... 1.1.3 beta (php >= 7.0)" — strip "(php >= 7.0)" first, then "beta"
  local last_idx=$(( ${#tokens[@]} - 1 ))
  local version="${tokens[${last_idx}]}"

  # If last token looks like a stability keyword and second-to-last is numeric, use second-to-last
  if [[ ${#tokens[@]} -ge 3 ]]; then
    local second_last="${tokens[$(( ${#tokens[@]} - 2 ))]}"
    if [[ "${version}" =~ ^(stable|beta|alpha)$ && "${second_last}" =~ ^[0-9] ]]; then
      version="${second_last}"
      last_idx=$(( ${#tokens[@]} - 2 ))
    fi
  fi

  # Find URLs from middle tokens (before version index)
  local urls=()
  local name_token=""
  local i
  for (( i=0; i<last_idx; i++ )); do
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
    type_id="$(_gs_cu_infer_type_from_url "${best_url}" "${version}")"
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

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    "${flags}" "${type}" "${identifier}" "" "${version}" "" "" ""
  return 0
}

# --------------------------------------------------------------------------
# Main parser: reads .env file and populates _GS_CU_RECORDS_* arrays
# --------------------------------------------------------------------------
_gs_cu_parse_env_file() {
  local env_file="${1}"
  local filter_pattern="${2:-}"

  local state="IDLE"
  local pending_flags=""
  local pending_type=""
  local pending_identifier=""
  local pending_hint=""
  local pending_version=""
  local pending_depends_on=""
  local pending_urls=""
  local pending_pecl_ref=""
  local pending_line_number=0
  local pending_raw_annotation=""
  local pending_git_fallback_url=""
  local pending_git_fallback_sha=""

  local line_number=0

  # Pattern for git fallback lines
  local _re_git_fallback
  _re_git_fallback='^[[:space:]]*#[[:space:]]*@todo[[:space:]]+could[[:space:]]+be[[:space:]]+a[[:space:]]+repo[[:space:]]+url[[:space:]]+(https://[^[:space:]]+)[[:space:]]+(branch[[:space:]]+or[[:space:]]+commit[[:space:]]+)?([a-f0-9]+)'

  # Pattern to detect already-migrated new format:
  # type must follow immediately after flags/check-updates — not embedded in a URL or hint
  local _re_already_migrated
  _re_already_migrated='^[[:space:]]*#.*@todo[[:space:]]+check-updates[[:space:]]+(\([^)]+\)[[:space:]]+)*(dockerhub|quay|github|npm|pecl|pecl-git|sdkman|sdkmanager|pypi|url):'

  while IFS= read -r line || [[ -n "${line}" ]]; do
    (( line_number++ )) || true

    # git fallback URL lines
    if [[ "${line}" =~ ${_re_git_fallback} ]]; then
      pending_git_fallback_url="${BASH_REMATCH[1]}"
      pending_git_fallback_sha="${BASH_REMATCH[3]}"
      _gs_cu_log_debug "Git fallback URL: ${pending_git_fallback_url} SHA: ${pending_git_fallback_sha}"
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
      pending_depends_on=""
      pending_urls=""
      pending_pecl_ref=""

      local parsed_result=""
      # Detect new format — type must immediately follow check-updates (+ optional flags)
      if [[ "${line}" =~ ${_re_already_migrated} ]]; then
        if parsed_result="$(_gs_cu_parse_annotation_new_format "${line}" 2>/dev/null)"; then
          IFS=$'\t' read -r pending_flags pending_type pending_identifier \
            pending_hint pending_version pending_depends_on pending_urls pending_pecl_ref <<< "${parsed_result}"
        else
          parsed_result=""
        fi
      fi

      if [[ -z "${parsed_result}" ]]; then
        if parsed_result="$(_gs_cu_parse_annotation_legacy_format "${line}" 2>/dev/null)"; then
          IFS=$'\t' read -r pending_flags pending_type pending_identifier \
            pending_hint pending_version pending_depends_on pending_urls pending_pecl_ref <<< "${parsed_result}"
        else
          _gs_cu_log_debug "Could not parse annotation at line ${line_number}: ${line}"
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
          sdkman_result="$(_gs_cu_infer_sdkman_candidate "${var_name}" "${var_value}")"
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
        local idx="${_GS_CU_RECORD_COUNT}"
        _GS_CU_RECORDS_ENV_VAR[${idx}]="${var_name}"
        _GS_CU_RECORDS_CURRENT_VERSION[${idx}]="${pending_version}"
        _GS_CU_RECORDS_TYPE[${idx}]="${pending_type}"
        _GS_CU_RECORDS_IDENTIFIER[${idx}]="${pending_identifier}"
        _GS_CU_RECORDS_HINT[${idx}]="${pending_hint}"
        _GS_CU_RECORDS_FLAGS[${idx}]="${pending_flags}"
        _GS_CU_RECORDS_GIT_FALLBACK_URL[${idx}]="${pending_git_fallback_url}"
        _GS_CU_RECORDS_GIT_FALLBACK_SHA[${idx}]="${pending_git_fallback_sha}"
        _GS_CU_RECORDS_LINE_NUMBER[${idx}]="${pending_line_number}"
        _GS_CU_RECORDS_RAW_ANNOTATION[${idx}]="${pending_raw_annotation}"
        _GS_CU_RECORDS_DEPENDS_ON[${idx}]="${pending_depends_on}"
        _GS_CU_RECORDS_URLS[${idx}]="${pending_urls}"
        _GS_CU_RECORDS_PECL_REF[${idx}]="${pending_pecl_ref}"
        (( _GS_CU_RECORD_COUNT++ )) || true

        _gs_cu_log_debug "Record #${idx}: ${var_name} [${pending_type}:${pending_identifier}] = ${pending_version}"

        state="IDLE"
        pending_git_fallback_url=""
        pending_git_fallback_sha=""
      fi
    fi

  done < "${env_file}"

  _gs_cu_log_debug "Total records parsed: ${_GS_CU_RECORD_COUNT}"
}
