#!/bin/bash
# extract.sh — gs_es_search_and_extract + gs_es_detect_multiple_defaults

# Include guard
[[ -n "${_GS_ES_EXTRACT_SH_LOADED:-}" ]] && return 0
readonly _GS_ES_EXTRACT_SH_LOADED=1

# shellcheck source=./../config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/defaults.sh"

# ── gs_es_detect_multiple_defaults ───────────────────────────────────────────────
# Args: input_file  current_file
# Reads from _GS_ES_CFG: source_merged_file, exclude_implicit_empty,
#                        exclude_explicit_empty
gs_es_detect_multiple_defaults() {
	local input_file="${1}"
	local current_file="${2}"

	local input_file_merge
	input_file_merge="${input_file}.src.all.merged"

	> "${input_file_merge}"

	cat "${input_file}" >> "${input_file_merge}"

	# P4: single awk pass replaces per-key grep (eliminates ~N grep forks)
	awk -F'=' '
		NR==FNR { if ($1!="" && substr($1,1,1)!="#") keys[$1]=1; next }
		($1 in keys)
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
				unique_values[key] = unique_values[key] ";" value; # Append with a delimiter
			}
		}
	}
	END {
		for (key in unique_values) {
			split(unique_values[key], vals, ";");  # Split values into an array
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
	}' "${input_file_merge}.expanded")

	if [[ -n "${_GS_ES_CFG[exclude_multiple_values_pattern]}" && -n "${multiple_default_values}" ]]; then
		multiple_default_values=$(echo "${multiple_default_values}" | grep -vE "${_GS_ES_CFG[exclude_multiple_values_pattern]}")
	fi

	if [[ -n "${multiple_default_values}" ]]; then
		echo -e "\n ---- (gs_es_detect_multiple_defaults): Entries defined multiple times in ${current_file} with multiple values:\n${multiple_default_values}\n"
	fi

	rm -rf \
		"${input_file_merge}" \
		"${input_file_merge}.expanded"
}

# ── gs_es_search_and_extract ─────────────────────────────────────────────────────
# Args: current_file  count
# Reads from _GS_ES_CFG: scan_ignore_pattern, scan_exclude_pattern,
#                        debug, debug_show_extracted_files, include_docker_args,
#                        scan_var_prefix, scan_output_file,
#                        scan_delete_output, cleanup_tmp,
#                        source_merged_file, exclude_implicit_empty,
#                        exclude_explicit_empty
# Session temp dir: _GS_ES_SESSION_TMP (set by gs_es_main)
gs_es_search_and_extract() {
	local current_file="${1}"
	local count="${2}"

	# P8: pre-compiled ignore regex used with bash =~ (no subshell grep)
	local _ignore_re
	_ignore_re="$(printf '%s' "${_GS_ES_CFG[scan_ignore_pattern]}" | sed '/^\s*$/d' | paste -sd '|')"
	if [[ -n "${_ignore_re}" && "${current_file}" =~ ${_ignore_re} ]]; then
		if [[ "true" = "${_GS_ES_CFG[debug]}" ]]; then
			echo -e "\n ---- (gs_es_search_and_extract): Ignoring path: ${current_file}\n"
		fi
		return 0
	fi

	if [[ "true" = "${_GS_ES_CFG[debug]}" && "true" = "${_GS_ES_CFG[debug_show_extracted_files]}" ]]; then
		echo -e "\n ---- (gs_es_search_and_extract): Extracting env variables from ${current_file}\n"
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
		if [[ -n "${_GS_ES_CFG[scan_exclude_pattern]}" ]]; then
			grep -vE "${_GS_ES_CFG[scan_exclude_pattern]}"
		else
			cat
		fi | tee -a "${_out_file}" >/dev/null

	if [[ "true" = "${_GS_ES_CFG[debug]}" && "true" = "${_GS_ES_CFG[debug_show_extracted_files]}" ]]; then
		cat "${_out_file}"
		echo -e "\n"
	fi

	gs_es_detect_multiple_defaults "${_out_file}" "${current_file}"

	cat "${_out_file}" >> "${_GS_ES_CFG[scan_output_file]}"
	[[ "true" = "${_GS_ES_CFG[scan_delete_output]}" && "true" = "${_GS_ES_CFG[cleanup_tmp]}" ]] && rm -rf "${_out_file}"
}

# ── _gs_es_run_extraction ────────────────────────────────────────────────────────
# Parallel find-and-extract loop, then consolidate results.
_gs_es_run_extraction() {
	true > "${_GS_ES_CFG[scan_output_file]}"

	if [[ -f "${_GS_ES_CFG[scan_path]}" ]]; then
		gs_es_search_and_extract "${_GS_ES_CFG[scan_path]}" 0
	elif [[ -d "${_GS_ES_CFG[scan_path]}" ]]; then
		local count=0
		local -a pids=()

		while IFS= read -r _file; do
			((count++))
			gs_es_search_and_extract "${_file}" "${count}" &
			pids+=($!)
		done < <(find "${_GS_ES_CFG[scan_path]}" -type f)

		# Wait for all background jobs; collect exit codes
		local failed=0
		local pid
		for pid in "${pids[@]}"; do
			wait "${pid}" || ((failed++))
		done
		[[ "${failed}" -eq 0 ]] || { echo "gs_es_search_and_extract: ${failed} background job(s) failed" >&2; exit 1; }
	else
		echo -e "\n ---- (gs_es_main): ${_GS_ES_CFG[scan_path]} is neither a file nor a directory, exiting !\n\n" >&2
		exit 1
	fi

	# Merge all per-file outputs into the final output file (parallel jobs each
	# appended to their own extract.N file; consolidate now that all are done).
	# P9: sort -u deduplicates across multiple files
	LC_ALL=C sort -u "${_GS_ES_CFG[scan_output_file]}" \
		-o "${_GS_ES_CFG[scan_output_file]}" 2>/dev/null || true
}
