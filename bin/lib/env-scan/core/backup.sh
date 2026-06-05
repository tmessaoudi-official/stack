#!/bin/bash
# backup.sh — backup helpers for env-scan (Phase 4.5 and Phase 6 extension)
#
# Exports:   _gs_es_backup_unconditional  _gs_es_backup_if_gitignored
#            _gs_es_backup_prune  _gs_es_backup_purge_all
# Sources:   none
# Deps:      bash 4.3+, cp, find, rm, git
# Env:       none (all inputs are arguments)
#
# Provides four composable backup operations used by _gs_es_main (Phase 4.5,
# Phase 6, Phase 6.5):
#   _gs_es_backup_unconditional   — always back up a file (used for env files)
#   _gs_es_backup_if_gitignored   — conditionally back up a Dockerfile (Phase 6)
#   _gs_es_backup_prune           — enforce --backup-keep retention limit (Phase 6.5)
#   _gs_es_backup_purge_all       — delete all backups before a run (--backup-purge)

# Include guard
[[ -n "${_GS_ES_BACKUP_SH_LOADED:-}" ]] && return 0
readonly _GS_ES_BACKUP_SH_LOADED=1

# _gs_es_backup_unconditional — copy file → file<suffix>.<ts> unconditionally.
#
# Args:    $1 file       — path to back up
#          $2 backup_ts  — timestamp suffix (e.g. 20260524-120000-12345)
#          $3 suffix     — suffix anchor (e.g. .bak)
#          $4 dry_run    — "true" → print what would happen, skip cp (default: false)
#          $5 quiet      — "true" → suppress informational output (default: false)
# Prints:  "[backup] file → dest" to stderr (unless quiet=true or dry_run=true)
# Returns: 0 on success or skipped (file not found); 1 if cp fails (disk full, etc.)
# Side fx: creates file<suffix>.<backup_ts> on disk when dry_run != true
_gs_es_backup_unconditional() {
  local _file="${1}"
  local _ts="${2}"
  local _suffix="${3}"
  local _dry_run="${4:-false}"
  local _quiet="${5:-false}"

  [[ -f "${_file}" ]] || return 0

  local _dest="${_file}${_suffix}.${_ts}"

  if [[ "${_dry_run}" == "true" ]]; then
    [[ "${_quiet}" == "true" ]] || echo " [backup] (dry-run) would back up ${_file} → ${_dest}" >&2
    return 0
  fi

  # A5: Check cp exit code — abort if backup fails (disk full, permissions, etc.)
  if ! cp -a "${_file}" "${_dest}"; then
    printf 'env-scan: backup failed for %s → %s (disk full?)\n' "${_file}" "${_dest}" >&2
    return 1
  fi
  [[ "${_quiet}" == "true" ]] || echo " [backup] ${_file} → ${_dest}" >&2
}

# _gs_es_backup_if_gitignored — back up file only when gitignored.
#
# Args:    $1 file       — file to conditionally back up (typically a Dockerfile)
#          $2 dir        — git repo root for git -C context
#          $3 backup_ts  — timestamp suffix
#          $4 suffix     — suffix anchor
#          $5 dry_run    — "true" → dry-run mode (default: false)
#          $6 quiet      — "true" → suppress informational output (default: false)
# Prints:  warning to stderr if dir is not a git repo (first occurrence only)
# Returns: 0 always (skip and warn rather than abort)
# Side fx: delegates to _gs_es_backup_unconditional when file is gitignored
_gs_es_backup_if_gitignored() {
  local _file="${1}"
  local _dir="${2}"
  local _ts="${3}"
  local _suffix="${4}"
  local _dry_run="${5:-false}"
  local _quiet="${6:-false}"

  if ! git -C "${_dir}" rev-parse --git-dir >/dev/null 2>&1; then
    [[ "${_quiet}" == "true" ]] || echo " [backup] warning: ${_dir} is not a git repo — skipping Dockerfile backup" >&2
    return 0
  fi

  if git -C "${_dir}" check-ignore -q "${_file}" 2>/dev/null; then
    _gs_es_backup_unconditional "${_file}" "${_ts}" "${_suffix}" "${_dry_run}" "${_quiet}"
  fi
}

# _gs_es_backup_prune — enforce retention limit for a file's backups.
#
# Args:    $1 file    — original file whose backups to prune
#          $2 suffix  — suffix anchor (e.g. .bak)
#          $3 keep    — number of newest backups to retain; 0 = unlimited (no-op)
#          $4 quiet   — "true" → suppress pruning notices (default: false)
# Prints:  "[backup] pruning old backup: <path>" to stderr per deleted file
# Returns: 0 always
# Side fx: deletes oldest backups (file<suffix>.*) down to keep count
#          lexicographic sort == chronological order for YYYYMMDD-HHMMSS timestamps
_gs_es_backup_prune() {
  local _file="${1}"
  local _suffix="${2}"
  local _keep="${3}"
  local _quiet="${4:-false}"

  [[ "${_keep}" -eq 0 ]] && return 0

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
    [[ "${_quiet}" == "true" ]] || echo " [backup] pruning old backup: ${_baks[${_i}]}" >&2
    rm -f -- "${_baks[${_i}]}"
  done
}

# _gs_es_backup_purge_all — delete ALL backups for destination files and Dockerfiles.
#
# Args:    $1 files_list  — space-separated list of destination files
#          $2 suffix      — suffix anchor
#          $3 scan_path   — root dir for Dockerfile search
#          $4 dir         — git repo root for gitignore check
#          $5 quiet       — "true" → suppress purge notices (default: false)
# Prints:  "[backup] purging: <path>" to stderr per deleted backup
# Returns: 0 always
# Side fx: rm -f all <file><suffix>.* for each file in files_list;
#          also purges gitignored Dockerfile backups under scan_path
_gs_es_backup_purge_all() {
  local _files_list="${1}"
  local _suffix="${2}"
  local _scan_path="${3}"
  local _dir="${4}"
  local _quiet="${5:-false}"

  local _f
  for _f in ${_files_list//[\"\'\`]/}; do
    while IFS= read -r -d '' _b; do
      [[ "${_quiet}" == "true" ]] || echo " [backup] purging: ${_b}" >&2
      rm -f -- "${_b}"
    done < <(find "$(dirname "${_f}")" -maxdepth 1 \
      -name "$(basename "${_f}")${_suffix}.*" -print0 2>/dev/null)
  done

  if [[ -d "${_scan_path}" ]] && git -C "${_dir}" rev-parse --git-dir >/dev/null 2>&1; then
    local _dockerfile
    while IFS= read -r _dockerfile; do
      if git -C "${_dir}" check-ignore -q "${_dockerfile}" 2>/dev/null; then
        while IFS= read -r -d '' _b; do
          [[ "${_quiet}" == "true" ]] || echo " [backup] purging: ${_b}" >&2
          rm -f -- "${_b}"
        done < <(find "$(dirname "${_dockerfile}")" -maxdepth 1 \
          -name "$(basename "${_dockerfile}")${_suffix}.*" -print0 2>/dev/null)
      fi
    done < <(find "${_scan_path}" -type f -name "Dockerfile*" 2>/dev/null | LC_ALL=C sort)
  fi
}
