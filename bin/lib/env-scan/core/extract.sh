#!/bin/bash
# extract.sh — variable extraction from Docker sources and multi-default conflict detection
#
# Exports:   gs_es_search_and_extract  gs_es_detect_multiple_defaults  _gs_es_run_extraction
# Sources:   config/defaults.sh
# Deps:      bash 4.3+, grep, awk, sed, find, sort, envsubst
# Env:       _GS_ES_CFG (scan_ignore_pattern, scan_var_ignore_pattern, debug,
#                        debug_show_extracted_files, include_docker_args, scan_var_prefix,
#                        scan_output_file, scan_delete_output, cleanup_tmp,
#                        source_merged_file, exclude_implicit_empty, exclude_explicit_empty,
#                        conflict_ignore_pattern, scan_path)
#            _GS_ES_SESSION_TMP (set by gs_es_main; temp dir for per-run extract.N files)
#
# gs_es_search_and_extract — extract all GLOBAL_STACK_* variable usages from one file.
#   12 source forms are matched: ARG, ENV, shell export, docker-compose list, YAML map,
#   shell reference (${VAR}), Caddyfile ({env.VAR}), PHP getenv(), PHP $_ENV[],
#   JS/TS process.env, Python os.environ.get(), Python os.environ[].
#   Output is normalised to KEY=value form; |implicit_empty| / |explicit_empty|
#   sentinels represent absent or shell-default values.
#
# gs_es_detect_multiple_defaults — report variables with conflicting values across sources.
#   Cross-checks scan output against source files via awk; prints a warning for each
#   variable that appears with two or more distinct non-empty, non-sentinel values.
#
# _gs_es_run_extraction — parallel extraction driver.
#   Forks gs_es_search_and_extract as background jobs per file; waits for all to
#   complete; consolidates per-file extract.N temp files into scan_output_file;
#   deduplicates with sort -u.

# Include guard
[[ -n "${_GS_ES_EXTRACT_SH_LOADED:-}" ]] && return 0
readonly _GS_ES_EXTRACT_SH_LOADED=1

# shellcheck source=./../config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/defaults.sh"

