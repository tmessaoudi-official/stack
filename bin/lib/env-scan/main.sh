#!/bin/bash
# main.sh — gs_es_main orchestration
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
# shellcheck source=./propagate.sh
source "$(dirname "${BASH_SOURCE[0]}")/propagate.sh"

# Session-scoped temp directory — set here, used by extract.sh and missing.sh
_GS_ES_SESSION_TMP=""

gs_es_main() {
	# Phase 1: Parse args
	_gs_es_profile_init   # records total start time before we know --profile value
	_gs_es_profile_start
	gs_es_parse_args "${@}"
	_gs_es_profile_end "Parse args"

	# Mode banners — always printed to stderr regardless of --quiet
	[[ "${_GS_ES_CFG[dry_run]:-false}" == "true" ]] && printf '[DRY-RUN MODE] no files will be written\n' >&2
	[[ "${_GS_ES_CFG[no_fail]:-false}" == "true" ]] && printf '[NO-FAIL MODE] scan errors will not abort — exit code forced to 0\n' >&2
	[[ "${_GS_ES_CFG[sync_values]:-true}" == "false" ]] && printf '[SYNC-VALUES=OFF MODE] destination values will not be overwritten\n' >&2
	[[ "${_GS_ES_CFG[backup]:-true}" == "false" ]] && printf '[NO-BACKUP MODE] backup step skipped\n' >&2
	[[ "${_GS_ES_CFG[backup_purge]:-false}" == "true" ]] && printf '[BACKUP-PURGE MODE] all existing backups will be deleted before run\n' >&2
	[[ "${_GS_ES_CFG[prune_removed]:-false}" == "true" ]] && printf '[PRUNE-REMOVED MODE] vars absent from source will be removed from dest\n' >&2

	# ── Session temp directory (infrastructure — not a profiled phase) ─────────
	_GS_ES_SESSION_TMP="$(mktemp -d)" || { printf 'env-scan: mktemp failed\n' >&2; exit 1; }
	# A4: Wait for any background jobs before cleaning up temp dir,
	# so extraction subprocesses don't race against rm -rf.
	_gs_es_cleanup() {
		wait 2>/dev/null || true
		rm -rf "${_GS_ES_SESSION_TMP}"
	}
	trap '_gs_es_cleanup' EXIT

	# Phase 2: Build source index
	_gs_es_profile_start
	> "${_GS_ES_CFG[source_merged_file]}"

	# P7: replace cat | sed | sed | sed with single sed
	local _src_file
	for _src_file in ${_GS_ES_CFG[source_files]//[\"\'\`]/}; do
		sed -e '/^\s*#/d' -e '/^\s*$/d' -e 's/[[:space:]]*$//' "${_src_file}" >> "${_GS_ES_CFG[source_merged_file]}"
		echo >> "${_GS_ES_CFG[source_merged_file]}"
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
	local _backup_ts
	# A3: Append PID to avoid timestamp collisions when two runs start in the same second
	_backup_ts="$(date +%Y%m%d-%H%M%S)-$$"
	_GS_ES_CFG[_backup_ts]="${_backup_ts}"

	if [[ "true" == "${_GS_ES_CFG[backup_purge]}" ]]; then
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

	# Phase 5: Sync env files
	local _count_src=0
	local _count_dest=0
	local _dest_file
	_gs_es_profile_start
	for _src_file in ${_GS_ES_CFG[source_files]//[\"\'\`]/}; do
		(( ++_count_src ))
		for _dest_file in ${_GS_ES_CFG[destination_files]//[\"\'\`]/}; do
			(( ++_count_dest ))
			gs_es_process_file \
				"${_src_file}" \
				"${_dest_file}" \
				"${_count_src}_${_count_dest}" \
				"${_GS_ES_CFG[dry_run]}"
		done
	done
	_gs_es_profile_end "Sync env files"

	# Phase 6: Propagate canonical values to Dockerfiles
	_gs_es_profile_start
	local _propagate_rc=0
	gs_es_propagate_to_dockerfiles \
		"${_GS_ES_CFG[source_files]}" \
		"${_GS_ES_CFG[scan_path]}" \
		"${_GS_ES_CFG[conflict_ignore_pattern]:-}" \
		"${_GS_ES_CFG[dry_run]}" || _propagate_rc=$?
	if [[ "${_propagate_rc}" -ne 0 ]]; then
		if [[ "${_GS_ES_CFG[no_fail]:-false}" == "true" ]]; then
			printf '[NO-FAIL] scan error present — exit code forced to 0\n' >&2
		else
			return "${_propagate_rc}"
		fi
	fi
	_gs_es_profile_end "Propagate to Dockerfiles"

	# Phase 6.5: Backup retention prune
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

	# Phase 7: Cleanup
	_gs_es_profile_start
	# ── Final cleanup of user-facing output files ──────────────────────────────
	[[ "true" = "${_GS_ES_CFG[scan_delete_output],,}" && "true" = "${_GS_ES_CFG[cleanup_tmp],,}" ]] &&
		rm -rf \
			"${_GS_ES_CFG[scan_output_file]}" \
			"${_GS_ES_CFG[source_merged_file]}"
	_gs_es_profile_end "Cleanup"

	# ── Print profile report if requested ─────────────────────────────────────
	[[ "true" = "${_GS_ES_CFG[profile]}" ]] && _gs_es_profile_report
	return 0
}
