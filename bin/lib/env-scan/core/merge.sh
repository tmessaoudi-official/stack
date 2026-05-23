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
#                        reverse_check_ignore_pattern, forward_check_ignore_pattern,
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
	local _line

	local merged_file
	merged_file="${dest_file}${_GS_ES_CFG[destination_file_merged_suffix]}.${count}"

	# GAP-3: Same-path guard — src and dest must not resolve to the same file.
	# realpath resolves symlinks; fall back to raw path if realpath is unavailable.
	local _src_real _dest_real
	_src_real="$(realpath -- "${src_file}" 2>/dev/null || printf '%s' "${src_file}")"
	_dest_real="$(realpath -- "${dest_file}" 2>/dev/null || printf '%s' "${dest_file}")"
	if [[ "${_src_real}" == "${_dest_real}" ]]; then
		printf 'env-scan: source and destination resolve to the same file: %s\n' "${_src_real}" >&2
		return 1
	fi

	if [[ "${dry_run}" != "true" ]]; then
		# A6: Guard source file — must exist and be non-empty before proceeding
		if [[ ! -f "${src_file}" ]] || [[ ! -s "${src_file}" ]]; then
			printf 'env-scan: source file not found or empty: %s\n' "${src_file}" >&2
			return 1
		fi
		if [[ ! -f "${dest_file}" ]]; then
			printf 'env-scan: creating new destination file: %s\n' "${dest_file}" >&2
			touch "${dest_file}"
		fi

		# GAP-2: Comments-only source guard — if src has no active KEY=value lines
		# (contains only comments, blanks, or is structurally empty after scanning),
		# skip silently rather than overwriting dest with a comment-only file.
		if ! grep -m1 -qE '^[A-Za-z_][A-Za-z0-9_]*=' "${src_file}" 2>/dev/null; then
			printf 'env-scan: source has no active variables after stripping (comments only) — skipping: %s\n' "${src_file}" >&2
			return 0
		fi

		# Build associative array of dest values keyed by variable name
		# (local -A: function-scoped; no bleed-through on repeated calls)
		local -A _gs_es_dest_vals=()
		local -A _gs_es_dest_emitted=()
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

			# B1: Append local-only dest keys (in dest but not in src) under a footer comment.
			# With --prune-removed=true, these orphaned keys are dropped with a warning.
			local _has_local_only=false
			local _prune_removed="${_GS_ES_CFG[prune_removed]:-false}"
			while IFS= read -r _line || [[ -n "${_line}" ]]; do
				if [[ "${_line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
					local _dkey="${BASH_REMATCH[1]}"
					if [[ -z "${_gs_es_dest_emitted[${_dkey}]:-}" ]]; then
						if [[ "${_GS_ES_CFG[orphan_quiet]:-false}" != "true" ]]; then
							local _orphan_exclude="${_GS_ES_CFG[orphan_ignore_pattern]:-}"
							if [[ -z "${_orphan_exclude}" || ! "${_dkey}" =~ ${_orphan_exclude} ]]; then
								printf 'env-scan: local-only var %s not in source (orphaned)\n' "${_dkey}" >&2
							fi
						fi
						if [[ "${_prune_removed}" == "true" ]]; then
							# Skip — effectively removing this key from .env.local
							continue
						fi
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

	# FORWARD Check 1 (scan → .env): vars found in scan output absent from source.
	# Suggests new GLOBAL_STACK_* usages in Docker files not yet declared in .env.
	[[ "true" = "${_GS_ES_CFG[check_missing]}" ]] &&
		gs_es_check_missing_variables \
			"${src_file}" \
			"src.${count}" \
			"${_GS_ES_CFG[forward_check_ignore_pattern]}|${_GS_ES_CFG[exclude_local_pattern]}" \
			"false"
	# FORWARD Check 2 (scan → .env.local): vars found in scan output absent from destination.
	# Suggests entries in .env not yet propagated to .env.local.
	[[ "true" = "${_GS_ES_CFG[check_missing]}" ]] &&
		gs_es_check_missing_variables \
			"${dest_file}" \
			"dest.${count}" \
			"${_GS_ES_CFG[forward_check_ignore_pattern]}" \
			"false"
	# REVERSE Check 3 (.env.local → scan): vars in destination absent from scan output.
	# Suggests stale/orphaned entries in .env.local with no corresponding Docker usage.
	[[ "true" = "${_GS_ES_CFG[check_missing]}" ]] &&
		gs_es_check_missing_variables \
			"${dest_file}" \
			"dest.${count}" \
			"${_GS_ES_CFG[reverse_check_ignore_pattern]}" \
			"true"

	[[ "true" = "${_GS_ES_CFG[show_added_entries]}" ]] &&
		gs_es_show_inconsistency \
			"${dest_file}" \
			"${src_file}" \
			"${_GS_ES_CFG[exclude_local_pattern]}" \
			""

	# Explicit return 0 — guards against bash set -e treating a false [[ ]] && pattern
	# on the last line of a function as a non-zero function exit (same class as args.sh P1 fix).
	return 0
}
