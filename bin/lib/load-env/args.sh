#!/bin/bash
# args.sh — CLI argument parser; populates _LE_CFG from "$@"

# Include guard
[[ -n "${_LE_ARGS_SH_LOADED:-}" ]] && return 0
readonly _LE_ARGS_SH_LOADED=1

# shellcheck source=./config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
# shellcheck source=./help.sh
source "$(dirname "${BASH_SOURCE[0]}")/help.sh"

le_parse_args() {
	while [[ $# -gt 0 ]]; do
		case "${1}" in
		--debug=*)                        _LE_CFG[debug]="${1#*=}";                        _LE_CFG[debug]="${_LE_CFG[debug],,}" ;;
		--debug-show-extracted-files=*)   _LE_CFG[debug_show_extracted_files]="${1#*=}";   _LE_CFG[debug_show_extracted_files]="${_LE_CFG[debug_show_extracted_files],,}" ;;
		--remove-dash=*)                  _LE_CFG[remove_dash]="${1#*=}";                  _LE_CFG[remove_dash]="${_LE_CFG[remove_dash],,}" ;;
		--remove-empty-lines=*)           _LE_CFG[remove_empty_lines]="${1#*=}";           _LE_CFG[remove_empty_lines]="${_LE_CFG[remove_empty_lines],,}" ;;
		--remove-trailing-spaces=*)       _LE_CFG[remove_trailing_spaces]="${1#*=}";       _LE_CFG[remove_trailing_spaces]="${_LE_CFG[remove_trailing_spaces],,}" ;;
		--show-added-entries=*)           _LE_CFG[show_added_entries]="${1#*=}";           _LE_CFG[show_added_entries]="${_LE_CFG[show_added_entries],,}" ;;
		--show-different-entries=*)       _LE_CFG[show_different_entries]="${1#*=}";       _LE_CFG[show_different_entries]="${_LE_CFG[show_different_entries],,}" ;;
		--extract-all-env=*)              _LE_CFG[extract_all_env]="${1#*=}";              _LE_CFG[extract_all_env]="${_LE_CFG[extract_all_env],,}" ;;
		--extract-all-env-delete-output=*) _LE_CFG[extract_all_env_delete_output]="${1#*=}"; _LE_CFG[extract_all_env_delete_output]="${_LE_CFG[extract_all_env_delete_output],,}" ;;
		--check-missing=*)                _LE_CFG[check_missing]="${1#*=}";                _LE_CFG[check_missing]="${_LE_CFG[check_missing],,}" ;;
		--cleanup-tmp=*)                  _LE_CFG[cleanup_tmp]="${1#*=}";                  _LE_CFG[cleanup_tmp]="${_LE_CFG[cleanup_tmp],,}" ;;
		--include-docker-args=*)          _LE_CFG[include_docker_args]="${1#*=}";          _LE_CFG[include_docker_args]="${_LE_CFG[include_docker_args],,}" ;;
		--dir=*)                          _LE_CFG[dir]="${1#*=}" ;;
		--destination-file-tmp-suffix=*)  _LE_CFG[destination_file_tmp_suffix]="${1#*=}" ;;
		--destination-file-merged-suffix=*) _LE_CFG[destination_file_merged_suffix]="${1#*=}" ;;
		--update-differences=*)           _LE_CFG[update_differences]="${1#*=}" ;;
		--extract-all-prefix=*)           _LE_CFG[extract_all_prefix]="${1#*=}" ;;
		--exclude-different-pattern=*)    _LE_CFG[exclude_different_pattern]="${1#*=}" ;;
		--extract-all-exclude-pattern=*)  _LE_CFG[extract_all_exclude_pattern]="${1#*=}" ;;
		--exclude-reverse-check-missing=*) _LE_CFG[exclude_reverse_check_missing]="${1#*=}" ;;
		--exclude-check-missing=*)        _LE_CFG[exclude_check_missing]="${1#*=}" ;;
		--search-path=*)                  _LE_CFG[search_path]="${1#*=}" ;;
		--search-path-ignore-pattern=*)   _LE_CFG[search_path_ignore_pattern]="${1#*=}" ;;
		--source-files=*)                 _LE_CFG[source_files]="${1#*=}" ;;
		--destination-files=*)            _LE_CFG[destination_files]="${1#*=}" ;;
		--extract-all-env-output-file=*)  _LE_CFG[extract_all_env_output_file]="${1#*=}" ;;
		--exclude-local-pattern=*)        _LE_CFG[exclude_local_pattern]="${1#*=}" ;;
		--all-src-env-merged-name=*)      _LE_CFG[all_src_env_merged_name]="${1#*=}" ;;
		--exclude-implicit-empty=*)       _LE_CFG[exclude_implicit_empty]="${1#*=}";       _LE_CFG[exclude_implicit_empty]="${_LE_CFG[exclude_implicit_empty],,}" ;;
		--exclude-explicit-empty=*)       _LE_CFG[exclude_explicit_empty]="${1#*=}";       _LE_CFG[exclude_explicit_empty]="${_LE_CFG[exclude_explicit_empty],,}" ;;
		--exclude-multiple-values-pattern=*) _LE_CFG[exclude_multiple_values_pattern]="${1#*=}" ;;
		--quiet=*)                        _LE_CFG[quiet]="${1#*=}";                        _LE_CFG[quiet]="${_LE_CFG[quiet],,}" ;;
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
		[remove_dash]=true
		[remove_empty_lines]=true
		[remove_trailing_spaces]=true
		[show_added_entries]=true
		[show_different_entries]=true
		[extract_all_env]=true
		[extract_all_env_delete_output]=true
		[check_missing]=true
		[cleanup_tmp]=true
		[include_docker_args]=true
		[exclude_implicit_empty]=true
		[exclude_explicit_empty]=true
		[quiet]=false
	)
	local _key
	for _key in "${!_bool_defaults[@]}"; do
		if [[ -z "${_LE_CFG[${_key}]+set}" ]]; then
			_LE_CFG[${_key}]="${_bool_defaults[${_key}]}"
		elif [[ "true" != "${_LE_CFG[${_key}]}" && "false" != "${_LE_CFG[${_key}]}" ]]; then
			_LE_CFG[${_key}]="${_bool_defaults[${_key}]}"
		fi
	done

	# ── Apply non-boolean defaults ────────────────────────────────────────────
	# P11: replace 3-nested-subshell DIR computation with 1 subprocess
	local _script_real
	_script_real="$(realpath "${0}")"

	[[ -z "${_LE_CFG[dir]+set}" ]]                          && _LE_CFG[dir]="${_script_real%/bin/load-env.sh}"
	[[ -z "${_LE_CFG[destination_file_tmp_suffix]+set}" ]]  && _LE_CFG[destination_file_tmp_suffix]=".tmp"
	[[ -z "${_LE_CFG[destination_file_merged_suffix]+set}" ]] && _LE_CFG[destination_file_merged_suffix]=".merged"
	[[ -z "${_LE_CFG[update_differences]+set}" ]]           && _LE_CFG[update_differences]=""
	[[ -z "${_LE_CFG[extract_all_prefix]+set}" ]]           && _LE_CFG[extract_all_prefix]="(GLOBAL_STACK_)"
	[[ -z "${_LE_CFG[exclude_different_pattern]+set}" ]]    && _LE_CFG[exclude_different_pattern]="${_LE_PATTERN_EXCLUDE_DIFFERENT}"
	[[ -z "${_LE_CFG[extract_all_exclude_pattern]+set}" ]]  && _LE_CFG[extract_all_exclude_pattern]="${_LE_PATTERN_EXTRACT_ALL_EXCLUDE}"
	[[ -z "${_LE_CFG[exclude_reverse_check_missing]+set}" ]] && _LE_CFG[exclude_reverse_check_missing]="${_LE_PATTERN_EXCLUDE_REVERSE_CHECK_MISSING}"
	[[ -z "${_LE_CFG[exclude_check_missing]+set}" ]]        && _LE_CFG[exclude_check_missing]="${_LE_PATTERN_EXCLUDE_CHECK_MISSING}"
	[[ -z "${_LE_CFG[exclude_multiple_values_pattern]+set}" ]] && _LE_CFG[exclude_multiple_values_pattern]="${_LE_PATTERN_EXCLUDE_MULTIPLE_VALUES}"

	# ── Dependent defaults (require dir / extract_all_prefix to be set first) ─
	if [[ -z "${_LE_CFG[search_path]+set}" ]]; then
		_LE_CFG[search_path]="${_LE_CFG[dir]}/docker"
	fi
	if [[ -z "${_LE_CFG[search_path_ignore_pattern]+set}" ]]; then
		_LE_CFG[search_path_ignore_pattern]="
