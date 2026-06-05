#!/bin/bash
# args.sh — CLI argument parser; populates _GS_ES_CFG from "$@"
#
# Exports:   _gs_es_parse_args
# Sources:   config/defaults.sh  reporting/help.sh
# Deps:      bash 4.3+, realpath
# Env:       _GS_ES_CFG (associative array, declared in defaults.sh)
#
# Parses every --flag=value pair onto _GS_ES_CFG, validates boolean values,
# then applies defaults for any key that was not set on the command line.
# Non-boolean defaults that depend on --dir are computed after --dir is
# resolved (dependent defaults section).

# Include guard
[[ -n "${_GS_ES_ARGS_SH_LOADED:-}" ]] && return 0
readonly _GS_ES_ARGS_SH_LOADED=1

# shellcheck source=./../config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/defaults.sh"
# shellcheck source=./../reporting/help.sh
source "$(dirname "${BASH_SOURCE[0]}")/../reporting/help.sh"

# _gs_es_parse_args — parse CLI flags and populate _GS_ES_CFG.
#
# Args:    "$@" — all CLI arguments
# Sets:    _GS_ES_CFG[*] — every supported flag key; unset keys receive defaults
# Prints:  error messages to stderr on invalid values
# Returns: 0 on success; exit 1 on invalid --backup-keep or unknown flag
# Side fx: calls _gs_es_show_help and exits 0 for --help;
#          prints version and exits 0 for --version;
#          sets reference=true for --reference[=SECTION]
_gs_es_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --debug=*)
        _GS_ES_CFG[debug]="${1#*=}"
        _GS_ES_CFG[debug]="${_GS_ES_CFG[debug],,}"
        ;;
      --debug-show-extracted-files=*)
        _GS_ES_CFG[debug_show_extracted_files]="${1#*=}"
        _GS_ES_CFG[debug_show_extracted_files]="${_GS_ES_CFG[debug_show_extracted_files],,}"
        ;;
      --strip-comments=*)
        _GS_ES_CFG[strip_comments]="${1#*=}"
        _GS_ES_CFG[strip_comments]="${_GS_ES_CFG[strip_comments],,}"
        ;;
      --remove-empty-lines=*)
        _GS_ES_CFG[remove_empty_lines]="${1#*=}"
        _GS_ES_CFG[remove_empty_lines]="${_GS_ES_CFG[remove_empty_lines],,}"
        ;;
      --remove-trailing-spaces=*)
        _GS_ES_CFG[remove_trailing_spaces]="${1#*=}"
        _GS_ES_CFG[remove_trailing_spaces]="${_GS_ES_CFG[remove_trailing_spaces],,}"
        ;;
      --show-added-entries=*)
        _GS_ES_CFG[show_added_entries]="${1#*=}"
        _GS_ES_CFG[show_added_entries]="${_GS_ES_CFG[show_added_entries],,}"
        ;;
      --show-different-entries=*)
        _GS_ES_CFG[show_different_entries]="${1#*=}"
        _GS_ES_CFG[show_different_entries]="${_GS_ES_CFG[show_different_entries],,}"
        ;;
      --scan-sources=*)
        _GS_ES_CFG[scan_sources]="${1#*=}"
        _GS_ES_CFG[scan_sources]="${_GS_ES_CFG[scan_sources],,}"
        ;;
      --scan-delete-output=*)
        _GS_ES_CFG[scan_delete_output]="${1#*=}"
        _GS_ES_CFG[scan_delete_output]="${_GS_ES_CFG[scan_delete_output],,}"
        ;;
      --check-missing=*)
        _GS_ES_CFG[check_missing]="${1#*=}"
        _GS_ES_CFG[check_missing]="${_GS_ES_CFG[check_missing],,}"
        ;;
      --cleanup-tmp=*)
        _GS_ES_CFG[cleanup_tmp]="${1#*=}"
        _GS_ES_CFG[cleanup_tmp]="${_GS_ES_CFG[cleanup_tmp],,}"
        ;;
      --include-docker-args=*)
        _GS_ES_CFG[include_docker_args]="${1#*=}"
        _GS_ES_CFG[include_docker_args]="${_GS_ES_CFG[include_docker_args],,}"
        ;;
      --dir=*) _GS_ES_CFG[dir]="${1#*=}" ;;
      --destination-file-tmp-suffix=*) _GS_ES_CFG[destination_file_tmp_suffix]="${1#*=}" ;;
      --destination-file-merged-suffix=*) _GS_ES_CFG[destination_file_merged_suffix]="${1#*=}" ;;
      --sync-values=*)
        _GS_ES_CFG[sync_values]="${1#*=}"
        _GS_ES_CFG[sync_values]="${_GS_ES_CFG[sync_values],,}"
        ;;
      --scan-var-prefix=*) _GS_ES_CFG[scan_var_prefix]="${1#*=}" ;;
      --diff-ignore-pattern=*) _GS_ES_CFG[diff_ignore_pattern]="${1#*=}" ;;
      --scan-var-ignore-pattern=*) _GS_ES_CFG[scan_var_ignore_pattern]="${1#*=}" ;;
      --reverse-check-ignore-pattern=*) _GS_ES_CFG[reverse_check_ignore_pattern]="${1#*=}" ;;
      --forward-check-ignore-pattern=*) _GS_ES_CFG[forward_check_ignore_pattern]="${1#*=}" ;;
      --scan-path=*) _GS_ES_CFG[scan_path]="${1#*=}" ;;
      --scan-ignore-pattern=*) _GS_ES_CFG[scan_ignore_pattern]="${1#*=}" ;;
      --source-files=*) _GS_ES_CFG[source_files]="${1#*=}" ;;
      --destination-files=*) _GS_ES_CFG[destination_files]="${1#*=}" ;;
      --scan-output-file=*) _GS_ES_CFG[scan_output_file]="${1#*=}" ;;
      --exclude-local-pattern=*) _GS_ES_CFG[exclude_local_pattern]="${1#*=}" ;;
      --source-merged-file=*) _GS_ES_CFG[source_merged_file]="${1#*=}" ;;
      --exclude-implicit-empty=*)
        _GS_ES_CFG[exclude_implicit_empty]="${1#*=}"
        _GS_ES_CFG[exclude_implicit_empty]="${_GS_ES_CFG[exclude_implicit_empty],,}"
        ;;
      --exclude-explicit-empty=*)
        _GS_ES_CFG[exclude_explicit_empty]="${1#*=}"
        _GS_ES_CFG[exclude_explicit_empty]="${_GS_ES_CFG[exclude_explicit_empty],,}"
        ;;
      --conflict-ignore-pattern=*) _GS_ES_CFG[conflict_ignore_pattern]="${1#*=}" ;;
      --quiet=*)
        _GS_ES_CFG[quiet]="${1#*=}"
        _GS_ES_CFG[quiet]="${_GS_ES_CFG[quiet],,}"
        ;;
      --profile=*)
        _GS_ES_CFG[profile]="${1#*=}"
        _GS_ES_CFG[profile]="${_GS_ES_CFG[profile],,}"
        ;;
      --dry-run) _GS_ES_CFG[dry_run]="true" ;;
      --yes)     _GS_ES_CFG[yes]="true" ;;
      --no-fail) _GS_ES_CFG[no_fail]="true" ;;
      --backup=*)
        _GS_ES_CFG[backup]="${1#*=}"
        _GS_ES_CFG[backup]="${_GS_ES_CFG[backup],,}"
        ;;
      --backup-purge=*)
        _GS_ES_CFG[backup_purge]="${1#*=}"
        _GS_ES_CFG[backup_purge]="${_GS_ES_CFG[backup_purge],,}"
        ;;
      --backup-keep=*)
        _GS_ES_CFG[backup_keep]="${1#*=}"
        if [[ ! "${_GS_ES_CFG[backup_keep]}" =~ ^[0-9]+$ ]]; then
          printf 'env-scan: --backup-keep requires a non-negative integer, got: %s\n' "${_GS_ES_CFG[backup_keep]}" >&2
          exit 1
        fi
        ;;
      --backup-suffix=*) _GS_ES_CFG[backup_suffix]="${1#*=}" ;;
      --prune-removed=*)
        _GS_ES_CFG[prune_removed]="${1#*=}"
        _GS_ES_CFG[prune_removed]="${_GS_ES_CFG[prune_removed],,}"
        ;;
      --orphan-ignore-pattern=*) _GS_ES_CFG[orphan_ignore_pattern]="${1#*=}" ;;
      --orphan-quiet=*)
        _GS_ES_CFG[orphan_quiet]="${1#*=}"
        _GS_ES_CFG[orphan_quiet]="${_GS_ES_CFG[orphan_quiet],,}"
        ;;
      --reference)
        _GS_ES_CFG[reference]="true"
        ;;
      --reference=*)
        _GS_ES_CFG[reference_section]="${1#*=}"
        _GS_ES_CFG[reference]="true"
        ;;
      --version)
        printf '%s\n' "${_GS_ES_VERSION}"
        exit 0
        ;;
      --help)
        _gs_es_show_help
        exit 0
        ;;
      *)
        printf '\n ---- Unknown option passed: '"'"'%s'"'"' \n\n' "${1}" >&2
        _gs_es_show_help
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
    [sync_values]=true
    [dry_run]=false
    [backup]=true
    [backup_purge]=false
    [prune_removed]=false
    [orphan_quiet]=false
    [no_fail]=false
    [yes]=false
  )
  local _key
  for _key in "${!_bool_defaults[@]}"; do
    if [[ -z "${_GS_ES_CFG[${_key}]+set}" ]]; then
      _GS_ES_CFG[${_key}]="${_bool_defaults[${_key}]}"
    elif [[ "true" != "${_GS_ES_CFG[${_key}]}" && "false" != "${_GS_ES_CFG[${_key}]}" ]]; then
      printf 'env-scan: invalid value for --%s: %s (expected true or false)\n' \
        "${_key//_/-}" "${_GS_ES_CFG[${_key}]}" >&2
      exit 1
    fi
  done

  # ── Apply non-boolean defaults ────────────────────────────────────────────
  # P11: replace 3-nested-subshell DIR computation with 1 subprocess
  local _script_real
  _script_real="$(realpath "${0}")"

  [[ -z "${_GS_ES_CFG[dir]+set}" ]] && _GS_ES_CFG[dir]="${_script_real%/bin/env-scan.sh}"
  [[ -z "${_GS_ES_CFG[destination_file_tmp_suffix]+set}" ]] && _GS_ES_CFG[destination_file_tmp_suffix]=".tmp"
  [[ -z "${_GS_ES_CFG[destination_file_merged_suffix]+set}" ]] && _GS_ES_CFG[destination_file_merged_suffix]=".merged"
  [[ -z "${_GS_ES_CFG[scan_var_prefix]+set}" ]] && _GS_ES_CFG[scan_var_prefix]="(GLOBAL_STACK_)"
  [[ -z "${_GS_ES_CFG[diff_ignore_pattern]+set}" ]] && _GS_ES_CFG[diff_ignore_pattern]="${_GS_ES_PATTERN_DIFF_IGNORE}"
  [[ -z "${_GS_ES_CFG[scan_var_ignore_pattern]+set}" ]] && _GS_ES_CFG[scan_var_ignore_pattern]="${_GS_ES_PATTERN_SCAN_VAR_IGNORE}"
  [[ -z "${_GS_ES_CFG[reverse_check_ignore_pattern]+set}" ]] && _GS_ES_CFG[reverse_check_ignore_pattern]="${_GS_ES_PATTERN_REVERSE_CHECK_IGNORE}"
  [[ -z "${_GS_ES_CFG[forward_check_ignore_pattern]+set}" ]] && _GS_ES_CFG[forward_check_ignore_pattern]="${_GS_ES_PATTERN_FORWARD_CHECK_IGNORE}"
  [[ -z "${_GS_ES_CFG[conflict_ignore_pattern]+set}" ]] && _GS_ES_CFG[conflict_ignore_pattern]="${_GS_ES_PATTERN_CONFLICT_IGNORE}"

  # ── Dependent defaults (require dir / scan_var_prefix to be set first) ───
  if [[ -z "${_GS_ES_CFG[scan_path]+set}" ]]; then
    _GS_ES_CFG[scan_path]="${_GS_ES_CFG[dir]}/docker"
  fi
  if [[ -z "${_GS_ES_CFG[scan_ignore_pattern]+set}" ]]; then
    _GS_ES_CFG[scan_ignore_pattern]="