# gs_es_detect_multiple_defaults — report variables with conflicting default values.
#
# Args:    $1 input_file   — per-file scan output (extract.N from gs_es_search_and_extract)
# Args:    $2 current_file — source path being checked (used in diagnostic output only)
# Reads:   _GS_ES_CFG[source_merged_file]  _GS_ES_CFG[exclude_implicit_empty]
#          _GS_ES_CFG[exclude_explicit_empty]  _GS_ES_CFG[conflict_ignore_pattern]
# Prints:  "(gs_es_detect_multiple_defaults): Entries defined multiple times..." to stdout
# Returns: 0 always (informational — does not abort the run)
# Side fx: creates and deletes input_file.src.all.merged and *.expanded temp files;
#          vars with ${...} in their .env value are skipped (matches propagate.sh guard);
#          self-referencing values (VAR=${VAR}, VAR=${VAR:-x}) are excluded from comparison
gs_es_detect_multiple_defaults() {
	local input_file="${1}"
	local current_file="${2}"

	[[ -f "${input_file}" ]] || return 0

	local input_file_merge
	input_file_merge="${input_file}.src.all.merged"

	> "${input_file_merge}"

	cat "${input_file}" >> "${input_file_merge}"

	# P4: single awk pass replaces per-key grep (eliminates ~N grep forks)
	# Skip source lines whose value contains ${ — they depend on shell expansion
	# and cannot be compared literally (mirrors the guard in propagate.sh line 64).
	awk -F'=' '
		NR==FNR { if ($1!="" && substr($1,1,1)!="#") keys[$1]=1; next }
		($1 in keys) && (index(substr($0, length($1)+2), "${") == 0)
	' "${input_file}" "${_GS_ES_CFG[source_merged_file]}" >> "${input_file_merge}"

	envsubst < "${input_file_merge}" > "${input_file_merge}.expanded"

	local multiple_default_values
	multiple_default_values=$(awk -F '=' -v exclude_implicit_empty="${_GS_ES_CFG[exclude_implicit_empty]}" -v exclude_explicit_empty="${_GS_ES_CFG[exclude_explicit_empty]}" '
	{
		key = $1;
		value = substr($0, length($1) + 2);  # Full value, preserves any = in the value

		# Check if we have an entry for this key
		if (!(key in unique_values)) {
			unique_values[key] = "";    # Initialize if not already present
		}

		useValue = "true";

		if (exclude_implicit_empty == "true" && value == "|implicit_empty|") {
			useValue = "false";
		}
		if (exclude_explicit_empty == "true" && value == "|explicit_empty|") {
			useValue = "false";
		}
		# Skip self-referencing values: VAR=${VAR}, VAR=${VAR:-default}, VAR=${VAR:=default}
		# These are pass-through / default patterns, not genuine distinct values.
		if (value ~ ("^\\${" key "([}]|:-|:=)")) {
			useValue = "false";
		}

		# Exact-match dedup via 2D seen array (index() was a substring check — wrong)
		if (!((key SUBSEP value) in seen) && value != "" && useValue == "true") {
			seen[key, value] = 1;
			if (unique_values[key] == "") {
				unique_values[key] = value; # First unique value
			} else {
				unique_values[key] = unique_values[key] "\001" value; # Append with SOH delimiter (safe — not present in env values)
			}
		}
	}
	END {
		for (key in unique_values) {
			split(unique_values[key], vals, "\001");  # Split on SOH delimiter
			if (length(vals) > 1) {                 # Check if there are multiple values
				printf "%s has values: ", key;
				for (i in vals) {
					printf "'"'"'%s'"'"' ", vals[i];
				}
				print "";
			} else if (length(vals) == 1) {
				# Handle the case with a single value
				# printf "%s has a single value: '"'"'%s'"'"'\n", key, vals[1];
			}
		}
	}' "${input_file_merge}.expanded" | LC_ALL=C sort)

	if [[ -n "${_GS_ES_CFG[conflict_ignore_pattern]}" && -n "${multiple_default_values}" ]]; then
		multiple_default_values=$(echo "${multiple_default_values}" | grep -vE "${_GS_ES_CFG[conflict_ignore_pattern]}" || true)
	fi

	if [[ -n "${multiple_default_values}" ]]; then
		printf '\n ---- (gs_es_detect_multiple_defaults): Entries defined multiple times in %s with multiple values:\n%s\n\n' "${current_file}" "${multiple_default_values}"
	fi

	rm -rf \
		"${input_file_merge}" \
		"${input_file_merge}.expanded"
}

# gs_es_search_and_extract — extract all matching variable usages from one file.
#
# Args:    $1 current_file — file to scan (any file type; polyglot extraction)
#          $2 count        — unique index for this invocation (temp file name: extract.<count>)
# Reads:   _GS_ES_CFG[scan_ignore_pattern]  _GS_ES_CFG[scan_var_ignore_pattern]
#          _GS_ES_CFG[debug]  _GS_ES_CFG[debug_show_extracted_files]
#          _GS_ES_CFG[include_docker_args]  _GS_ES_CFG[scan_var_prefix]
#          _GS_ES_CFG[scan_delete_output]  _GS_ES_CFG[cleanup_tmp]
#          _GS_ES_SESSION_TMP (global)
# Prints:  debug output to stdout when debug=true and debug_show_extracted_files=true
# Returns: 0 always (grep failures are suppressed with || true)
# Side fx: writes extract.<count> to _GS_ES_SESSION_TMP;
#          calls gs_es_detect_multiple_defaults on the per-file output;
#          early-returns (no write) when current_file matches scan_ignore_pattern
gs_es_search_and_extract() {
	local current_file="${1}"
	local count="${2}"

	# P8: pre-compiled ignore regex used with bash =~ (no subshell grep)
	local _ignore_re
	_ignore_re="$(printf '%s' "${_GS_ES_CFG[scan_ignore_pattern]}" | sed '/^\s*$/d' | paste -sd '|')"
	if [[ -n "${_ignore_re}" && "${current_file}" =~ ${_ignore_re} ]]; then
		if [[ "true" = "${_GS_ES_CFG[debug]}" ]]; then
			printf '\n ---- (gs_es_search_and_extract): Ignoring path: %s\n\n' "${current_file}"
		fi
		return 0
	fi

	if [[ "true" = "${_GS_ES_CFG[debug]}" && "true" = "${_GS_ES_CFG[debug_show_extracted_files]}" ]]; then
		printf '\n ---- (gs_es_search_and_extract): Extracting env variables from %s\n\n' "${current_file}"
	fi

	# Per-file output goes into the session temp dir to avoid collisions
	local _out_file="${_GS_ES_SESSION_TMP}/extract.${count}"

	# Build two extraction regexes covering all env-var source forms.
	#
	# _pat1 — assignment forms (whole-line matches; greedy =.* consumes the RHS)
	#  #   Source form                      Example(s)
	#  ─   ──────────────────────────────   ─────────────────────────────────────────
	#  1   Dockerfile ARG  (opt.)           ARG GLOBAL_STACK_FOO=default
	#  2   Dockerfile ENV  (first line)     ENV GLOBAL_STACK_FOO=bar
	#  3   Plain assignment / export        GLOBAL_STACK_FOO=bar  /  export KEY=bar
	#       ↳ multi-line ENV continuation   [spaces]GLOBAL_STACK_VERSION="${...}" \
	#  4   docker-compose list              - GLOBAL_STACK_FOO=bar  /  - KEY
	#  5   YAML map                         GLOBAL_STACK_FOO: bar
	#
	# _pat2 — reference forms (token-level; run on the FULL file so ${VAR}
	#         references embedded in RHS values of _pat1 lines are also captured)
	#  6   Shell reference                  ${GLOBAL_STACK_FOO:-default}  /  $KEY
	#  7   Caddyfile                        {env.GLOBAL_STACK_FOO}
	#  8   PHP getenv()                     getenv('GLOBAL_STACK_FOO')
	#  9   PHP $_ENV                        $_ENV['GLOBAL_STACK_FOO']
	# 10   JS / TS                          process.env.GLOBAL_STACK_FOO
	# 11   Python os.environ.get()          os.environ.get('GLOBAL_STACK_FOO')
	# 12   Python os.environ[]              os.environ['GLOBAL_STACK_FOO']
	local _pref="${_GS_ES_CFG[scan_var_prefix]}"

	# Pass 1: assignment / definition forms (whole-line, greedy)
	local _pat1=""
	[[ "true" = "${_GS_ES_CFG[include_docker_args]}" ]] && \
		_pat1+="(^ARG[[:space:]]+${_pref}[A-Za-z0-9_]+(=[^[:space:]]*)?)|"
	_pat1+="(^ENV[[:space:]]+${_pref}[A-Za-z0-9_]+[ =].*)|"
	_pat1+="(^[[:space:]]*(export[[:space:]]+)?${_pref}[A-Za-z0-9_]+=.*)|"
	_pat1+="(^[[:space:]]*-[[:space:]]+${_pref}[A-Za-z0-9_]+(=.*)?)|"
	_pat1+="(^[[:space:]]*${_pref}[A-Za-z0-9_]+:[[:space:]].*)"

	# Pass 2: reference / usage forms (token-level, scans every line including RHS)
	# _dlr holds a literal $ so "\\${_dlr}" produces \$ in the regex string
	# (bash "\$" collapses to $, the EOL anchor — not a literal dollar sign).
	local _dlr='$'
	local _pat2=""
	_pat2+="\\${_dlr}\\{?${_pref}[A-Za-z0-9_]+(\\:(-|=)[^}]*)?\\}?|"
	_pat2+="\\{env\\.${_pref}[A-Za-z0-9_]+\\}|"
	_pat2+="getenv\\(['\"]${_pref}[A-Za-z0-9_]+['\"]|"
	_pat2+="\\${_dlr}_ENV\\[['\"]${_pref}[A-Za-z0-9_]+['\"]|"
	_pat2+="process\\.env\\.${_pref}[A-Za-z0-9_]+|"
	_pat2+="os\\.environ\\.get\\(['\"]${_pref}[A-Za-z0-9_]+|"
	_pat2+="os\\.environ\\[['\"]${_pref}[A-Za-z0-9_]+"

	{ grep -oE "${_pat1}" "${current_file}" 2>/dev/null || true
	  grep -oE "${_pat2}" "${current_file}" 2>/dev/null || true; } |
		awk '
		{
			# Remember origin: shell refs ($VAR / ${VAR}) need :- / := handling;
			# plain KEY=value lines must NOT have gsub run on their values.
			is_shell_ref    = ($0 ~ /^\$[{A-Za-z]/)
			is_caddyfile_ref = ($0 ~ /^\{env\./)
			is_lang_ref     = ($0 ~ /getenv\(/ || $0 ~ /\$_ENV\[/ || $0 ~ /os\.environ/)

			# ── 1. Strip source-form prefixes ─────────────────────────────
			sub(/^[[:space:]]+/, "")               # leading whitespace
			sub(/^-[[:space:]]+/, "")              # docker-compose list marker
			sub(/^ARG[[:space:]]+/, "")            # Dockerfile ARG
			if (sub(/^ENV[[:space:]]+/, "")) {     # Dockerfile ENV
				# Space form "ENV KEY VALUE" → "KEY=VALUE"
				if ($0 !~ /=/) sub(/[[:space:]]+/, "=")
			}
			sub(/^export[[:space:]]+/, "")         # shell export
			sub(/^\{env\./, "")                    # Caddyfile {env.KEY} — before generic { strip
			sub(/^\$/, ""); sub(/^\{/, "")         # shell $VAR / ${VAR} — remove leading $ and {
			# Only strip trailing } for reference forms; assignment values may end with }
			if (is_shell_ref || is_caddyfile_ref) sub(/\}$/, "")
			sub(/^getenv\(['\''"]/, "")            # PHP getenv()
			sub(/^\$_ENV\[['\''"]/, "")            # PHP $_ENV[]
			sub(/^process\.env\./, "")             # JS/TS process.env
			sub(/^os\.environ\.get\(['\''"]/, "")  # Python os.environ.get()
			sub(/^os\.environ\[['\''"]/, "")       # Python os.environ[]
			if (is_shell_ref || is_caddyfile_ref || is_lang_ref) sub(/['\''"\]]+$/, "")  # trailing quote/bracket from language patterns

			# ── 2. Shell default operators (:- and :=) ────────────────────
			# Guarded by is_shell_ref: plain KEY=value lines already have = and
			# must not have URL/value colons corrupted by gsub.
			if (is_shell_ref) {
				if      (sub(/:-$/, ""))  { $0 = $0 "=|explicit_empty|" }
				else if (sub(/:=$/, ""))  { $0 = $0 "=|explicit_empty|" }
				else { gsub(/:-/, "="); gsub(/:=/, "=") }
			}

			# ── 3. YAML map form: "KEY: value" → "KEY=value" ──────────────
			# Runs after :- / := so URL colons (foo://bar) are not affected —
			# sub() only replaces the first ": " which is right after the key.
			if (match($0, /^[A-Za-z0-9_]+:[[:space:]]/)) sub(/:[[:space:]]+/, "=")

			# ── 4. Trailing cleanup ────────────────────────────────────────
			sub(/[[:space:]]*\\$/, "")  # backslash-continuation marker at EOL
			sub(/[[:space:]]+$/, "")    # trailing whitespace

			# ── 5. Unquote value if entirely single- or double-quoted ──────
			# KEY="value" → KEY=value  |  KEY='\''value'\'' → KEY=value
			n = index($0, "=")
			if (n > 0) {
				val = substr($0, n + 1)
				q   = substr(val, 1, 1)
				if (length(val) >= 2 && (q == "\"" || q == "'\''") &&
						substr(val, length(val), 1) == q) {
					$0 = substr($0, 1, n) substr(val, 2, length(val) - 2)
				}
			}

			# ── 6. Normalise to KEY=VALUE form ─────────────────────────────
			if ($0 !~ /=/)  { $0 = $0 "=" }   # bare key → KEY=
			sub(/=$/, "=|implicit_empty|")      # KEY= → KEY=|implicit_empty|
			print
		}' |
		if [[ -n "${_GS_ES_CFG[scan_var_ignore_pattern]}" ]]; then
			grep -vE "${_GS_ES_CFG[scan_var_ignore_pattern]}" || true
		else
			cat
		fi | tee -a "${_out_file}" >/dev/null

	if [[ "true" = "${_GS_ES_CFG[debug]}" && "true" = "${_GS_ES_CFG[debug_show_extracted_files]}" ]]; then
		cat "${_out_file}"
		printf '\n\n'
	fi

	gs_es_detect_multiple_defaults "${_out_file}" "${current_file}"
	# I1: Per-file output stays in extract.N — consolidated sequentially by
	# _gs_es_run_extraction after all background jobs complete (race fix).
}

# _gs_es_run_extraction — parallel extraction driver and result consolidator.
#
# Args:    none (reads _GS_ES_CFG[scan_path] for the root path)
# Reads:   _GS_ES_CFG[scan_path]  _GS_ES_CFG[scan_output_file]
#          _GS_ES_CFG[scan_delete_output]  _GS_ES_CFG[cleanup_tmp]
#          _GS_ES_SESSION_TMP (global)
# Prints:  error to stderr if any background job fails
# Returns: 0 on success; 1 if scan_path is neither a file nor a directory, or
#          if any background extraction job exits non-zero
# Side fx: forks one gs_es_search_and_extract background job per file under scan_path;
#          waits for all jobs and aggregates exit codes;
#          sequentially consolidates extract.N temp files into scan_output_file;
#          deduplicates with sort -u -o in place (I1 race-condition fix)
_gs_es_run_extraction() {
	true > "${_GS_ES_CFG[scan_output_file]}"

	# I1: count declared here (outside the if/elif) so the consolidation loop
	# below covers both the single-file path (count=0 → extract.0) and the
	# directory path (count=1..N from background jobs).
	local count=0

	if [[ -f "${_GS_ES_CFG[scan_path]}" ]]; then
		gs_es_search_and_extract "${_GS_ES_CFG[scan_path]}" 0
	elif [[ -d "${_GS_ES_CFG[scan_path]}" ]]; then
		local _file
		local -a pids=()

		while IFS= read -r _file; do
			(( ++count ))
			gs_es_search_and_extract "${_file}" "${count}" &
			pids+=($!)
		done < <(find "${_GS_ES_CFG[scan_path]}" -type f)

		# Wait for all background jobs; collect exit codes
		local failed=0
		local pid
		for pid in "${pids[@]}"; do
			wait "${pid}" || (( ++failed ))
		done
		[[ "${failed}" -eq 0 ]] || { printf 'gs_es_search_and_extract: %d background job(s) failed\n' "${failed}" >&2; return 1; }
	else
		printf '\n ---- (gs_es_main): %s is neither a file nor a directory, exiting !\n\n\n' "${_GS_ES_CFG[scan_path]}" >&2
		return 1
	fi

	# I1: Sequential consolidation — collect each per-file extract.N into the
	# final output file now that all background jobs have completed.
	# This replaces the old concurrent cat >> approach (race fix).
	# P9: sort -u deduplicates across multiple files
	local _ci
	for (( _ci = 0; _ci <= count; _ci++ )); do
		local _cf="${_GS_ES_SESSION_TMP}/extract.${_ci}"
		[[ -f "${_cf}" ]] && cat "${_cf}" >> "${_GS_ES_CFG[scan_output_file]}"
		[[ "true" = "${_GS_ES_CFG[scan_delete_output]}" && "true" = "${_GS_ES_CFG[cleanup_tmp]}" ]] \
			&& rm -rf "${_cf}"
	done
	# GNU sort supports -u -o with same input/output file; POSIX does not guarantee this.
	# 2>/dev/null: suppress "unrecognized option" on non-GNU sort.
	# || true: empty file causes sort to exit 1; treat as no-op.
	LC_ALL=C sort -u "${_GS_ES_CFG[scan_output_file]}" \
		-o "${_GS_ES_CFG[scan_output_file]}" 2>/dev/null || true
}
