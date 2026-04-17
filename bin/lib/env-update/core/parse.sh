#!/bin/bash
# .env annotation parser — state machine reading line by line.
# Produces structured records from @todo env-update annotations.
#
# Record fields (all stored in parallel arrays indexed by _GS_EU_RECORD_COUNT):
#   _GS_EU_RECORDS_ENV_VAR[]           env variable name
#   _GS_EU_RECORDS_CURRENT_VERSION[]   current value from .env
#   _GS_EU_RECORDS_TYPE[]              fetcher type (dockerhub, github, npm, ...)
#   _GS_EU_RECORDS_IDENTIFIER[]        type-specific identifier
#   _GS_EU_RECORDS_HINT[]              hint text (e.g. "php >= 8.5.0")
#   _GS_EU_RECORDS_FLAGS[]             space-separated flags: override skip manual
#   _GS_EU_RECORDS_GIT_FALLBACK_URL[]  from "could be a repo url" lines
#   _GS_EU_RECORDS_GIT_FALLBACK_SHA[]  the SHA from same line
#   _GS_EU_RECORDS_LINE_NUMBER[]       line number of annotation in .env
#   _GS_EU_RECORDS_RAW_ANNOTATION[]    the raw annotation comment text
#   _GS_EU_RECORDS_DEPENDS_ON[]        "(depends-on:VAR:constraint)"
#   _GS_EU_RECORDS_URLS[]              space-separated reference URLs from "urls:" section
#   _GS_EU_RECORDS_PECL_REF[]          PECL extension name for pecl-git
#   _GS_EU_RECORDS_TAG_FILTER[]        (tag-filter:REGEX) — keep only matching tags
#   _GS_EU_RECORDS_TAG_EXCLUDE[]       (tag-exclude:REGEX) — drop matching tags
#   _GS_EU_RECORDS_TAG_STRIP_PREFIX[]  (tag-strip-prefix:LITERAL) — strip literal prefix from tags
#   _GS_EU_RECORDS_TAG_STRIP_SUFFIX[]  (tag-strip-suffix:LITERAL) — strip literal suffix from tags
#   _GS_EU_RECORDS_TAG_EXTRACT[]       (tag-extract:REGEX) — extract capture group 1 from tags
#   _GS_EU_RECORDS_FETCH_EXTRACT[]     (fetch-extract:REGEX) — extract from fetched body
#   _GS_EU_RECORDS_FETCH_JSON[]        (fetch-json:JQ_PATH) — jq path from fetched JSON
#   _GS_EU_RECORDS_URL_PROBE[]         (url-probe:PATH1,PATH2,...) — probe paths
#   _GS_EU_RECORDS_URL_PROBE_DEPTH[]   (url-probe-depth:N) — depth (default 6)
#   _GS_EU_RECORDS_TAG_REPLACE_FROM[]  (tag-replace:FROM:TO) — replace FROM with TO in tags
#   _GS_EU_RECORDS_TAG_REPLACE_TO[]    (tag-replace:FROM:TO) — replacement string
#   _GS_EU_RECORDS_CHANNEL[]           (channel:VALUE) — tracking channel (nightly, stable, beta)
#   _GS_EU_RECORDS_VERSION_PREFIX[]    (version-prefix:PREFIX) — prefix prepended to proposed version

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_EU_PARSE_SH_LOADED:-}" ]] && return 0
readonly _GS_EU_PARSE_SH_LOADED=1

# shellcheck source=../config/type_map.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/type_map.sh"