^${_GS_ES_CFG[dir]}/docker/config/root/.bash_history$
^${_GS_ES_CFG[dir]}/docker/config/root/.zsh_history$
^${_GS_ES_CFG[dir]}/docker/storage.*
^${_GS_ES_CFG[dir]}/docker/registry.*
^${_GS_ES_CFG[dir]}/docker/logs.*
^${_GS_ES_CFG[dir]}/docker/data.*
"
  fi
  [[ -z "${_GS_ES_CFG[source_files]+set}" ]] && _GS_ES_CFG[source_files]="${_GS_ES_CFG[dir]}/.env"
  [[ -z "${_GS_ES_CFG[destination_files]+set}" ]] && _GS_ES_CFG[destination_files]="${_GS_ES_CFG[dir]}/.env.local"
  [[ -z "${_GS_ES_CFG[scan_output_file]+set}" ]] && _GS_ES_CFG[scan_output_file]="${_GS_ES_CFG[dir]}/.env.all.local"
  if [[ -z "${_GS_ES_CFG[exclude_local_pattern]+set}" ]]; then
    _GS_ES_CFG[exclude_local_pattern]="^${_GS_ES_CFG[scan_var_prefix]/\)/}LOCAL_)"
  fi
  [[ -z "${_GS_ES_CFG[source_merged_file]+set}" ]] && _GS_ES_CFG[source_merged_file]="${_GS_ES_CFG[dir]}/.env.src.all.merged"
  [[ -z "${_GS_ES_CFG[backup_keep]+set}" ]] && _GS_ES_CFG[backup_keep]="10"
  [[ -z "${_GS_ES_CFG[backup_suffix]+set}" ]] && _GS_ES_CFG[backup_suffix]=".bak"
  [[ -z "${_GS_ES_CFG[orphan_ignore_pattern]+set}" ]] && _GS_ES_CFG[orphan_ignore_pattern]="${_GS_ES_PATTERN_ORPHAN_IGNORE}"
  [[ -z "${_GS_ES_CFG[reference]+set}" ]] && _GS_ES_CFG[reference]="false"
  [[ -z "${_GS_ES_CFG[reference_section]+set}" ]] && _GS_ES_CFG[reference_section]="all"
  # Explicit return 0 — guards against bash set -e treating a false [[ ]] && pattern
  # on the last line of a function as a non-zero function exit (surfaced by Sprint H tests).
  return 0
}
