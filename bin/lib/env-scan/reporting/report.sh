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
	added_entries=$(awk -F "=" -v exclude_pattern="${exclude_pattern}" 'NR == FNR { original[$1]; next } !($1 in original) && $1 !~ /^#|^\s*$/ && (exclude_pattern == "" || !($1 ~ exclude_pattern)) { print $1 "=" $2 }' "${dest_file}" "${src_file}")
	if [[ -n "${added_entries}" ]]; then
		if [[ "add" = "${operation}" ]]; then
			echo -e "\n ---- (gs_es_show_inconsistency): New entries added to ${dest_file} from ${src_file}:\n${added_entries}\n"
		else
			echo -e "\n ---- (gs_es_show_inconsistency): Entries missing in ${dest_file} from ${src_file}:\n${added_entries}\n"
		fi
	else
		if [[ "true" = "${_GS_ES_CFG[debug]}" ]]; then
			echo -e "\n ---- (gs_es_show_inconsistency): All ${src_file} variables are present in ${dest_file}\n"
		fi
	fi
}

# ── gs_es_show_differences ───────────────────────────────────────────────────────
# Args: src_file  dest_file  count
# Reads from _GS_ES_CFG: exclude_different_pattern, show_different_entries,
#                        debug, sync_values, quiet
gs_es_show_differences() {
	local src_file="${1}"
	local dest_file="${2}"
	local count="${3}"

	[[ "${_GS_ES_CFG[quiet]}" == "true" ]] && return 0

	local different_entries
	different_entries=$(awk -F "=" -v exclude_pattern="${_GS_ES_CFG[exclude_different_pattern]}" 'NR == FNR { source[$1]=$2; next } ($1 in source) && ($2 != source[$1]) && (exclude_pattern == "" || !($1 ~ exclude_pattern)) { print $1 "=" $2 "\n(--------- is : \"" source[$1] "\" in source)\n" }' "${src_file}" "${dest_file}")
	if [[ "true" = "${_GS_ES_CFG[show_different_entries]}" ]]; then
		if [[ -n "${different_entries}" ]]; then
			echo -e "\n ---- (gs_es_show_differences): Entries in ${dest_file} differ from ${src_file}:\n${different_entries}\n"
		else
			if [[ "true" = "${_GS_ES_CFG[debug]}" ]]; then
				echo -e "\n ---- (gs_es_show_differences): ${dest_file} values are in sync with source file ${src_file}\n"
			fi
		fi
	fi

	if [[ -n "${different_entries}" && "true" = "${_GS_ES_CFG[sync_values]}" && "${_GS_ES_CFG[dry_run]:-false}" != "true" ]]; then
		awk -F "=" -v exclude_pattern="${_GS_ES_CFG[exclude_different_pattern]}" 'NR == FNR { source[$1] = $2; next } (exclude_pattern != "" && $1 ~ exclude_pattern) { print $0; next } ($1 in source) && ($2 != source[$1]) { print $1 "=" source[$1]; next } { print $0; next }' "${src_file}" "${dest_file}" >"${dest_file}.updated.tmp.${count}" && mv "${dest_file}.updated.tmp.${count}" "${dest_file}"
		if [[ "true" = "${_GS_ES_CFG[debug]}" ]]; then
			echo -e "\n ---- (gs_es_show_differences): ${dest_file} values updated to match with values from source ${src_file}\n"
		fi
	fi
}
