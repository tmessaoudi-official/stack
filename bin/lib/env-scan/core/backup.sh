#!/bin/bash
# backup.sh — backup helpers for env-scan (Phase 4.5 and Phase 6 extension)

# Include guard
[[ -n "${_GS_ES_BACKUP_SH_LOADED:-}" ]] && return 0
readonly _GS_ES_BACKUP_SH_LOADED=1

# ── _gs_es_backup_unconditional ──────────────────────────────────────────────
# Args: file  backup_ts  suffix  dry_run  quiet
# Copies file → file<suffix>.<backup_ts>. Logs "[backup] ..." unless quiet=true.
# Skips silently if file does not exist.
_gs_es_backup_unconditional() {
  local _file="${1}"
  local _ts="${2}"
  local _suffix="${3}"
  local _dry_run="${4:-false}"
  local _quiet="${5:-false}"

  [[ -f "${_file}" ]] || return 0

  local _dest="${_file}${_suffix}.${_ts}"

  if [[ "${_dry_run}" == "true" ]]; then
    [[ "${_quiet}" == "true" ]] || echo " [backup] (dry-run) would back up ${_file} → ${_dest}"
    return 0
  fi

  # A5: Check cp exit code — abort if backup fails (disk full, permissions, etc.)
  if ! cp -a "${_file}" "${_dest}"; then
    printf 'env-scan: backup failed for %s → %s (disk full?)\n' "${_file}" "${_dest}" >&2
    return 1
  fi
  [[ "${_quiet}" == "true" ]] || echo " [backup] ${_file} → ${_dest}"
}

# ── _gs_es_backup_if_gitignored ──────────────────────────────────────────────
# Args: file  dir  backup_ts  suffix  dry_run  quiet
# Backs up file only if git check-ignore reports it as gitignored.
# If not in a git repo, skips silently with one warning (only first time).
_gs_es_backup_if_gitignored() {
  local _file="${1}"
  local _dir="${2}"
  local _ts="${3}"
  local _suffix="${4}"
  local _dry_run="${5:-false}"
  local _quiet="${6:-false}"

  if ! git -C "${_dir}" rev-parse --git-dir >/dev/null 2>&1; then
    [[ "${_quiet}" == "true" ]] || echo " [backup] warning: ${_dir} is not a git repo — skipping Dockerfile backup"
    return 0
  fi

  if git -C "${_dir}" check-ignore -q "${_file}" 2>/dev/null; then
    _gs_es_backup_unconditional "${_file}" "${_ts}" "${_suffix}" "${_dry_run}" "${_quiet}"
  fi
}

# ── _gs_es_backup_prune ───────────────────────────────────────────────────────
# Args: file  suffix  keep  quiet
# Lists file<suffix>.* sorted by name (lexicographic = chronological for YYYYMMDD-HHMMSS),
# deletes all but the newest `keep`. No-op when keep=0 (unlimited).
_gs_es_backup_prune() {
  local _file="${1}"
  local _suffix="${2}"
  local _keep="${3}"
  local _quiet="${4:-false}"

  [[ "${_keep}" -eq 0 ]] 2>/dev/null && return 0

  local -a _baks
  while IFS= read -r -d '' _b; do
    _baks+=("${_b}")
  done < <(find "$(dirname "${_file}")" -maxdepth 1 \
    -name "$(basename "${_file}")${_suffix}.*" -print0 2>/dev/null | sort -z)

  local _total="${#_baks[@]}"
  if [[ "${_total}" -le "${_keep}" ]]; then
    return 0
  fi

  local _remove=$((_total - _keep))
  local _i
  for ((_i = 0; _i < _remove; _i++)); do
    [[ "${_quiet}" == "true" ]] || echo " [backup] pruning old backup: ${_baks[${_i}]}"
    rm -f -- "${_baks[${_i}]}"
  done
}

# ── _gs_es_backup_purge_all ───────────────────────────────────────────────────
# Args: files_list  suffix  scan_path  dir  quiet
# Deletes all <file><suffix>.* for each file in files_list (space-separated).
# Also purges gitignored Dockerfile backups under scan_path.
_gs_es_backup_purge_all() {
  local _files_list="${1}"
  local _suffix="${2}"
  local _scan_path="${3}"
  local _dir="${4}"
  local _quiet="${5:-false}"

  local _f
  for _f in ${_files_list//[\"\'\`]/}; do
    local _pat
    while IFS= read -r -d '' _b; do
      [[ "${_quiet}" == "true" ]] || echo " [backup] purging: ${_b}"
      rm -f -- "${_b}"
    done < <(find "$(dirname "${_f}")" -maxdepth 1 \
      -name "$(basename "${_f}")${_suffix}.*" -print0 2>/dev/null)
  done

  if [[ -d "${_scan_path}" ]] && git -C "${_dir}" rev-parse --git-dir >/dev/null 2>&1; then
    local _dockerfile
    while IFS= read -r _dockerfile; do
      if git -C "${_dir}" check-ignore -q "${_dockerfile}" 2>/dev/null; then
        while IFS= read -r -d '' _b; do
          [[ "${_quiet}" == "true" ]] || echo " [backup] purging: ${_b}"
          rm -f -- "${_b}"
        done < <(find "$(dirname "${_dockerfile}")" -maxdepth 1 \
          -name "$(basename "${_dockerfile}")${_suffix}.*" -print0 2>/dev/null)
      fi
    done < <(find "${_scan_path}" -type f -name "Dockerfile*" 2>/dev/null | LC_ALL=C sort)
  fi
}
