#!/bin/bash

global_stack_load_env_show_help() {
	cat << EOF
Usage: load-env.sh [OPTIONS]

Options:
  --debug=<value>                            Enable debug mode (default: false)
  --debug-show-extracted-files=<value>       Show files from which environment variables were extracted (default: false)
  --remove-dash=<value>                      Remove commented lines from output (default: true)
  --remove-empty-lines=<value>               Remove empty lines from output (default: true)
  --remove-trailing-spaces=<value>           Remove trailing spaces from lines in output (default: true)
  --show-added-entries=<value>               Show newly added entries from source to destination files (default: true)
  --show-different-entries=<value>           Show entries with differing values between source and destination files (default: true)
  --extract-all-env=<value>                  Extract all environment variables from files (default: true)
  --extract-all-env-delete-output=<value>    Delete temporary extracted environment variable files (default: true)
  --check-missing=<value>                    Check for missing variables in the destination files (default: true)
  --cleanup-tmp=<value>                      Clean up temporary files after processing (default: true)
  --include-docker-args=<value>              Include Docker ARGs when extracting environment variables (default: true)
  --dir=<value>                              Set the working directory (default: inferred from script location removing /bin)
  --destination-file-tmp-suffix=<value>      Temporary file suffix for destination files (default: .tmp)
  --destination-file-merged-suffix=<value>   Merged file suffix for destination files (default: .merged)
  --update-differences=<value>               Update destination files to match source values (default: not set)
  --extract-all-prefix=<value>               Prefix pattern for environment variable extraction (default: "(GLOBAL_STACK_)")
  --exclude-different-pattern=<value>        Pattern to exclude from difference detection (default: predefined regex)
  --extract-all-exclude-pattern=<value>      Pattern to exclude from variable extraction (default: predefined regex)
  --exclude-reverse-check-missing=<value>    Pattern to exclude from reverse missing check (default: predefined regex)
  --exclude-check-missing=<value>            Pattern to exclude from missing checks (default: predefined regex)
  --search-path=<value>                      Search path for environment variable files (default: "<working-dir>/docker")
  --search-path-ignore-pattern=<value>       Ignore specific paths during search (default: predefined paths)
  --source-files=<value>                     Source environment files for processing (default: "<working-dir>/.env")
  --destination-files=<value>                Destination environment files for processing (default: "<working-dir>/.env.local")
  --extract-all-env-output-file=<value>      File to store all extracted environment variables (default: "<working-dir>/.env.all.local")
  --exclude-local-pattern=<value>            Exclude local patterns during extraction (default: derived from extract-all-prefix)
  --all-src-env-merged-name=<value>          Path of the file where all source env files will be merged (default: <working-dir>/.env.src.all.merged)
  --exclude-implicit-empty=<value>           Exclude implicit empty from multiple default values (default: true)
  --exclude-explicit-empty=<value>           Exclude explicit empty from multiple default values (default: true)

Examples:
  ./load-env.sh --debug=true --dir=/stack/.env --show-added-entries=false
  ./load-env.sh --source-files="file1.env file2.env" --destination-files="dest1.env dest2.env"
  ./load-env.sh --search-path=/config --update-differences=update_differences

Description:
  This script processes environment variable files, performing operations like:
  - Extracting variables from source files.
  - Syncing and merging with destination files.
  - Cleaning up formats (removing empty lines, trailing spaces, etc.).
  - Detecting differences or missing variables between source and destination.
  - Optionally updating destination files to match source files.
EOF
}