^${_LE_CFG[dir]}/docker/config/root/.bash_history$
^${_LE_CFG[dir]}/docker/config/root/.zsh_history$
^${_LE_CFG[dir]}/docker/storage.*
^${_LE_CFG[dir]}/docker/registry.*
^${_LE_CFG[dir]}/docker/logs.*
^${_LE_CFG[dir]}/docker/data.*
"
	fi
	[[ -z "${_LE_CFG[source_files]+set}" ]]               && _LE_CFG[source_files]="${_LE_CFG[dir]}/.env"
	[[ -z "${_LE_CFG[destination_files]+set}" ]]          && _LE_CFG[destination_files]="${_LE_CFG[dir]}/.env.local"
	[[ -z "${_LE_CFG[extract_all_env_output_file]+set}" ]] && _LE_CFG[extract_all_env_output_file]="${_LE_CFG[dir]}/.env.all.local"
	if [[ -z "${_LE_CFG[exclude_local_pattern]+set}" ]]; then
		_LE_CFG[exclude_local_pattern]="^${_LE_CFG[extract_all_prefix]/\)/}LOCAL_)"
	fi
	[[ -z "${_LE_CFG[all_src_env_merged_name]+set}" ]]    && _LE_CFG[all_src_env_merged_name]="${_LE_CFG[dir]}/.env.src.all.merged"
}
