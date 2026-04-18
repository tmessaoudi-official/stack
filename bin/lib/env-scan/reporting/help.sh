#!/bin/bash
# help.sh — gs_es_show_help

# Include guard
[[ -n "${_GS_ES_HELP_SH_LOADED:-}" ]] && return 0
readonly _GS_ES_HELP_SH_LOADED=1

gs_es_show_help() {
	cat << EOF
Usage: env-scan.sh [OPTIONS]

Options:
  --debug=<value>                            Enable debug mode (default: false)
  --debug-show-extracted-files=<value>       Show files from which environment variables were extracted (default: false)
  --strip-comments=<value>                   Remove commented lines from output (default: true)
  --remove-empty-lines=<value>               Remove empty lines from output (default: true)
  --remove-trailing-spaces=<value>           Remove trailing spaces from lines in output (default: true)
  --show-added-entries=<value>               Show newly added entries from source to destination files (default: true)
  --show-different-entries=<value>           Show entries with differing values between source and destination files (default: true)
  --scan-sources=<value>                     Extract all environment variables from files (default: true)
  --scan-delete-output=<value>               Delete temporary extracted environment variable files (default: true)
  --check-missing=<value>                    Check for missing variables in the destination files (default: true)
  --cleanup-tmp=<value>                      Clean up temporary files after processing (default: true)
  --include-docker-args=<value>              Include Docker ARGs when extracting environment variables (default: true)
  --dir=<value>                              Set the working directory (default: inferred from script location removing /bin)
  --destination-file-tmp-suffix=<value>      Temporary file suffix for destination files (default: .tmp)
  --destination-file-merged-suffix=<value>   Merged file suffix for destination files (default: .merged)
  --sync-values=<value>                      Sync destination values to match source when they differ (default: false)
  --dry-run                                  Report propagation changes but suppress Dockerfile writes; env file syncing still runs (default: false)
  --scan-var-prefix=<value>                  Prefix pattern for environment variable extraction (default: "(GLOBAL_STACK_)")
  --exclude-different-pattern=<value>        Pattern to exclude from difference detection (default: predefined regex)
  --scan-exclude-pattern=<value>             Pattern to exclude from variable extraction (default: predefined regex)
  --exclude-source-check-pattern=<value>     Pattern to exclude from reverse missing check (default: predefined regex)
  --exclude-check-missing=<value>            Pattern to exclude from missing checks (default: predefined regex)
  --scan-path=<value>                        Search path for environment variable files (default: "<working-dir>/docker")
  --scan-ignore-pattern=<value>              Ignore specific paths during search (default: predefined paths)
  --source-files=<value>                     Source environment files for processing (default: "<working-dir>/.env")
  --destination-files=<value>                Destination environment files for processing (default: "<working-dir>/.env.local")
  --scan-output-file=<value>                 File to store all extracted environment variables (default: "<working-dir>/.env.all.local")
  --exclude-local-pattern=<value>            Exclude local patterns during extraction (default: derived from scan-var-prefix)
  --source-merged-file=<value>               Path of the file where all source env files will be merged (default: <working-dir>/.env.src.all.merged)
  --exclude-implicit-empty=<value>           Exclude implicit empty from multiple default values (default: true)
  --exclude-explicit-empty=<value>           Exclude explicit empty from multiple default values (default: true)
  --exclude-multiple-values-pattern=<value>  Pattern to exclude vars from multiple-values detection (default: predefined regex)
  --quiet=<value>                            Suppress informational output; errors still print (default: false)
  --profile=<value>                          Show execution time and memory usage per phase (default: false)

Examples:
  ./env-scan.sh --debug=true --dir=/stack/.env --show-added-entries=false
  ./env-scan.sh --source-files="file1.env file2.env" --destination-files="dest1.env dest2.env"
  ./env-scan.sh --scan-path=/config --sync-values=true

Description:
  This script processes environment variable files, performing operations like:
  - Extracting variables from source files.
  - Syncing and merging with destination files.
  - Cleaning up formats (removing empty lines, trailing spaces, etc.).
  - Detecting differences or missing variables between source and destination.
  - Optionally updating destination files to match source files (--sync-values).
  - Propagating canonical .env values to Dockerfile ARG defaults (Phase 6).
  - Pass --dry-run to suppress Dockerfile ARG propagation writes (Phase 6 only).
EOF
}
