#!/bin/bash
# main.sh — le_main orchestration

# Include guard
[[ -n "${_LE_MAIN_SH_LOADED:-}" ]] && return 0
readonly _LE_MAIN_SH_LOADED=1

# shellcheck source=./config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
# shellcheck source=./args.sh
source "$(dirname "${BASH_SOURCE[0]}")/args.sh"
# shellcheck source=./extract.sh
source "$(dirname "${BASH_SOURCE[0]}")/extract.sh"
# shellcheck source=./merge.sh
source "$(dirname "${BASH_SOURCE[0]}")/merge.sh"

# Session-scoped temp directory — set here, used by extract.sh and missing.sh
_LE_SESSION_TMP=""

le_main() {
	le_parse_args "${@}"

	# ── Session temp directory (prevents collisions from concurrent invocations) ──
	_LE_SESSION_TMP="$(mktemp -d)"
	# shellcheck disable=SC2064
	trap "rm -rf '${_LE_SESSION_TMP}'" EXIT

	# ── Build merged source file ───────────────────────────────────────────────
	> "${_LE_CFG[all_src_env_merged_name]}"

	# P7: replace cat | sed | sed | sed with single sed
	local _src_file
	for _src_file in ${_LE_CFG[source_files]//[\"\'\`]/}; do
		sed -e '/^\s*#/d' -e '/^\s*$/d' -e 's/[[:space:]]*$//' "${_src_file}" >> "${_LE_CFG[all_src_env_merged_name]}"
		echo >> "${_LE_CFG[all_src_env_merged_name]}"
	done

	# ── Extract all env vars ───────────────────────────────────────────────────
	if [[ "true" = "${_LE_CFG[extract_all_env],,}" ]]; then
		_le_run_extraction
	fi

	# ── Consolidated multiple-defaults check (sequential, after all extractions) ─
	le_detect_multiple_defaults \
		"${_LE_CFG[extract_all_env_output_file]}" \
		"${_LE_CFG[search_path]}"

	# ── Process each source/destination pair ──────────────────────────────────
	local _count_src=0
	local _count_dest=0
	local _dest_file

	for _src_file in ${_LE_CFG[source_files]//[\"\'\`]/}; do
		((_count_src++))
		for _dest_file in ${_LE_CFG[destination_files]//[\"\'\`]/}; do
			((_count_dest++))
			le_process_file \
				"${_src_file}" \
				"${_dest_file}" \
				"${_count_src}_${_count_dest}"
		done
	done

	# ── Final cleanup of user-facing output files ─────────────────────────────
	[[ "true" = "${_LE_CFG[extract_all_env_delete_output],,}" && "true" = "${_LE_CFG[cleanup_tmp],,}" ]] &&
		rm -rf \
			"${_LE_CFG[extract_all_env_output_file]}" \
			"${_LE_CFG[all_src_env_merged_name]}"
}
