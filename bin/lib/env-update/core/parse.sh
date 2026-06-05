#!/bin/bash
# parse.sh — .env annotation parser (two-pass: hoist flags, then parse TYPE:ID/version).
#
# Exports:   _gs_eu2_is_recognized_flag  _gs_eu2_hoist_all_flags
#            _gs_eu2_dispatch_flag  _gs_eu2_parse_env_file
# Sources:   core/records.sh
# Deps:      bash 4.3+ (nameref used in _gs_eu2_hoist_all_flags)
# Env:       none
#
# Two-pass annotation parsing:
#   Pass 1 (_gs_eu2_hoist_all_flags): scan the entire annotation string for balanced
#          (flag) groups whose key is in the recognised-flag set; extract them
#          position-agnostically into a $'\x1f'-delimited list.
#   Pass 2: parse TYPE:IDENTIFIER[:MAJOR_HINT] from the cleaned (flags-removed) string,
#          then extract sha:/urls: keywords and a trailing (hint) parenthetical.
#
# This two-pass design means flags can appear anywhere in the annotation line
# (before or after the TYPE:ID field) without breaking the parser.

[[ -n "${_GS_EU2_PARSE_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_PARSE_SH_LOADED=1

# shellcheck source=./records.sh
source "$(dirname "${BASH_SOURCE[0]}")/records.sh"

# _gs_eu2_is_recognized_flag — test whether a flag name is in the known-flag set.
#
# Args:    $1 flag_content — content inside parens (e.g. "channel:rc", "manual")
# Prints:  nothing
# Returns: 0 if the flag name (before any ":") is recognised; 1 if not
#
# Used by _gs_eu2_hoist_all_flags to decide whether a balanced (…) group is a
# flag to extract or a hint/compat note to leave in the annotation string.
_gs_eu2_is_recognized_flag() {
  local _f="${1}" _name
  [[ "${_f}" == *:* ]] && _name="${_f%%:*}" || _name="${_f}"
  case "${_name}" in
    override | manual | propagate | use-sha | prefer-specific | check-tags | \
      note | \
      channel | skip | lock | \
      tag-filter | tag-exclude | tag-strip-prefix | tag-strip-suffix | \
      tag-channel-prefix | \
      tag-extract | tag-suffix | tag-replace | \
      fetch-extract | fetch-json | \
      url-probe | url-probe-depth | \
      version-prefix | watch-major | \
      replace | \
      depends-on | git) return 0 ;;
    *) return 1 ;;
  esac
}

