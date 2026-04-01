#!/bin/bash
# main.sh — le_main orchestration

# Include guard
[[ -n "${_GS_LE_MAIN_SH_LOADED:-}" ]] && return 0
readonly _GS_LE_MAIN_SH_LOADED=1

# shellcheck source=./config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/config/defaults.sh"
# shellcheck source=./core/args.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/args.sh"
# shellcheck source=./core/extract.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/extract.sh"
# shellcheck source=./core/merge.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/merge.sh"
# shellcheck source=./reporting/profile.sh
source "$(dirname "${BASH_SOURCE[0]}")/reporting/profile.sh"

# Session-scoped temp directory — set here, used by extract.sh and missing.sh
_GS_LE_SESSION_TMP=""

le_main() {
	# Phase 1: Parse args
	_gs_le_profile_init   # records total start time before we know --profile value
	_gs_le_profile_start
	le_parse_args "${@}"
	_gs_le_profile_end "Parse args"

	# ── Session temp directory (infrastructure — not a profiled phase) ─────────
	_GS_LE_SESSION_TMP="$(mktemp -d)"
	# shellcheck disable=SC2064
	trap "rm -rf '${_GS_LE_SESSION_TMP}'" EXIT

	# Phase 2: Build source index
	_gs_le_profile_start
	> "${_GS_LE_CFG[source_merged_file]}"

	# P7: replace cat | sed | sed | sed with single sed
	local _src_file
	for _src_file in ${_GS_LE_CFG[source_files]//[\"\'\`]/}; do
		sed -e '/^\s*#/d' -e '/^\s*$/d' -e 's/[[:space:]]*$//' "${_src_file}" >> "${_GS_LE_CFG[source_merged_file]}"
		echo >> "${_GS_LE_CFG[source_merged_file]}"
	done
	_gs_le_profile_end "Build source index"

	# Phase 3: Scan docker sources
	_gs_le_profile_start
	if [[ "true" = "${_GS_LE_CFG[scan_sources],,}" ]]; then
		_le_run_extraction
	fi
	_gs_le_profile_end "Scan docker sources"

	# Phase 4: Detect conflicting values
	_gs_le_profile_start
	# ── Consolidated multiple-defaults check (sequential, after all extractions) ─
	le_detect_multiple_defaults \
		"${_GS_LE_CFG[scan_output_file]}" \
		"${_GS_LE_CFG[scan_path]}"
	_gs_le_profile_end "Detect conflicting values"

	# Phase 5: Sync env files
	local _count_src=0
	local _count_dest=0
	local _dest_file
	_gs_le_profile_start
	for _src_file in ${_GS_LE_CFG[source_files]//[\"\'\`]/}; do
		((_count_src++))
		for _dest_file in ${_GS_LE_CFG[destination_files]//[\"\'\`]/}; do
			((_count_dest++))
			le_process_file \
				"${_src_file}" \
				"${_dest_file}" \
				"${_count_src}_${_count_dest}"
		done
	done
	_gs_le_profile_end "Sync env files"

	# Phase 6: Cleanup
	_gs_le_profile_start
	# ── Final cleanup of user-facing output files ──────────────────────────────
	[[ "true" = "${_GS_LE_CFG[scan_delete_output],,}" && "true" = "${_GS_LE_CFG[cleanup_tmp],,}" ]] &&
		rm -rf \
			"${_GS_LE_CFG[scan_output_file]}" \
			"${_GS_LE_CFG[source_merged_file]}"
	_gs_le_profile_end "Cleanup"

	# ── Print profile report if requested ─────────────────────────────────────
	[[ "true" = "${_GS_LE_CFG[profile]}" ]] && _gs_le_profile_report
}
