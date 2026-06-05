#!/bin/bash
# missing.sh — _gs_es_check_missing_variables: forward and reverse variable-presence checks
#
# Exports:   _gs_es_check_missing_variables
# Sources:   config/defaults.sh
# Deps:      bash 4.3+, cut, sort, comm, grep
# Env:       _GS_ES_CFG (scan_output_file, scan_path, debug, cleanup_tmp, quiet)
#            _GS_ES_SESSION_TMP (set by _gs_es_main; temp dir for per-run scratch files)
#
# Implements three directed checks (called from merge.sh):
#   Forward Check 1 (reverse_checking=false, target=.env):
#     Vars in scan output absent from source — new Docker usages not yet in .env.
#   Forward Check 2 (reverse_checking=false, target=.env.local):
#     Vars in scan output absent from destination — entries added to .env not yet
#     propagated to .env.local.
#   Reverse Check 3 (reverse_checking=true, target=.env.local):
#     Vars in destination absent from scan output — stale/orphaned entries in
#     .env.local with no corresponding Docker usage.
#
# The check direction is selected by the reverse_checking argument.

# Include guard
[[ -n "${_GS_ES_MISSING_SH_LOADED:-}" ]] && return 0
readonly _GS_ES_MISSING_SH_LOADED=1

# shellcheck source=./../config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/defaults.sh"

# _gs_es_check_missing_variables — report variables present in one set but absent from another.
#
# Args:    $1 target_file       — env file to check against (one side of the diff)
#          $2 txt_file_name     — name stem used for per-invocation temp files in _GS_ES_SESSION_TMP
#          $3 exclude_pattern   — ERE; matching variable names are suppressed from output
#          $4 reverse_checking  — "true"  → dest→scan direction (Check 3, stale-entry)
#                               — "false" → scan→env direction (Checks 1+2, new-usage)
# Reads:   _GS_ES_CFG[scan_output_file]  _GS_ES_CFG[scan_path]
#          _GS_ES_CFG[debug]  _GS_ES_CFG[cleanup_tmp]  _GS_ES_CFG[quiet]
#          _GS_ES_SESSION_TMP (global)
# Prints:  missing variable names to stdout; debug message when all present
# Returns: 0 always (informational — does not abort the run)
# Side fx: writes/reads two temp files in _GS_ES_SESSION_TMP; deletes them if
#          cleanup_tmp=true
_gs_es_check_missing_variables() {
	local target_file="${1}"
	local txt_file_name="${2}"
	local exclude_pattern="${3}"
	local reverse_checking="${4}"

	[[ "${_GS_ES_CFG[quiet]}" == "true" ]] && return 0

	local _extracted_vars_file="${_GS_ES_SESSION_TMP}/${txt_file_name}_extracted_vars.txt"
	local _vars_file="${_GS_ES_SESSION_TMP}/${txt_file_name}_vars.txt"

	if [[ -f "${_GS_ES_CFG[scan_output_file]}" ]]; then
		cut -d'=' -f1 "${_GS_ES_CFG[scan_output_file]}" | LC_ALL=C sort -u > "${_extracted_vars_file}"
	else
		> "${_extracted_vars_file}"
	fi
	cut -d'=' -f1 "${target_file}" | LC_ALL=C sort -u > "${_vars_file}"

	local missing_variables
	if [[ "true" = "${reverse_checking}" ]]; then
		missing_variables=$(LC_ALL=C comm -23 "${_vars_file}" "${_extracted_vars_file}" | { if [[ -n "${exclude_pattern}" ]]; then grep -vE "${exclude_pattern}" || true; else cat; fi; })
	else
		missing_variables=$(LC_ALL=C comm -23 "${_extracted_vars_file}" "${_vars_file}" | { if [[ -n "${exclude_pattern}" ]]; then grep -vE "${exclude_pattern}" || true; else cat; fi; })
	fi

	if [[ -n "${missing_variables}" ]]; then
		if [[ "true" = "${reverse_checking}" ]]; then
			printf '\n ---- (_gs_es_check_missing_variables: reverse=%s): Missing variables from %s in %s:\n%s\n\n' "${reverse_checking}" "${target_file}" "${_GS_ES_CFG[scan_path]}" "${missing_variables}"
		else
			printf '\n ---- (_gs_es_check_missing_variables: reverse=%s): Missing variables from %s in %s:\n%s\n\n' "${reverse_checking}" "${_GS_ES_CFG[scan_path]}" "${target_file}" "${missing_variables}"
		fi
	else
		if [[ "true" = "${_GS_ES_CFG[debug]}" ]]; then
			if [[ "true" = "${reverse_checking}" ]]; then
				printf '\n ---- (_gs_es_check_missing_variables: reverse=%s): All the environment variables present in %s are in %s\n\n' "${reverse_checking}" "${target_file}" "${_GS_ES_CFG[scan_path]}"
			else
				printf '\n ---- (_gs_es_check_missing_variables: reverse=%s): All the environment variables present in %s are in %s\n\n' "${reverse_checking}" "${_GS_ES_CFG[scan_path]}" "${target_file}"
			fi
		fi
	fi

	if [[ "true" = "${_GS_ES_CFG[cleanup_tmp]}" ]]; then
		rm -rf \
			"${_extracted_vars_file}" \
			"${_vars_file}"
	fi
}
