#!/bin/bash
# merge.sh — gs_es_process_file (src→dst merge + cleanup)

# Include guard
[[ -n "${_GS_ES_MERGE_SH_LOADED:-}" ]] && return 0
readonly _GS_ES_MERGE_SH_LOADED=1

# shellcheck source=./../config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/defaults.sh"
# shellcheck source=./../reporting/report.sh
source "$(dirname "${BASH_SOURCE[0]}")/../reporting/report.sh"
# shellcheck source=./missing.sh
source "$(dirname "${BASH_SOURCE[0]}")/missing.sh"

# ── gs_es_process_file ───────────────────────────────────────────────────────────
# Args: src_file  dest_file  count  dry_run
# Reads from _GS_ES_CFG: destination_file_tmp_suffix, destination_file_merged_suffix,
#                        strip_comments, remove_empty_lines, remove_trailing_spaces,
#                        show_added_entries, check_missing, exclude_local_pattern,
#                        exclude_source_check_pattern, exclude_check_missing,
#                        cleanup_tmp, debug, show_different_entries,
#                        sync_values, scan_output_file,
#                        dir, scan_path
# When dry_run="true": all filesystem writes are suppressed; the function still
# computes and reports what would change (added entries, differences, missing).
gs_es_process_file() {
	local src_file="${1}"
	local dest_file="${2}"
	local count="${3}"
	local dry_run="${4:-false}"

	local tmp_file
	tmp_file="${dest_file}${_GS_ES_CFG[destination_file_tmp_suffix]}.${count}"
	local merged_file
	merged_file="${dest_file}${_GS_ES_CFG[destination_file_merged_suffix]}.${count}"

	if [[ "${dry_run}" != "true" ]]; then
		touch "${src_file}" "${dest_file}"

		# Build associative array of dest values keyed by variable name
		declare -A _gs_es_dest_vals=()
		declare -A _gs_es_dest_emitted=()
		while IFS= read -r _line || [[ -n "${_line}" ]]; do
			# Only record KEY=value lines (skip blank lines and comments)
			if [[ "${_line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
				_gs_es_dest_vals["${BASH_REMATCH[1]}"]="${_line}"
			fi
		done < "${dest_file}"

		# Walk src top-to-bottom, preserving source order
		{
			while IFS= read -r _line || [[ -n "${_line}" ]]; do
				if [[ "${_line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
					local _key="${BASH_REMATCH[1]}"
					_gs_es_dest_emitted["${_key}"]=1
					if [[ -v _gs_es_dest_vals["${_key}"] ]]; then
						# Key exists in dest: emit the dest line (preserves dest value;
						# sync_values=true will overwrite via report.sh after this step)
						printf '%s\n' "${_gs_es_dest_vals[${_key}]}"
					else
						# New key from src: emit src line at this position
						printf '%s\n' "${_line}"
					fi
				else
					# Blank/comment line: emit verbatim (preserves @todo annotations)
					printf '%s\n' "${_line}"
				fi
			done < "${src_file}"

			# Append local-only dest keys (in dest but not in src) under a footer comment
			local _has_local_only=false
			while IFS= read -r _line || [[ -n "${_line}" ]]; do
				if [[ "${_line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
					local _dkey="${BASH_REMATCH[1]}"
					if [[ -z "${_gs_es_dest_emitted[${_dkey}]:-}" ]]; then
						if [[ "${_has_local_only}" = "false" ]]; then
							printf '\n# --- local-only keys (not present in .env) ---\n'
							_has_local_only=true
						fi
						printf '%s\n' "${_line}"
					fi
				fi
			done < "${dest_file}"
		} > "${merged_file}"

		# P6: merge three sed -i passes into one
		local _sed_args=()
		[[ "${_GS_ES_CFG[strip_comments]}" = "true" ]]         && _sed_args+=(-e '/^\s*#/d')
		[[ "${_GS_ES_CFG[remove_empty_lines]}" = "true" ]]     && _sed_args+=(-e '/^\s*$/d')
		[[ "${_GS_ES_CFG[remove_trailing_spaces]}" = "true" ]] && _sed_args+=(-e 's/[[:space:]]*$//')
		[[ ${#_sed_args[@]} -gt 0 ]] && sed -i "${_sed_args[@]}" "${merged_file}"
	fi

	# Show added entries if enabled
	[[ "true" = "${_GS_ES_CFG[show_added_entries]}" ]] &&
		gs_es_show_inconsistency \
			"${src_file}" \
			"${dest_file}" \
			"" \
			"add"

	# Overwrite destination with merged content (suppressed under dry-run)
	if [[ "${dry_run}" != "true" ]]; then
		mv "${merged_file}" "${dest_file}"
	fi

	# Show different/missing entries if enabled
	gs_es_show_differences \
		"${src_file}" \
		"${dest_file}" \
		"${count}"

	[[ "true" = "${_GS_ES_CFG[check_missing]}" ]] &&
		gs_es_check_missing_variables \
			"${src_file}" \
			"src.${count}" \
			"${_GS_ES_CFG[exclude_check_missing]}|${_GS_ES_CFG[exclude_local_pattern]}" \
			"false"
	[[ "true" = "${_GS_ES_CFG[check_missing]}" ]] &&
		gs_es_check_missing_variables \
			"${dest_file}" \
			"dest.${count}" \
			"${_GS_ES_CFG[exclude_check_missing]}" \
			"false"
	[[ "true" = "${_GS_ES_CFG[check_missing]}" ]] &&
		gs_es_check_missing_variables \
			"${dest_file}" \
			"dest.${count}" \
			"${_GS_ES_CFG[exclude_source_check_pattern]}" \
			"true"

	[[ "true" = "${_GS_ES_CFG[show_added_entries]}" ]] &&
		gs_es_show_inconsistency \
			"${dest_file}" \
			"${src_file}" \
			"${_GS_ES_CFG[exclude_local_pattern]}" \
			""

	[[ "true" = "${_GS_ES_CFG[cleanup_tmp]}" ]] &&
		rm -rf \
			"${tmp_file}"
}