# _gs_eu2_hoist_all_flags — extract all recognised flag groups from an annotation string.
#
# Args:    $1 flags_var   — nameref: output variable for extracted flags (joined by $'\x1f')
#          $2 cleaned_var — nameref: output variable for annotation with flags removed
#          $3 input       — raw annotation string after "@todo env-update "
# Reads:   nothing
# Sets:    $1 (by nameref): $'\x1f'-delimited list of flag contents (e.g. "manual\x1fchannel:rc")
#          $2 (by nameref): annotation with recognised flags and their trailing spaces removed
# Prints:  nothing
# Returns: 0 always
#
# Pass 1 of the two-pass parser.  Handles nested parens (depth tracking) and
# consumes one trailing space after each extracted flag to avoid double-space
# artifacts in the cleaned string.  Unrecognised (…) groups and unbalanced
# parens are passed through unchanged.
_gs_eu2_hoist_all_flags() {
  local -n _haf_flags="${1}"
  local -n _haf_cleaned="${2}"
  local _haf_in="${3}"

  _haf_flags=""
  local _haf_result="" _haf_len="${#_haf_in}" _haf_i=0

  while ((_haf_i < _haf_len)); do
    local _haf_ch="${_haf_in:${_haf_i}:1}"

    if [[ "${_haf_ch}" != "(" ]]; then
      _haf_result+="${_haf_ch}"
      ((++_haf_i)) || true
      continue
    fi

    # Found '(' — extract the balanced group
    local _haf_depth=0 _haf_content="" _haf_found=false _haf_end=0 _haf_j
    for ((_haf_j = _haf_i; _haf_j < _haf_len; _haf_j++)); do
      local _haf_c="${_haf_in:${_haf_j}:1}"
      if [[ "${_haf_c}" == "(" ]]; then
        ((++_haf_depth)) || true
        ((_haf_depth > 1)) && _haf_content+="${_haf_c}"
      elif [[ "${_haf_c}" == ")" ]]; then
        ((--_haf_depth)) || true
        if ((_haf_depth == 0)); then
          _haf_found=true
          _haf_end=$((_haf_j + 1))
          break
        else
          _haf_content+="${_haf_c}"
        fi
      else
        _haf_content+="${_haf_c}"
      fi
    done

    if [[ "${_haf_found}" == "true" ]] && _gs_eu2_is_recognized_flag "${_haf_content}"; then
      # Recognised flag — extract it
      [[ -n "${_haf_flags}" ]] && _haf_flags+=$'\x1f'
      _haf_flags+="${_haf_content}"
      # Swallow one trailing space (flag separator) if present
      if ((_haf_end < _haf_len)) && [[ "${_haf_in:${_haf_end}:1}" == " " ]]; then
        ((++_haf_end)) || true
      fi
      _haf_i="${_haf_end}"
    elif [[ "${_haf_found}" == "true" ]]; then
      # Not a recognised flag (hint or compat note) — keep the whole group
      _haf_result+="(${_haf_content})"
      _haf_i="${_haf_end}"
    else
      # Unbalanced paren — keep as-is
      _haf_result+="${_haf_ch}"
      ((++_haf_i)) || true
    fi
  done

  # Trim leading and trailing whitespace
  _haf_cleaned="${_haf_result#"${_haf_result%%[! ]*}"}"
  _haf_cleaned="${_haf_cleaned%"${_haf_cleaned##*[! ]}"}"
}

# _gs_eu2_dispatch_flag — validate a flag token and write its value to the record.
#
# Args:    $1 flag_content — content inside parens (e.g. "channel:rc", "manual")
#          $2 env_file     — path to the .env file (for error messages only)
#          $3 line_num     — annotation line number (for error messages)
#          $4 record_idx   — 0-based record index to write field into
# Reads:   nothing (validation is done inline)
# Sets:    record fields via _gs_eu2_record_set (specific field depends on flag name)
# Prints:  error message to stderr on unknown/invalid flag
# Returns: 0 on success; exits 1 on unknown or malformed flag
#
# See the checklist at the bottom of this file when adding a new flag.
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
    override)
      _gs_eu2_record_set "${_idx}" override "true"
      return 0
      ;;
    manual)
      _gs_eu2_record_set "${_idx}" manual "true"
      return 0
      ;;
    propagate)
      _gs_eu2_record_set "${_idx}" propagate "true"
      return 0
      ;;
    use-sha)
      _gs_eu2_record_set "${_idx}" use_sha "true"
      return 0
      ;;
    prefer-specific)
      _gs_eu2_record_set "${_idx}" prefer_specific "true"
      return 0
      ;;
    check-tags)
      _gs_eu2_record_set "${_idx}" check_tags "true"
      return 0
      ;;
    watch-major)
      # Value is optional: watch-major defaults to depth 1, watch-major:N sets depth N
      local _wm_depth="${_val:-1}"
      if [[ ! "${_wm_depth}" =~ ^[1-9][0-9]*$ ]]; then
        printf 'env-update: %s:%s: flag watch-major depth must be a positive integer (got: %q)\n' \
          "${_env_file}" "${_lnum}" "${_wm_depth}" >&2
        exit 1
      fi
      _gs_eu2_record_set "${_idx}" watch_major_depth "${_wm_depth}"
      return 0
      ;;
  esac

  # Keyed flags: validate non-empty value
  case "${_name}" in
    note | \
      channel | skip | lock | tag-filter | tag-exclude | tag-strip-prefix | tag-strip-suffix | \
      tag-channel-prefix | \
      tag-extract | tag-suffix | fetch-extract | fetch-json | url-probe | url-probe-depth | \
      version-prefix)
      if [[ -z "${_val}" ]]; then
        printf 'env-update: %s:%s: flag %q requires a non-empty value\n' \
          "${_env_file}" "${_lnum}" "${_name}" >&2
        exit 1
      fi
      ;;
    tag-replace)
      if [[ -z "${_val}" || "${_val}" != *:* ]]; then
        printf 'env-update: %s:%s: flag tag-replace requires FROM:TO format\n' \
          "${_env_file}" "${_lnum}" >&2
        exit 1
      fi
      ;;
    replace)
      if [[ -z "${_val}" || "${_val}" != *=* ]]; then
        printf 'env-update: %s:%s: flag replace requires TARGET=template format\n' \
          "${_env_file}" "${_lnum}" >&2
        exit 1
      fi
      ;;
    depends-on)
      if [[ -z "${_val}" || "${_val}" != *:* ]]; then
        printf 'env-update: %s:%s: malformed depends-on — expected VAR:constraint, got %q\n' \
          "${_env_file}" "${_lnum}" "${_val:-<empty>}" >&2
        exit 1
      fi
      ;;
    git)
      if [[ -z "${_val}" || "${_val}" != */* ]]; then
        printf 'env-update: %s:%s: flag git requires OWNER/REPO format\n' \
          "${_env_file}" "${_lnum}" >&2
        exit 1
      fi
      ;;
    *)
      printf 'env-update: %s:%s: unknown flag %q in annotation\n' \
        "${_env_file}" "${_lnum}" "${_name}" >&2
      exit 1
      ;;
  esac

  case "${_name}" in
    note) _gs_eu2_record_set "${_idx}" note "${_val}" ;;
    channel) _gs_eu2_record_set "${_idx}" channel "${_val}" ;;
    skip) _gs_eu2_record_set "${_idx}" skip_reason "${_val}" ;;
    lock) _gs_eu2_record_set "${_idx}" lock_reason "${_val}" ;;
    tag-filter) _gs_eu2_record_set "${_idx}" tag_filter "${_val}" ;;
    tag-exclude) _gs_eu2_record_set "${_idx}" tag_exclude "${_val}" ;;
    tag-strip-prefix) _gs_eu2_record_set "${_idx}" tag_strip_prefix "${_val}" ;;
    tag-strip-suffix) _gs_eu2_record_set "${_idx}" tag_strip_suffix "${_val}" ;;
    tag-channel-prefix) _gs_eu2_record_set "${_idx}" tag_channel_prefix "${_val}" ;;
    tag-extract) _gs_eu2_record_set "${_idx}" tag_extract "${_val}" ;;
    tag-suffix) _gs_eu2_record_set "${_idx}" tag_suffix "${_val}" ;;
    fetch-extract) _gs_eu2_record_set "${_idx}" fetch_extract "${_val}" ;;
    fetch-json) _gs_eu2_record_set "${_idx}" fetch_json "${_val}" ;;
    url-probe) _gs_eu2_record_set "${_idx}" url_probe "${_val}" ;;
    url-probe-depth) _gs_eu2_record_set "${_idx}" url_probe_depth "${_val}" ;;
    # D2: version_prefix stored; applied during fetch/compare in Phase 3
    version-prefix) _gs_eu2_record_set "${_idx}" version_prefix "${_val}" ;;
    # pecl-ref removed: use pecl:EXTNAME (git:owner/repo) instead
    depends-on) _gs_eu2_record_set "${_idx}" depends_on "${_val}" ;;
    git) _gs_eu2_record_set "${_idx}" git_repo "${_val}" ;;
    tag-replace)
      _gs_eu2_record_set "${_idx}" tag_replace_from "${_val%%:*}"
      _gs_eu2_record_set "${_idx}" tag_replace_to "${_val#*:}"
      ;;
    replace)
      # Append target and template using $'\x1f' as delimiter (parallel arrays).
      local _rep_target="${_val%%=*}"
      local _rep_tmpl="${_val#*=}"
      local _cur_targets _cur_tmpls
      _cur_targets="$(_gs_eu2_record_get "${_idx}" replace_targets)"
      _cur_tmpls="$(_gs_eu2_record_get "${_idx}" replace_templates)"
      if [[ -n "${_cur_targets}" ]]; then
        _gs_eu2_record_set "${_idx}" replace_targets "${_cur_targets}"$'\x1f'"${_rep_target}"
        _gs_eu2_record_set "${_idx}" replace_templates "${_cur_tmpls}"$'\x1f'"${_rep_tmpl}"
      else
        _gs_eu2_record_set "${_idx}" replace_targets "${_rep_target}"
        _gs_eu2_record_set "${_idx}" replace_templates "${_rep_tmpl}"
      fi
      ;;
  esac
}

# ── Adding a new CLI annotation flag checklist ─────────────────────────────
# When adding a new (flag-name:value) annotation:
# 1. Add validation in _gs_eu2_parse_hoist_flag() above: "flag-name) return 0 ;;"
# 2. Add dispatch in _gs_eu2_parse_hoist_dispatch() above: "flag-name) _gs_eu2_record_set ... ;;"
# 3. Add the new field to _gs_eu2_record_fields() in core/records.sh (if needed)
# 4. Add banner in main.sh (if it is a global mode flag like --unstable/--stable)
# 5. Add --dump serialization if the flag affects record state (it's automatic
#    if it's a record field — dump.sh iterates _gs_eu2_record_fields())
# 6. Update templates/tips/env-update.md §5 flag reference table
# 7. Add at least two tests:
#    - flag is parsed and stored (record field matches expected value)
#    - flag is effective (fetcher or decide.sh behaves differently with it)

# _gs_eu2_parse_env_file — read a .env file and populate the record array.
#
# Args:    $1 env_file — path to the .env file to parse
#          $2 filter   — optional regex or "type:TYPE" prefix to include only
#                        matching variables (empty = include all)
#          $3 exclude  — optional regex: skip variables whose name matches
# Reads:   env_file line by line
# Sets:    all record fields for each matched annotation+variable pair
#          (via _gs_eu2_record_new + _gs_eu2_record_set)
# Prints:  error messages to stderr on malformed annotations
# Returns: 0 on success; exits 1 on parse errors (duplicate annotation, missing
#          assignment, unknown flag, bad range syntax)
# Side fx: increments _GS_EU2_REC_COUNT and writes _GS_EU2_REC_* flat variables
#
# State machine: IDLE → AWAITING_VARIABLE → IDLE.
# Blank lines and comment lines between the annotation and the VAR= line are
# tolerated (C2 rule); any other non-assignment line is an error and resets state.
_gs_eu2_parse_env_file() {
  local _env_file="${1}"
  local _filter="${2:-}"
  local _exclude="${3:-}"

  local _state="IDLE"
  local _pending_annotation="" _pending_lnum=0
  local _pending_type="" _pending_identifier="" _pending_major_hint="" _pending_major_hint_min=""
  local _pending_flags="" _pending_version="" _pending_hint=""
  local _pending_sha="" _pending_sha_date=""
  local _pending_git_url="" _pending_git_sha=""
  local _pend_urls=""
  local _line_number=0

  local _re_git_fallback
  _re_git_fallback='^[[:space:]]*#[[:space:]]*@todo[[:space:]]+could[[:space:]]+be[[:space:]]+a[[:space:]]+repo[[:space:]]+url[[:space:]]+(https://[^[:space:]]+)[[:space:]]+(branch[[:space:]]+or[[:space:]]+commit[[:space:]]+)?([a-f0-9]+)'

  local _re_annotation='^[[:space:]]*#[[:space:]]*@todo[[:space:]]+env-update[[:space:]]'

  local _line
  while IFS= read -r _line || [[ -n "${_line}" ]]; do
    ((++_line_number)) || true

    # Git fallback line
    if [[ "${_line}" =~ ${_re_git_fallback} ]]; then
      _pending_git_url="${BASH_REMATCH[1]}"
      _pending_git_sha="${BASH_REMATCH[3]}"
      continue
    fi

    # Annotation line
    if [[ "${_line}" =~ ${_re_annotation} ]]; then
      if [[ "${_state}" == "AWAITING_VARIABLE" ]]; then
        printf 'env-update: %s:%s: duplicate @todo env-update before assignment (previous at line %s)\n' \
          "${_env_file}" "${_line_number}" "${_pending_lnum}" >&2
        exit 1
      fi

      _state="AWAITING_VARIABLE"
      _pending_lnum="${_line_number}"
      _pending_annotation="${_line}"
      _pending_type="" _pending_identifier="" _pending_major_hint="" _pending_major_hint_min=""
      _pending_flags="" _pending_version="" _pending_hint=""
      _pending_sha="" _pending_sha_date=""
      _pend_urls=""

      local _content="${_line#*@todo env-update}"
      _content="${_content#"${_content%%[! ]*}"}"

      # Pass 1: hoist all recognised flag parens (position-agnostic)
      local _flags_str="" _content_clean=""
      _gs_eu2_hoist_all_flags _flags_str _content_clean "${_content}"

      # Pass 2: parse TYPE:IDENTIFIER[:MAJOR_HINT] from cleaned content
      local _remaining=""
      local _type_token=""
      if [[ "${_content_clean}" =~ ^([a-z_-]+:[^[:space:]]+)[[:space:]](.*) ]]; then
        _type_token="${BASH_REMATCH[1]}"
        _remaining="${BASH_REMATCH[2]}"
      elif [[ "${_content_clean}" =~ ^([a-z_-]+:[^[:space:]]+)$ ]]; then
        _type_token="${BASH_REMATCH[1]}"
        _remaining=""
      else
        # Detect unrecognised leading flag for a better error message
        if [[ "${_content_clean:0:1}" == "(" ]]; then
          local _bad_flag="${_content_clean#(}"
          _bad_flag="${_bad_flag%%)*}"
          _bad_flag="${_bad_flag%%:*}"
          printf 'env-update: %s:%s: unknown flag %q in annotation\n' \
            "${_env_file}" "${_line_number}" "${_bad_flag}" >&2
        else
          local _got="${_content_clean%% *}"
          printf 'env-update: %s:%s: annotation has no TYPE:IDENTIFIER (got: %q)\n' \
            "${_env_file}" "${_line_number}" "${_got:-<empty>}" >&2
        fi
        exit 1
      fi

      _pending_type="${_type_token%%:*}"
      local _type_rest="${_type_token#*:}"
      _pending_identifier="${_type_rest}"
      _pending_major_hint=""
      _pending_major_hint_min=""
      if [[ "${_type_rest}" == *:* ]]; then
        local _maybe_major="${_type_rest##*:}"
        if [[ "${_maybe_major}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
          # Range syntax: TYPE:IDENTIFIER:LOW-HIGH
          # LOW = fallback major (use until HIGH ships), HIGH = desired major.
          # Parse time validation: LOW must be < HIGH (integers only).
          local _range_low="${BASH_REMATCH[1]}" _range_high="${BASH_REMATCH[2]}"
          if (( _range_low >= _range_high )); then
            printf 'env-update: %s:%s: range annotation requires LOW < HIGH (got %s-%s)\n' \
              "${_env_file}" "${_line_number}" "${_range_low}" "${_range_high}" >&2
            exit 1
          fi
          _pending_major_hint="${_range_high}"
          _pending_major_hint_min="${_range_low}"
          _pending_identifier="${_type_rest%:*}"
        elif [[ "${_maybe_major}" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
          _pending_major_hint="${_maybe_major}"
          _pending_identifier="${_type_rest%:*}"
        fi
      fi

      _pending_flags="${_flags_str}"

      # Trim leading whitespace from remaining
      _remaining="${_remaining#"${_remaining%%[! ]*}"}"

      # urls: keyword (not a paren flag — handled separately)
      if [[ " ${_remaining} " =~ [[:space:]]urls:[[:space:]] ]]; then
        local _before_urls="${_remaining%%urls:*}"
        local _after_urls="${_remaining#*urls:}"
        _after_urls="${_after_urls#"${_after_urls%%[! ]*}"}"
        local _url_tok _rest_after="" _url_arr=()
        read -ra _url_arr <<< "${_after_urls}"
        for _url_tok in "${_url_arr[@]}"; do
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

      # sha: keyword — annotated commit SHA (not a paren flag — handled separately)
      # Format: sha:HASH or sha:HASH (YYYY-MM-DD) — the date paren must be consumed
      # here before the hint regex would otherwise swallow it.
      local _sha_date_re='(^|[[:space:]])sha:([0-9a-f]+)[[:space:]]+\(([0-9]{4}-[0-9]{2}-[0-9]{2})\)'
      if [[ "${_remaining}" =~ ${_sha_date_re} ]]; then
        _pending_sha="${BASH_REMATCH[2]}"
        _pending_sha_date="${BASH_REMATCH[3]}"
        # Remove the matched portion (sha:HASH (YYYY-MM-DD)) from _remaining
        local _sha_with_date="sha:${_pending_sha} (${_pending_sha_date})"
        _remaining="${_remaining//${_sha_with_date}/}"
        _remaining="${_remaining#"${_remaining%%[! ]*}"}"
        _remaining="${_remaining%"${_remaining##*[! ]}"}"
      elif [[ " ${_remaining} " == *" sha:"* || "${_remaining}" == sha:* ]]; then
        local _sha_tok _remaining_no_sha=""
        for _sha_tok in ${_remaining}; do
          if [[ "${_sha_tok}" == sha:* && -z "${_pending_sha}" ]]; then
            _pending_sha="${_sha_tok#sha:}"
          else
            _remaining_no_sha+="${_sha_tok} "
          fi
        done
        _remaining="${_remaining_no_sha% }"
        _remaining="${_remaining#"${_remaining%%[! ]*}"}"
        _remaining="${_remaining%"${_remaining##*[! ]}"}"
      fi

      # hint: trailing (text) parenthetical — non-flag, may contain spaces
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
      # C2: blank lines and comment lines keep the AWAITING_VARIABLE state
      if [[ "${_line}" =~ ^[[:space:]]*# ]]; then
        continue
      fi
      if [[ -z "${_line}" ]]; then
        continue
      fi

      if [[ "${_line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        local _var_name="${BASH_REMATCH[1]}"
        local _var_value="${BASH_REMATCH[2]}"

        # Filter: by type prefix (type:dockerhub) or var-name regex (current behaviour)
        if [[ -n "${_filter}" ]]; then
          if [[ "${_filter}" == type:* ]]; then
            local _filter_type="${_filter#type:}"
            if [[ "${_pending_type}" != "${_filter_type}" ]]; then
              _state="IDLE"
              _pending_sha="" _pending_sha_date=""
              _pending_git_url="" _pending_git_sha=""
              continue
            fi
          else
            # Case-insensitive match: capture result before resetting shopt
            local _filter_matched=0
            shopt -s nocasematch
            [[ "${_var_name}" =~ ${_filter} ]] && _filter_matched=1
            shopt -u nocasematch
            if [[ "${_filter_matched}" -eq 0 ]]; then
              _state="IDLE"
              _pending_sha="" _pending_sha_date=""
              _pending_git_url="" _pending_git_sha=""
              continue
            fi
          fi
        fi

        # Exclude: skip vars whose name matches --exclude regex.
        if [[ -n "${_exclude}" && "${_var_name}" =~ ${_exclude} ]]; then
          _state="IDLE"
          _pending_sha="" _pending_sha_date=""
          _pending_git_url="" _pending_git_sha=""
          continue
        fi

        local _final_version="${_pending_version}"
        [[ -z "${_final_version}" ]] && _final_version="${_var_value}"

        _gs_eu2_record_new
        local _idx="${_GS_EU2_LAST_IDX}"

        _gs_eu2_record_set "${_idx}" env_var "${_var_name}"
        _gs_eu2_record_set "${_idx}" current_version "${_final_version}"
        _gs_eu2_record_set "${_idx}" type "${_pending_type}"
        _gs_eu2_record_set "${_idx}" identifier "${_pending_identifier}"
        _gs_eu2_record_set "${_idx}" major_hint "${_pending_major_hint}"
        _gs_eu2_record_set "${_idx}" major_hint_min "${_pending_major_hint_min}"
        _gs_eu2_record_set "${_idx}" hint "${_pending_hint}"
        _gs_eu2_record_set "${_idx}" line_number "${_pending_lnum}"
        _gs_eu2_record_set "${_idx}" raw_annotation "${_pending_annotation}"
        _gs_eu2_record_set "${_idx}" git_fallback_url "${_pending_git_url}"
        _gs_eu2_record_set "${_idx}" git_fallback_sha "${_pending_git_sha}"
        _gs_eu2_record_set "${_idx}" urls "${_pend_urls}"
        _gs_eu2_record_set "${_idx}" annotation_sha "${_pending_sha}"
        _gs_eu2_record_set "${_idx}" annotation_sha_date "${_pending_sha_date}"
        # actual_var_value: raw VAR= value before any processing — used by drift detection
        # to compare what the env file actually contains vs. what the annotation claims.
        _gs_eu2_record_set "${_idx}" actual_var_value "${_var_value}"

        # Dispatch all hoisted flags (position-agnostic)
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
        _pending_sha="" _pending_sha_date=""
        _pending_git_url="" _pending_git_sha=""
      else
        # C2: non-blank non-comment non-assignment line — annotation not followed by var
        printf 'env-update: %s:%d: annotation not followed by variable assignment (got: %s)\n' \
          "${_env_file}" "${_line_number}" "${_line}" >&2
        _state="IDLE"
        _pending_git_url="" _pending_git_sha=""
      fi
    fi
  done <"${_env_file}"
}
