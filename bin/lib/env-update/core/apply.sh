#!/bin/bash
# apply.sh — rewrite .env AUTO decisions back to the env file

[[ -n "${_GS_EU2_APPLY_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_APPLY_SH_LOADED=1

# shellcheck source=./records.sh
source "$(dirname "${BASH_SOURCE[0]}")/records.sh"

# Rewrite a VAR=value line and its @todo annotation comment in one awk pass (atomic via tmp+mv).
# $4 = raw_annotation (exact comment line to match); $5 = current version token to replace.
# $6 = current annotation SHA (for sha: keyword replacement in annotation).
# $7 = new SHA to write into sha: keyword.
# $8 = use_sha flag ("true" → write new SHA to VAR= instead of new version).
# Finds " curval" as a literal word boundary — immune to trailing urls: extras.
_gs_eu2_apply_single() {
  local _file="${1}" _var="${2}" _new="${3}" _raw_ann="${4:-}" _cur="${5:-}" \
        _cur_sha="${6:-}" _new_sha="${7:-}" _use_sha="${8:-false}"
  local _tmp
  _tmp="$(mktemp)" || { printf 'env-update/apply: mktemp failed\n' >&2; return 1; }
  awk -v var="${_var}" -v newval="${_new}" -v raw_ann="${_raw_ann}" \
      -v curval="${_cur}" -v cur_sha="${_cur_sha}" -v new_sha="${_new_sha}" \
      -v use_sha="${_use_sha}" '
    /^[[:space:]]*#/ {
      if (raw_ann != "" && $0 == raw_ann) {
        line = $0
        # Update version token (space + version, first occurrence)
        if (curval != "" && newval != "") {
          idx = index(line, " " curval)
          if (idx > 0)
            line = substr(line, 1, idx) newval substr(line, idx + 1 + length(curval))
        }
        # Update sha: keyword (literal replacement)
        if (cur_sha != "" && new_sha != "") {
          sha_idx = index(line, "sha:" cur_sha)
          if (sha_idx > 0)
            line = substr(line, 1, sha_idx - 1) "sha:" new_sha \
                   substr(line, sha_idx + 4 + length(cur_sha))
        }
        print line; next
      }
      print; next
    }
    index($0, var "=") == 1 {
      # Skip VAR= rewrite when newval is empty and use_sha is not set.
      # This handles SHA-only updates where only the annotation comment changes.
      if (newval == "" && use_sha != "true") { print; next }
      val = (use_sha == "true" && new_sha != "") ? new_sha : newval
      print var "=" val; next
    }
    { print }
  ' "${_file}" > "${_tmp}" && mv "${_tmp}" "${_file}"
}

# Apply all AUTO decisions from records to the env file.
# Args: $1 = env_file, $2 = dry_run ("true" → no writes)
_gs_eu2_apply_updates() {
  local _env_file="${1}" _dry_run="${2:-false}"
  local _count; _count="$(_gs_eu2_record_count)"
  local _n_applied=0 _n_would=0

  local _i _var _cur _prop _decision _raw_ann
  local _ann_sha _ann_sha_date _new_sha _new_sha_date _use_sha
  local _n_sha_applied=0 _n_sha_would=0
  for (( _i = 0; _i < _count; _i++ )); do
    _decision="$(_gs_eu2_record_get "${_i}" decision)"

    # ── SHA-only update path ───────────────────────────────────────────────
    if [[ "${_decision}" == "SHA" ]]; then
      _var="$(_gs_eu2_record_get "${_i}" env_var)"
      _raw_ann="$(_gs_eu2_record_get "${_i}" raw_annotation)"
      _ann_sha="$(_gs_eu2_record_get "${_i}" annotation_sha)"
      _new_sha="$(_gs_eu2_record_get "${_i}" proposed_sha)"
      _new_sha_date="$(_gs_eu2_record_get "${_i}" proposed_sha_date)"
      # Construct new sha token: sha:FULLHASH (YYYY-MM-DD)
      local _new_sha_tok="${_new_sha}"
      [[ -n "${_new_sha_date}" ]] && _new_sha_tok="${_new_sha} (${_new_sha_date})"
      # Build old sha token to replace in annotation (match bare or with date)
      local _old_sha_tok="${_ann_sha}"
      _ann_sha_date="$(_gs_eu2_record_get "${_i}" annotation_sha_date)"
      [[ -n "${_ann_sha_date}" ]] && _old_sha_tok="${_ann_sha} (${_ann_sha_date})"

      if [[ "${_dry_run}" == "true" ]]; then
        printf '  [DRY-RUN]  %-55s  sha:%s → sha:%s\n' "${_var}" "${_ann_sha:0:8}" "${_new_sha:0:8}"
        (( ++_n_sha_would )) || true
      else
        # For SHA-only: pass empty _prop/_cur/_new (version line untouched);
        # reuse apply_single with cur_sha=old_sha_tok and new_sha=new_sha_tok.
        _gs_eu2_apply_single "${_env_file}" "${_var}" "" "${_raw_ann}" "" \
                              "${_old_sha_tok}" "${_new_sha_tok}" "false"
        printf '  [SHA]      %-55s  sha:%s → sha:%s\n' "${_var}" "${_ann_sha:0:8}" "${_new_sha:0:8}"
        (( ++_n_sha_applied )) || true
      fi
      continue
    fi

    # ── Version update path (AUTO decisions) ──────────────────────────────
    [[ "${_decision}" != "AUTO" ]] && continue
    _var="$(_gs_eu2_record_get "${_i}" env_var)"
    _cur="$(_gs_eu2_record_get "${_i}" current_version)"
    _prop="$(_gs_eu2_record_get "${_i}" proposed_version)"
    _raw_ann="$(_gs_eu2_record_get "${_i}" raw_annotation)"
    _ann_sha="$(_gs_eu2_record_get "${_i}" annotation_sha)"
    _ann_sha_date="$(_gs_eu2_record_get "${_i}" annotation_sha_date)"
    _new_sha="$(_gs_eu2_record_get "${_i}" proposed_sha)"
    _new_sha_date="$(_gs_eu2_record_get "${_i}" proposed_sha_date)"
    _use_sha="$(_gs_eu2_record_get "${_i}" use_sha)"
    [[ -z "${_prop}" || "${_prop}" == "${_cur}" ]] && continue

    # Build sha tokens for annotation rewrite (include date when available)
    local _old_sha_tok2="${_ann_sha}"
    [[ -n "${_ann_sha_date}" ]] && _old_sha_tok2="${_ann_sha} (${_ann_sha_date})"
    local _new_sha_tok2="${_new_sha}"
    [[ -n "${_new_sha_date}" ]] && _new_sha_tok2="${_new_sha} (${_new_sha_date})"

    if [[ "${_dry_run}" == "true" ]]; then
      local _display_proposed="${_prop}"
      [[ "${_use_sha:-false}" == "true" && -n "${_new_sha}" ]] && _display_proposed="${_new_sha}"
      printf '  [DRY-RUN]  %-55s  %s → %s\n' "${_var}" "${_cur}" "${_display_proposed}"
      (( ++_n_would )) || true
    else
      _gs_eu2_apply_single "${_env_file}" "${_var}" "${_prop}" "${_raw_ann}" "${_cur}" \
                            "${_old_sha_tok2}" "${_new_sha_tok2}" "${_use_sha:-false}"
      printf '  [APPLIED]  %-55s  %s → %s\n' "${_var}" "${_cur}" "${_prop}"
      (( ++_n_applied )) || true
    fi
  done

  if [[ "${_dry_run}" == "true" ]]; then
    local _total_would=$(( _n_would + _n_sha_would ))
    printf '  %d update(s) would be applied (%d version, %d SHA) (--dry-run — no writes)\n' \
      "${_total_would}" "${_n_would}" "${_n_sha_would}"
  else
    local _total_applied=$(( _n_applied + _n_sha_applied ))
    printf '  %d update(s) applied to %s (%d version, %d SHA)\n' \
      "${_total_applied}" "${_env_file}" "${_n_applied}" "${_n_sha_applied}"
  fi
}
