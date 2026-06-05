#!/bin/bash
# reference.sh — comprehensive reference for env-scan: pipeline phases, flags,
#                propagation rules, conflict detection, and worked scenarios.
#
# Exports:   _gs_es_show_reference
# Sources:   none
# Deps:      bash 4.3+
# Env:       none
#
# Called by: main.sh when --reference[=SECTION] is passed (exits before env file access)
# Sections:  all (default) | pipeline | flags | propagation | conflicts | scenarios

[[ -n "${_GS_ES_REFERENCE_SH_LOADED:-}" ]] && return 0
readonly _GS_ES_REFERENCE_SH_LOADED=1

# _gs_es_show_reference — print the comprehensive reference for env-scan.
#
# Args:
#   $1  section — which section(s) to print; one of:
#         all          print every section (default)
#         pipeline     8-phase pipeline overview
#         flags        all CLI flags with types and defaults
#         propagation  Dockerfile ARG propagation rules and skip conditions
#         conflicts    conflict detection and --conflict-ignore-pattern
#         scenarios    worked examples (fresh install, drift, multi-source, etc.)
# Returns (stdout): human-readable reference text
# Side-effects: none (read-only)
_gs_es_show_reference() {
  local _section="${1:-all}"

  # Validate section name — exit 1 with list of valid sections if unknown
  case "${_section}" in
    all|pipeline|flags|propagation|conflicts|scenarios) ;;
    *)
      printf 'env-scan: unknown reference section: '\''%s'\''\n' "${_section}" >&2
      printf 'Valid sections: all, pipeline, flags, propagation, conflicts, scenarios\n' >&2
      exit 1
      ;;
  esac

  # ──────────────────────────────────────────────────────────────────────────
  # SECTION: pipeline
  # ──────────────────────────────────────────────────────────────────────────
  if [[ "${_section}" == "all" || "${_section}" == "pipeline" ]]; then
    cat << 'PIPELINE_EOF'
env-scan reference — SECTION: pipeline
────────────────────────────────────────────────────────────────────────────────

8-PHASE PIPELINE
  env-scan runs in a fixed 8-phase sequence. Each phase has a distinct purpose
  and a set of observable effects.

  Phase 1 — Parse args
    Read CLI flags, validate types, apply defaults. All subsequent phases use
    the populated _GS_ES_CFG associative array.

  Phase 2 — Build source index
    Resolve --source-files (default: <dir>/.env). When multiple source files are
    specified they are each processed independently in later phases.

  Phase 3 — Scan docker sources
    Walk docker/ looking for ARG lines in Dockerfiles (controlled by
    --scan-sources=true/false). Builds the list of vars present in Dockerfiles
    for conflict detection and propagation.

  Phase 4 — Detect conflicts
    Compare each source-file var against every other source file and against
    docker scan results. Variables appearing with different values in multiple
    sources are flagged as [CONFLICT]. Protected by --conflict-ignore-pattern.

  Phase 5 — Backup pre-flight
    If --backup=true (default), take a timestamped backup of each destination
    file before writing. Backup path: <file><suffix>.<YYYYMMDD-HHMMSS>
    Controlled by: --backup=true|false, --backup-keep=N, --backup-purge=true,
                   --backup-suffix=<str>

  Phase 6 — Sync env files
    Write merged content to each destination file (default: .env.local). New
    vars from source are added; existing dest vars retain their values when
    --sync-values=false; values are overwritten when --sync-values=true (default).
    In --dry-run mode this phase is skipped (report only).

  Phase 7 — Propagate to Dockerfiles
    For each source file and each Dockerfile, rewrite ARG lines whose values
    diverge from the canonical source value. Vars with ${...} in their source
    value are skipped (expansion-dependent). Also skipped when --dry-run.
    Protected by --conflict-ignore-pattern on a per-var basis.

  Phase 8 — Retention prune + cleanup
    Delete old backups exceeding --backup-keep=N (0 = keep all).
    Remove temp files produced during the run.

PIPELINE_EOF
  fi

  # ──────────────────────────────────────────────────────────────────────────
  # SECTION: flags
  # ──────────────────────────────────────────────────────────────────────────
  if [[ "${_section}" == "all" || "${_section}" == "flags" ]]; then
    cat << 'FLAGS_EOF'
env-scan reference — SECTION: flags
────────────────────────────────────────────────────────────────────────────────

