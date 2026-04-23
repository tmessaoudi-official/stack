#!/bin/bash
# dump.sh — record printer (text and JSON formats)

[[ -n "${_GS_EU2_DUMP_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_DUMP_SH_LOADED=1

# shellcheck source=./../core/records.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/records.sh"

_gs_eu2_dump_text() {
  local _count
  _count="$(_gs_eu2_record_count)"
  local _i _field _val
  for (( _i = 0; _i < _count; _i++ )); do
    echo "=== record ${_i} ==="
    while IFS= read -r _field; do
      _val="$(_gs_eu2_record_get "${_i}" "${_field}")"
      printf '%s: %s\n' "${_field}" "${_val}"
    done < <(_gs_eu2_record_fields)
  done
}

_gs_eu2_dump_json() {
  local _count
  _count="$(_gs_eu2_record_count)"
  printf '[\n'
  local _i _field _val
  for (( _i = 0; _i < _count; _i++ )); do
    [[ "${_i}" -gt 0 ]] && printf ',\n'
    printf '  {\n'
    local _first=true
    while IFS= read -r _field; do
      _val="$(_gs_eu2_record_get "${_i}" "${_field}")"
      [[ "${_first}" == "true" ]] && _first=false || printf ',\n'
      # Escape backslashes and double-quotes for JSON
      local _escaped
      _escaped="${_val//\\/\\\\}"
      _escaped="${_escaped//\"/\\\"}"
      printf '    %s: %s' "$(printf '"%s"' "${_field}")" "$(printf '"%s"' "${_escaped}")"
    done < <(_gs_eu2_record_fields)
    printf '\n  }'
  done
  printf '\n]\n'
}

_gs_eu2_dump_records() {
  local _format="${1:-text}"
  case "${_format}" in
    text) _gs_eu2_dump_text ;;
    json) _gs_eu2_dump_json ;;
    *)
      printf 'env-update-v2: unknown --format value: %q (valid: text, json)\n' "${_format}" >&2
      exit 1 ;;
  esac
}
