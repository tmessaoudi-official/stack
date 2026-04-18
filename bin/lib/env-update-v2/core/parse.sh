#!/bin/bash
# parse.sh — annotation parser (state machine)

[[ -n "${_GS_EU2_PARSE_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_PARSE_SH_LOADED=1

# shellcheck source=./records.sh
source "$(dirname "${BASH_SOURCE[0]}")/records.sh"

# ── Extract balanced parenthesised flags from the start of a string ────────
# Ported from v1's _gs_eu_extract_balanced_flags.
# Sets two caller-scope vars (by nameref):
#   $1 = flags_var  → flags joined by $'\x1f' (unit separator)
#   $2 = remaining_var → rest of string after last extracted flag
_gs_eu2_extract_balanced_flags() {
  local -n _ebf_flags="${1}"
  local -n _ebf_rem="${2}"
  local _ebf_in="${3}"

  _ebf_flags=""
  _ebf_rem="${_ebf_in}"

  while true; do
    local _ebf_trimmed="${_ebf_rem#"${_ebf_rem%%[! ]*}"}"
    [[ "${_ebf_trimmed:0:1}" == "(" ]] || break

    local _ebf_depth=0 _ebf_content="" _ebf_found=false
    local _ebf_len="${#_ebf_trimmed}" _ebf_i _ebf_ch
    for (( _ebf_i = 0; _ebf_i < _ebf_len; _ebf_i++ )); do
      _ebf_ch="${_ebf_trimmed:${_ebf_i}:1}"
      if [[ "${_ebf_ch}" == "(" ]]; then
        (( ++_ebf_depth )) || true   # depth 0→1: pre-increment returns new value = 1
        (( _ebf_depth > 1 )) && _ebf_content+="${_ebf_ch}"
      elif [[ "${_ebf_ch}" == ")" ]]; then
        (( --_ebf_depth )) || true   # depth 1→0: pre-decrement returns new value = 0
        if (( _ebf_depth == 0 )); then
          _ebf_found=true
          local _ebf_after="${_ebf_trimmed:$(( _ebf_i + 1 ))}"
          _ebf_after="${_ebf_after#"${_ebf_after%%[! ]*}"}"
          _ebf_rem="${_ebf_after}"
          break
        else
          _ebf_content+="${_ebf_ch}"
        fi
      else
        _ebf_content+="${_ebf_ch}"
      fi
    done

    [[ "${_ebf_found}" == "true" ]] || break
    _ebf_content="${_ebf_content%"${_ebf_content##*[! ]}"}"
    [[ -n "${_ebf_flags}" ]] && _ebf_flags+=$'\x1f'
    _ebf_flags+="${_ebf_content}"
  done
}

# ── Validate and dispatch one flag token → record field ───────────────────
# $1 = flag content (inside parens), $2 = env_file, $3 = line_num, $4 = idx
_gs_eu2_dispatch_flag() {
  local _f="${1}" _env_file="${2}" _lnum="${3}" _idx="${4}"
  local _name _val

  if [[ "${_f}" == *:* ]]; then
    _name="${_f%%:*}"
    _val="${_f#*:}"
  else
    _name="${_f}"
    _val=""
  fi

  case "${_name}" in
    override)  _gs_eu2_record_set "${_idx}" override  "true"; return 0 ;;
    manual)    _gs_eu2_record_set "${_idx}" manual    "true"; return 0 ;;
    propagate) _gs_eu2_record_set "${_idx}" propagate "true"; return 0 ;;
  esac

  # Keyed flags: validate non-empty value
  case "${_name}" in
    channel|skip|tag-filter|tag-exclude|tag-strip-prefix|tag-strip-suffix|\
    tag-extract|tag-suffix|fetch-extract|fetch-json|url-probe|url-probe-depth|\
    version-prefix)
      if [[ -z "${_val}" ]]; then
        printf 'env-update-v2: %s:%s: flag %q requires a non-empty value\n' \
          "${_env_file}" "${_lnum}" "${_name}" >&2
        exit 1
      fi
      ;;
    tag-replace)
      if [[ -z "${_val}" || "${_val}" != *:* ]]; then
        printf 'env-update-v2: %s:%s: flag tag-replace requires FROM:TO format\n' \
          "${_env_file}" "${_lnum}" >&2
        exit 1
      fi
      ;;
    *)
      printf 'env-update-v2: %s:%s: unknown flag %q in annotation\n' \
        "${_env_file}" "${_lnum}" "${_name}" >&2
      exit 1
      ;;
  esac

  case "${_name}" in
    channel)           _gs_eu2_record_set "${_idx}" channel         "${_val}" ;;
    skip)              _gs_eu2_record_set "${_idx}" skip_reason     "${_val}" ;;
    tag-filter)        _gs_eu2_record_set "${_idx}" tag_filter      "${_val}" ;;
    tag-exclude)       _gs_eu2_record_set "${_idx}" tag_exclude     "${_val}" ;;
    tag-strip-prefix)  _gs_eu2_record_set "${_idx}" tag_strip_prefix "${_val}" ;;
    tag-strip-suffix)  _gs_eu2_record_set "${_idx}" tag_strip_suffix "${_val}" ;;
    tag-extract)       _gs_eu2_record_set "${_idx}" tag_extract     "${_val}" ;;
    tag-suffix)        _gs_eu2_record_set "${_idx}" tag_suffix      "${_val}" ;;
    fetch-extract)     _gs_eu2_record_set "${_idx}" fetch_extract   "${_val}" ;;
    fetch-json)        _gs_eu2_record_set "${_idx}" fetch_json      "${_val}" ;;
    url-probe)         _gs_eu2_record_set "${_idx}" url_probe       "${_val}" ;;
    url-probe-depth)   _gs_eu2_record_set "${_idx}" url_probe_depth "${_val}" ;;
    version-prefix)    _gs_eu2_record_set "${_idx}" version_prefix  "${_val}" ;;
    tag-replace)
      _gs_eu2_record_set "${_idx}" tag_replace_from "${_val%%:*}"
      _gs_eu2_record_set "${_idx}" tag_replace_to   "${_val#*:}"
      ;;
  esac
}

