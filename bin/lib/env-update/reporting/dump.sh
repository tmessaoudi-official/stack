#!/bin/bash
# dump.sh — record printer for --dump flag (text and JSON formats).
#
# Exports:   _gs_eu2_dump_text  _gs_eu2_dump_json  _gs_eu2_dump_records
# Sources:   core/records.sh
# Deps:      jq (JSON format only — used for correct string escaping)
# Env:       none

[[ -n "${_GS_EU2_DUMP_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_DUMP_SH_LOADED=1

# shellcheck source=./../core/records.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/records.sh"

# _gs_eu2_dump_text — print all records in human-readable key:value format.
#
# Args:    none (reads all records via _gs_eu2_record_count / _gs_eu2_record_get)
# Prints:  one "=== record N ===" header per record, followed by field:value lines
# Returns: 0 always
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

# _gs_eu2_dump_json — print all records as a JSON array.
#
# Args:    none
# Prints:  valid JSON array; uses jq for proper string escaping (\n, \t, control chars)
# Returns: 0 always
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
      # Use jq for correct JSON string escaping (handles \n, \t, \r, control chars, etc.)
      local _json_key _json_val
      _json_key="$(printf '%s' "${_field}" | jq -Rs '.')"
      _json_val="$(printf '%s' "${_val}"   | jq -Rs '.')"
      printf '    %s: %s' "${_json_key}" "${_json_val}"
    done < <(_gs_eu2_record_fields)
    printf '\n  }'
  done
  printf '\n]\n'
}

# _gs_eu2_dump_records — dispatch to text or JSON printer based on format flag.
#
# Args:    $1 format — "text" (default) or "json"
# Prints:  record dump in the requested format
# Returns: 0 on success; exits non-zero for unknown format values
_gs_eu2_dump_records() {
  local _format="${1:-text}"
  case "${_format}" in
    text) _gs_eu2_dump_text ;;
    json) _gs_eu2_dump_json ;;
    *)
      printf 'env-update: unknown --format value: %q (valid: text, json)\n' "${_format}" >&2
      exit 1 ;;
  esac
}