GLOBAL FLAGS
  --version                 Print version and exit.
  --help                    Print help text and exit.
  --reference[=SECTION]     Print this reference and exit. No env file needed.
                            SECTION: all (default) | pipeline | flags |
                                     propagation | conflicts | scenarios
  --dry-run                 Report only — skip Phase 6 (sync) and Phase 7 (propagate).
  --no-fail                 Always exit 0; suppress Phase 7 propagation errors.
                            Infrastructure and backup failures remain fatal.
  --quiet=true|false        Suppress informational output. Default: false.
  --profile=true|false      Show per-phase timing at end of run. Default: false.

PATH / SOURCE FLAGS
  --dir=<path>              Project root. Default: resolved from script location.
  --source-files=<list>     Space-separated list of source env files.
                            Default: <dir>/.env
  --destination-files=<list> Space-separated list of destination env files.
                            Default: <dir>/.env.local
  --source-merged-file=<path> Path for merged-source temp file. Auto-cleaned.

SCAN FLAGS
  --scan-sources=true|false   Scan docker/ for ARG lines. Default: true.
  --scan-path=<path>          Where to scan. Default: <dir>/docker
  --scan-ignore-pattern=<re>  Newline-separated ERE; matched paths are excluded.
  --scan-var-prefix=<re>      Regex anchoring which var names to include.
                              Default: (GLOBAL_STACK_)
  --scan-var-ignore-pattern=<re>  Vars matching this pattern are never extracted.
  --scan-output-file=<path>   Where to write the combined scan output.
                              Default: <dir>/.env.all.local
  --scan-delete-output=true|false  Delete scan output file after run. Default: true.
  --include-docker-args=true|false  Include ARG values from docker scan. Default: true.

MERGE / SYNC FLAGS
  --sync-values=true|false    Overwrite dest values from source. Default: true.
                              Set false to preserve local overrides.
  --show-added-entries=true|false  Report new vars added to dest. Default: true.
  --show-different-entries=true|false  Report vars with differing values. Default: true.
  --check-missing=true|false  Report vars in source not in any dest. Default: true.
  --exclude-implicit-empty=true|false  Exclude vars with empty default. Default: true.
  --exclude-explicit-empty=true|false  Exclude explicitly empty vars. Default: true.
  --exclude-local-pattern=<re>  Vars matching pattern skipped in dest sync.
  --prune-removed=true|false  Remove dest vars absent from all sources. Default: false.
  --orphan-ignore-pattern=<re>  Vars protected from pruning.
  --orphan-quiet=true|false   Suppress prune reporting. Default: false.

CONFLICT FLAGS
  --conflict-ignore-pattern=<re>  Vars matching are never flagged as conflicts
                                   and never rewritten in Dockerfiles.
  --diff-ignore-pattern=<re>      Vars ignored when comparing source vs dest.
  --reverse-check-ignore-pattern=<re>   Vars ignored in reverse conflict check.
  --forward-check-ignore-pattern=<re>   Vars ignored in forward conflict check.

BACKUP FLAGS
  --backup=true|false         Take backup before writing. Default: true.
  --backup-suffix=<str>       Suffix anchor. Default: .bak
                              Full name: <file><suffix>.<YYYYMMDD-HHMMSS>
  --backup-keep=<N>           Keep N newest backups per file. 0=unlimited. Default: 10.
  --backup-purge=true|false   Delete all existing backups before run. Default: false.

DEBUG FLAGS
  --debug=true|false                      Enable verbose debug output. Default: false.
  --debug-show-extracted-files=true|false Show extracted file list. Default: false.
  --destination-file-tmp-suffix=<str>     Suffix for merge temp files. Default: .tmp
  --destination-file-merged-suffix=<str>  Suffix for merged output. Default: .merged
  --cleanup-tmp=true|false                Delete temp files on exit. Default: true.
  --strip-comments=true|false             Strip comments from extracted output. Default: true.
  --remove-empty-lines=true|false         Remove blank lines. Default: true.
  --remove-trailing-spaces=true|false     Remove trailing whitespace. Default: true.

FLAGS_EOF
  fi

  # ──────────────────────────────────────────────────────────────────────────
  # SECTION: propagation
  # ──────────────────────────────────────────────────────────────────────────
  if [[ "${_section}" == "all" || "${_section}" == "propagation" ]]; then
    cat << 'PROP_EOF'
env-scan reference — SECTION: propagation
────────────────────────────────────────────────────────────────────────────────

