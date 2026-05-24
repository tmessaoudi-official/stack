#!/bin/bash
# summary.sh — default output when no action flags are given.
#
# Exports:   _gs_eu2_print_summary
# Sources:   config/defaults.sh  core/records.sh
# Deps:      bash 4.3+
# Env:       _GS_EU2_VERSION

[[ -n "${_GS_EU2_SUMMARY_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_SUMMARY_SH_LOADED=1

# shellcheck source=./../config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/defaults.sh"
# shellcheck source=./../core/records.sh
source "$(dirname "${BASH_SOURCE[0]}")/../core/records.sh"

# _gs_eu2_print_summary — print per-type count summary when no action flags given.
#
# Args:    $1 env_file — path to the parsed env file (shown in header line)
# Prints:  version header + count of annotated variables + per-type breakdown
# Returns: 0 always
_gs_eu2_print_summary() {
  local _env_file="${1}"
  local _count
  _count="$(_gs_eu2_record_count)"

  local _noun="variables"
  [[ "${_count}" -eq 1 ]] && _noun="variable"

  printf 'env-update v%s — parsed %s\n\n' "${_GS_EU2_VERSION}" "${_env_file}"
  printf '  %s annotated %s' "${_count}" "${_noun}"

  if [[ "${_count}" -eq 0 ]]; then
    printf '\n'
    return 0
  fi

  # Count by type
  local -A _type_counts=()
  local _i
  for (( _i = 0; _i < _count; _i++ )); do
    local _t
    _t="$(_gs_eu2_record_get "${_i}" type)"
    [[ -z "${_t}" ]] && _t="unknown"
    _type_counts["${_t}"]=$(( ${_type_counts["${_t}"]:-0} + 1 ))
  done

  # Collect sorted type names
  local -a _types=()
  local _k
  for _k in "${!_type_counts[@]}"; do
    _types+=("${_k}")
  done
  IFS=$'\n' read -r -d '' -a _types < <(printf '%s\n' "${_types[@]}" | sort && printf '\0') || true

  if [[ "${#_types[@]}" -gt 0 ]]; then
    local _type_count="${#_types[@]}"
    printf ' across %s fetcher %s:\n' "${_type_count}" "$( [[ "${_type_count}" -eq 1 ]] && echo "type" || echo "types" )"
    local _col=0
    for _k in "${_types[@]}"; do
      printf '    %-12s %-4s' "${_k}" "${_type_counts[${_k}]}"
      (( ++_col )) || true
      if (( _col % 3 == 0 )); then
        printf '\n'
        _col=0
      fi
    done
    [[ "$(( _col % 3 ))" -ne 0 ]] && printf '\n'
  else
    printf '\n'
  fi

  printf '\n'
  printf '  Hint: run --check to fetch latest versions (network required)\n'
  printf '        run --dump  to emit structured records\n'
  printf '        run --help  for all options\n'
}
