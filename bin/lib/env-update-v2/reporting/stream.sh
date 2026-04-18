#!/bin/bash
# stream.sh — streaming per-record [TAG] output + summary for --check

[[ -n "${_GS_EU2_STREAM_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_STREAM_SH_LOADED=1

# shellcheck source=./../core/records.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/records.sh"

_gs_eu2_stream_records() {
  local _count
  _count="$(_gs_eu2_record_count)"
  [[ "${_count}" -eq 0 ]] && return 0

  local _n_auto=0 _n_hold=0 _n_skip=0 _n_error=0 _n_manual=0
  local _i _env_var _cur _prop _decision _err

  for (( _i = 0; _i < _count; _i++ )); do
    _env_var="$(_gs_eu2_record_get "${_i}" env_var)"
    _cur="$(_gs_eu2_record_get "${_i}" current_version)"
    _prop="$(_gs_eu2_record_get "${_i}" proposed_version)"
    _decision="$(_gs_eu2_record_get "${_i}" decision)"
    _err="$(_gs_eu2_record_get "${_i}" error_message)"

    case "${_decision}" in
      AUTO)   (( ++_n_auto ))   || true ;;
      HOLD)   (( ++_n_hold ))   || true ;;
      SKIP)   (( ++_n_skip ))   || true ;;
      ERROR)  (( ++_n_error ))  || true ;;
      MANUAL) (( ++_n_manual )) || true ;;
      *)      (( ++_n_skip ))   || true ;;
    esac

    local _tag
    case "${_decision}" in
      AUTO)   _tag="[AUTO  ]" ;;
      HOLD)   _tag="[HOLD  ]" ;;
      SKIP)   _tag="[SKIP  ]" ;;
      ERROR)  _tag="[ERROR ]" ;;
      MANUAL) _tag="[MANUAL]" ;;
      *)      _tag="[SKIP  ]" ;;
    esac

    local _change=""
    if [[ -n "${_prop}" && "${_prop}" != "${_cur}" ]]; then
      _change="  ${_cur} → ${_prop}"
    elif [[ -n "${_err}" ]]; then
      _change="  (${_err})"
    fi

    printf '%s  %-60s%s\n' "${_tag}" "${_env_var}" "${_change}"
  done

  local _total=$(( _n_auto + _n_hold + _n_skip + _n_error + _n_manual ))
  printf '%-60s\n' "──────────────────────────────────────────────────────────────"
  printf '  Summary: %d AUTO, %d HOLD, %d MANUAL, %d SKIP, %d ERROR  (%d checked)\n' \
    "${_n_auto}" "${_n_hold}" "${_n_manual}" "${_n_skip}" "${_n_error}" "${_total}"
}
