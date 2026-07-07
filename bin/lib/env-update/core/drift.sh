#!/bin/bash
# drift.sh — signal sub-functions for per-record sub-line output in env-update.
#
# Exports:   _gs_eu2_signal_primary_line  _gs_eu2_signal_fallback
#            _gs_eu2_signal_pin_miss  _gs_eu2_signal_watch
#            _gs_eu2_signal_sha  _gs_eu2_signal_unstable
#            _gs_eu2_signal_stable  _gs_eu2_signal_depends_on
#            _gs_eu2_signal_drift  _gs_eu2_signal_replace_drift
# Sources:   core/records.sh  core/semver.sh  core/apply.sh
# Deps:      bash 4.3+
# Env:       _GS_EU2_CFG (no_drift, no_notes, unstable, stable)
#
# Each _gs_eu2_signal_* function handles one class of sub-line output for a
# single record.  They are called as plain function calls (not subshells) so
# they can increment the _n_* counters that live in the parent loop scope via
# dynamic scoping — no `local` re-declaration of counter variables here.
# All sub-functions end with `return 0` to prevent set -e / ERR-trap from
# firing when an internal [[ … ]] test evaluates to false.

[[ -n "${_GS_EU2_CORE_DRIFT_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_CORE_DRIFT_SH_LOADED=1

# ── Signal sub-functions ──────────────────────────────────────────────────────
# Each _gs_eu2_signal_* function handles one class of sub-line output for a
# single record.  They are called as plain function calls (not subshells) so
# they can increment the _n_* counters that live in the parent loop scope via
# dynamic scoping — no `local` re-declaration of counter variables here.
# All sub-functions end with `return 0` to prevent set -e / ERR-trap from
# firing when an internal [[ … ]] test evaluates to false.

# _gs_eu2_signal_primary_line — print the main decision line + optional note sub-line.
# Args: _tag _max_var_len _env_var _change _note
_gs_eu2_signal_primary_line() {
  local _tag="${1}" _max_var_len="${2}" _env_var="${3}" _change="${4}" _note="${5}"
  printf "%s  %-${_max_var_len}s%s\n" "${_tag}" "${_env_var}" "${_change}"
  [[ -n "${_note}" && "${_GS_EU2_CFG[no_notes]:-false}" != "true" ]] && \
    printf '%10s↳ %s\n' "" "${_note}"
  return 0
}

# _gs_eu2_signal_fallback — [FALLBACK] sub-line when major range fell back to LOW major.
# Args: _i _major _major_min
_gs_eu2_signal_fallback() {
  local _i="${1}" _major="${2}" _major_min="${3}"
  local _using_fallback_disp
  _using_fallback_disp="$(_gs_eu2_record_get "${_i}" using_fallback_major)"
  if [[ "${_using_fallback_disp}" == "true" && -n "${_major_min}" ]]; then
    printf '%10s↳ [FALLBACK] major=%s not yet in registry — using fallback major=%s\n' \
      "" "${_major}" "${_major_min}"
    (( ++_n_fallback )) || true
  fi
  return 0
}

# _gs_eu2_signal_pin_miss — [PIN-MISS] sub-line when major-pin produced zero results.
# Args: _i _decision _major _skip_err_disp
_gs_eu2_signal_pin_miss() {
  local _i="${1}" _decision="${2}" _major="${3}" _skip_err_disp="${4}"
  if [[ "${_decision}" == "SKIP" && -n "${_major}" && -n "${_skip_err_disp}" ]]; then
    local _pin_uc
    _pin_uc="$(_gs_eu2_record_get "${_i}" latest_unconstrained)"
    if [[ -n "${_pin_uc}" ]]; then
      printf '%10s↳ [PIN-MISS] major=%s not yet in registry — globally latest: %s\n' \
        "" "${_major}" "${_pin_uc}"
    fi
  fi
  return 0
}

# _gs_eu2_signal_watch — [WATCH] sub-line when a new runtime generation is available.
# Args: _i _decision _cur _prop
_gs_eu2_signal_watch() {
  local _i="${1}" _decision="${2}" _cur="${3}" _prop="${4}"
  if [[ "${_decision}" != "ERROR" ]]; then
    local _wm_depth_r
    _wm_depth_r="$(_gs_eu2_record_get "${_i}" watch_major_depth)"
    if [[ -n "${_wm_depth_r}" ]]; then
      local _wm_latest
      _wm_latest="$(_gs_eu2_record_get "${_i}" latest_unconstrained)"
      [[ -z "${_wm_latest}" ]] && _wm_latest="${_prop}"
      if [[ -n "${_wm_latest}" && -n "${_cur}" ]]; then
        local _wm_cur_pfx _wm_lat_pfx
        _wm_cur_pfx="$(_gs_eu2_version_prefix "${_cur}" "${_wm_depth_r}")"
        _wm_lat_pfx="$(_gs_eu2_version_prefix "${_wm_latest}" "${_wm_depth_r}")"
        if [[ -n "${_wm_cur_pfx}" && -n "${_wm_lat_pfx}" && \
              "${_wm_cur_pfx}" != "${_wm_lat_pfx}" ]]; then
          local _wm_higher
          _wm_higher="$(printf '%s\n%s\n' "${_wm_cur_pfx}" "${_wm_lat_pfx}" | sort -V | tail -1)"
          if [[ "${_wm_higher}" == "${_wm_lat_pfx}" ]]; then
            printf '%10s↳ [WATCH] New generation available: %s (depth %s: %s → %s)\n' \
              "" "${_wm_latest}" "${_wm_depth_r}" "${_wm_cur_pfx}" "${_wm_lat_pfx}"
            (( ++_n_watch )) || true
          fi
        fi
      fi
    fi
  fi
  return 0
}

# _gs_eu2_signal_sha — SHA sub-line display + +sha counter logic.
# Args: _i _decision
_gs_eu2_signal_sha() {
  local _i="${1}" _decision="${2}"
  # SHA sub-line: show short SHA (8 chars) + date for AUTO, SHA, and MANUAL decisions
  if [[ "${_decision}" == "AUTO" || "${_decision}" == "SHA" || "${_decision}" == "MANUAL" ]]; then
    local _disp_prop_sha _disp_ann_sha _disp_sha_date
    _disp_prop_sha="$(_gs_eu2_record_get "${_i}" proposed_sha)"
    _disp_ann_sha="$(_gs_eu2_record_get "${_i}" annotation_sha)"
    _disp_sha_date="$(_gs_eu2_record_get "${_i}" proposed_sha_date)"
    if [[ -n "${_disp_prop_sha}" && "${_disp_prop_sha}" != "${_disp_ann_sha}" ]]; then
      local _sha_sub="sha: ${_disp_prop_sha:0:8}"
      [[ -n "${_disp_sha_date}" ]] && _sha_sub+=" (${_disp_sha_date})"
      [[ -n "${_disp_ann_sha}" ]] && _sha_sub+="  ← was ${_disp_ann_sha:0:8}"
      printf '%10s↳ %s\n' "" "${_sha_sub}"
    fi
  fi
  # +sha counter: AUTO or MANUAL decisions that also carry a sha annotation update.
  # Pure SHA decisions (decision=SHA) are already in the primary SHA counter — excluded here.
  if [[ "${_decision}" == "AUTO" || "${_decision}" == "MANUAL" ]]; then
    local _sha_anno_prop _sha_anno_ann
    _sha_anno_prop="$(_gs_eu2_record_get "${_i}" proposed_sha)"
    _sha_anno_ann="$(_gs_eu2_record_get "${_i}" annotation_sha)"
    if [[ -n "${_sha_anno_prop}" && "${_sha_anno_prop}" != "${_sha_anno_ann}" ]]; then
      (( ++_n_sha_anno )) || true
    fi
  fi
  return 0
}

# _gs_eu2_signal_unstable — [UNSTABLE] info sub-line.
# Args: _i _cur
_gs_eu2_signal_unstable() {
  local _i="${1}" _cur="${2}"
  if [[ "${_GS_EU2_CFG[unstable]:-}" == "info" && "${_GS_EU2_CFG[stable]:-}" != "full" ]]; then
    local _unstable_disp
    _unstable_disp="$(_gs_eu2_record_get "${_i}" unstable_proposed)"
    if [[ -n "${_unstable_disp}" && "${_unstable_disp}" != "${_cur}" ]]; then
      printf '%10s↳ [UNSTABLE] unstable: %s\n' "" "${_unstable_disp}"
    fi
  fi
  return 0
}

# _gs_eu2_signal_stable — [STABLE] info sub-line.
# Args: _i _cur
_gs_eu2_signal_stable() {
  local _i="${1}" _cur="${2}"
  if [[ "${_GS_EU2_CFG[stable]:-}" == "info" ]]; then
    local _stable_disp
    _stable_disp="$(_gs_eu2_record_get "${_i}" stable_proposed)"
    if [[ -n "${_stable_disp}" && "${_stable_disp}" != "${_cur}" ]]; then
      printf '%10s↳ [STABLE] stable: %s\n' "" "${_stable_disp}"
    fi
  fi
  return 0
}

# _gs_eu2_signal_depends_on — [WARN] depends-on safety warning sub-line.
# Args: _i
_gs_eu2_signal_depends_on() {
  local _i="${1}"
  local _depends_on
  _depends_on="$(_gs_eu2_record_get "${_i}" depends_on)"
  if [[ -n "${_depends_on}" ]]; then
    printf '%10s↳ [WARN] (depends-on:%s) not enforced — dependency ordering\n' \
      "" "${_depends_on}"
    printf '%10s         unimplemented; verify %s manually before --apply\n' \
      "" "${_depends_on%%:*}"
    (( ++_n_warn_depends_on )) || true
  fi
  return 0
}

# _gs_eu2_signal_drift — [DRIFT] sub-line + post-drift counter updates.
# Covers: use-sha case (case 3), empty-var case (case 1), differ case (case 2).
# Also increments _n_drift, _n_drift_fixable, _n_downgrade, _n_downgrade_force.
# Args: _i _decision _cur _prop _skip_reason
# shellcheck disable=SC2154
_gs_eu2_signal_drift() {
  local _i="${1}" _decision="${2}" _cur="${3}" _prop="${4}" _skip_reason="${5}"
  # RESOLVED: drift comparison is meaningless for floating aliases — skip entire block.
  if [[ "${_GS_EU2_CFG[no_drift]:-false}" != "true" && "${_decision}" != "RESOLVED" ]]; then
    local _drift_actual _drift_ann_ver _drift_ann_sha _drift_use_sha
    _drift_actual="$(_gs_eu2_record_get "${_i}" actual_var_value)"
    _drift_ann_ver="$(_gs_eu2_record_get "${_i}" current_version)"
    _drift_ann_sha="$(_gs_eu2_record_get "${_i}" annotation_sha)"
    _drift_use_sha="$(_gs_eu2_record_get "${_i}" use_sha)"
    if [[ "${_drift_use_sha}" == "true" ]]; then
      # (use-sha) VAR= may carry a (version-prefix:) applied at write time (e.g.
      # github.com/php/php-src@<sha> for php.edge); the annotation sha: token is bare.
      # Strip the prefix before comparing so an up-to-date prefixed VAR does not
      # false-fire [DRIFT] against the bare sha.
      local _drift_vp
      _drift_vp="$(_gs_eu2_record_get "${_i}" version_prefix)"
      [[ -n "${_drift_vp}" ]] && _drift_actual="${_drift_actual#"${_drift_vp}"}"
      # Case 3: use-sha record — compare VAR= value vs. annotation sha
      if [[ -n "${_drift_actual}" && -n "${_drift_ann_sha}" \
            && "${_drift_actual}" != "${_drift_ann_sha}" ]]; then
        if [[ "${_decision}" == "LOCK" ]]; then
          printf '%10s↳ [DRIFT] var SHA (%s) differs from annotation sha:(%s) — locked; update annotation or revert VAR= manually\n' \
            "" "${_drift_actual:0:8}" "${_drift_ann_sha:0:8}"
        elif [[ -n "${_skip_reason}" ]]; then
          printf '%10s↳ [DRIFT] var SHA (%s) differs from annotation sha:(%s) — frozen by skip flag; update annotation or revert VAR= manually\n' \
            "" "${_drift_actual:0:8}" "${_drift_ann_sha:0:8}"
        elif [[ "${_decision}" == "SKIP" ]]; then
          printf '%10s↳ [DRIFT] var SHA (%s) differs from annotation sha:(%s) — update annotation or revert VAR= manually (--apply skips up-to-date records)\n' \
            "" "${_drift_actual:0:8}" "${_drift_ann_sha:0:8}"
        elif [[ "${_decision}" == "HOLD" || "${_decision}" == "MANUAL" ]]; then
          printf '%10s↳ [DRIFT] var SHA (%s) differs from annotation sha:(%s) — --force-auto --apply to resolve\n' \
            "" "${_drift_actual:0:8}" "${_drift_ann_sha:0:8}"
        elif [[ "${_decision}" == "ERROR" ]]; then
          printf '%10s↳ [DRIFT] var SHA (%s) differs from annotation sha:(%s) — fetch failed; fix error then re-run\n' \
            "" "${_drift_actual:0:8}" "${_drift_ann_sha:0:8}"
        else
          # AUTO or SHA: --apply can resolve
          printf '%10s↳ [DRIFT] var SHA (%s) differs from annotation sha:(%s) — re-run --apply to resolve\n' \
            "" "${_drift_actual:0:8}" "${_drift_ann_sha:0:8}"
        fi
        _drift_fired=true
      fi
    else
      if [[ -z "${_drift_actual}" && -n "${_drift_ann_ver}" ]]; then
        # Case 1: empty var — decision-aware enable-warning
        if [[ "${_decision}" == "LOCK" ]]; then
          printf '%10s↳ [DRIFT] var is empty — annotation locked at %s; feature disabled (set VAR= manually to re-enable — lock blocks --apply and --force-auto)\n' \
            "" "${_drift_ann_ver}"
          _drift_fired=true
        elif [[ -n "${_skip_reason}" ]]; then
          : # skip-gate blocks apply; empty var is intentional — no drift message
        elif [[ "${_decision}" == "HOLD" ]]; then
          printf '%10s↳ [DRIFT] var is empty — annotation tracks %s (feature disabled? --force-auto --apply will write it to enable)\n' \
            "" "${_drift_ann_ver}"
          _drift_fired=true
        elif [[ "${_decision}" == "MANUAL" ]]; then
          printf '%10s↳ [DRIFT] var is empty — annotation tracks %s (feature disabled? --force-auto --apply will write it to enable)\n' \
            "" "${_drift_ann_ver}"
          _drift_fired=true
        elif [[ "${_decision}" == "AUTO" ]]; then
          printf '%10s↳ [DRIFT] var is empty — annotation tracks %s (feature disabled? --apply will write %s to enable it)\n' \
            "" "${_drift_ann_ver}" "${_prop:-${_drift_ann_ver}}"
          _drift_fired=true
        elif [[ "${_decision}" == "SHA" ]]; then
          printf '%10s↳ [DRIFT] var is empty — annotation tracks %s (feature disabled? set VAR= manually to enable)\n' \
            "" "${_drift_ann_ver}"
          _drift_fired=true
        else
          # SKIP (up-to-date, not skip-gate) or ERROR: informational only
          printf '%10s↳ [DRIFT] var is empty — annotation tracks %s (feature disabled?)\n' \
            "" "${_drift_ann_ver}"
          _drift_fired=true
        fi
      elif [[ -n "${_drift_actual}" && -n "${_drift_ann_ver}" \
              && "${_drift_actual}" != "${_drift_ann_ver}" ]]; then
        # Case 2: both non-empty but differ — direction-aware + decision-aware message
        local _drift_dir_msg=""
        if [[ "${_drift_actual}" =~ ^v?[0-9][0-9.]*$ && \
              "${_drift_ann_ver}" =~ ^v?[0-9][0-9.]*$ ]]; then
          local _drift_oldest
          _drift_oldest="$(printf '%s\n%s\n' "${_drift_actual}" "${_drift_ann_ver}" | sort -V | head -1)"
          if [[ "${_drift_oldest}" == "${_drift_actual}" && "${_drift_actual}" != "${_drift_ann_ver}" ]]; then
            _drift_dir_msg=" — re-run --apply or update annotation"
          else
            _drift_dir_msg=" — VAR is ahead of annotation (downgrade risk: run --apply only if intentional)"
            _drift_dir_downgrade=true
          fi
        fi
        # Decision-aware message (B2-B11)
        if [[ "${_decision}" == "LOCK" ]]; then
          printf '%10s↳ [DRIFT] annotation says %s but VAR=%s — locked; update annotation manually to resolve\n' \
            "" "${_drift_ann_ver}" "${_drift_actual}"
          _drift_fired=true
        elif [[ -n "${_skip_reason}" ]]; then
          printf '%10s↳ [DRIFT] annotation says %s but VAR=%s — frozen by skip flag; update annotation manually to resolve\n' \
            "" "${_drift_ann_ver}" "${_drift_actual}"
          _drift_fired=true
        elif [[ "${_decision}" == "HOLD" ]]; then
          if [[ "${_drift_dir_downgrade}" == "true" ]]; then
            printf '%10s↳ [DRIFT] annotation says %s but VAR=%s%s\n' \
              "" "${_drift_ann_ver}" "${_drift_actual}" "${_drift_dir_msg}"
          else
            printf '%10s↳ [DRIFT] annotation says %s but VAR=%s — --force-auto --apply to resolve\n' \
              "" "${_drift_ann_ver}" "${_drift_actual}"
          fi
          _drift_fired=true
        elif [[ "${_decision}" == "MANUAL" ]]; then
          if [[ "${_drift_dir_downgrade}" == "true" ]]; then
            printf '%10s↳ [DRIFT] annotation says %s but VAR=%s%s\n' \
              "" "${_drift_ann_ver}" "${_drift_actual}" "${_drift_dir_msg}"
          else
            printf '%10s↳ [DRIFT] annotation says %s but VAR=%s — --force-auto --apply to resolve\n' \
              "" "${_drift_ann_ver}" "${_drift_actual}"
          fi
          _drift_fired=true
        elif [[ "${_decision}" == "ERROR" ]]; then
          printf '%10s↳ [DRIFT] annotation says %s but VAR=%s%s — fetch failed; fix error then re-run\n' \
            "" "${_drift_ann_ver}" "${_drift_actual}" "${_drift_dir_msg:-}"
          _drift_fired=true
        elif [[ "${_decision}" == "SKIP" && -z "${_skip_reason}" ]]; then
          printf '%10s↳ [DRIFT] annotation says %s but VAR=%s%s — update annotation or revert VAR= manually (--apply skips up-to-date records)\n' \
            "" "${_drift_ann_ver}" "${_drift_actual}" "${_drift_dir_msg:-}"
          _drift_fired=true
        else
          # AUTO, SHA — neutral fallback when non-semver (no _drift_dir_msg)
          printf '%10s↳ [DRIFT] annotation says %s but VAR=%s%s\n' \
            "" "${_drift_ann_ver}" "${_drift_actual}" "${_drift_dir_msg:- — re-run --apply or update annotation}"
          _drift_fired=true
        fi
      fi
    fi
  fi
  # Post-drift counter updates (outside the no_drift guard — _drift_fired is false when suppressed)
  if [[ "${_drift_fired}" == "true" ]]; then
    (( ++_n_drift )) || true
    if [[ "${_drift_dir_downgrade}" == "true" ]]; then
      # Count downgrade only when --apply CAN write VAR=
      # LOCK/FROZEN/SKIP/ERROR drift is informational — downgrade not actionable by --apply
      if [[ "${_decision}" != "LOCK" && -z "${_skip_reason}" \
            && "${_decision}" != "SKIP" && "${_decision}" != "ERROR" ]]; then
        if [[ "${_decision}" == "MANUAL" || "${_decision}" == "HOLD" ]]; then
          (( ++_n_downgrade_force )) || true
        else
          (( ++_n_downgrade )) || true
        fi
      fi
    elif [[ "${_decision}" == "AUTO" || "${_decision}" == "HOLD" \
            || "${_decision}" == "MANUAL" || "${_decision}" == "SHA" ]]; then
      (( ++_n_drift_fixable )) || true
    fi
  fi
  return 0
}

# _gs_eu2_signal_replace_drift — [REPLACE-DRIFT] sub-line for (replace:TARGET=template) records.
# Args: _i _decision _cur _prop _skip_reason
_gs_eu2_signal_replace_drift() {
  local _i="${1}" _decision="${2}" _cur="${3}" _prop="${4}" _skip_reason="${5}"
  if [[ "${_GS_EU2_CFG[no_drift]:-false}" != "true" && "${_decision}" != "ERROR" ]]; then
    local _rd_rep_tgts _rd_rep_tmpls
    _rd_rep_tgts="$(_gs_eu2_record_get "${_i}" replace_targets)"
    _rd_rep_tmpls="$(_gs_eu2_record_get "${_i}" replace_templates)"
    if [[ -n "${_rd_rep_tgts}" ]]; then
      local _rd_old_ifs="${IFS}"
      IFS=$'\x1f'
      local _rd_rt_arr _rd_rm_arr
      read -ra _rd_rt_arr <<< "${_rd_rep_tgts}"
      read -ra _rd_rm_arr <<< "${_rd_rep_tmpls}"
      IFS="${_rd_old_ifs}"
      local _rd_ri
      for (( _rd_ri = 0; _rd_ri < ${#_rd_rt_arr[@]}; _rd_ri++ )); do
        local _rd_rt="${_rd_rt_arr[${_rd_ri}]}"
        local _rd_rm="${_rd_rm_arr[${_rd_ri}]:-}"
        local _rd_tgt_actual _rd_exp_cur _rd_exp_prop
        _rd_tgt_actual="$(grep -m1 "^${_rd_rt}=" "${_GS_EU2_CFG[env_file]}" 2>/dev/null \
          | cut -d= -f2-)"
        _rd_exp_cur="$(_gs_eu2_expand_replace_template "${_rd_rm}" "${_cur:-}")"
        _rd_exp_prop="$(_gs_eu2_expand_replace_template "${_rd_rm}" "${_prop:-}")"
        local _rd_stale_now=false _rd_update_pending=false
        [[ "${_rd_tgt_actual}" != "${_rd_exp_cur}" ]] && _rd_stale_now=true
        [[ "${_rd_exp_cur}" != "${_rd_exp_prop}" ]] && _rd_update_pending=true

        if [[ "${_decision}" == "AUTO" || "${_decision}" == "SHA" ]]; then
          if [[ "${_rd_stale_now}" == "true" || "${_rd_update_pending}" == "true" ]]; then
            if [[ "${_rd_stale_now}" == "true" ]]; then
              printf '%10s↳ (replace) %-47s  %s → %s  [REPLACE-DRIFT]\n' \
                "" "${_rd_rt}" "${_rd_tgt_actual}" "${_rd_exp_prop}"
            else
              printf '%10s↳ (replace) %-47s  %s → %s\n' \
                "" "${_rd_rt}" "${_rd_tgt_actual}" "${_rd_exp_prop}"
            fi
          fi
        elif [[ "${_decision}" == "SKIP" && -z "${_skip_reason}" && "${_rd_stale_now}" == "true" ]]; then
          printf '%10s↳ [REPLACE-DRIFT] %s  actual=%s ≠ expected=%s — run --apply to fix\n' \
            "" "${_rd_rt}" "${_rd_tgt_actual}" "${_rd_exp_cur}"
        elif [[ ( "${_decision}" == "HOLD" || "${_decision}" == "MANUAL" ) \
                && "${_rd_stale_now}" == "true" ]]; then
          printf '%10s↳ [REPLACE-DRIFT] %s  actual=%s ≠ expected=%s — run --force-auto --apply to fix\n' \
            "" "${_rd_rt}" "${_rd_tgt_actual}" "${_rd_exp_cur}"
        elif [[ ( "${_decision}" == "HOLD" || "${_decision}" == "MANUAL" ) \
                && "${_rd_stale_now}" == "false" && "${_rd_update_pending}" == "true" ]]; then
          printf '%10s↳ (replace) %-47s  → %s  (with --force-auto --apply)\n' \
            "" "${_rd_rt}" "${_rd_exp_prop}"
        elif [[ -n "${_skip_reason}" && "${_rd_stale_now}" == "true" ]]; then
          printf '%10s↳ [REPLACE-DRIFT] %s  actual=%s ≠ expected=%s — informational only (frozen)\n' \
            "" "${_rd_rt}" "${_rd_tgt_actual}" "${_rd_exp_cur}"
        elif [[ "${_decision}" == "LOCK" && "${_rd_stale_now}" == "true" ]]; then
          printf '%10s↳ [REPLACE-DRIFT] %s  actual=%s ≠ expected=%s — informational only (locked)\n' \
            "" "${_rd_rt}" "${_rd_tgt_actual}" "${_rd_exp_cur}"
        fi

        # Per-record counters (at most once per record)
        if [[ "${_rd_stale_now}" == "true" && "${_record_replace_drift_counted}" == "false" ]]; then
          (( ++_n_replace_drift )) || true
          _record_replace_drift_counted=true
        fi
        if [[ "${_record_replace_cascade_counted}" == "false" \
              && ( "${_rd_stale_now}" == "true" || "${_rd_update_pending}" == "true" ) \
              && ( "${_decision}" == "AUTO" || "${_decision}" == "SHA" ) ]]; then
          (( ++_n_replace_cascade )) || true
          _record_replace_cascade_counted=true
        fi
      done
    fi
  fi
  return 0
}
