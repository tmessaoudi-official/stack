#!/bin/bash
# missing.sh — le_check_missing_variables

# Include guard
[[ -n "${_LE_MISSING_SH_LOADED:-}" ]] && return 0
readonly _LE_MISSING_SH_LOADED=1

# shellcheck source=./config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# ── le_check_missing_variables ────────────────────────────────────────────────
# Args: target_file  txt_file_name  exclude_pattern  reverse_checking
# Reads from _LE_CFG: extract_all_env_output_file, search_path, debug,
#                     cleanup_tmp, quiet
# Session temp dir: _LE_SESSION_TMP (set by le_main)
le_check_missing_variables() {
	local target_file="${1}"
	local txt_file_name="${2}"
	local exclude_pattern="${3}"
	local reverse_checking="${4}"

	[[ "${_LE_CFG[quiet]}" == "true" ]] && return 0

	local _extracted_vars_file="${_LE_SESSION_TMP}/${txt_file_name}_extracted_vars.txt"
	local _vars_file="${_LE_SESSION_TMP}/${txt_file_name}_vars.txt"

	cut -d'=' -f1 "${_LE_CFG[extract_all_env_output_file]}" | LC_ALL=C sort -u > "${_extracted_vars_file}"
	cut -d'=' -f1 "${target_file}" | LC_ALL=C sort -u > "${_vars_file}"

	local missing_variables
	if [[ "true" = "${reverse_checking}" ]]; then
		missing_variables=$(LC_ALL=C comm -23 "${_vars_file}" "${_extracted_vars_file}" | if [[ -n "${exclude_pattern}" ]]; then grep -vE "${exclude_pattern}"; else cat; fi)
	else
		missing_variables=$(LC_ALL=C comm -23 "${_extracted_vars_file}" "${_vars_file}" | if [[ -n "${exclude_pattern}" ]]; then grep -vE "${exclude_pattern}"; else cat; fi)
	fi

	if [[ -n "${missing_variables}" ]]; then
		if [[ "true" = "${reverse_checking}" ]]; then
			echo -e "\n ---- (le_check_missing_variables: reverse=${reverse_checking}): Missing variables from ${target_file} in ${_LE_CFG[search_path]}:\n${missing_variables}\n"
		else
			echo -e "\n ---- (le_check_missing_variables: reverse=${reverse_checking}): Missing variables from ${_LE_CFG[search_path]} in ${target_file}:\n${missing_variables}\n"
		fi
	else
		if [[ "true" = "${_LE_CFG[debug]}" ]]; then
			if [[ "true" = "${reverse_checking}" ]]; then
				echo -e "\n ---- (le_check_missing_variables: reverse=${reverse_checking}): All the environment variables present in ${target_file} are in ${_LE_CFG[search_path]}\n"
			else
				echo -e "\n ---- (le_check_missing_variables: reverse=${reverse_checking}): All the environment variables present in ${_LE_CFG[search_path]} are in ${target_file}\n"
			fi
		fi
	fi

	if [[ "true" = "${_LE_CFG[cleanup_tmp]}" ]]; then
		rm -rf \
			"${_extracted_vars_file}" \
			"${_vars_file}"
	fi
}
