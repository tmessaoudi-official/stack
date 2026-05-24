#!/bin/bash
# help.sh — gs_es_show_help: print CLI usage to stdout
#
# Exports:   gs_es_show_help
# Sources:   none (reads _GS_ES_VERSION from defaults.sh at runtime via calling context)
# Deps:      bash 4.3+
# Env:       _GS_ES_VERSION (from config/defaults.sh; embedded in the usage header)

# Include guard
[[ -n "${_GS_ES_HELP_SH_LOADED:-}" ]] && return 0
readonly _GS_ES_HELP_SH_LOADED=1

# gs_es_show_help — print the complete CLI flag reference to stdout.
#
# Args:    none
# Prints:  usage text with all supported flags, their types, defaults, and examples
# Returns: 0 always
# Side fx: none
gs_es_show_help() {
	cat << EOF
bin/env-scan.sh v${_GS_ES_VERSION} — env sync + Dockerfile propagation

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
  --sync-values=<value>                      Sync destination values to match source when they differ (default: true)
  --dry-run                                  Report what would change but suppress all filesystem writes (env file sync and Dockerfile propagation) (default: false)
  --no-fail                                  Always exit 0, even when a propagation error occurs (source env file not found).
                                             Scope: only suppresses return 1 from Phase 6 propagation. Infrastructure errors
                                             (mktemp failure), backup failures, and usage errors remain fatal.
                                             When suppressed a stderr notice is printed:
                                             "[NO-FAIL] Phase 6 propagation error suppressed — exit code forced to 0"
  --scan-var-prefix=<value>                  Prefix pattern for environment variable extraction (default: "(GLOBAL_STACK_)")
  --diff-ignore-pattern=<value>              Pattern to suppress from "different value" warnings (default: predefined regex)
  --scan-var-ignore-pattern=<value>          Pattern to suppress VARIABLE NAMES (not file paths) from scan extraction (default: predefined regex)
  --reverse-check-ignore-pattern=<value>     Pattern for REVERSE check (.env.local → scan): vars absent from scan output (default: predefined regex)
  --forward-check-ignore-pattern=<value>     Pattern for FORWARD checks (scan → .env / .env.local): vars absent from env files (default: predefined regex)
  --scan-path=<value>                        Search path for environment variable files (default: "<working-dir>/docker")
  --scan-ignore-pattern=<value>              Ignore specific paths during search (default: predefined paths)
  --source-files=<value>                     Source environment files for processing (default: "<working-dir>/.env")
  --destination-files=<value>                Destination environment files for processing (default: "<working-dir>/.env.local")
  --scan-output-file=<value>                 File to store all extracted environment variables (default: "<working-dir>/.env.all.local")
  --exclude-local-pattern=<value>            Exclude local patterns during extraction (default: derived from scan-var-prefix)
  --source-merged-file=<value>               Path of the file where all source env files will be merged (default: <working-dir>/.env.src.all.merged)
  --exclude-implicit-empty=<value>           Exclude implicit empty from multiple default values (default: true)
  --exclude-explicit-empty=<value>           Exclude explicit empty from multiple default values (default: true)
  --conflict-ignore-pattern=<value>          Pattern to exclude vars from conflicting-defaults detection (default: predefined regex)
  --quiet=<value>                            Suppress informational output; errors still print (default: false)
  --profile=<value>                          Show execution time and memory usage per phase (default: false)
  --backup=<bool>                            Create a timestamped backup of destination files before overwriting (default: true)
  --backup-keep=<N>                          Keep the N newest backups per file after each run; 0 = unlimited (default: 10)
  --backup-purge=<bool>                      Delete ALL existing <file>.bak.* backups before the run (default: false)
  --backup-suffix=<str>                      Suffix anchor for backup files; full name: <file><suffix>.<YYYYMMDD-HHMMSS> (default: .bak)
  --prune-removed=<bool>                     Drop orphaned (local-only) vars from .env.local instead of keeping them (default: false)
  --orphan-ignore-pattern=<regex>            ERE regex: suppress orphaned-var warnings for matching var names (default: "")
  --orphan-quiet=<bool>                      Suppress ALL orphaned-var warnings; vars are still kept in .env.local (default: false)

Examples:
  ./env-scan.sh --debug=true --dir=/stack/.env --show-added-entries=false
  ./env-scan.sh --source-files="file1.env file2.env" --destination-files="dest1.env dest2.env"
  ./env-scan.sh --scan-path=/config --sync-values=true
  bin/env-scan.sh --orphan-ignore-pattern='GLOBAL_STACK_LOCAL_'   # silence machine-local vars
  bin/env-scan.sh --orphan-quiet=true                              # silence all orphan warnings
  bin/env-scan.sh --no-fail                                        # always exit 0 even on propagation error

Description:
  This script processes environment variable files, performing operations like:
  - Extracting variables from source files.
  - Syncing and merging with destination files.
  - Cleaning up formats (removing empty lines, trailing spaces, etc.).
  - Detecting differences or missing variables between source and destination.
  - Optionally updating destination files to match source files (--sync-values).
  - Propagating canonical .env values to Dockerfile ARG defaults (Phase 6).
  - Pass --dry-run to suppress all writes: env file sync (Phase 5) and Dockerfile propagation (Phase 6).
  - Creating timestamped backups of destination files and gitignored Dockerfiles before overwriting (Phase 4.5 / 6).

Common backup workflows:
  Normal run, keep 10 backups:           bin/env-scan.sh
  Disable backup this run:               bin/env-scan.sh --backup=false
  Delete all old backups, no new one:    bin/env-scan.sh --backup=false --backup-purge=true
  Delete all old backups, fresh one:     bin/env-scan.sh --backup-purge=true
  Unlimited retention:                   bin/env-scan.sh --backup-keep=0
EOF
}
