#!/bin/bash
# apply.sh — rewrite .env AUTO/SHA/LOCK/RESOLVED decisions back to the env file.
#
# Exports:   _gs_eu2_apply_single  _gs_eu2_apply_replace_target
#            _gs_eu2_expand_replace_template  _gs_eu2_apply_updates
#            _gs_eu2_journal_append
# Sources:   core/records.sh  core/git.sh
# Deps:      awk, mktemp, mv, cp, date
# Env:       _GS_EU2_CFG (env_file, dry_run, no_fail, backup, backup_keep,
#                         backup_purge, backup_suffix, apply_resolve)
#
# All writes go through awk-based rewrite with atomic tmp+mv to avoid partial
# file state.  A snapshot of the env file is taken before the loop; on error
# the snapshot is restored so cascaded (replace:) failures don't leave the file
# in a partially-written state.

[[ -n "${_GS_EU2_APPLY_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_APPLY_SH_LOADED=1

# shellcheck source=./records.sh
source "$(dirname "${BASH_SOURCE[0]}")/records.sh"
# shellcheck source=./git.sh
source "$(dirname "${BASH_SOURCE[0]}")/git.sh"
# shellcheck source=./semver.sh
source "$(dirname "${BASH_SOURCE[0]}")/semver.sh"

# _gs_eu2_journal_append — append one audit line to docs/env-update-journal.log.
#
# Args:    $1 var      — env variable name
#          $2 old      — current (pre-apply) value
#          $3 new      — new value being written
#          $4 decision — "AUTO" or "RESOLVED"
#          $5 channel  — annotation channel value ("stable", "unstable", empty → "latest")
# Reads:   BASH_SOURCE[0] to derive repo root
# Sets:    nothing
# Prints:  nothing (all errors silently suppressed)
# Returns: 0 always (journal failure must never abort apply)
# Side fx: creates docs/env-update-journal.log if absent; writes one line
_gs_eu2_journal_append() {
  local _var="${1}" _old="${2}" _new="${3}" _decision="${4}" _channel="${5:-}"
  [[ -z "${_channel}" ]] && _channel="latest"
  local _self_dir
  _self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || return 0
  # apply.sh lives at bin/lib/env-update/core/ — four levels up is the repo root.
  local _journal="${_self_dir}/../../../../docs/env-update-journal.log"
  mkdir -p "$(dirname "${_journal}")" 2>/dev/null || true
  printf '%s %s %s → %s [%s] [%s]\n' \
    "$(date -Iseconds)" "${_var}" "${_old}" "${_new}" "${_decision}" "${_channel}" \
    >> "${_journal}" 2>/dev/null || true
}

# _gs_eu2_apply_single — rewrite a VAR=value line and its annotation in one awk pass.
#
# Args:    $1  file           — path to the env file
#          $2  var_name       — env variable name (matched as prefix of lines)
#          $3  new_value      — new version value for VAR= line
#          $4  raw_annotation — exact annotation comment line to match and rewrite
#          $5  cur_version    — current version token in the annotation (replaced with $3)
#          $6  cur_sha        — current sha: hash in the annotation (empty = no sha rewrite)
#          $7  new_sha        — new sha: hash for the annotation (may include "(YYYY-MM-DD)")
#          $8  use_sha        — "true" → write new SHA to VAR= instead of new version
#          $9  annotation_only— "true" → skip VAR= rewrite (LOCK path: annotation updated only)
#          $10 bare_sha       — raw 40-char SHA without date (used for the VAR= value only;
#                               prevents date leaking into the variable value — Bug E fix)
# Reads:   file on disk
# Sets:    nothing (writes to file via awk + tmp+mv)
# Prints:  error message to stderr on mktemp/awk/mv failure
# Returns: 0 on success; 1 on failure (caller should abort or roll back)
# Side fx: rewrites file atomically (tmp+mv); does NOT create a backup (caller handles that)
#
# Design note: uses the LAST occurrence of " curval" in the annotation to avoid
# collisions with major-hint tokens (e.g. "... repo 2 2.4.0" — first " 2" is the
# hint; the version token is the last " 2.4.0").
_gs_eu2_apply_single() {
  local _file="${1}" _var="${2}" _new="${3}" _raw_ann="${4:-}" _cur="${5:-}" \
        _cur_sha="${6:-}" _new_sha="${7:-}" _use_sha="${8:-false}" \
        _annotation_only="${9:-false}" _bare_sha="${10:-}"
  local _tmp
  _tmp="$(mktemp)" || { printf 'env-update/apply: mktemp failed\n' >&2; return 1; }
  awk -v var="${_var}" -v newval="${_new}" -v raw_ann="${_raw_ann}" \
      -v curval="${_cur}" -v cur_sha="${_cur_sha}" -v new_sha="${_new_sha}" \
      -v use_sha="${_use_sha}" -v annotation_only="${_annotation_only}" \
      -v bare_sha="${_bare_sha}" '
    /^[[:space:]]*#/ {
      if (raw_ann != "" && $0 == raw_ann) {
        line = $0
        # Update version token: find the LAST occurrence of " curval" in the annotation.
        # Using the last occurrence prevents collisions with major-hint tokens that appear
        # earlier in the annotation (e.g. "... repo 2 2.4.0" → first " 2" is the hint;
        # the version token is the last " 2.4.0").
        if (curval != "" && newval != "") {
          idx = 0
          pos = 1
          while ((p = index(substr(line, pos), " " curval)) > 0) {
            idx = pos + p - 1
            pos = idx + 1
          }
          if (idx > 0)
            line = substr(line, 1, idx) newval substr(line, idx + 1 + length(curval))
        }
        # Update sha: keyword in annotation (uses new_sha which may include date)
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
      # Skip VAR= rewrite when newval is empty and use_sha is not set,
      # OR when annotation_only is set (LOCK: annotation updated, VAR= untouched).
      if ((newval == "" && use_sha != "true") || annotation_only == "true") { print; next }
      # Use bare_sha (no date) for the VAR= value when use_sha is active.
      # new_sha may carry "HASH (YYYY-MM-DD)" for the annotation line — do not leak the date
      # into the variable value itself.
      val = (use_sha == "true" && bare_sha != "") ? bare_sha : newval
      print var "=" val; next
    }
    { print }
  ' "${_file}" > "${_tmp}" || { rm -f "${_tmp}"; return 1; }
  mv "${_tmp}" "${_file}" || { rm -f "${_tmp}"; return 1; }
}

# _gs_eu2_apply_replace_target — rewrite a single VAR=value line (no annotation rewrite).
#
# Args:    $1 file      — path to the env file
#          $2 var_name  — env variable name to match
#          $3 new_value — new value for the VAR= line
# Reads:   file on disk
# Sets:    nothing
# Prints:  error to stderr on failure
# Returns: 0 on success; 1 on failure
# Side fx: rewrites file atomically (tmp+mv); used by (replace:) cascade writes
_gs_eu2_apply_replace_target() {
  local _file="${1}" _var="${2}" _new="${3}"
  local _tmp _art_old_umask
  # umask 0077: temp file holds env content — restrict to owner only.
  _art_old_umask="$(umask)"
  umask 0077
  _tmp="$(mktemp)"
  umask "${_art_old_umask}"
  [[ -n "${_tmp}" ]] || { printf 'env-update/apply: mktemp failed\n' >&2; return 1; }
  awk -v var="${_var}" -v newval="${_new}" '
    index($0, var "=") == 1 { print var "=" newval; next }
    { print }
  ' "${_file}" > "${_tmp}" || { rm -f "${_tmp}"; return 1; }
  mv "${_tmp}" "${_file}" || { rm -f "${_tmp}"; return 1; }
}

# _gs_eu2_expand_replace_template — expand {version}/{major}/{minor}/{patch} tokens.
#
# Args:    $1 template — template string containing {version}, {major}, {minor}, {patch}
#          $2 proposed — proposed version (used to extract major/minor/patch components)
# Reads:   nothing
# Sets:    nothing
# Prints:  expanded template string (v-prefix stripped from components)
# Returns: 0 always
# Side fx: none
_gs_eu2_expand_replace_template() {
  local _tmpl="${1}" _prop="${2}"
  local _ver="${_prop#v}"
  local _major="${_ver%%.*}"
  local _rest="${_ver#*.}"
  local _minor="${_rest%%.*}"
  local _patch="${_rest#*.}"
  _patch="${_patch%%[-+]*}"
  _tmpl="${_tmpl//\{version\}/${_ver}}"
  _tmpl="${_tmpl//\{major\}/${_major}}"
  _tmpl="${_tmpl//\{minor\}/${_minor}}"
  _tmpl="${_tmpl//\{patch\}/${_patch}}"
  printf '%s' "${_tmpl}"
}

# _gs_eu2_apply_updates — apply all AUTO/SHA/LOCK/RESOLVED decisions to the env file.
#
# Args:    $1 env_file — path to the .env file to rewrite
#          $2 dry_run  — "true" → print what would be applied without writing
# Reads:   all record arrays (decision, env_var, current_version, proposed_version,
#          raw_annotation, annotation_sha, proposed_sha, use_sha, replace_targets,
#          replace_templates), _GS_EU2_CFG
# Sets:    nothing (reads record state set by run_check)
# Prints:  [APPLIED]/[DRY-RUN]/[SHA]/[LOCK]/[REPLACE] lines to stdout; errors to stderr
# Returns: 0 on success; 1 on write error (unless --no-fail suppresses it)
# Side fx: rewrites env_file in-place for non-dry-run runs; creates a tmpdir snapshot
#          for rollback on (replace:) cascade failure; the snapshot is cleaned up on RETURN
_gs_eu2_apply_updates() {
  local _env_file="${1}" _dry_run="${2:-false}"

  # Rule 8: guard against overwriting a tracked file with uncommitted changes.
  # Skip in dry-run mode — no writes occur so the check is noise.
  if [[ "${_dry_run}" != "true" ]]; then
    if ! _gs_eu2_check_tracked_file_state "${_env_file}"; then
      # Warning already emitted by the helper.
      if [[ "${_GS_EU2_CFG[no_fail]:-false}" == "true" ]]; then
        printf '[SKIP] env-update apply: skipping %s due to uncommitted changes (--no-fail active)\n' \
          "${_env_file}" >&2
        return 0
      fi
      return 1
    fi
  fi

  # Snapshot the env file so we can roll back if a cascade write fails mid-way.
  # Covers both the AUTO cascade pass and the SKIP replace-only pass.
  # Dry-run: no snapshot needed (no writes occur).
  local _snapshot="" _snap_old_umask
  if [[ "${_dry_run}" != "true" ]]; then
    # umask 0077: snapshot holds the entire env file — restrict to owner only.
    _snap_old_umask="$(umask)"
    umask 0077
    _snapshot="$(mktemp)"
    umask "${_snap_old_umask}"
    [[ -n "${_snapshot}" ]] || { printf 'env-update/apply: snapshot mktemp failed\n' >&2; return 1; }
    cp "${_env_file}" "${_snapshot}" || { rm -f "${_snapshot}"; return 1; }
    # shellcheck disable=SC2064
    trap "rm -f '${_snapshot}'" RETURN
  fi

  local _count; _count="$(_gs_eu2_record_count)"
  # Four non-overlapping counters — sum to the reported total:
  #   version-only : AUTO records where only VAR= (and annotation version) changed
  #   version+sha  : AUTO records where VAR= AND sha: annotation both changed
  #   sha          : SHA-decision records (SKIP but sha advanced; use_sha may also update VAR=)
  #   lock         : LOCK records (annotation version bumped, VAR= untouched)
  local _n_auto_only_applied=0 _n_auto_only_would=0
  local _n_auto_sha_applied=0  _n_auto_sha_would=0
  local _n_sha_applied=0       _n_sha_would=0
  local _n_lock_applied=0      _n_lock_would=0
  local _n_resolve_applied=0

  local _i _var _cur _prop _decision _raw_ann
  local _ann_sha _ann_sha_date _new_sha _new_sha_date _use_sha
  for (( _i = 0; _i < _count; _i++ )); do
    _decision="$(_gs_eu2_record_get "${_i}" decision)"

    # ── SHA-only update path ───────────────────────────────────────────────
    if [[ "${_decision}" == "SHA" ]]; then
      _var="$(_gs_eu2_record_get "${_i}" env_var)"
      _raw_ann="$(_gs_eu2_record_get "${_i}" raw_annotation)"
      _ann_sha="$(_gs_eu2_record_get "${_i}" annotation_sha)"
      _new_sha="$(_gs_eu2_record_get "${_i}" proposed_sha)"
      _new_sha_date="$(_gs_eu2_record_get "${_i}" proposed_sha_date)"
      _use_sha="$(_gs_eu2_record_get "${_i}" use_sha)"
      local _new_sha_tok="${_new_sha}"
      # _new_sha_date is available but intentionally omitted — annotation carries sha:HASH only
      # Build old sha token to replace in annotation (match bare or with date)
      local _old_sha_tok="${_ann_sha}"
      _ann_sha_date="$(_gs_eu2_record_get "${_i}" annotation_sha_date)"
      [[ -n "${_ann_sha_date}" ]] && _old_sha_tok="${_ann_sha} (${_ann_sha_date})"

      if [[ "${_dry_run}" == "true" ]]; then
        printf '  [DRY-RUN]  %-55s  sha:%s → sha:%s\n' "${_var}" "${_ann_sha:0:8}" "${_new_sha:0:8}"
        (( ++_n_sha_would )) || true
      else
        # Annotation sha: is always updated.
        # When use_sha=true (e.g. PECL use-sha), VAR= is also updated with the new bare SHA
        # so that [DRIFT] does not immediately re-fire after --apply.
        _gs_eu2_apply_single "${_env_file}" "${_var}" "" "${_raw_ann}" "" \
                              "${_old_sha_tok}" "${_new_sha_tok}" "${_use_sha:-false}" "false" "${_new_sha}"
        printf '  [SHA]      %-55s  sha:%s → sha:%s\n' "${_var}" "${_ann_sha:0:8}" "${_new_sha:0:8}"
        (( ++_n_sha_applied )) || true
      fi
      continue
    fi

    # ── Lock annotation-only update path (LOCK decisions) ────────────────
    if [[ "${_decision}" == "LOCK" ]]; then
      _var="$(_gs_eu2_record_get "${_i}" env_var)"
      _cur="$(_gs_eu2_record_get "${_i}" current_version)"
      _prop="$(_gs_eu2_record_get "${_i}" proposed_version)"
      _raw_ann="$(_gs_eu2_record_get "${_i}" raw_annotation)"
      # Floating current (next, edge, latest, …) means the annotation intentionally
      # carries an alias — rewriting it to a concrete version breaks the lock semantics.
      _gs_eu2_is_unversioned "${_cur}" && continue
      # Only rewrite annotation when proposed differs from annotation version (idempotency).
      [[ -z "${_prop}" || "${_prop}" == "${_cur}" ]] && continue
      if [[ "${_dry_run}" == "true" ]]; then
        printf '  [DRY-RUN]  %-55s  annotation: %s → %s (locked — VAR= untouched)\n' \
          "${_var}" "${_cur}" "${_prop}"
        (( ++_n_lock_would )) || true
      else
        # 10th arg bare_sha: unused (annotation_only=true, VAR= untouched), pass "".
        _gs_eu2_apply_single "${_env_file}" "${_var}" "${_prop}" "${_raw_ann}" "${_cur}" \
                              "" "" "false" "true" ""
        printf '  [LOCK]     %-55s  annotation: %s → %s\n' "${_var}" "${_cur}" "${_prop}"
        (( ++_n_lock_applied )) || true
      fi
      continue
    fi

    # ── RESOLVED path: float-to-concrete pin (requires --apply-resolve) ────
    # RESOLVED entries are informational only. --force-auto does NOT promote them.
    # Only --apply-resolve --apply triggers the write path.
    # (replace:) cascade fires when --apply-resolve is active, same as AUTO path.
    if [[ "${_decision}" == "RESOLVED" ]]; then
      if [[ "${_GS_EU2_CFG[apply_resolve]:-false}" == "true" ]]; then
        _var="$(_gs_eu2_record_get "${_i}" env_var)"
        _cur="$(_gs_eu2_record_get "${_i}" current_version)"
        _prop="$(_gs_eu2_record_get "${_i}" proposed_version)"
        _raw_ann="$(_gs_eu2_record_get "${_i}" raw_annotation)"
        [[ -z "${_prop}" || "${_prop}" == "${_cur}" ]] && continue
        if [[ "${_dry_run}" == "true" ]]; then
          printf '  [DRY-RUN]  %-55s  %s → %s (float pinned)\n' "${_var}" "${_cur}" "${_prop}"
          # (replace:) dry-run sub-lines for RESOLVED + --apply-resolve
          local _res_rep_targets_dr _res_rep_tmpls_dr
          _res_rep_targets_dr="$(_gs_eu2_record_get "${_i}" replace_targets)"
          _res_rep_tmpls_dr="$(_gs_eu2_record_get "${_i}" replace_templates)"
          if [[ -n "${_res_rep_targets_dr}" ]]; then
            local _res_old_ifs_dr="${IFS}"
            IFS=$'\x1f'
            local _res_rt_arr_dr _res_rm_arr_dr
            read -ra _res_rt_arr_dr <<< "${_res_rep_targets_dr}"
            read -ra _res_rm_arr_dr <<< "${_res_rep_tmpls_dr}"
            IFS="${_res_old_ifs_dr}"
            local _res_ri_dr
            for (( _res_ri_dr = 0; _res_ri_dr < ${#_res_rt_arr_dr[@]}; _res_ri_dr++ )); do
              local _res_rt_dr="${_res_rt_arr_dr[${_res_ri_dr}]}"
              local _res_rm_dr="${_res_rm_arr_dr[${_res_ri_dr}]:-}"
              local _res_expanded_dr
              _res_expanded_dr="$(_gs_eu2_expand_replace_template "${_res_rm_dr}" "${_prop}")"
              printf '  [DRY-RUN]    ↳ (replace) %-47s  → %s\n' "${_res_rt_dr}" "${_res_expanded_dr}"
            done
          fi
        else
          # Write concrete version to VAR= and update annotation CURRENT_VERSION from float to concrete.
          _gs_eu2_apply_single "${_env_file}" "${_var}" "${_prop}" "${_raw_ann}" "${_cur}" \
                               "" "" "false" "false" ""
          printf '  [PINNED ]  %-55s  %s → %s\n' "${_var}" "${_cur}" "${_prop}"
          _gs_eu2_journal_append "${_var}" "${_cur}" "${_prop}" "RESOLVED" \
            "$(_gs_eu2_record_get "${_i}" channel)"
          (( ++_n_resolve_applied )) || true
          # (replace:) cascade for RESOLVED records (same logic as AUTO path)
          local _res_rep_targets _res_rep_tmpls
          _res_rep_targets="$(_gs_eu2_record_get "${_i}" replace_targets)"
          _res_rep_tmpls="$(_gs_eu2_record_get "${_i}" replace_templates)"
          if [[ -n "${_res_rep_targets}" ]]; then
            local _res_old_ifs="${IFS}"
            IFS=$'\x1f'
            local _res_rt_arr _res_rm_arr
            read -ra _res_rt_arr <<< "${_res_rep_targets}"
            read -ra _res_rm_arr <<< "${_res_rep_tmpls}"
            IFS="${_res_old_ifs}"
            local _res_ri
            for (( _res_ri = 0; _res_ri < ${#_res_rt_arr[@]}; _res_ri++ )); do
              local _res_rt="${_res_rt_arr[${_res_ri}]}"
              local _res_rm="${_res_rm_arr[${_res_ri}]:-}"
              local _res_expanded
              _res_expanded="$(_gs_eu2_expand_replace_template "${_res_rm}" "${_prop}")"
              if ! grep -q "^${_res_rt}=" "${_env_file}" 2>/dev/null; then
                printf '  [ERROR]    %-55s  replace: target %s not found in %s\n' \
                  "${_var}" "${_res_rt}" "${_env_file}" >&2
                if [[ "${_GS_EU2_CFG[no_fail]:-false}" != "true" ]]; then
                  [[ -n "${_snapshot}" ]] && cp "${_snapshot}" "${_env_file}" || true
                  return 1
                fi
                continue
              fi
              if ! _gs_eu2_apply_replace_target "${_env_file}" "${_res_rt}" "${_res_expanded}"; then
                printf '  [ERROR]    %-55s  replace: failed to rewrite target %s\n' \
                  "${_var}" "${_res_rt}" >&2
                if [[ "${_GS_EU2_CFG[no_fail]:-false}" != "true" ]]; then
                  [[ -n "${_snapshot}" ]] && cp "${_snapshot}" "${_env_file}" || true
                  return 1
                fi
                continue
              fi
              printf '  [REPLACE]    ↳ (replace) %-47s  → %s\n' "${_res_rt}" "${_res_expanded}"
            done
          fi
        fi
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

    # Build sha tokens for annotation rewrite
    # old_sha_tok2 preserves date suffix for matching existing annotations that carry dates
    local _old_sha_tok2="${_ann_sha}"
    [[ -n "${_ann_sha_date}" ]] && _old_sha_tok2="${_ann_sha} (${_ann_sha_date})"
    local _new_sha_tok2="${_new_sha}"
    # _new_sha_date intentionally omitted — annotation carries sha:HASH only (no date)

    # sha: annotation also updated when both tokens are present and differ.
    # This is a silent side-effect of the AUTO path — surfaced in the summary as "version+sha".
    local _auto_has_sha_update="false"
    [[ -n "${_ann_sha}" && -n "${_new_sha}" && "${_old_sha_tok2}" != "${_new_sha_tok2}" ]] \
      && _auto_has_sha_update="true"

    if [[ "${_dry_run}" == "true" ]]; then
      local _display_proposed="${_prop}"
      [[ "${_use_sha:-false}" == "true" && -n "${_new_sha}" ]] && _display_proposed="${_new_sha}"
      printf '  [DRY-RUN]  %-55s  %s → %s\n' "${_var}" "${_cur}" "${_display_proposed}"
      if [[ "${_auto_has_sha_update}" == "true" ]]; then
        (( ++_n_auto_sha_would )) || true
      else
        (( ++_n_auto_only_would )) || true
      fi
      # (replace:) dry-run sub-lines
      local _rep_targets_dr _rep_tmpls_dr
      _rep_targets_dr="$(_gs_eu2_record_get "${_i}" replace_targets)"
      _rep_tmpls_dr="$(_gs_eu2_record_get "${_i}" replace_templates)"
      if [[ -n "${_rep_targets_dr}" ]]; then
        local _old_ifs_rep_dr="${IFS}"
        IFS=$'\x1f'
        local _rt_arr_dr _rm_arr_dr
        read -ra _rt_arr_dr <<< "${_rep_targets_dr}"
        read -ra _rm_arr_dr <<< "${_rep_tmpls_dr}"
        IFS="${_old_ifs_rep_dr}"
        local _ri_dr
        for (( _ri_dr = 0; _ri_dr < ${#_rt_arr_dr[@]}; _ri_dr++ )); do
          local _rt_dr="${_rt_arr_dr[${_ri_dr}]}"
          local _rm_dr="${_rm_arr_dr[${_ri_dr}]:-}"
          local _expanded_dr
          _expanded_dr="$(_gs_eu2_expand_replace_template "${_rm_dr}" "${_prop}")"
          printf '  [DRY-RUN]    ↳ (replace) %-47s  → %s\n' "${_rt_dr}" "${_expanded_dr}"
        done
      fi
    else
      # 10th arg bare_sha: raw SHA without date, for the VAR= line when use_sha=true.
      _gs_eu2_apply_single "${_env_file}" "${_var}" "${_prop}" "${_raw_ann}" "${_cur}" \
                            "${_old_sha_tok2}" "${_new_sha_tok2}" "${_use_sha:-false}" "false" "${_new_sha}"
      printf '  [APPLIED]  %-55s  %s → %s\n' "${_var}" "${_cur}" "${_prop}"
      _gs_eu2_journal_append "${_var}" "${_cur}" "${_prop}" "AUTO" \
        "$(_gs_eu2_record_get "${_i}" channel)"
      if [[ "${_auto_has_sha_update}" == "true" ]]; then
        (( ++_n_auto_sha_applied )) || true
      else
        (( ++_n_auto_only_applied )) || true
      fi
      # (replace:) cascade: rewrite each target VAR= with the expanded template value.
      local _rep_targets _rep_tmpls
      _rep_targets="$(_gs_eu2_record_get "${_i}" replace_targets)"
      _rep_tmpls="$(_gs_eu2_record_get "${_i}" replace_templates)"
      if [[ -n "${_rep_targets}" ]]; then
        local _old_ifs_rep="${IFS}"
        IFS=$'\x1f'
        local _rt_arr _rm_arr
        read -ra _rt_arr <<< "${_rep_targets}"
        read -ra _rm_arr <<< "${_rep_tmpls}"
        IFS="${_old_ifs_rep}"
        local _ri
        for (( _ri = 0; _ri < ${#_rt_arr[@]}; _ri++ )); do
          local _rt="${_rt_arr[${_ri}]}"
          local _rm="${_rm_arr[${_ri}]:-}"
          local _expanded
          _expanded="$(_gs_eu2_expand_replace_template "${_rm}" "${_prop}")"
          # Verify the target VAR exists in the env file before rewriting.
          if ! grep -q "^${_rt}=" "${_env_file}" 2>/dev/null; then
            printf '  [ERROR]    %-55s  replace: target %s not found in %s\n' \
              "${_var}" "${_rt}" "${_env_file}" >&2
            if [[ "${_GS_EU2_CFG[no_fail]:-false}" != "true" ]]; then
              # Roll back to pre-apply snapshot — primary var was already written
              [[ -n "${_snapshot}" ]] && cp "${_snapshot}" "${_env_file}" || true
              return 1
            fi
            continue
          fi
          if ! _gs_eu2_apply_replace_target "${_env_file}" "${_rt}" "${_expanded}"; then
            printf '  [ERROR]    %-55s  replace: failed to rewrite target %s\n' \
              "${_var}" "${_rt}" >&2
            if [[ "${_GS_EU2_CFG[no_fail]:-false}" != "true" ]]; then
              [[ -n "${_snapshot}" ]] && cp "${_snapshot}" "${_env_file}" || true
              return 1
            fi
            continue
          fi
          printf '  [REPLACE]    ↳ (replace) %-47s  → %s\n' "${_rt}" "${_expanded}"
        done
      fi
    fi
  done

  # ── SKIP replace-only pass ───────────────────────────────────────────────
  # Plain SKIP decisions (cur==prop, up-to-date) are skipped by the AUTO gate above.
  # But their (replace:) targets may still be stale (target_actual ≠ expand_template(cur)).
  # This second pass rewrites stale replace targets for SKIP records.
  # No-op guard: skip if target_actual already equals the expanded value.
  local _n_replace_only_applied=0 _n_replace_only_would=0
  local _skip_rep_targets _skip_rep_tmpls
  for (( _i = 0; _i < _count; _i++ )); do
    _decision="$(_gs_eu2_record_get "${_i}" decision)"
    # Only plain SKIP (not skip-gate / FROZEN — those have _skip_reason set).
    # Access skip_reason via record field; LOCK/ERROR/HOLD/MANUAL/AUTO/SHA handled elsewhere.
    [[ "${_decision}" != "SKIP" ]] && continue
    # Check for skip-gate (frozen by (skip:) annotation) — those must not be written.
    local _sk_skip_reason
    _sk_skip_reason="$(_gs_eu2_record_get "${_i}" skip_reason)"
    [[ -n "${_sk_skip_reason}" ]] && continue

    _skip_rep_targets="$(_gs_eu2_record_get "${_i}" replace_targets)"
    _skip_rep_tmpls="$(_gs_eu2_record_get "${_i}" replace_templates)"
    [[ -z "${_skip_rep_targets}" ]] && continue

    local _sk_cur _sk_var
    _sk_var="$(_gs_eu2_record_get "${_i}" env_var)"
    _sk_cur="$(_gs_eu2_record_get "${_i}" current_version)"

    local _sk_old_ifs="${IFS}"
    IFS=$'\x1f'
    local _sk_rt_arr _sk_rm_arr
    read -ra _sk_rt_arr <<< "${_skip_rep_targets}"
    read -ra _sk_rm_arr <<< "${_skip_rep_tmpls}"
    IFS="${_sk_old_ifs}"
    local _sk_ri
    for (( _sk_ri = 0; _sk_ri < ${#_sk_rt_arr[@]}; _sk_ri++ )); do
      local _sk_rt="${_sk_rt_arr[${_sk_ri}]}"
      local _sk_rm="${_sk_rm_arr[${_sk_ri}]:-}"
      local _sk_exp_cur _sk_tgt_actual
      _sk_exp_cur="$(_gs_eu2_expand_replace_template "${_sk_rm}" "${_sk_cur:-}")"
      _sk_tgt_actual="$(grep -m1 "^${_sk_rt}=" "${_env_file}" 2>/dev/null | cut -d= -f2-)"
      # No-op guard: target already matches — skip silently
      [[ "${_sk_tgt_actual}" == "${_sk_exp_cur}" ]] && continue
      # Verify target exists in the env file
      if ! grep -q "^${_sk_rt}=" "${_env_file}" 2>/dev/null; then
        printf '  [ERROR]    %-55s  replace-only: target %s not found in %s\n' \
          "${_sk_var}" "${_sk_rt}" "${_env_file}" >&2
        if [[ "${_GS_EU2_CFG[no_fail]:-false}" != "true" ]]; then
          [[ -n "${_snapshot}" ]] && cp "${_snapshot}" "${_env_file}" || true
          return 1
        fi
        continue
      fi
      if [[ "${_dry_run}" == "true" ]]; then
        printf '  [DRY-RUN]  %-55s  ↳ replace-only %s → %s\n' "${_sk_var}" "${_sk_rt}" "${_sk_exp_cur}"
        (( ++_n_replace_only_would )) || true
      else
        _gs_eu2_apply_replace_target "${_env_file}" "${_sk_rt}" "${_sk_exp_cur}"
        printf '  [REPLACE]    ↳ (replace) %-47s  → %s  (replace-only)\n' "${_sk_rt}" "${_sk_exp_cur}"
        (( ++_n_replace_only_applied )) || true
      fi
    done
  done

  if [[ "${_dry_run}" == "true" ]]; then
    local _total_would=$(( _n_auto_only_would + _n_auto_sha_would + _n_sha_would + _n_lock_would + _n_replace_only_would ))
    printf '  %d update(s) would be applied (%d version-only, %d version+sha, %d sha, %d lock, %d replace-only) (--dry-run — no writes)\n' \
      "${_total_would}" "${_n_auto_only_would}" "${_n_auto_sha_would}" "${_n_sha_would}" "${_n_lock_would}" "${_n_replace_only_would}"
  else
    local _total_applied=$(( _n_auto_only_applied + _n_auto_sha_applied + _n_sha_applied + _n_lock_applied + _n_replace_only_applied ))
    printf '  %d update(s) applied to %s (%d version-only, %d version+sha, %d sha, %d lock, %d replace-only)\n' \
      "${_total_applied}" "${_env_file}" "${_n_auto_only_applied}" "${_n_auto_sha_applied}" "${_n_sha_applied}" "${_n_lock_applied}" "${_n_replace_only_applied}"
    # Floating ref pins are a separate operation (--apply-resolve), counted independently.
    (( _n_resolve_applied > 0 )) && printf '  %d floating ref(s) pinned\n' "${_n_resolve_applied}"
  fi
}