DOCKERFILE ARG PROPAGATION (Phase 7)
  env-scan rewrites ARG lines in Dockerfiles to stay in sync with source .env.

  RULES
  1. Only ARG lines whose value differs from the canonical source value are touched.
  2. The source value is taken from the first source file that defines the var.
  3. Vars with ${...} in their .env value are SKIPPED — expansion-dependent values
     cannot be resolved at scan time (e.g. GLOBAL_STACK_DB_URL=${HOST}:${PORT}).
  4. Vars matching --conflict-ignore-pattern are NEVER rewritten.
  5. In --dry-run mode, Phase 7 is skipped entirely.
  6. Multi-source: propagation runs once per source file, not once globally.

  DOCKERFILE LINE FORMAT
  Only lines of the form:
    ARG VARNAME=value
  are matched. ARG lines without a default value (ARG VARNAME) are left untouched
  because they have no value to synchronise.

  PROPAGATION SKIP CONDITIONS (per var)
  - Source value contains ${  → skip (expansion-dependent)
  - Var matches --conflict-ignore-pattern → skip
  - Value already matches source → skip (no-op, no write)
  - Dockerfile is in a path matching --scan-ignore-pattern → skip

  EXAMPLE
    Source (.env):
      GLOBAL_STACK_POSTGRES18_VERSION=18.4-alpine3.23

    Dockerfile (before):
      ARG GLOBAL_STACK_POSTGRES18_VERSION=18.3-alpine3.23

    Dockerfile (after Phase 7):
      ARG GLOBAL_STACK_POSTGRES18_VERSION=18.4-alpine3.23

PROP_EOF
  fi

  # ──────────────────────────────────────────────────────────────────────────
  # SECTION: conflicts
  # ──────────────────────────────────────────────────────────────────────────
  if [[ "${_section}" == "all" || "${_section}" == "conflicts" ]]; then
    cat << 'CONFLICT_EOF'
env-scan reference — SECTION: conflicts
────────────────────────────────────────────────────────────────────────────────

CONFLICT DETECTION (Phase 4)
  A conflict is when a variable appears with different values in multiple sources.

  TYPES OF CONFLICT
  - Source vs source:   var defined differently in two source files.
  - Source vs docker:   var in .env differs from ARG in a Dockerfile.

  OUTPUT
  Conflicts are printed with a [CONFLICT] tag on stderr, showing:
    [CONFLICT] VARNAME
      source1.env: VALUE_A
      source2.env: VALUE_B

  SUPPRESSION
  --conflict-ignore-pattern=<ERE>
    Variables matching this pattern are never flagged and never rewritten.
    Default pattern protects known cross-service vars (see defaults.sh).

  NOTE
  Conflicts do not abort the run by default. They are reported and then
  env-scan continues with the first-seen value as canonical.
  Use --no-fail to suppress exit codes from Phase 7 propagation errors, but
  conflict detection itself is always informational.

CONFLICT_EOF
  fi

  # ──────────────────────────────────────────────────────────────────────────
  # SECTION: scenarios
  # ──────────────────────────────────────────────────────────────────────────
  if [[ "${_section}" == "all" || "${_section}" == "scenarios" ]]; then
    cat << 'SCENARIOS_EOF'
env-scan reference — SECTION: scenarios
────────────────────────────────────────────────────────────────────────────────

WORKED SCENARIOS

1. Fresh install — .env.local does not exist yet
   $ bin/env-scan.sh
   Phase 6 creates .env.local from .env.
   Phase 7 rewrites divergent ARG lines in all Dockerfiles.
   Output: shows [ADDED] lines for every new var.

2. Version bump — update one var in .env, propagate everywhere
   # Edit .env: GLOBAL_STACK_POSTGRES18_VERSION=18.4-alpine3.23
   $ bin/env-scan.sh
   Phase 6: .env.local gets GLOBAL_STACK_POSTGRES18_VERSION=18.4-alpine3.23
   Phase 7: all Dockerfiles with ARG GLOBAL_STACK_POSTGRES18_VERSION=... are updated.

3. Dry-run preview before writing
   $ bin/env-scan.sh --dry-run
   Shows what would change; skips Phase 6 and Phase 7.
   Output: [DRY-RUN MODE] banner; [ADDED]/[DIFFERENT] lines without writing.

4. Preserve local overrides
   $ bin/env-scan.sh --sync-values=false
   New vars are added to .env.local (Phase 6) but existing values are kept.
   Useful when .env.local has machine-specific values that differ from .env defaults.

5. Multi-source merge
   $ bin/env-scan.sh --source-files=".env .env.extra"
   Both source files are merged. First definition wins for duplicates.
   Propagation runs once per source file.

6. Suppress Dockerfile propagation
   $ bin/env-scan.sh --scan-sources=false
   Phases 3 and 7 are skipped. Only .env.local is updated.

7. Prune removed vars
   $ bin/env-scan.sh --prune-removed=true
   Vars present in .env.local but absent from all source files are removed.
   Protected by --orphan-ignore-pattern.

SCENARIOS_EOF
  fi

  return 0
}
