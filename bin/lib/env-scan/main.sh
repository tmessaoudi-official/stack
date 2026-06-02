#!/bin/bash
# main.sh — gs_es_main orchestration for env-scan 8-phase pipeline.
#
# Exports:   gs_es_main
# Sources:   config/defaults.sh  core/args.sh  core/backup.sh  core/extract.sh
#            core/merge.sh  reporting/profile.sh  reporting/reference.sh
#            propagate.sh
# Deps:      bash 4.3+, mktemp, realpath, envsubst, sed, awk, find
# Env:       _GS_ES_CFG (associative array — populated by args.sh)
#
# 8-phase pipeline (see templates/tips/env-scan.md for full reference):
#   Phase 1: Parse args
#   Phase 2: Build source index
#   Phase 3: Scan docker sources (ARG lines in Dockerfiles)
#   Phase 4: Detect conflicting values across sources
#   Phase 4.5: Backup pre-flight (purge + snapshot)
#   Phase 5: Sync env files (.env → .env.local)
#   Phase 6: Propagate to Dockerfiles
#   Phase 6.5: Backup retention prune
#   Phase 7: Cleanup
set -eEuo pipefail

# Include guard — B4: fix name to follow _GS_ES_MODULENAME_SH_LOADED convention
[[ -n "${_GS_ES_MAIN_SH_LOADED:-}" ]] && return 0
readonly _GS_ES_MAIN_SH_LOADED=1

# shellcheck source=./config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/config/defaults.sh"
# shellcheck source=./core/args.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/args.sh"
# shellcheck source=./core/backup.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/backup.sh"
# shellcheck source=./core/extract.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/extract.sh"
# shellcheck source=./core/merge.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/merge.sh"
# shellcheck source=./reporting/profile.sh
source "$(dirname "${BASH_SOURCE[0]}")/reporting/profile.sh"
# shellcheck source=./reporting/reference.sh
source "$(dirname "${BASH_SOURCE[0]}")/reporting/reference.sh"
# shellcheck source=./propagate.sh
source "$(dirname "${BASH_SOURCE[0]}")/propagate.sh"

# Session-scoped temp directory — set here, used by extract.sh and missing.sh
_GS_ES_SESSION_TMP=""

# _gs_es_confirm_write — interactive confirmation gate before env-scan writes files.
#
# Args:    none
# Reads:   _GS_ES_CFG[yes]     — when "true", skip prompt and proceed immediately
#          _GS_ES_CFG[dry_run] — when "true", no gate needed (no writes will occur)
# Prints:  prompt to stderr (TTY path); nothing on non-TTY (proceed silently)
# Returns: 0 (proceed) | exits 1 (user declined on TTY)
# Side fx: reads one line from stdin when on a TTY
#
# Gate logic (gentler than env-update — env-scan is designed for automated use):
#   dry_run=true    → return 0 immediately (no writes, no gate needed)
#   --yes=true      → return 0 (explicit bypass for scripting and --scan cascade)
#   stdin not TTY   → return 0 (non-interactive: Makefile, CI, scripts — proceed silently)
#   TTY, user y/Y   → return 0
#   TTY, other      → exit 1
_gs_es_confirm_write() {
  [[ "${_GS_ES_CFG[dry_run]:-false}" == "true" ]] && return 0
  [[ "${_GS_ES_CFG[yes]:-false}" == "true" ]] && return 0
  [[ ! -t 0 ]] && return 0  # non-interactive: proceed without prompt
  # TTY path: ask the user
  local _reply
  printf '\nProceed with env-scan (sync .env.local + propagate to Dockerfiles)? [y/N]: ' >&2
  read -r _reply || _reply=""
  if [[ "${_reply}" =~ ^[Yy]$ ]]; then
    return 0
  fi
  printf 'Aborted.\n' >&2
  exit 1
}

