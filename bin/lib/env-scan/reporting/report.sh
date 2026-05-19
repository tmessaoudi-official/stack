#!/bin/bash
# report.sh — gs_es_show_inconsistency + gs_es_show_differences

# Include guard
[[ -n "${_GS_ES_REPORT_SH_LOADED:-}" ]] && return 0
readonly _GS_ES_REPORT_SH_LOADED=1

# shellcheck source=./../config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/defaults.sh"

# ── gs_es_show_inconsistency ─────────────────────────────────────────────────────
# Args: src_file  dest_file  exclude_pattern  operation
# Reads from _GS_ES_CFG: debug, quiet
gs_es_show_inconsistency() {
	local src_file="${1}"
	local dest_file="${2}"
	local exclude_pattern="${3}"
	local operation="${4}"

	[[ "${_GS_ES_CFG[quiet]}" == "true" ]] && return 0

	local added_entries
	added_entries=$(awk -v exclude_pattern="${exclude_pattern}" 'NR == FNR { key=$0; sub(/=.*/,"",key); original[key]; next } { key=$0; sub(/=.*/,"",key) } !(key in original) && key !~ /^#|^\s*$/ && (exclude_pattern == "" || !(key ~ exclude_pattern)) { print $0 }' "${dest_file}" "${src_file}")
	if [[ -n "${added_entries}" ]]; then
		if [[ "add" = "${operation}" ]]; then
			printf '\n ---- (gs_es_show_inconsistency): New entries added to %s from %s:\n%s\n\n' "${dest_file}" "${src_file}" "${added_entries}"
		else
			printf '\n ---- (gs_es_show_inconsistency): Entries missing in %s from %s:\n%s\n\n' "${dest_file}" "${src_file}" "${added_entries}"
		fi
	else
		if [[ "true" = "${_GS_ES_CFG[debug]}" ]]; then
			printf '\n ---- (gs_es_show_inconsistency): All %s variables are present in %s\n\n' "${src_file}" "${dest_file}"
		fi
	fi
}

# ── gs_es_show_differences ───────────────────────────────────────────────────────
# Args: src_file  dest_file  count
# Reads from _GS_ES_CFG: diff_ignore_pattern, show_different_entries,
#                        debug, sync_values, quiet
gs_es_show_differences() {
	local src_file="${1}"
	local dest_file="${2}"
	local count="${3}"

	[[ "${_GS_ES_CFG[quiet]}" == "true" ]] && return 0

	local different_entries
	different_entries=$(awk -v exclude_pattern="${_GS_ES_CFG[diff_ignore_pattern]}" '
		{
			key=$0; sub(/=.*/,"",key)
			val=substr($0,length(key)+2)
			# Normalize trailing whitespace for comparison (env files may have it)
			nval=val; gsub(/[[:space:]]+$/, "", nval)
		}
		NR == FNR { source[key]=nval; next }
		(key in source) && (nval != source[key]) && (exclude_pattern == "" || !(key ~ exclude_pattern)) {
			print key "=" val "\n(--------- is : \"" source[key] "\" in source)\n"
		}' "${src_file}" "${dest_file}")
	if [[ "true" = "${_GS_ES_CFG[show_different_entries]}" ]]; then
		if [[ -n "${different_entries}" ]]; then
			printf '\n ---- (gs_es_show_differences): Entries in %s differ from %s:\n%s\n\n' "${dest_file}" "${src_file}" "${different_entries}"
		else
			if [[ "true" = "${_GS_ES_CFG[debug]}" ]]; then
				printf '\n ---- (gs_es_show_differences): %s values are in sync with source file %s\n\n' "${dest_file}" "${src_file}"
			fi
		fi
	fi

	if [[ -n "${different_entries}" && "true" = "${_GS_ES_CFG[sync_values]}" && "${_GS_ES_CFG[dry_run]:-false}" != "true" ]]; then
		awk -v exclude_pattern="${_GS_ES_CFG[diff_ignore_pattern]}" '
			{
				key=$0; sub(/=.*/,"",key)
				val=substr($0,length(key)+2)
				nval=val; gsub(/[[:space:]]+$/, "", nval)
			}
			NR == FNR { source[key]=nval; next }
			(exclude_pattern != "" && key ~ exclude_pattern) { print $0; next }
			(key in source) && (nval != source[key]) { print key "=" source[key]; next }
			{ print $0; next }' "${src_file}" "${dest_file}" >"${dest_file}.updated.tmp.${count}" && mv "${dest_file}.updated.tmp.${count}" "${dest_file}"
		if [[ "true" = "${_GS_ES_CFG[debug]}" ]]; then
			printf '\n ---- (gs_es_show_differences): %s values updated to match with values from source %s\n\n' "${dest_file}" "${src_file}"
		fi
	fi
}