# ── Main parser: reads .env file, populates records ────────────────────────
_gs_eu2_parse_env_file() {
  local _env_file="${1}"
  local _filter="${2:-}"

  local _state="IDLE"
  local _pending_annotation="" _pending_lnum=0
  local _pending_type="" _pending_identifier="" _pending_major_hint=""
  local _pending_flags="" _pending_version="" _pending_hint=""
  local _pending_git_url="" _pending_git_sha=""
  local _pend_pecl="" _pend_dep="" _pend_urls=""
  local _line_number=0

  local _re_git_fallback
  _re_git_fallback='^[[:space:]]*#[[:space:]]*@todo[[:space:]]+could[[:space:]]+be[[:space:]]+a[[:space:]]+repo[[:space:]]+url[[:space:]]+(https://[^[:space:]]+)[[:space:]]+(branch[[:space:]]+or[[:space:]]+commit[[:space:]]+)?([a-f0-9]+)'

  local _re_annotation='^[[:space:]]*#[[:space:]]*@todo[[:space:]]+env-update[[:space:]]'

  local _line
  while IFS= read -r _line || [[ -n "${_line}" ]]; do
    (( ++_line_number )) || true

    # Git fallback line
    if [[ "${_line}" =~ ${_re_git_fallback} ]]; then
      _pending_git_url="${BASH_REMATCH[1]}"
      _pending_git_sha="${BASH_REMATCH[3]}"
      continue
    fi

    # Annotation line
    if [[ "${_line}" =~ ${_re_annotation} ]]; then
      if [[ "${_state}" == "AWAITING_VARIABLE" ]]; then
        printf 'env-update-v2: %s:%s: duplicate @todo env-update before assignment (previous at line %s)\n' \
          "${_env_file}" "${_line_number}" "${_pending_lnum}" >&2
        exit 1
      fi

      _state="AWAITING_VARIABLE"
      _pending_lnum="${_line_number}"
      _pending_annotation="${_line}"
      _pending_type="" _pending_identifier="" _pending_major_hint=""
      _pending_flags="" _pending_version="" _pending_hint=""
      _pend_pecl="" _pend_dep="" _pend_urls=""

      local _content="${_line#*@todo env-update}"
      _content="${_content#"${_content%%[! ]*}"}"

      local _flags_str="" _remaining=""
      _gs_eu2_extract_balanced_flags _flags_str _remaining "${_content}"

      # Parse TYPE:IDENTIFIER:MAJOR
      local _type_token=""
      if [[ "${_remaining}" =~ ^([a-z_-]+:[^[:space:]]+)[[:space:]](.*) ]]; then
        _type_token="${BASH_REMATCH[1]}"
        _remaining="${BASH_REMATCH[2]}"
      elif [[ "${_remaining}" =~ ^([a-z_-]+:[^[:space:]]+)$ ]]; then
        _type_token="${BASH_REMATCH[1]}"
        _remaining=""
      else
        local _got="${_remaining%% *}"
        printf 'env-update-v2: %s:%s: annotation has no TYPE:IDENTIFIER (got: %q)\n' \
          "${_env_file}" "${_line_number}" "${_got:-<empty>}" >&2
        exit 1
      fi

      _pending_type="${_type_token%%:*}"
      local _type_rest="${_type_token#*:}"
      _pending_identifier="${_type_rest}"
      _pending_major_hint=""
      if [[ "${_type_rest}" == *:* ]]; then
        local _maybe_major="${_type_rest##*:}"
        if [[ "${_maybe_major}" =~ ^[0-9][0-9.]*$ ]]; then
          _pending_major_hint="${_maybe_major}"
          _pending_identifier="${_type_rest%:*}"
        fi
      fi

      _pending_flags="${_flags_str}"

      # pecl-ref
      local _re_pecl='\(pecl-ref:([^)]+)\)'
      if [[ "${_remaining}" =~ ${_re_pecl} ]]; then
        _pend_pecl="${BASH_REMATCH[1]}"
        _remaining="${_remaining//${BASH_REMATCH[0]}/}"
        _remaining="${_remaining#"${_remaining%%[! ]*}"}"
        _remaining="${_remaining%"${_remaining##*[! ]}"}"
      fi

      # depends-on
      local _re_depends='\(depends-on:([^)]+)\)'
      if [[ "${_remaining}" =~ ${_re_depends} ]]; then
        local _dep_val="${BASH_REMATCH[1]}"
        if [[ "${_dep_val}" != *:* ]]; then
          printf 'env-update-v2: %s:%s: malformed depends-on — expected VAR:constraint, got %q\n' \
            "${_env_file}" "${_line_number}" "${_dep_val}" >&2
          exit 1
        fi
        _pend_dep="${_dep_val}"
        _remaining="${_remaining//${BASH_REMATCH[0]}/}"
        _remaining="${_remaining#"${_remaining%%[! ]*}"}"
        _remaining="${_remaining%"${_remaining##*[! ]}"}"
      fi

      # urls:
      if [[ " ${_remaining} " =~ [[:space:]]urls:[[:space:]] ]]; then
        local _before_urls="${_remaining%%urls:*}"
        local _after_urls="${_remaining#*urls:}"
        _after_urls="${_after_urls#"${_after_urls%%[! ]*}"}"
        local _url_tok _rest_after=""
        for _url_tok in ${_after_urls}; do
          if [[ "${_url_tok}" =~ ^https?:// ]]; then
            _pend_urls+="${_url_tok} "
          else
            _rest_after+="${_url_tok} "
          fi
        done
        _pend_urls="${_pend_urls% }"
        _remaining="${_before_urls}${_rest_after}"
        _remaining="${_remaining#"${_remaining%%[! ]*}"}"
        _remaining="${_remaining%"${_remaining##*[! ]}"}"
      fi

      # hint: trailing (text) parenthetical
      local _re_hint='^(.*)[[:space:]][(]([^)]+)[)][[:space:]]*$'
      if [[ "${_remaining}" =~ ${_re_hint} ]]; then
        _pending_hint="${BASH_REMATCH[2]}"
        _remaining="${BASH_REMATCH[1]}"
      fi

      _remaining="${_remaining#"${_remaining%%[! ]*}"}"
      _remaining="${_remaining%"${_remaining##*[! ]}"}"
      _pending_version="${_remaining}"
      continue
    fi

    # Variable assignment line
    if [[ "${_state}" == "AWAITING_VARIABLE" ]]; then
      if [[ "${_line}" =~ ^[[:space:]]*# ]]; then
        continue
      fi
      if [[ -z "${_line}" ]]; then
        _state="IDLE"
        _pending_git_url="" _pending_git_sha=""
        continue
      fi

      if [[ "${_line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        local _var_name="${BASH_REMATCH[1]}"
        local _var_value="${BASH_REMATCH[2]}"

        if [[ -n "${_filter}" && ! "${_var_name}" =~ ${_filter} ]]; then
          _state="IDLE"
          _pending_git_url="" _pending_git_sha=""
          continue
        fi

        local _final_version="${_pending_version}"
        [[ -z "${_final_version}" ]] && _final_version="${_var_value}"

        _gs_eu2_record_new
        local _idx="${_GS_EU2_LAST_IDX}"

        _gs_eu2_record_set "${_idx}" env_var          "${_var_name}"
        _gs_eu2_record_set "${_idx}" current_version  "${_final_version}"
        _gs_eu2_record_set "${_idx}" type             "${_pending_type}"
        _gs_eu2_record_set "${_idx}" identifier       "${_pending_identifier}"
        _gs_eu2_record_set "${_idx}" major_hint       "${_pending_major_hint}"
        _gs_eu2_record_set "${_idx}" hint             "${_pending_hint}"
        _gs_eu2_record_set "${_idx}" line_number      "${_pending_lnum}"
        _gs_eu2_record_set "${_idx}" raw_annotation   "${_pending_annotation}"
        _gs_eu2_record_set "${_idx}" git_fallback_url "${_pending_git_url}"
        _gs_eu2_record_set "${_idx}" git_fallback_sha "${_pending_git_sha}"
        _gs_eu2_record_set "${_idx}" pecl_ref         "${_pend_pecl}"
        _gs_eu2_record_set "${_idx}" depends_on       "${_pend_dep}"
        _gs_eu2_record_set "${_idx}" urls             "${_pend_urls}"

        # Dispatch inline flags
        if [[ -n "${_pending_flags}" ]]; then
          local _old_ifs="${IFS}"
          IFS=$'\x1f'
          local _frag
          for _frag in ${_pending_flags}; do
            IFS="${_old_ifs}"
            _gs_eu2_dispatch_flag "${_frag}" "${_env_file}" "${_pending_lnum}" "${_idx}"
          done
          IFS="${_old_ifs}"
        fi

        _state="IDLE"
        _pending_git_url="" _pending_git_sha=""
      fi
    fi
  done < "${_env_file}"
}