# Global record arrays
declare -a _GS_EU_RECORDS_ENV_VAR=()
declare -a _GS_EU_RECORDS_CURRENT_VERSION=()
declare -a _GS_EU_RECORDS_TYPE=()
declare -a _GS_EU_RECORDS_IDENTIFIER=()
declare -a _GS_EU_RECORDS_HINT=()
declare -a _GS_EU_RECORDS_FLAGS=()
declare -a _GS_EU_RECORDS_GIT_FALLBACK_URL=()
declare -a _GS_EU_RECORDS_GIT_FALLBACK_SHA=()
declare -a _GS_EU_RECORDS_LINE_NUMBER=()
declare -a _GS_EU_RECORDS_RAW_ANNOTATION=()
declare -a _GS_EU_RECORDS_DEPENDS_ON=()   # "(depends-on:VAR:constraint)"
declare -a _GS_EU_RECORDS_URLS=()          # space-separated reference URLs from "urls:" section
declare -a _GS_EU_RECORDS_PECL_REF=()      # PECL extension name for pecl-git
declare -a _GS_EU_RECORDS_TAG_SUFFIX=()         # from (tag-suffix:VALUE) flag
declare -a _GS_EU_RECORDS_SKIP_REASON=()        # from (skip:REASON) flag
declare -a _GS_EU_RECORDS_TAG_FILTER=()         # from (tag-filter:REGEX) flag
declare -a _GS_EU_RECORDS_TAG_EXCLUDE=()        # from (tag-exclude:REGEX) flag
declare -a _GS_EU_RECORDS_TAG_STRIP_PREFIX=()   # from (tag-strip-prefix:LITERAL) flag
declare -a _GS_EU_RECORDS_TAG_STRIP_SUFFIX=()   # from (tag-strip-suffix:LITERAL) flag
declare -a _GS_EU_RECORDS_TAG_EXTRACT=()        # from (tag-extract:REGEX) flag
declare -a _GS_EU_RECORDS_FETCH_EXTRACT=()      # from (fetch-extract:REGEX) flag
declare -a _GS_EU_RECORDS_FETCH_JSON=()         # from (fetch-json:JQ_PATH) flag
declare -a _GS_EU_RECORDS_URL_PROBE=()          # from (url-probe:PATH1,PATH2,...) flag
declare -a _GS_EU_RECORDS_URL_PROBE_DEPTH=()    # from (url-probe-depth:N) flag
declare -a _GS_EU_RECORDS_TAG_REPLACE_FROM=()   # from (tag-replace:FROM:TO) flag — FROM string
declare -a _GS_EU_RECORDS_TAG_REPLACE_TO=()     # from (tag-replace:FROM:TO) flag — TO string
declare -a _GS_EU_RECORDS_CHANNEL=()            # from (channel:VALUE) flag — e.g. nightly/stable/beta
declare -a _GS_EU_RECORDS_VERSION_PREFIX=()     # from (version-prefix:PREFIX) flag
_GS_EU_RECORD_COUNT=0

# Regex patterns stored in variables to avoid bash ERE backslash issues
# NOTE: _RE_FLAG_PREFIX is intentionally NOT used for flag extraction anymore.
# Flag extraction uses _gs_eu_extract_balanced_flags() to handle nested parens.
# Matches: text_before(hint_text) at end of string
readonly _RE_HINT_SUFFIX='^([^(]*)[[]?)[(]([^)]+)[)][[:space:]]*$'
# Simpler hint: text_before (hint) end
readonly _RE_HINT_SIMPLE='^(.*)[[:space:]][(]([^)]+)[)][[:space:]]*$'

