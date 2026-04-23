#!/bin/bash
# apply.sh — rewrite .env AUTO decisions back to the env file

[[ -n "${_GS_EU2_APPLY_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_APPLY_SH_LOADED=1

# shellcheck source=./records.sh
source "$(dirname "${BASH_SOURCE[0]}")/records.sh"

# Rewrite a single VAR=value line in an env file (atomic via tmp+mv).
# Uses index() for literal matching — no regex escaping needed.
_gs_eu2_apply_single() {
  local _file="${1}" _var="${2}" _new="${3}"
  local _tmp
  _tmp="$(mktemp)"
  awk -v var="${_var}" -v newval="${_new}" '
    /^[[:space:]]*#/ { print; next }
    index($0, var "=") == 1 { print var "=" newval; next }
    { print }
  ' "${_file}" > "${_tmp}" && mv "${_tmp}" "${_file}"
}

# Apply all AUTO decisions from records to the env file.
# Args: $1 = env_file, $2 = dry_run ("true" → no writes)
_gs_eu2_apply_updates() {
  local _env_file="${1}" _dry_run="${2:-false}"
  local _count; _count="$(_gs_eu2_record_count)"
  local _n_applied=0 _n_would=0

  local _i _var _cur _prop _decision
  for (( _i = 0; _i < _count; _i++ )); do
    _decision="$(_gs_eu2_record_get "${_i}" decision)"
    [[ "${_decision}" != "AUTO" ]] && continue
    _var="$(_gs_eu2_record_get "${_i}" env_var)"
    _cur="$(_gs_eu2_record_get "${_i}" current_version)"
    _prop="$(_gs_eu2_record_get "${_i}" proposed_version)"
    [[ -z "${_prop}" || "${_prop}" == "${_cur}" ]] && continue

    if [[ "${_dry_run}" == "true" ]]; then
      printf '  [DRY-RUN]  %-55s  %s → %s\n' "${_var}" "${_cur}" "${_prop}"
      (( ++_n_would )) || true
    else
      _gs_eu2_apply_single "${_env_file}" "${_var}" "${_prop}"
      printf '  [APPLIED]  %-55s  %s → %s\n' "${_var}" "${_cur}" "${_prop}"
      (( ++_n_applied )) || true
    fi
  done

  if [[ "${_dry_run}" == "true" ]]; then
    printf '  %d update(s) would be applied (--dry-run — no writes)\n' "${_n_would}"
  else
    printf '  %d update(s) applied to %s\n' "${_n_applied}" "${_env_file}"
  fi
}