global_stack_load_env_detect_multiple_default_different_values_for_key() {
	local INPUT_FILE
	INPUT_FILE="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local CURRENT_FILE
	CURRENT_FILE="$(echo "${2}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local ALL_SRC_ENV_MERGED_NAME
	ALL_SRC_ENV_MERGED_NAME="$(echo "${3}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local EXCLUDE_IMPLICIT_EMPTY
	EXCLUDE_IMPLICIT_EMPTY="$(echo "${4,,}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local EXCLUDE_EXPLICIT_EMPTY
	EXCLUDE_EXPLICIT_EMPTY="$(echo "${5,,}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"

	local INPUT_FILE_MERGE_ALL_SRC_ENV
	INPUT_FILE_MERGE_ALL_SRC_ENV="${INPUT_FILE}.src.all.merged"

	> "${INPUT_FILE_MERGE_ALL_SRC_ENV}"

	cat "${INPUT_FILE}" >> "${INPUT_FILE_MERGE_ALL_SRC_ENV}"

	while IFS='=' read -r key value; do
		if [[ -n "${key}" && "${key}" != \#* ]]; then
			grep "^$key=" "${ALL_SRC_ENV_MERGED_NAME}" >> "${INPUT_FILE_MERGE_ALL_SRC_ENV}"
		fi
	done < "${INPUT_FILE}"

	envsubst < "${INPUT_FILE_MERGE_ALL_SRC_ENV}" > "${INPUT_FILE_MERGE_ALL_SRC_ENV}.expanded"

	local MULTIPLE_DEFAULT_VALUES
	MULTIPLE_DEFAULT_VALUES=$(awk -F '=' -v exclude_implicit_empty="${EXCLUDE_IMPLICIT_EMPTY}" -v exclude_explicit_empty="${EXCLUDE_EXPLICIT_EMPTY}" '
	{
		key = $1;
		value = $2;

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

		# Use a temporary variable to ensure we only add unique values
		if (!index(unique_values[key], value) && value != "" && useValue == "true") {
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
					printf "'%s' ", vals[i];
				}
				print "";
			} else if (length(vals) == 1) {
				# Handle the case with a single value
				# printf "%s has a single value: '%s'\n", key, vals[1];
			}
		}
	}' "${INPUT_FILE_MERGE_ALL_SRC_ENV}.expanded")

	if [[ -n "${MULTIPLE_DEFAULT_VALUES}" ]]; then
		echo -e "\n ---- (global_stack_load_env_detect_multiple_default_different_values_for_key): Entries defined multiple times in ${CURRENT_FILE} with multiple values:\n${MULTIPLE_DEFAULT_VALUES}\n"
	fi

	rm -rf \
		"${INPUT_FILE_MERGE_ALL_SRC_ENV}" \
		"${INPUT_FILE_MERGE_ALL_SRC_ENV}.expanded"
}

# Functions for various processing steps
global_stack_load_env_search_and_extract() {
	local CURRENT_FILE
	CURRENT_FILE="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local SEARCH_IGNORE
	SEARCH_IGNORE="$(echo "${2}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local EXCLUDE_PATTERN
	EXCLUDE_PATTERN="$(echo "${3}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local COUNT
	COUNT="$(echo "${4}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local DEBUG
	DEBUG="$(echo "${5}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local DEBUG_SHOW_EXTRACTED_FILES
	DEBUG_SHOW_EXTRACTED_FILES="$(echo "${6}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local INCLUDE_DOCKER_ARGS
	INCLUDE_DOCKER_ARGS="$(echo "${7}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local EXTRACT_ALL_PREFIX
	EXTRACT_ALL_PREFIX="$(echo "${8}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local EXTRACT_ALL_ENV_OUTPUT_FILE
	EXTRACT_ALL_ENV_OUTPUT_FILE="$(echo "${9}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local EXTRACT_ALL_ENV_DELETE_OUTPUT
	EXTRACT_ALL_ENV_DELETE_OUTPUT="$(echo "${10}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local CLEANUP_TMP
	CLEANUP_TMP="$(echo "${11}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local ALL_SRC_ENV_MERGED_NAME
	ALL_SRC_ENV_MERGED_NAME="$(echo "${12}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local EXCLUDE_IMPLICIT_EMPTY
	EXCLUDE_IMPLICIT_EMPTY="$(echo "${13,,}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local EXCLUDE_EXPLICIT_EMPTY
	EXCLUDE_EXPLICIT_EMPTY="$(echo "${14,,}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"

	if grep -qE "$(echo "${SEARCH_IGNORE}" | sed '/^\s*$/d')" <<< "${CURRENT_FILE}"; then
		if [[ "true" = "${DEBUG}" ]]; then
			echo -e "\n ---- (global_stack_load_env_search_and_extract): Ignoring path: ${CURRENT_FILE}\n"
		fi

		return 0
	fi

	if [[ "true" = "${DEBUG}" && "true" = "${DEBUG_SHOW_EXTRACTED_FILES}" ]]; then
		echo -e "\n ---- (global_stack_load_env_search_and_extract): Extracting env variables from ${CURRENT_FILE}\n"
	fi
	grep -oE "$(if [[ "true" = "${INCLUDE_DOCKER_ARGS}" ]]; then echo "(^ARG ([^=]+)(=?)(.*))|"; fi)(\\$\\{?${EXTRACT_ALL_PREFIX}[A-Za-z0-9_]+(\\:(-|=)[^\\}]*)?\\}?)" "${CURRENT_FILE}" |
		sed -E 's/^ARG //;' |
		sed -E 's/^\$//; s/^\{//; s/\}$//; s/:-$/=|explicit_empty|/g; s/:=$/=|explicit_empty|/g; s/:-/=/g; s/:=/=/g;' |
		if [[ -n "${EXCLUDE_PATTERN}" ]]; then
			grep -vE "${EXCLUDE_PATTERN}"
		else
			cat
		fi |
		sed -E 's/=(.*)/=\1/; s/^([A-Za-z0-9_]+)=?$/\1=/' |
		sed -E 's/=$/=|implicit_empty|/;' |
		tee -a "${EXTRACT_ALL_ENV_OUTPUT_FILE}${COUNT}" >"$([[ "true" = "${DEBUG}" && "true" = "${DEBUG_SHOW_EXTRACTED_FILES}" ]] && echo /dev/stdout || echo /dev/null)"
	if [[ "true" = "${DEBUG}" && "true" = "${DEBUG_SHOW_EXTRACTED_FILES}" ]]; then
		echo -e "\n"
	fi
	global_stack_load_env_detect_multiple_default_different_values_for_key \
		--input-file="${EXTRACT_ALL_ENV_OUTPUT_FILE}${COUNT}" \
		--current-file="${CURRENT_FILE}" \
		--all-src-env-merged-name="${ALL_SRC_ENV_MERGED_NAME}" \
		--exclude-implicit-empty="${EXCLUDE_IMPLICIT_EMPTY}" \
		--exclude-explicit-empty="${EXCLUDE_EXPLICIT_EMPTY}"
	cat "${EXTRACT_ALL_ENV_OUTPUT_FILE}${COUNT}" >>"${EXTRACT_ALL_ENV_OUTPUT_FILE}"
	[[ "true" = "${EXTRACT_ALL_ENV_DELETE_OUTPUT}" && "true" = "${CLEANUP_TMP}" ]] && rm -rf "${EXTRACT_ALL_ENV_OUTPUT_FILE}${COUNT}"
}

global_stack_load_env_process_file() {
	local SRC_FILE
	SRC_FILE="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local DEST_FILE
	DEST_FILE="$(echo "${2}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local COUNT
	COUNT="$(echo "${3}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local DESTINATION_FILE_TMP_SUFFIX
	DESTINATION_FILE_TMP_SUFFIX="$(echo "${4}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local DESTINATION_FILE_MERGED_SUFFIX
	DESTINATION_FILE_MERGED_SUFFIX="$(echo "${5}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local REMOVE_DASH
	REMOVE_DASH="$(echo "${6}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local REMOVE_EMPTY_LINES
	REMOVE_EMPTY_LINES="$(echo "${7}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local REMOVE_TRAILING_SPACES
	REMOVE_TRAILING_SPACES="$(echo "${8}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local SHOW_ADDED_ENTRIES
	SHOW_ADDED_ENTRIES="$(echo "${9}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local EXCLUDE_DIFFERENT_PATTERN
	EXCLUDE_DIFFERENT_PATTERN="$(echo "${10}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local CHECK_MISSING
	CHECK_MISSING="$(echo "${11}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local EXCLUDE_LOCAL_PATTERN
	EXCLUDE_LOCAL_PATTERN="$(echo "${12}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local EXCLUDE_REVERSE_CHECK_MISSING
	EXCLUDE_REVERSE_CHECK_MISSING="$(echo "${13}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local EXCLUDE_CHECK_MISSING
	EXCLUDE_CHECK_MISSING="$(echo "${14}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local CLEANUP_TMP
	CLEANUP_TMP="$(echo "${15}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local DEBUG
	DEBUG="$(echo "${16}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local SHOW_DIFFERENT_ENTRIES
	SHOW_DIFFERENT_ENTRIES="$(echo "${17}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local UPDATE_DIFFERENCES
	UPDATE_DIFFERENCES="$(echo "${18}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local EXTRACT_ALL_ENV_OUTPUT_FILE
	EXTRACT_ALL_ENV_OUTPUT_FILE="$(echo "${19}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local DIR
	DIR="$(echo "${20}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local SEARCH_PATH
	SEARCH_PATH="$(echo "${21}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"

	local TMP_FILE
	TMP_FILE="${DEST_FILE}${DESTINATION_FILE_TMP_SUFFIX}.${COUNT}"
	local MERGED_FILE
	MERGED_FILE="${DEST_FILE}${DESTINATION_FILE_MERGED_SUFFIX}.${COUNT}"

	touch "${SRC_FILE}" "${DEST_FILE}"
	cp "${DEST_FILE}" "${TMP_FILE}"
	sed -i -e "\$a\\" "${TMP_FILE}"
	cat "${SRC_FILE}" >>"${TMP_FILE}"

	awk -F "=" '!seen[$1]++' "${TMP_FILE}" >"${MERGED_FILE}"

	# Perform cleanups if enabled
	[[ "${REMOVE_DASH}" = "true" ]] && sed -i '/^\s*#/d' "${MERGED_FILE}"
	[[ "${REMOVE_EMPTY_LINES}" = "true" ]] && sed -i '/^\s*$/d' "${MERGED_FILE}"
	[[ "${REMOVE_TRAILING_SPACES}" = "true" ]] && sed -i 's/[[:space:]]*$//' "${MERGED_FILE}"

	# Show added entries if enabled
	[[ "true" = "${SHOW_ADDED_ENTRIES}" ]] &&
		global_stack_load_env_show_files_inconsistency \
			--src-file="${SRC_FILE}" \
			--dest-file="${DEST_FILE}" \
			--exclude-pattern="" \
			--operation="add" \
			--debug="${DEBUG}"

	# Overwrite destination with merged content
	mv "${MERGED_FILE}" "${DEST_FILE}"

	# Show different/missing entries if enabled
	global_stack_load_env_show_files_differences \
		--src-file="${SRC_FILE}" \
		--dest-file="${DEST_FILE}" \
		--exclude-pattern="${EXCLUDE_DIFFERENT_PATTERN}" \
		--count="${COUNT}" \
		--show-different-entries="${SHOW_DIFFERENT_ENTRIES}" \
		--debug="${DEBUG}" \
		--update-differences="${UPDATE_DIFFERENCES}"
	[[ "true" = "${CHECK_MISSING}" ]] &&
		global_stack_load_env_check_missing_variables \
			--target-file="${SRC_FILE}" \
			--txt-file-name="src.${COUNT}" \
			--exclude-pattern="${EXCLUDE_CHECK_MISSING}|${EXCLUDE_LOCAL_PATTERN}" \
			--reverse-checking="false" \
			--extract-all-env-output-file="${EXTRACT_ALL_ENV_OUTPUT_FILE}" \
			--dir="${DIR}" \
			--search-path="${SEARCH_PATH}" \
			--debug="${DEBUG}" \
			--cleanup-tmp="${CLEANUP_TMP}"
	[[ "true" = "${CHECK_MISSING}" ]] &&
		global_stack_load_env_check_missing_variables \
			--target-file="${DEST_FILE}" \
			--txt-file-name="dest.${COUNT}" \
			--exclude-pattern="${EXCLUDE_CHECK_MISSING}" \
			--reverse-checking="false" \
			--extract-all-env-output-file="${EXTRACT_ALL_ENV_OUTPUT_FILE}" \
			--dir="${DIR}" \
			--search-path="${SEARCH_PATH}" \
			--debug="${DEBUG}" \
			--cleanup-tmp="${CLEANUP_TMP}"
	[[ "true" = "${CHECK_MISSING}" ]] &&
		global_stack_load_env_check_missing_variables \
			--target-file="${DEST_FILE}" \
			--txt-file-name="dest.${COUNT}" \
			--exclude-pattern="${EXCLUDE_REVERSE_CHECK_MISSING}" \
			--reverse-checking="true" \
			--extract-all-env-output-file="${EXTRACT_ALL_ENV_OUTPUT_FILE}" \
			--dir="${DIR}" \
			--search-path="${SEARCH_PATH}" \
			--debug="${DEBUG}" \
			--cleanup-tmp="${CLEANUP_TMP}"
	[[ "true" = "${SHOW_ADDED_ENTRIES}" ]] &&
		global_stack_load_env_show_files_inconsistency \
			--src-file="${DEST_FILE}" \
			--dest-file="${SRC_FILE}" \
			--exclude-pattern="${EXCLUDE_LOCAL_PATTERN}" \
			--operation="" \
			--debug="${DEBUG}"

	[[ "true" = "${CLEANUP_TMP}" ]] &&
		rm -rf \
			"${TMP_FILE}"
}

global_stack_load_env_show_files_inconsistency() {
	local SRC_FILE
	SRC_FILE="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local DEST_FILE
	DEST_FILE="$(echo "${2}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local EXCLUDE_PATTERN
	EXCLUDE_PATTERN="$(echo "${3}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local OPERATION
	OPERATION="$(echo "${4}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local DEBUG
	DEBUG="$(echo "${5}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"

	local ADDED_ENTRIES
	ADDED_ENTRIES=$(awk -F "=" -v exclude_pattern="${EXCLUDE_PATTERN}" 'NR == FNR { original[$1]; next } !($1 in original) && $1 !~ /^#|^\s*$/ && (exclude_pattern == "" || !($1 ~ exclude_pattern)) { print $1 "=" $2 }' "${DEST_FILE}" "${SRC_FILE}")
	if [[ -n "${ADDED_ENTRIES}" ]]; then
		if [[ "add" = "${OPERATION}" ]]; then
			echo -e "\n ---- (global_stack_load_env_show_files_inconsistency): New entries added to ${DEST_FILE} from ${SRC_FILE}:\n${ADDED_ENTRIES}\n"
		else
			echo -e "\n ---- (global_stack_load_env_show_files_inconsistency): Entries missing in ${DEST_FILE} from ${SRC_FILE}:\n${ADDED_ENTRIES}\n"
		fi
	else
		if [[ "true" = "${DEBUG}" ]]; then
			echo -e "\n ---- (global_stack_load_env_show_files_inconsistency): All ${SRC_FILE} variables are present in ${DEST_FILE}\n"
		fi
	fi
}

global_stack_load_env_show_files_differences() {
	local SRC_FILE
	SRC_FILE="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local DEST_FILE
	DEST_FILE="$(echo "${2}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local EXCLUDE_PATTERN
	EXCLUDE_PATTERN="$(echo "${3}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local COUNT
	COUNT="$(echo "${4}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local SHOW_DIFFERENT_ENTRIES
	SHOW_DIFFERENT_ENTRIES="$(echo "${5}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local DEBUG
	DEBUG="$(echo "${6}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local UPDATE_DIFFERENCES
	UPDATE_DIFFERENCES="$(echo "${7}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"

	local DIFFERENT_ENTRIES
	DIFFERENT_ENTRIES=$(awk -F "=" -v exclude_pattern="${EXCLUDE_PATTERN}" 'NR == FNR { source[$1]=$2; next } ($1 in source) && ($2 != source[$1]) && (exclude_pattern == "" || !($1 ~ exclude_pattern)) { print $1 "=" $2 "\n(--------- is : \"" source[$1] "\" in source)\n" }' "${SRC_FILE}" "${DEST_FILE}")
	if [[ "true" = "${SHOW_DIFFERENT_ENTRIES}" ]]; then
		if [[ -n "${DIFFERENT_ENTRIES}" ]]; then
			echo -e "\n ---- (global_stack_load_env_show_files_differences): Entries in ${DEST_FILE} differ from ${SRC_FILE}:\n${DIFFERENT_ENTRIES}\n"
		else
			if [[ "true" = "${DEBUG}" ]]; then
				echo -e "\n ---- (global_stack_load_env_show_files_differences): ${DEST_FILE} values are in sync with source file ${SRC_FILE}\n"
			fi
		fi
	fi

	if [[ -n "${DIFFERENT_ENTRIES}" && "update_differences" = "${UPDATE_DIFFERENCES}" ]]; then
		awk -F "=" -v exclude_pattern="${EXCLUDE_PATTERN}" 'NR == FNR { source[$1] = $2; next } (exclude_pattern != "" && $1 ~ exclude_pattern) { print $0; next } ($1 in source) && ($2 != source[$1]) { print $1 "=" source[$1]; next } { print $0; next }' "${SRC_FILE}" "${DEST_FILE}" >"${DEST_FILE}.updated.tmp.${COUNT}" && mv "${DEST_FILE}.updated.tmp.${COUNT}" "${DEST_FILE}"
		if [[ "true" = "${DEBUG}" ]]; then
			echo -e "\n ---- (global_stack_load_env_show_files_differences): ${DEST_FILE} values updated to match with values from source ${SRC_FILE}\n"
		fi
	fi
}

global_stack_load_env_check_missing_variables() {
	local TARGET_FILE
	TARGET_FILE="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local TXT_FILE_NAME
	TXT_FILE_NAME="$(echo "${2}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local EXCLUDE_PATTERN
	EXCLUDE_PATTERN="$(echo "${3}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local REVERSE_CHECKING
	REVERSE_CHECKING="$(echo "${4}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local EXTRACT_ALL_ENV_OUTPUT_FILE
	EXTRACT_ALL_ENV_OUTPUT_FILE="$(echo "${5}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local DIR
	DIR="$(echo "${6}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local SEARCH_PATH
	SEARCH_PATH="$(echo "${7}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local DEBUG
	DEBUG="$(echo "${8}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"
	local CLEANUP_TMP
	CLEANUP_TMP="$(echo "${9}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')"

	cut -d'=' -f1 "${EXTRACT_ALL_ENV_OUTPUT_FILE}" | sort -u >"${DIR}/${TXT_FILE_NAME}_extracted_vars.txt"
	cut -d'=' -f1 "${TARGET_FILE}" | sort -u >"${DIR}/${TXT_FILE_NAME}_vars.txt"
	local MISSING_VARIABLES
	if [[ "true" = "${REVERSE_CHECKING}" ]]; then
		MISSING_VARIABLES=$(comm -23 "${DIR}/${TXT_FILE_NAME}_vars.txt" "${DIR}/${TXT_FILE_NAME}_extracted_vars.txt" | if [[ -n "${EXCLUDE_PATTERN}" ]]; then grep -vE "${EXCLUDE_PATTERN}"; else cat; fi)
	else
		MISSING_VARIABLES=$(comm -23 "${DIR}/${TXT_FILE_NAME}_extracted_vars.txt" "${DIR}/${TXT_FILE_NAME}_vars.txt" | if [[ -n "${EXCLUDE_PATTERN}" ]]; then grep -vE "${EXCLUDE_PATTERN}"; else cat; fi)
	fi
	if [[ -n "${MISSING_VARIABLES}" ]]; then
		if [[ "true" = "${REVERSE_CHECKING}" ]]; then
			echo -e "\n ---- (global_stack_load_env_check_missing_variables: reverse=${REVERSE_CHECKING}): Missing variables from ${TARGET_FILE} in ${SEARCH_PATH}:\n${MISSING_VARIABLES}\n"
		else
			echo -e "\n ---- (global_stack_load_env_check_missing_variables: reverse=${REVERSE_CHECKING}): Missing variables from ${SEARCH_PATH} in ${TARGET_FILE}:\n${MISSING_VARIABLES}\n"
		fi
	else
		if [[ "true" = "${DEBUG}" ]]; then
			if [[ "true" = "${REVERSE_CHECKING}" ]]; then
				echo -e "\n ---- (global_stack_load_env_check_missing_variables: reverse=${REVERSE_CHECKING}): All the environment variables present in ${TARGET_FILE} are in ${SEARCH_PATH}\n"
			else
				echo -e "\n ---- (global_stack_load_env_check_missing_variables: reverse=${REVERSE_CHECKING}): All the environment variables present in ${SEARCH_PATH} are in ${TARGET_FILE}\n"
			fi
		fi
	fi
	if [[ "true" = "${CLEANUP_TMP}" ]]; then
		rm -rf \
			"${DIR}/${TXT_FILE_NAME}_extracted_vars.txt" \
			"${DIR}/${TXT_FILE_NAME}_vars.txt"
	fi
}

global_stack_load_env_main() {
	local GLOBAL_STACK_LOAD_ENV_DEBUG
	local GLOBAL_STACK_LOAD_ENV_DEBUG_SHOW_EXTRACTED_FILES
	local GLOBAL_STACK_LOAD_ENV_REMOVE_DASH
	local GLOBAL_STACK_LOAD_ENV_REMOVE_EMPTY_LINES
	local GLOBAL_STACK_LOAD_ENV_REMOVE_TRAILING_SPACES
	local GLOBAL_STACK_LOAD_ENV_SHOW_ADDED_ENTRIES
	local GLOBAL_STACK_LOAD_ENV_SHOW_DIFFERENT_ENTRIES
	local GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV
	local GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV_DELETE_OUTPUT
	local GLOBAL_STACK_LOAD_ENV_CHECK_MISSING
	local GLOBAL_STACK_LOAD_ENV_CLEANUP_TMP
	local GLOBAL_STACK_LOAD_ENV_INCLUDE_DOCKER_ARGS
	local GLOBAL_STACK_LOAD_ENV_DIR
	local GLOBAL_STACK_LOAD_ENV_DESTINATION_FILE_TMP_SUFFIX
	local GLOBAL_STACK_LOAD_ENV_DESTINATION_FILE_MERGED_SUFFIX
	local GLOBAL_STACK_LOAD_ENV_UPDATE_DIFFERENCES
	local GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_PREFIX
	local GLOBAL_STACK_LOAD_ENV_EXCLUDE_DIFFERENT_PATTERN
	local GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_EXCLUDE_PATTERN
	local GLOBAL_STACK_LOAD_ENV_EXCLUDE_REVERSE_CHECK_MISSING
	local GLOBAL_STACK_LOAD_ENV_EXCLUDE_CHECK_MISSING
	local GLOBAL_STACK_LOAD_ENV_SEARCH_PATH
	local GLOBAL_STACK_LOAD_ENV_SEARCH_PATH_IGNORE_PATTERN
	local GLOBAL_STACK_LOAD_ENV_SOURCE_FILES
	local GLOBAL_STACK_LOAD_ENV_DESTINATION_FILES
	local GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV_OUTPUT_FILE
	local GLOBAL_STACK_LOAD_ENV_EXCLUDE_LOCAL_PATTERN
	local GLOBAL_STACK_LOAD_ENV_ALL_SRC_ENV_MERGED_NAME
	local GLOBAL_STACK_LOAD_ENV_EXCLUDE_IMPLICIT_EMPTY
	local GLOBAL_STACK_LOAD_ENV_EXCLUDE_EXPLICIT_EMPTY

	while [[ $# -gt 0 ]]; do
		case "${1}" in
		--debug=*) GLOBAL_STACK_LOAD_ENV_DEBUG="$(echo "${1,,}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--debug-show-extracted-files=*) GLOBAL_STACK_LOAD_ENV_DEBUG_SHOW_EXTRACTED_FILES="$(echo "${1,,}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--remove-dash=*) GLOBAL_STACK_LOAD_ENV_REMOVE_DASH="$(echo "${1,,}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--remove-empty-lines=*) GLOBAL_STACK_LOAD_ENV_REMOVE_EMPTY_LINES="$(echo "${1,,}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--remove-trailing-spaces=*) GLOBAL_STACK_LOAD_ENV_REMOVE_TRAILING_SPACES="$(echo "${1,,}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--show-added-entries=*) GLOBAL_STACK_LOAD_ENV_SHOW_ADDED_ENTRIES="$(echo "${1,,}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--show-different-entries=*) GLOBAL_STACK_LOAD_ENV_SHOW_DIFFERENT_ENTRIES="$(echo "${1,,}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--extract-all-env=*) GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV="$(echo "${1,,}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--extract-all-env-delete-output=*) GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV_DELETE_OUTPUT="$(echo "${1,,}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--check-missing=*) GLOBAL_STACK_LOAD_ENV_CHECK_MISSING="$(echo "${1,,}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--cleanup-tmp=*) GLOBAL_STACK_LOAD_ENV_CLEANUP_TMP="$(echo "${1,,}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--include-docker-args=*) GLOBAL_STACK_LOAD_ENV_INCLUDE_DOCKER_ARGS="$(echo "${1,,}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--dir=*) GLOBAL_STACK_LOAD_ENV_DIR="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--destination-file-tmp-suffix=*) GLOBAL_STACK_LOAD_ENV_DESTINATION_FILE_TMP_SUFFIX="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--destination-file-merged-suffix=*) GLOBAL_STACK_LOAD_ENV_DESTINATION_FILE_MERGED_SUFFIX="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--update-differences=*) GLOBAL_STACK_LOAD_ENV_UPDATE_DIFFERENCES="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--extract-all-prefix=*) GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_PREFIX="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--exclude-different-pattern=*) GLOBAL_STACK_LOAD_ENV_EXCLUDE_DIFFERENT_PATTERN="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--extract-all-exclude-pattern=*) GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_EXCLUDE_PATTERN="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--exclude-reverse-check-missing=*) GLOBAL_STACK_LOAD_ENV_EXCLUDE_REVERSE_CHECK_MISSING="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--exclude-check-missing=*) GLOBAL_STACK_LOAD_ENV_EXCLUDE_CHECK_MISSING="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--search-path=*) GLOBAL_STACK_LOAD_ENV_SEARCH_PATH="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--search-path-ignore-pattern=*) GLOBAL_STACK_LOAD_ENV_SEARCH_PATH_IGNORE_PATTERN="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--source-files=*) GLOBAL_STACK_LOAD_ENV_SOURCE_FILES="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--destination-files=*) GLOBAL_STACK_LOAD_ENV_DESTINATION_FILES="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--extract-all-env-output-file=*) GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV_OUTPUT_FILE="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--exclude-local-pattern=*) GLOBAL_STACK_LOAD_ENV_EXCLUDE_LOCAL_PATTERN="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--all-src-env-merged-name=*) GLOBAL_STACK_LOAD_ENV_ALL_SRC_ENV_MERGED_NAME="$(echo "${1}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--exclude-implicit-empty=*) GLOBAL_STACK_LOAD_ENV_EXCLUDE_IMPLICIT_EMPTY="$(echo "${1,,}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--exclude-explicit-empty=*) GLOBAL_STACK_LOAD_ENV_EXCLUDE_EXPLICIT_EMPTY="$(echo "${1,,}" | sed 's/^--[a-zA-Z0-9_-]\+=//' | sed 's/^--[a-zA-Z0-9_-]\+=//')" ;;
		--help) 
			global_stack_load_env_show_help
			exit 1
			;;
		*)
			echo -e "\n ---- Unknown option passed: '${1}' \n" >&2
			global_stack_load_env_show_help
			exit 1
			;;
		esac
		shift
	done

	# Set boolean flags with default values
	local -A BOOLEAN_FLAGS=(
		[GLOBAL_STACK_LOAD_ENV_DEBUG]=false
		[GLOBAL_STACK_LOAD_ENV_DEBUG_SHOW_EXTRACTED_FILES]=false
		[GLOBAL_STACK_LOAD_ENV_REMOVE_DASH]=true
		[GLOBAL_STACK_LOAD_ENV_REMOVE_EMPTY_LINES]=true
		[GLOBAL_STACK_LOAD_ENV_REMOVE_TRAILING_SPACES]=true
		[GLOBAL_STACK_LOAD_ENV_SHOW_ADDED_ENTRIES]=true
		[GLOBAL_STACK_LOAD_ENV_SHOW_DIFFERENT_ENTRIES]=true
		[GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV]=true
		[GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV_DELETE_OUTPUT]=true
		[GLOBAL_STACK_LOAD_ENV_CHECK_MISSING]=true
		[GLOBAL_STACK_LOAD_ENV_CLEANUP_TMP]=true
		[GLOBAL_STACK_LOAD_ENV_INCLUDE_DOCKER_ARGS]=true
		[GLOBAL_STACK_LOAD_ENV_EXCLUDE_IMPLICIT_EMPTY]=true
		[GLOBAL_STACK_LOAD_ENV_EXCLUDE_EXPLICIT_EMPTY]=true
	)
	for VAR in "${!BOOLEAN_FLAGS[@]}"; do
		[[ -z "${!VAR+set}" ]] && eval "${VAR}=\"${BOOLEAN_FLAGS[${VAR}]}\""

		if [[ "true" != "${!VAR}" && "false" != "${!VAR}" ]]; then
			eval "${VAR}=\"${BOOLEAN_FLAGS[${VAR}]}\""
		fi
	done

	# Set patterns/directory/files variables with defaults
	local -A DEFAULTS=(
		[GLOBAL_STACK_LOAD_ENV_DIR]="$(dirname "$(realpath "${0}")" | sed "s/\/bin//")"
		[GLOBAL_STACK_LOAD_ENV_DESTINATION_FILE_TMP_SUFFIX]=".tmp"
		[GLOBAL_STACK_LOAD_ENV_DESTINATION_FILE_MERGED_SUFFIX]=".merged"
		[GLOBAL_STACK_LOAD_ENV_UPDATE_DIFFERENCES]="" # update_differences
		[GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_PREFIX]="(GLOBAL_STACK_)"
		[GLOBAL_STACK_LOAD_ENV_EXCLUDE_DIFFERENT_PATTERN]='^(ARG )?(GLOBAL_STACK_POSTGRES17_DBS|GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS|GLOBAL_STACK_HTTPS_LOCALHOST_IPS|GLOBAL_STACK_PODMAN_CHANEL|COMPOSE_FILE|COMPOSE_BAKE|BUILDX_EXPERIMENTAL|GLOBAL_STACK_HOST_GATEWAY_IP|GLOBAL_STACK_SERVERLESS_FRAMEWORK_SERVERLESS_ACCESS_KEY|GLOBAL_STACK_(.+)_PORT_[0-9]+(.*))'
		[GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_EXCLUDE_PATTERN]='^(NODE_CONFIG_PACKAGE_|NODE_INSTALL_PACKAGE_|PHP_CONFIG_PACKAGE|PHP_INSTALL_PACKAGE|SDKMAN_CONFIG_PACKAGE|SDKMAN_INSTALL_PACKAGE|PYTHON_CONFIG_PACKAGE_|PYTHON_INSTALL_PACKAGE_|RUBY_CONFIG_PACKAGE_|RUBY_INSTALL_PACKAGE_|JAVA_VERSION|JAVA_VERSION_AS|NODE_VERSION|NODE_VERSION_AS|PYTHON_VERSION_AS|RUBY_VERSION_AS|NVM_MODE|GLOBAL_STACK_NODE_UPGRADE|GLOBAL_STACK_PHP_VERSION|GLOBAL_STACK_PYTHON_VERSION|GLOBAL_STACK_RUBY_VERSION|GLOBAL_STACK_CURRENT_VERSION|GLOBAL_STACK_IMAGE_MARIADB_VERSION|GLOBAL_STACK_IMAGE_MONGO_VERSION|GLOBAL_STACK_IMAGE_MYSQL_VERSION|GLOBAL_STACK_IMAGE_POSTGRES_VERSION|GLOBAL_STACK_IMAGE_UBUNTU_VERSION|GLOBAL_STACK_SHOW_WAITING)'
		[GLOBAL_STACK_LOAD_ENV_EXCLUDE_REVERSE_CHECK_MISSING]='^(ARG )?(COMPOSE_DOCKER_CLI_BUILD|COMPOSE_PROJECT_NAME|GLOBAL_STACK_COMPOSE_CLI|COMPOSE_FILE|COMPOSE_BAKE|BUILDX_EXPERIMENTAL|COMPOSE_HTTP_TIMEOUT|COMPOSE_PATH_SEPARATOR|COMPOSE_REMOVE_ORPHANS|DOCKER_BUILDKIT|GLOBAL_STACK_LOCAL_REGISTRY_NAME|GLOBAL_STACK_LOCAL_REGISTRY_VERSION|GLOBAL_STACK_SERVERLESS_FRAMEWORK_HOST|GLOBAL_STACK_BASE_CA_BUNDLE|GLOBAL_STACK_LOCALSTACK_LOCALSTACK_PORT_4566|GLOBAL_STACK_LOCALSTACK_LOCALSTACK_PORT_4566_WITH_STARTING_POINTS)'
		[GLOBAL_STACK_LOAD_ENV_EXCLUDE_CHECK_MISSING]='^(ARG )?(ANDROID_HOME|ANDROID_NDK_HOME|ANDROID_SDK_HOME|ANDROID_SDK_ROOT|CARGO_HOME|CAROOT|COMPOSER_HOME|COMPOSER_SOURCE|CYPRESS_CACHE_FOLDER|DENO_DIR|DENO_INSTALL|DENO_INSTALL_ROOT|FLUTTER_HOME|GRADLE_USER_HOME|MISE_CACHE_DIR|MISE_CONFIG_DIR|MISE_DATA_DIR|MISE_DEBUG|MISE_INSTALL_PATH|MISE_QUIET|MISE_STATE_DIR|MISE_VERSION|NPM_CACHE_DIR|NVM_DIR|PHPBREW_BIN|GOPATH|PHPBREW_HOME|PHPBREW_RC_ENABLE|PHPBREW_ROOT|PHPBREW_SET_PROMPT|PHPBREW_SKIP_INIT|PHPBREW_SRC|PNPM_HOME|PUB_CACHE|PYENV_ROOT|RBENV_ROOT|RUSTUP_HOME|SDKMAN_DIR|SYMFONY_HOME|YARN_CACHE_FOLDER|YARN_GLOBAL_FOLDER|YARN_OFFLINE_MIRROR|GLOBAL_STACK_DOCKER_USER_CONFIG|GLOBAL_STACK_BASE_USERNAME|GLOBAL_STACK_BASE_USER_HOME_GROUP_PAIRS|GLOBAL_STACK_BASE_USER_HOME_GROUP_PAIR|GLOBAL_STACK_BASE_USER_HOME|GLOBAL_STACK_BASE_GROUP)'
	)
	for VAR in "${!DEFAULTS[@]}"; do
		[[ -z "${!VAR+set}" ]] && eval "${VAR}=\"${DEFAULTS[${VAR}]}\""
	done

	# Set patterns/directory/files variables that depends on other variables with defaults
	local -A DEPENDENT_DEFAULTS=(
		[GLOBAL_STACK_LOAD_ENV_SEARCH_PATH]="${GLOBAL_STACK_LOAD_ENV_DIR}/docker"
		[GLOBAL_STACK_LOAD_ENV_SEARCH_PATH_IGNORE_PATTERN]="
^${GLOBAL_STACK_LOAD_ENV_DIR}/docker/config/root/.bash_history$
^${GLOBAL_STACK_LOAD_ENV_DIR}/docker/config/root/.zsh_history$
^${GLOBAL_STACK_LOAD_ENV_DIR}/docker/storage.*
^${GLOBAL_STACK_LOAD_ENV_DIR}/docker/registry.*
^${GLOBAL_STACK_LOAD_ENV_DIR}/docker/logs.*
^${GLOBAL_STACK_LOAD_ENV_DIR}/docker/data.*
"
		[GLOBAL_STACK_LOAD_ENV_SOURCE_FILES]="${GLOBAL_STACK_LOAD_ENV_DIR}/.env"
		[GLOBAL_STACK_LOAD_ENV_DESTINATION_FILES]="${GLOBAL_STACK_LOAD_ENV_DIR}/.env.local"
		[GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV_OUTPUT_FILE]="${GLOBAL_STACK_LOAD_ENV_DIR}/.env.all.local"
		[GLOBAL_STACK_LOAD_ENV_EXCLUDE_LOCAL_PATTERN]="^${GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_PREFIX/\)/}LOCAL_)"
		[GLOBAL_STACK_LOAD_ENV_ALL_SRC_ENV_MERGED_NAME]="${GLOBAL_STACK_LOAD_ENV_DIR}/.env.src.all.merged"
	)
	for VAR in "${!DEPENDENT_DEFAULTS[@]}"; do
		[[ -z "${!VAR+set}" ]] && eval "${VAR}=\"${DEPENDENT_DEFAULTS[${VAR}]}\""
	done

	> "${GLOBAL_STACK_LOAD_ENV_ALL_SRC_ENV_MERGED_NAME}"

	for SRC_FILE in ${GLOBAL_STACK_LOAD_ENV_SOURCE_FILES//[\"\'\`]/}; do
		cat "${SRC_FILE}" | sed '/^\s*#/d' | sed '/^\s*$/d' | sed 's/[[:space:]]*$//' >> "${GLOBAL_STACK_LOAD_ENV_ALL_SRC_ENV_MERGED_NAME}"
		echo >> "${GLOBAL_STACK_LOAD_ENV_ALL_SRC_ENV_MERGED_NAME}"
	done

	local COUNT_SEARCH_EXTRACT
	COUNT_SEARCH_EXTRACT=0
	# Execute environment extraction if enabled
	if [[ "true" = "${GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV,,}" ]]; then
		true >"${GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV_OUTPUT_FILE}"
		if [[ -f "${GLOBAL_STACK_LOAD_ENV_SEARCH_PATH}" ]]; then
			global_stack_load_env_search_and_extract \
				--current-file="${GLOBAL_STACK_LOAD_ENV_SEARCH_PATH}" \
				--search-ignore="${GLOBAL_STACK_LOAD_ENV_SEARCH_PATH_IGNORE_PATTERN}" \
				--exclude-pattern="${GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_EXCLUDE_PATTERN}" \
				--count="${COUNT_SEARCH_EXTRACT}" \
				--debug="${GLOBAL_STACK_LOAD_ENV_DEBUG}" \
				--debug-show-extracted-files="${GLOBAL_STACK_LOAD_ENV_DEBUG_SHOW_EXTRACTED_FILES}" \
				--include-docker-args="${GLOBAL_STACK_LOAD_ENV_INCLUDE_DOCKER_ARGS}" \
				--extract-all-prefix="${GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_PREFIX}" \
				--extract-all-env-output-file="${GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV_OUTPUT_FILE}" \
				--extract-all-env-delete-output="${GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV_DELETE_OUTPUT}" \
				--cleanup-tmp="${GLOBAL_STACK_LOAD_ENV_CLEANUP_TMP}" \
				--all-src-env-merged-name="${GLOBAL_STACK_LOAD_ENV_ALL_SRC_ENV_MERGED_NAME}" \
				--exclude-implicit-empty="${GLOBAL_STACK_LOAD_ENV_EXCLUDE_IMPLICIT_EMPTY}" \
				--exclude-explicit-empty="${GLOBAL_STACK_LOAD_ENV_EXCLUDE_EXPLICIT_EMPTY}"
		elif [[ -d "${GLOBAL_STACK_LOAD_ENV_SEARCH_PATH}" ]]; then
			find "${GLOBAL_STACK_LOAD_ENV_SEARCH_PATH}" -type f | while read -r FILE; do
				((COUNT_SEARCH_EXTRACT++))
				global_stack_load_env_search_and_extract \
					--current-file="${FILE}" \
					--search-ignore="${GLOBAL_STACK_LOAD_ENV_SEARCH_PATH_IGNORE_PATTERN}" \
					--exclude-pattern="${GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_EXCLUDE_PATTERN}" \
					--count="${COUNT_SEARCH_EXTRACT}" \
					--debug="${GLOBAL_STACK_LOAD_ENV_DEBUG}" \
					--debug-show-extracted-files="${GLOBAL_STACK_LOAD_ENV_DEBUG_SHOW_EXTRACTED_FILES}" \
					--include-docker-args="${GLOBAL_STACK_LOAD_ENV_INCLUDE_DOCKER_ARGS}" \
					--extract-all-prefix="${GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_PREFIX}" \
					--extract-all-env-output-file="${GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV_OUTPUT_FILE}" \
					--extract-all-env-delete-output="${GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV_DELETE_OUTPUT}" \
					--cleanup-tmp="${GLOBAL_STACK_LOAD_ENV_CLEANUP_TMP}" \
					--all-src-env-merged-name="${GLOBAL_STACK_LOAD_ENV_ALL_SRC_ENV_MERGED_NAME}" \
					--exclude-implicit-empty="${GLOBAL_STACK_LOAD_ENV_EXCLUDE_IMPLICIT_EMPTY}" \
					--exclude-explicit-empty="${GLOBAL_STACK_LOAD_ENV_EXCLUDE_EXPLICIT_EMPTY}"
			done
		else
			echo -e "\n ---- (global_stack_load_env_main): ${GLOBAL_STACK_LOAD_ENV_SEARCH_PATH} is neither a file nor a directory, exiting !\n\n"
			exit 1
		fi
		sort -u "${GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV_OUTPUT_FILE}" -o "${GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV_OUTPUT_FILE}"
	fi

	global_stack_load_env_detect_multiple_default_different_values_for_key \
		--input-file="${GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV_OUTPUT_FILE}" \
		--current-file="${GLOBAL_STACK_LOAD_ENV_SEARCH_PATH}" \
		--all-src-env-merged-name="${GLOBAL_STACK_LOAD_ENV_ALL_SRC_ENV_MERGED_NAME}" \
		--exclude-implicit-empty="${GLOBAL_STACK_LOAD_ENV_EXCLUDE_IMPLICIT_EMPTY}" \
		--exclude-explicit-empty="${GLOBAL_STACK_LOAD_ENV_EXCLUDE_EXPLICIT_EMPTY}"

	local COUNT_SRC
	COUNT_SRC=0
	local COUNT_DEST
	COUNT_DEST=0
	# Process each source and destination pair
	for SRC_FILE in ${GLOBAL_STACK_LOAD_ENV_SOURCE_FILES//[\"\'\`]/}; do
		((COUNT_SRC++))
		for DEST_FILE in ${GLOBAL_STACK_LOAD_ENV_DESTINATION_FILES//[\"\'\`]/}; do
			((COUNT_DEST++))
			global_stack_load_env_process_file \
				--src-file="${SRC_FILE}" \
				--dest-file="${DEST_FILE}" \
				--count="${COUNT_SRC}_${COUNT_DEST}" \
				--destination-file-tmp-suffix="${GLOBAL_STACK_LOAD_ENV_DESTINATION_FILE_TMP_SUFFIX}" \
				--destination-file-merged-suffix="${GLOBAL_STACK_LOAD_ENV_DESTINATION_FILE_MERGED_SUFFIX}" \
				--remove-dash="${GLOBAL_STACK_LOAD_ENV_REMOVE_DASH}" \
				--remove-empty-lines="${GLOBAL_STACK_LOAD_ENV_REMOVE_EMPTY_LINES}" \
				--remove-trailing-spaces="${GLOBAL_STACK_LOAD_ENV_REMOVE_TRAILING_SPACES}" \
				--show-added-entries="${GLOBAL_STACK_LOAD_ENV_SHOW_ADDED_ENTRIES}" \
				--exclude-different-pattern="${GLOBAL_STACK_LOAD_ENV_EXCLUDE_DIFFERENT_PATTERN}" \
				--check-missing="${GLOBAL_STACK_LOAD_ENV_CHECK_MISSING}" \
				--exclude-local-pattern="${GLOBAL_STACK_LOAD_ENV_EXCLUDE_LOCAL_PATTERN}" \
				--exclude-reverse-check-missing="${GLOBAL_STACK_LOAD_ENV_EXCLUDE_REVERSE_CHECK_MISSING}" \
				--exclude-check-missing="${GLOBAL_STACK_LOAD_ENV_EXCLUDE_CHECK_MISSING}" \
				--cleanup-tmp="${GLOBAL_STACK_LOAD_ENV_CLEANUP_TMP}" \
				--debug="${GLOBAL_STACK_LOAD_ENV_DEBUG}" \
				--show-different-entries="${GLOBAL_STACK_LOAD_ENV_SHOW_DIFFERENT_ENTRIES}" \
				--update-differences="${GLOBAL_STACK_LOAD_ENV_UPDATE_DIFFERENCES}" \
				--extract-all-env-output-file="${GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV_OUTPUT_FILE}" \
				--dir="${GLOBAL_STACK_LOAD_ENV_DIR}" \
				--search-path="${GLOBAL_STACK_LOAD_ENV_SEARCH_PATH}"
		done
	done

	[[ "true" = "${GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV_DELETE_OUTPUT,,}" && "true" = "${GLOBAL_STACK_LOAD_ENV_CLEANUP_TMP,,}" ]] &&
		rm -rf \
			"${GLOBAL_STACK_LOAD_ENV_EXTRACT_ALL_ENV_OUTPUT_FILE}" \
			"${GLOBAL_STACK_LOAD_ENV_ALL_SRC_ENV_MERGED_NAME}"

}

global_stack_load_env_main "${@}"
