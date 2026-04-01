#!/bin/bash
# merge.sh — le_process_file (src→dst merge + cleanup)

# Include guard
[[ -n "${_GS_LE_MERGE_SH_LOADED:-}" ]] && return 0
readonly _GS_LE_MERGE_SH_LOADED=1

# shellcheck source=./../config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/defaults.sh"
# shellcheck source=./../reporting/report.sh
source "$(dirname "${BASH_SOURCE[0]}")/../reporting/report.sh"
# shellcheck source=./missing.sh
source "$(dirname "${BASH_SOURCE[0]}")/missing.sh"

# ── le_process_file ───────────────────────────────────────────────────────────
# Args: src_file  dest_file  count
# Reads from _GS_LE_CFG: destination_file_tmp_suffix, destination_file_merged_suffix,
#                        strip_comments, remove_empty_lines, remove_trailing_spaces,
#                        show_added_entries, check_missing, exclude_local_pattern,
#                        exclude_source_check_pattern, exclude_check_missing,
#                        cleanup_tmp, debug, show_different_entries,
#                        sync_values, scan_output_file,
#                        dir, scan_path
le_process_file() {
	local src_file="${1}"
	local dest_file="${2}"
	local count="${3}"

	local tmp_file
	tmp_file="${dest_file}${_GS_LE_CFG[destination_file_tmp_suffix]}.${count}"
	local merged_file
	merged_file="${dest_file}${_GS_LE_CFG[destination_file_merged_suffix]}.${count}"

	touch "${src_file}" "${dest_file}"
	cp "${dest_file}" "${tmp_file}"
	sed -i -e "\$a\\" "${tmp_file}"
	cat "${src_file}" >> "${tmp_file}"

	awk -F "=" '!seen[$1]++' "${tmp_file}" > "${merged_file}"

	# P6: merge three sed -i passes into one
	local _sed_args=()
	[[ "${_GS_LE_CFG[strip_comments]}" = "true" ]]          && _sed_args+=(-e '/^\s*#/d')
	[[ "${_GS_LE_CFG[remove_empty_lines]}" = "true" ]]      && _sed_args+=(-e '/^\s*$/d')
	[[ "${_GS_LE_CFG[remove_trailing_spaces]}" = "true" ]]  && _sed_args+=(-e 's/[[:space:]]*$//')
	[[ ${#_sed_args[@]} -gt 0 ]] && sed -i "${_sed_args[@]}" "${merged_file}"

	# Show added entries if enabled
	[[ "true" = "${_GS_LE_CFG[show_added_entries]}" ]] &&
		le_show_inconsistency \
			"${src_file}" \
			"${dest_file}" \
			"" \
			"add"

	# Overwrite destination with merged content
	mv "${merged_file}" "${dest_file}"

	# Show different/missing entries if enabled
	le_show_differences \
		"${src_file}" \
		"${dest_file}" \
		"${count}"

	[[ "true" = "${_GS_LE_CFG[check_missing]}" ]] &&
		le_check_missing_variables \
			"${src_file}" \
			"src.${count}" \
			"${_GS_LE_CFG[exclude_check_missing]}|${_GS_LE_CFG[exclude_local_pattern]}" \
			"false"
	[[ "true" = "${_GS_LE_CFG[check_missing]}" ]] &&
		le_check_missing_variables \
			"${dest_file}" \
			"dest.${count}" \
			"${_GS_LE_CFG[exclude_check_missing]}" \
			"false"
	[[ "true" = "${_GS_LE_CFG[check_missing]}" ]] &&
		le_check_missing_variables \
			"${dest_file}" \
			"dest.${count}" \
			"${_GS_LE_CFG[exclude_source_check_pattern]}" \
			"true"

	[[ "true" = "${_GS_LE_CFG[show_added_entries]}" ]] &&
		le_show_inconsistency \
			"${dest_file}" \
			"${src_file}" \
			"${_GS_LE_CFG[exclude_local_pattern]}" \
			""

	[[ "true" = "${_GS_LE_CFG[cleanup_tmp]}" ]] &&
		rm -rf \
			"${tmp_file}"
}