# gs_es_main — top-level entry point; runs the full 8-phase pipeline.
#
# Args:    "$@" — all CLI arguments (passed through to gs_es_parse_args)
# Prints:  phase output to stdout; banners + backup messages to stderr
# Returns: 0 on success; non-zero on Phase 6 propagation error (unless --no-fail)
gs_es_main() {
  # Phase 1: Parse args
  _gs_es_profile_init # records total start time before we know --profile value
  _gs_es_profile_start
  gs_es_parse_args "${@}"
  _gs_es_profile_end "Parse args"

  # --reference: print comprehensive reference and exit (before any env file access)
  if [[ "${_GS_ES_CFG[reference]:-false}" == "true" ]]; then
    _gs_es_show_reference "${_GS_ES_CFG[reference_section]:-all}"
    exit 0
  fi

  # Mode banners — always printed to stderr regardless of --quiet
  [[ "${_GS_ES_CFG[dry_run]:-false}" == "true" ]] && printf '[DRY-RUN MODE] no files will be written\n' >&2
  [[ "${_GS_ES_CFG[no_fail]:-false}" == "true" ]] && printf '[NO-FAIL MODE] Phase 6 propagation errors will not abort — exit code forced to 0\n' >&2
  [[ "${_GS_ES_CFG[sync_values]:-true}" == "false" ]] && printf '[SYNC-VALUES=OFF MODE] destination values will not be overwritten\n' >&2
  [[ "${_GS_ES_CFG[backup]:-true}" == "false" ]] && printf '[NO-BACKUP MODE] backup step skipped\n' >&2
  [[ "${_GS_ES_CFG[backup_purge]:-false}" == "true" ]] && printf '[BACKUP-PURGE MODE] all existing backups will be deleted before run\n' >&2
  [[ "${_GS_ES_CFG[prune_removed]:-false}" == "true" ]] && printf '[PRUNE-REMOVED MODE] vars absent from source will be removed from dest\n' >&2

  # ── Write confirmation gate ───────────────────────────────────────────────
  # On TTY: prompt before any files are written. Non-TTY: proceed silently.
  # --yes bypasses the TTY prompt (used by env-update --scan cascade).
  _gs_es_confirm_write

  # ── Session temp directory (infrastructure — not a profiled phase) ─────────
  _GS_ES_SESSION_TMP="$(mktemp -d)" || {
    printf 'env-scan: mktemp failed\n' >&2
    exit 1
  }
  # A4: Wait for any background jobs before cleaning up temp dir,
  # so extraction subprocesses don't race against rm -rf.
  _gs_es_cleanup() {
    wait 2>/dev/null || true
    rm -rf "${_GS_ES_SESSION_TMP}"
  }
  trap '_gs_es_cleanup' EXIT

  # Phase 2: Build source index
  _gs_es_profile_start
  >"${_GS_ES_CFG[source_merged_file]}"

  # P7: replace cat | sed | sed | sed with single sed
  local _src_file
  for _src_file in ${_GS_ES_CFG[source_files]//[\"\'\`]/}; do
    sed -e '/^\s*#/d' -e '/^\s*$/d' -e 's/[[:space:]]*$//' "${_src_file}" >>"${_GS_ES_CFG[source_merged_file]}"
    echo >>"${_GS_ES_CFG[source_merged_file]}"
  done
  _gs_es_profile_end "Build source index"

  # Phase 3: Scan docker sources
  _gs_es_profile_start
  if [[ "true" = "${_GS_ES_CFG[scan_sources],,}" ]]; then
    _gs_es_run_extraction
  fi
  _gs_es_profile_end "Scan docker sources"

  # Phase 4: Detect conflicting values
  _gs_es_profile_start
  # ── Consolidated multiple-defaults check (sequential, after all extractions) ─
  gs_es_detect_multiple_defaults \
    "${_GS_ES_CFG[scan_output_file]}" \
    "${_GS_ES_CFG[scan_path]}"
  _gs_es_profile_end "Detect conflicting values"

  # Phase 4.5: Backup pre-flight (purge + snapshot)
  _gs_es_profile_start
  local _backup_ts
  # A3: Append PID to avoid timestamp collisions when two runs start in the same second
  _backup_ts="$(date +%Y%m%d-%H%M%S)-$$"
  _GS_ES_CFG[_backup_ts]="${_backup_ts}"

  if [[ "true" == "${_GS_ES_CFG[backup_purge]}" && "true" != "${_GS_ES_CFG[dry_run]}" ]]; then
    _gs_es_backup_purge_all \
      "${_GS_ES_CFG[destination_files]}" \
      "${_GS_ES_CFG[backup_suffix]}" \
      "${_GS_ES_CFG[scan_path]}" \
      "${_GS_ES_CFG[dir]}" \
      "${_GS_ES_CFG[quiet]}"
  fi

  if [[ "true" == "${_GS_ES_CFG[backup]}" && "true" != "${_GS_ES_CFG[dry_run]}" ]]; then
    local _bk_dest
    for _bk_dest in ${_GS_ES_CFG[destination_files]//[\"\'\`]/}; do
      # A5: abort if backup fails — do not overwrite without a safety copy
      _gs_es_backup_unconditional \
        "${_bk_dest}" \
        "${_backup_ts}" \
        "${_GS_ES_CFG[backup_suffix]}" \
        "false" \
        "${_GS_ES_CFG[quiet]}" || exit 1
    done
  elif [[ "true" == "${_GS_ES_CFG[backup]}" && "true" == "${_GS_ES_CFG[dry_run]}" ]]; then
    local _bk_dest
    for _bk_dest in ${_GS_ES_CFG[destination_files]//[\"\'\`]/}; do
      [[ -f "${_bk_dest}" ]] || continue
      echo " [backup] (dry-run) would back up ${_bk_dest} → ${_bk_dest}${_GS_ES_CFG[backup_suffix]}.${_backup_ts}"
    done
  fi
  _gs_es_profile_end "Backup pre-flight"

  # Phase 5: Sync env files
  local _count_src=0
  local _count_dest=0
  local _dest_file
  _gs_es_profile_start
  for _src_file in ${_GS_ES_CFG[source_files]//[\"\'\`]/}; do
    ((++_count_src))
    for _dest_file in ${_GS_ES_CFG[destination_files]//[\"\'\`]/}; do
      ((++_count_dest))
      gs_es_process_file \
        "${_src_file}" \
        "${_dest_file}" \
        "${_count_src}_${_count_dest}" \
        "${_GS_ES_CFG[dry_run]}"
    done
  done
  _gs_es_profile_end "Sync env files"

  # Phase 6: Propagate canonical values to Dockerfiles.
  # es-F001: source_files may be space-separated when --source-files has multiple values.
  # gs_es_propagate_to_dockerfiles expects a single file path — loop over each source file.
  _gs_es_profile_start
  local _propagate_rc=0
  local _prop_src_file
  for _prop_src_file in ${_GS_ES_CFG[source_files]//[\"\'\`]/}; do
    local _one_propagate_rc=0
    gs_es_propagate_to_dockerfiles \
      "${_prop_src_file}" \
      "${_GS_ES_CFG[scan_path]}" \
      "${_GS_ES_CFG[conflict_ignore_pattern]:-}" \
      "${_GS_ES_CFG[dry_run]}" || _one_propagate_rc=$?
    if [[ "${_one_propagate_rc}" -ne 0 ]]; then
      _propagate_rc="${_one_propagate_rc}"
    fi
  done
  if [[ "${_propagate_rc}" -ne 0 ]]; then
    if [[ "${_GS_ES_CFG[no_fail]:-false}" == "true" ]]; then
      printf '[NO-FAIL] Phase 6 propagation error suppressed (exit code %d) — continuing\n' \
        "${_propagate_rc}" >&2
    else
      return "${_propagate_rc}"
    fi
  fi
  _gs_es_profile_end "Propagate to Dockerfiles"

  # Phase 6.5: Backup retention prune
  _gs_es_profile_start
  if [[ "true" == "${_GS_ES_CFG[backup]}" && "true" != "${_GS_ES_CFG[dry_run]}" ]]; then
    local _pr_dest
    for _pr_dest in ${_GS_ES_CFG[destination_files]//[\"\'\`]/}; do
      _gs_es_backup_prune \
        "${_pr_dest}" \
        "${_GS_ES_CFG[backup_suffix]}" \
        "${_GS_ES_CFG[backup_keep]}" \
        "${_GS_ES_CFG[quiet]}"
    done
  fi
  _gs_es_profile_end "Backup retention prune"

  # Phase 7: Cleanup
  _gs_es_profile_start
  # ── Final cleanup of user-facing output files ──────────────────────────────
  [[ "true" = "${_GS_ES_CFG[scan_delete_output],,}" && "true" = "${_GS_ES_CFG[cleanup_tmp],,}" ]] \
    && rm -rf \
      "${_GS_ES_CFG[scan_output_file]}" \
      "${_GS_ES_CFG[source_merged_file]}"
  _gs_es_profile_end "Cleanup"

  # ── Print profile report if requested ─────────────────────────────────────
  [[ "true" = "${_GS_ES_CFG[profile]}" ]] && _gs_es_profile_report
  return 0
}
