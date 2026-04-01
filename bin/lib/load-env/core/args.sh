#!/bin/bash
# args.sh — CLI argument parser; populates _GS_LE_CFG from "$@"

# Include guard
[[ -n "${_GS_LE_ARGS_SH_LOADED:-}" ]] && return 0
readonly _GS_LE_ARGS_SH_LOADED=1

# shellcheck source=./../config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/defaults.sh"
# shellcheck source=./../reporting/help.sh
source "$(dirname "${BASH_SOURCE[0]}")/../reporting/help.sh"

le_parse_args() {
	while [[ $# -gt 0 ]]; do
		case "${1}" in
		--debug=*)                        _GS_LE_CFG[debug]="${1#*=}";                        _GS_LE_CFG[debug]="${_GS_LE_CFG[debug],,}" ;;
		--debug-show-extracted-files=*)   _GS_LE_CFG[debug_show_extracted_files]="${1#*=}";   _GS_LE_CFG[debug_show_extracted_files]="${_GS_LE_CFG[debug_show_extracted_files],,}" ;;
		--strip-comments=*)               _GS_LE_CFG[strip_comments]="${1#*=}";               _GS_LE_CFG[strip_comments]="${_GS_LE_CFG[strip_comments],,}" ;;
		--remove-empty-lines=*)           _GS_LE_CFG[remove_empty_lines]="${1#*=}";           _GS_LE_CFG[remove_empty_lines]="${_GS_LE_CFG[remove_empty_lines],,}" ;;
		--remove-trailing-spaces=*)       _GS_LE_CFG[remove_trailing_spaces]="${1#*=}";       _GS_LE_CFG[remove_trailing_spaces]="${_GS_LE_CFG[remove_trailing_spaces],,}" ;;
		--show-added-entries=*)           _GS_LE_CFG[show_added_entries]="${1#*=}";           _GS_LE_CFG[show_added_entries]="${_GS_LE_CFG[show_added_entries],,}" ;;
		--show-different-entries=*)       _GS_LE_CFG[show_different_entries]="${1#*=}";       _GS_LE_CFG[show_different_entries]="${_GS_LE_CFG[show_different_entries],,}" ;;
		--scan-sources=*)                 _GS_LE_CFG[scan_sources]="${1#*=}";                 _GS_LE_CFG[scan_sources]="${_GS_LE_CFG[scan_sources],,}" ;;
		--scan-delete-output=*)           _GS_LE_CFG[scan_delete_output]="${1#*=}";           _GS_LE_CFG[scan_delete_output]="${_GS_LE_CFG[scan_delete_output],,}" ;;
		--check-missing=*)                _GS_LE_CFG[check_missing]="${1#*=}";                _GS_LE_CFG[check_missing]="${_GS_LE_CFG[check_missing],,}" ;;
		--cleanup-tmp=*)                  _GS_LE_CFG[cleanup_tmp]="${1#*=}";                  _GS_LE_CFG[cleanup_tmp]="${_GS_LE_CFG[cleanup_tmp],,}" ;;
		--include-docker-args=*)          _GS_LE_CFG[include_docker_args]="${1#*=}";          _GS_LE_CFG[include_docker_args]="${_GS_LE_CFG[include_docker_args],,}" ;;
		--dir=*)                          _GS_LE_CFG[dir]="${1#*=}" ;;
		--destination-file-tmp-suffix=*)  _GS_LE_CFG[destination_file_tmp_suffix]="${1#*=}" ;;
		--destination-file-merged-suffix=*) _GS_LE_CFG[destination_file_merged_suffix]="${1#*=}" ;;
		--sync-values=*)                  _GS_LE_CFG[sync_values]="${1#*=}";                  _GS_LE_CFG[sync_values]="${_GS_LE_CFG[sync_values],,}" ;;
		--scan-var-prefix=*)              _GS_LE_CFG[scan_var_prefix]="${1#*=}" ;;
		--exclude-different-pattern=*)    _GS_LE_CFG[exclude_different_pattern]="${1#*=}" ;;
		--scan-exclude-pattern=*)         _GS_LE_CFG[scan_exclude_pattern]="${1#*=}" ;;
		--exclude-source-check-pattern=*) _GS_LE_CFG[exclude_source_check_pattern]="${1#*=}" ;;
		--exclude-check-missing=*)        _GS_LE_CFG[exclude_check_missing]="${1#*=}" ;;
		--scan-path=*)                    _GS_LE_CFG[scan_path]="${1#*=}" ;;
		--scan-ignore-pattern=*)          _GS_LE_CFG[scan_ignore_pattern]="${1#*=}" ;;
		--source-files=*)                 _GS_LE_CFG[source_files]="${1#*=}" ;;
		--destination-files=*)            _GS_LE_CFG[destination_files]="${1#*=}" ;;
		--scan-output-file=*)             _GS_LE_CFG[scan_output_file]="${1#*=}" ;;
		--exclude-local-pattern=*)        _GS_LE_CFG[exclude_local_pattern]="${1#*=}" ;;
		--source-merged-file=*)           _GS_LE_CFG[source_merged_file]="${1#*=}" ;;
		--exclude-implicit-empty=*)       _GS_LE_CFG[exclude_implicit_empty]="${1#*=}";       _GS_LE_CFG[exclude_implicit_empty]="${_GS_LE_CFG[exclude_implicit_empty],,}" ;;
		--exclude-explicit-empty=*)       _GS_LE_CFG[exclude_explicit_empty]="${1#*=}";       _GS_LE_CFG[exclude_explicit_empty]="${_GS_LE_CFG[exclude_explicit_empty],,}" ;;
		--exclude-multiple-values-pattern=*) _GS_LE_CFG[exclude_multiple_values_pattern]="${1#*=}" ;;
		--quiet=*)                        _GS_LE_CFG[quiet]="${1#*=}";                        _GS_LE_CFG[quiet]="${_GS_LE_CFG[quiet],,}" ;;
		--profile=*)                      _GS_LE_CFG[profile]="${1#*=}";                      _GS_LE_CFG[profile]="${_GS_LE_CFG[profile],,}" ;;
		--help)
			le_show_help
			exit 1
			;;
		*)
			echo -e "\n ---- Unknown option passed: '${1}' \n" >&2
			le_show_help
			exit 1
			;;
		esac
		shift
	done

	# ── Apply boolean flag defaults ───────────────────────────────────────────
	local -A _bool_defaults=(
		[debug]=false
		[debug_show_extracted_files]=false
		[strip_comments]=true
		[remove_empty_lines]=true
		[remove_trailing_spaces]=true
		[show_added_entries]=true
		[show_different_entries]=true
		[scan_sources]=true
		[scan_delete_output]=true
		[check_missing]=true
		[cleanup_tmp]=true
		[include_docker_args]=true
		[exclude_implicit_empty]=true
		[exclude_explicit_empty]=true
		[quiet]=false
		[profile]=false
		[sync_values]=false
	)
	local _key
	for _key in "${!_bool_defaults[@]}"; do
		if [[ -z "${_GS_LE_CFG[${_key}]+set}" ]]; then
			_GS_LE_CFG[${_key}]="${_bool_defaults[${_key}]}"
		elif [[ "true" != "${_GS_LE_CFG[${_key}]}" && "false" != "${_GS_LE_CFG[${_key}]}" ]]; then
			_GS_LE_CFG[${_key}]="${_bool_defaults[${_key}]}"
		fi
	done

	# ── Apply non-boolean defaults ────────────────────────────────────────────
	# P11: replace 3-nested-subshell DIR computation with 1 subprocess
	local _script_real
	_script_real="$(realpath "${0}")"

	[[ -z "${_GS_LE_CFG[dir]+set}" ]]                          && _GS_LE_CFG[dir]="${_script_real%/bin/load-env.sh}"
	[[ -z "${_GS_LE_CFG[destination_file_tmp_suffix]+set}" ]]  && _GS_LE_CFG[destination_file_tmp_suffix]=".tmp"
	[[ -z "${_GS_LE_CFG[destination_file_merged_suffix]+set}" ]] && _GS_LE_CFG[destination_file_merged_suffix]=".merged"
	[[ -z "${_GS_LE_CFG[scan_var_prefix]+set}" ]]              && _GS_LE_CFG[scan_var_prefix]="(GLOBAL_STACK_)"
	[[ -z "${_GS_LE_CFG[exclude_different_pattern]+set}" ]]    && _GS_LE_CFG[exclude_different_pattern]="${_GS_LE_PATTERN_EXCLUDE_DIFFERENT}"
	[[ -z "${_GS_LE_CFG[scan_exclude_pattern]+set}" ]]         && _GS_LE_CFG[scan_exclude_pattern]="${_GS_LE_PATTERN_SCAN_EXCLUDE}"
	[[ -z "${_GS_LE_CFG[exclude_source_check_pattern]+set}" ]] && _GS_LE_CFG[exclude_source_check_pattern]="${_GS_LE_PATTERN_EXCLUDE_SOURCE_CHECK}"
	[[ -z "${_GS_LE_CFG[exclude_check_missing]+set}" ]]        && _GS_LE_CFG[exclude_check_missing]="${_GS_LE_PATTERN_EXCLUDE_CHECK_MISSING}"
	[[ -z "${_GS_LE_CFG[exclude_multiple_values_pattern]+set}" ]] && _GS_LE_CFG[exclude_multiple_values_pattern]="${_GS_LE_PATTERN_EXCLUDE_MULTIPLE_VALUES}"

	# ── Dependent defaults (require dir / scan_var_prefix to be set first) ───
	if [[ -z "${_GS_LE_CFG[scan_path]+set}" ]]; then
		_GS_LE_CFG[scan_path]="${_GS_LE_CFG[dir]}/docker"
	fi
	if [[ -z "${_GS_LE_CFG[scan_ignore_pattern]+set}" ]]; then
		_GS_LE_CFG[scan_ignore_pattern]="