# --------------------------------------------------------------------------
# Extract leading parenthesized flags from a string, supporting nested parens.
# Flags look like: (tag-extract:^RELEASE_([0-9]+_[0-9]+_[0-9]+)$) (skip) ...
# Sets two variables in the caller's scope (pass names as args):
#   $1 = nameref for flags string (space-separated extracted flag contents)
#   $2 = nameref for remaining string (everything after the last leading flag)
# Usage: _gs_eu_extract_balanced_flags flags_var remaining_var "${content}"
# --------------------------------------------------------------------------
_gs_eu_extract_balanced_flags() {
  local -n _ebf_flags_ref="${1}"
  local -n _ebf_remaining_ref="${2}"
  local _ebf_input="${3}"

  _ebf_flags_ref=""
  _ebf_remaining_ref="${_ebf_input}"

  while true; do
    # Skip leading whitespace
    local _ebf_trimmed="${_ebf_remaining_ref#"${_ebf_remaining_ref%%[! ]*}"}"

    # Must start with '(' to be a flag
    [[ "${_ebf_trimmed:0:1}" == "(" ]] || break

    # Walk characters to find the balanced closing ')'
    local _ebf_depth=0
    local _ebf_content=""
    local _ebf_i _ebf_ch _ebf_found=false
    local _ebf_len="${#_ebf_trimmed}"
    for (( _ebf_i = 0; _ebf_i < _ebf_len; _ebf_i++ )); do
      _ebf_ch="${_ebf_trimmed:${_ebf_i}:1}"
      if [[ "${_ebf_ch}" == "(" ]]; then
        (( _ebf_depth++ ))
        (( _ebf_depth > 1 )) && _ebf_content+="${_ebf_ch}"
      elif [[ "${_ebf_ch}" == ")" ]]; then
        (( _ebf_depth-- ))
        if (( _ebf_depth == 0 )); then
          _ebf_found=true
          # Advance past the closing ')' and any trailing spaces
          local _ebf_after="${_ebf_trimmed:$(( _ebf_i + 1 ))}"
          _ebf_after="${_ebf_after#"${_ebf_after%%[! ]*}"}"
          _ebf_remaining_ref="${_ebf_after}"
          break
        else
          _ebf_content+="${_ebf_ch}"
        fi
      else
        _ebf_content+="${_ebf_ch}"
      fi
    done

    [[ "${_ebf_found}" == "true" ]] || break

    # Rtrim content and append to flags
    _ebf_content="${_ebf_content%"${_ebf_content##*[! ]}"}"
    [[ -n "${_ebf_flags_ref}" ]] && _ebf_flags_ref+=" "
    _ebf_flags_ref+="${_ebf_content}"
  done
}

# --------------------------------------------------------------------------
# Split a tab-delimited parsed result string into 8 named variables.
# Using herestring (<<<) with IFS=$'\t' strips leading tab chars when the
# first field is empty, causing all fields to shift left by one.  This
# helper uses parameter-expansion splitting which preserves empty leading
# fields correctly.
#
# Usage:
#   _gs_eu_split_parsed_result "$parsed_result" \
#     flags type identifier hint version depends_on urls pecl_ref
# (variable names are passed by reference via nameref — bash 4.3+)
# --------------------------------------------------------------------------
_gs_eu_split_parsed_result() {
  local _spr_str="${1}"
  # Eight output variable names passed as $2..$9
  local _spr_sep=$'\t'
  local _spr_rest="${_spr_str}"
  local _spr_i _spr_field

  for _spr_i in 2 3 4 5 6 7 8 9; do
    # Extract the portion before the first tab
    _spr_field="${_spr_rest%%${_spr_sep}*}"
    # Advance past that field (if there is a tab remaining)
    if [[ "${_spr_rest}" == *"${_spr_sep}"* ]]; then
      _spr_rest="${_spr_rest#*${_spr_sep}}"
    else
      _spr_rest=""
    fi
    # Assign by nameref — requires bash 4.3+
    printf -v "${!_spr_i}" '%s' "${_spr_field}"
  done
}

# --------------------------------------------------------------------------
# Parse a single structured annotation line
# Format: # @todo env-update [FLAGS] <TYPE>:<IDENTIFIER> [HINT] <VERSION>
# Returns 8 tab-separated fields:
#   flags TAB type TAB identifier TAB hint TAB version TAB depends_on TAB urls TAB pecl_ref
# --------------------------------------------------------------------------
_gs_eu_parse_annotation_new_format() {
  local line="${1}"
  # Strip leading comment and whitespace
  local content
  content="${line#*@todo env-update}"
  content="${content#"${content%%[! ]*}"}"  # ltrim

  local flags=""
  local type_id=""
  local hint=""
  local version=""
  local depends_on=""
  local urls=""
  local pecl_ref=""

  # Extract flags: parenthesized tokens before type:id — supports nested parens.
  # e.g. "(override)" "(skip:REASON)" "(tag-extract:^RELEASE_([0-9]+_[0-9]+)$)"
  local remaining="${content}"
  _gs_eu_extract_balanced_flags flags remaining "${content}"

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
# Format: # @todo [FLAGS] env-update <NAME> <URL> [<URL2>...] <VERSION>
# Returns 8 tab-separated fields (depends_on/urls/pecl_ref will be empty)
# --------------------------------------------------------------------------
_gs_eu_parse_annotation_legacy_format() {
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

  # Strip "env-update" keyword
  remaining="${remaining#env-update}"
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
    type_id="$(_gs_eu_infer_type_from_url "${best_url}" "${version}")"
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
# Main parser: reads .env file and populates _GS_EU_RECORDS_* arrays
# --------------------------------------------------------------------------
_gs_eu_parse_env_file() {
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

  # Pattern to detect already-migrated new format.
  # We do NOT try to parse flags here (they may contain nested parens).
  # Just check that a known type:identifier appears somewhere after env-update.
  # The new-format parser (_gs_eu_parse_annotation_new_format) does the real work.
  local _re_already_migrated
  _re_already_migrated='^[[:space:]]*#[[:space:]]*@todo[[:space:]]+env-update[[:space:]].*(dockerhub|quay|github|codeberg|npm|pecl|pecl-git|sdkman|sdkmanager|pypi|url|rubygems):'

  while IFS= read -r line || [[ -n "${line}" ]]; do
    (( line_number++ )) || true

    # git fallback URL lines
    if [[ "${line}" =~ ${_re_git_fallback} ]]; then
      pending_git_fallback_url="${BASH_REMATCH[1]}"
      pending_git_fallback_sha="${BASH_REMATCH[3]}"
      _gs_eu_log_debug "Git fallback URL: ${pending_git_fallback_url} SHA: ${pending_git_fallback_sha}"
      continue
    fi

    # annotation lines
    if [[ "${line}" =~ ^[[:space:]]*#[[:space:]]*@todo.*env-update ]]; then
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
      # Detect new format — type must immediately follow env-update (+ optional flags)
      if [[ "${line}" =~ ${_re_already_migrated} ]]; then
        if parsed_result="$(_gs_eu_parse_annotation_new_format "${line}" 2>/dev/null)"; then
          _gs_eu_split_parsed_result "${parsed_result}" \
            pending_flags pending_type pending_identifier \
            pending_hint pending_version pending_depends_on pending_urls pending_pecl_ref
        else
          parsed_result=""
        fi
      fi

      if [[ -z "${parsed_result}" ]]; then
        if parsed_result="$(_gs_eu_parse_annotation_legacy_format "${line}" 2>/dev/null)"; then
          _gs_eu_split_parsed_result "${parsed_result}" \
            pending_flags pending_type pending_identifier \
            pending_hint pending_version pending_depends_on pending_urls pending_pecl_ref
        else
          _gs_eu_log_debug "Could not parse annotation at line ${line_number}: ${line}"
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
          sdkman_result="$(_gs_eu_infer_sdkman_candidate "${var_name}" "${var_value}")"
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

        # Extract all flags from flags string
        local _pending_tag_suffix="" _pending_skip_reason=""
        local _pending_tag_filter="" _pending_tag_exclude=""
        local _pending_tag_strip_prefix="" _pending_tag_strip_suffix=""
        local _pending_tag_extract="" _pending_fetch_extract="" _pending_fetch_json=""
        local _pending_url_probe="" _pending_url_probe_depth="6"
        local _pending_tag_replace_from="" _pending_tag_replace_to=""
        local _pending_channel="" _pending_version_prefix=""
        local _f
        for _f in ${pending_flags}; do
          if [[ "${_f}" =~ ^tag-suffix:(.+)$ ]]; then
            _pending_tag_suffix="${BASH_REMATCH[1]}"
          elif [[ "${_f}" =~ ^skip:(.+)$ ]]; then
            _pending_skip_reason="${BASH_REMATCH[1]}"
          elif [[ "${_f}" =~ ^tag-filter:(.+)$ ]]; then
            _pending_tag_filter="${BASH_REMATCH[1]}"
          elif [[ "${_f}" =~ ^tag-exclude:(.+)$ ]]; then
            _pending_tag_exclude="${BASH_REMATCH[1]}"
          elif [[ "${_f}" =~ ^tag-strip-prefix:(.+)$ ]]; then
            _pending_tag_strip_prefix="${BASH_REMATCH[1]}"
          elif [[ "${_f}" =~ ^tag-strip-suffix:(.+)$ ]]; then
            _pending_tag_strip_suffix="${BASH_REMATCH[1]}"
          elif [[ "${_f}" =~ ^tag-extract:(.+)$ ]]; then
            _pending_tag_extract="${BASH_REMATCH[1]}"
          elif [[ "${_f}" =~ ^tag-replace:(.+):(.*)$ ]]; then
            _pending_tag_replace_from="${BASH_REMATCH[1]}"
            _pending_tag_replace_to="${BASH_REMATCH[2]}"
          elif [[ "${_f}" =~ ^fetch-extract:(.+)$ ]]; then
            _pending_fetch_extract="${BASH_REMATCH[1]}"
          elif [[ "${_f}" =~ ^fetch-json:(.+)$ ]]; then
            _pending_fetch_json="${BASH_REMATCH[1]}"
          elif [[ "${_f}" =~ ^url-probe:(.+)$ ]]; then
            _pending_url_probe="${BASH_REMATCH[1]}"
          elif [[ "${_f}" =~ ^url-probe-depth:([0-9]+)$ ]]; then
            _pending_url_probe_depth="${BASH_REMATCH[1]}"
          elif [[ "${_f}" =~ ^channel:(.+)$ ]]; then
            _pending_channel="${BASH_REMATCH[1]}"
          elif [[ "${_f}" =~ ^version-prefix:(.+)$ ]]; then
            _pending_version_prefix="${BASH_REMATCH[1]}"
          fi
        done

        # Store record
        local idx="${_GS_EU_RECORD_COUNT}"
        _GS_EU_RECORDS_ENV_VAR[${idx}]="${var_name}"
        _GS_EU_RECORDS_CURRENT_VERSION[${idx}]="${pending_version}"
        _GS_EU_RECORDS_TYPE[${idx}]="${pending_type}"
        _GS_EU_RECORDS_IDENTIFIER[${idx}]="${pending_identifier}"
        _GS_EU_RECORDS_HINT[${idx}]="${pending_hint}"
        _GS_EU_RECORDS_FLAGS[${idx}]="${pending_flags}"
        _GS_EU_RECORDS_GIT_FALLBACK_URL[${idx}]="${pending_git_fallback_url}"
        _GS_EU_RECORDS_GIT_FALLBACK_SHA[${idx}]="${pending_git_fallback_sha}"
        _GS_EU_RECORDS_LINE_NUMBER[${idx}]="${pending_line_number}"
        _GS_EU_RECORDS_RAW_ANNOTATION[${idx}]="${pending_raw_annotation}"
        _GS_EU_RECORDS_DEPENDS_ON[${idx}]="${pending_depends_on}"
        _GS_EU_RECORDS_URLS[${idx}]="${pending_urls}"
        _GS_EU_RECORDS_PECL_REF[${idx}]="${pending_pecl_ref}"
        _GS_EU_RECORDS_TAG_SUFFIX[${idx}]="${_pending_tag_suffix}"
        _GS_EU_RECORDS_SKIP_REASON[${idx}]="${_pending_skip_reason}"
        _GS_EU_RECORDS_TAG_FILTER[${idx}]="${_pending_tag_filter}"
        _GS_EU_RECORDS_TAG_EXCLUDE[${idx}]="${_pending_tag_exclude}"
        _GS_EU_RECORDS_TAG_STRIP_PREFIX[${idx}]="${_pending_tag_strip_prefix}"
        _GS_EU_RECORDS_TAG_STRIP_SUFFIX[${idx}]="${_pending_tag_strip_suffix}"
        _GS_EU_RECORDS_TAG_EXTRACT[${idx}]="${_pending_tag_extract}"
        _GS_EU_RECORDS_FETCH_EXTRACT[${idx}]="${_pending_fetch_extract}"
        _GS_EU_RECORDS_FETCH_JSON[${idx}]="${_pending_fetch_json}"
        _GS_EU_RECORDS_URL_PROBE[${idx}]="${_pending_url_probe}"
        _GS_EU_RECORDS_URL_PROBE_DEPTH[${idx}]="${_pending_url_probe_depth}"
        _GS_EU_RECORDS_TAG_REPLACE_FROM[${idx}]="${_pending_tag_replace_from}"
        _GS_EU_RECORDS_TAG_REPLACE_TO[${idx}]="${_pending_tag_replace_to}"
        _GS_EU_RECORDS_CHANNEL[${idx}]="${_pending_channel}"
        _GS_EU_RECORDS_VERSION_PREFIX[${idx}]="${_pending_version_prefix}"
        (( _GS_EU_RECORD_COUNT++ )) || true

        _gs_eu_log_debug "Record #${idx}: ${var_name} [${pending_type}:${pending_identifier}] = ${pending_version}"

        state="IDLE"
        pending_git_fallback_url=""
        pending_git_fallback_sha=""
      fi
    fi

  done < "${env_file}"

  _gs_eu_log_debug "Total records parsed: ${_GS_EU_RECORD_COUNT}"
}