^${_GS_LE_CFG[dir]}/docker/config/root/.bash_history$
^${_GS_LE_CFG[dir]}/docker/config/root/.zsh_history$
^${_GS_LE_CFG[dir]}/docker/storage.*
^${_GS_LE_CFG[dir]}/docker/registry.*
^${_GS_LE_CFG[dir]}/docker/logs.*
^${_GS_LE_CFG[dir]}/docker/data.*
"
	fi
	[[ -z "${_GS_LE_CFG[source_files]+set}" ]]               && _GS_LE_CFG[source_files]="${_GS_LE_CFG[dir]}/.env"
	[[ -z "${_GS_LE_CFG[destination_files]+set}" ]]          && _GS_LE_CFG[destination_files]="${_GS_LE_CFG[dir]}/.env.local"
	[[ -z "${_GS_LE_CFG[scan_output_file]+set}" ]]           && _GS_LE_CFG[scan_output_file]="${_GS_LE_CFG[dir]}/.env.all.local"
	if [[ -z "${_GS_LE_CFG[exclude_local_pattern]+set}" ]]; then
		_GS_LE_CFG[exclude_local_pattern]="^${_GS_LE_CFG[scan_var_prefix]/\)/}LOCAL_)"
	fi
	[[ -z "${_GS_LE_CFG[source_merged_file]+set}" ]]         && _GS_LE_CFG[source_merged_file]="${_GS_LE_CFG[dir]}/.env.src.all.merged"
}
