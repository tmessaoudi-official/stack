#!/bin/bash
# args.sh — CLI argument parser and validator; populates _GS_EU2_CFG associative array.
#
# Exports:   _gs_eu2_parse_args
# Sources:   config/defaults.sh  reporting/help.sh
# Deps:      bash 4.3+ (associative arrays), grep (ERE validation)
# Env:       _GS_EU2_CFG (associative array, declared in config/defaults.sh)
#
# _gs_eu2_parse_args:
#   1. Parse all CLI flags (while/case) into _GS_EU2_CFG
#   2. Fill missing keys with defaults
#   3. Validate regex args (--filter, --exclude) — exit 1 on invalid ERE
#   4. Validate mutual exclusivity (--dry-run/--apply, --stable=full/--unstable=full)
#   5. Validate confirmation gate for --force-auto --apply
#
# Note: --dry-run and --apply are now mutually exclusive. Previously --apply implied
# --dry-run when combined (v1 behaviour). The current model is: use --check --dry-run
# for preview, then --apply separately (the 30-min gate in main.sh enforces this).

[[ -n "${_GS_EU2_ARGS_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_ARGS_SH_LOADED=1

# shellcheck source=./../config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/defaults.sh"
# shellcheck source=./../reporting/help.sh
source "$(dirname "${BASH_SOURCE[0]}")/../reporting/help.sh"

# _gs_eu2_parse_args — parse CLI arguments and populate _GS_EU2_CFG.
#
# Args:    "$@" — all CLI arguments from bin/env-update.sh
# Reads:   nothing
# Sets:    _GS_EU2_CFG keys (all flags listed in the module header above)
# Prints:  error messages to stderr on invalid/missing arguments
# Returns: 0 on success; exits 1 on unknown flag or validation failure
_gs_eu2_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "${1}" in
      --version)
        printf '%s\n' "${_GS_EU2_VERSION}"
        exit 0
        ;;
      --help)
        _gs_eu2_show_help
        exit 0
        ;;
      --env-file=*)   _GS_EU2_CFG[env_file]="${1#*=}" ;;
      --filter=*)     _GS_EU2_CFG[filter]="${1#*=}" ;;
      --exclude=*)    _GS_EU2_CFG[exclude]="${1#*=}" ;;
      --dump)         _GS_EU2_CFG[dump]="true" ;;
      --format=*)     _GS_EU2_CFG[format]="${1#*=}" ;;
      --dry-run)      _GS_EU2_CFG[dry_run]="true" ;;
      --check)        _GS_EU2_CFG[check]="true" ;;
      --apply)        _GS_EU2_CFG[apply]="true" ;;
      --scan)         _GS_EU2_CFG[scan]="true" ;;
      --no-cache)     _GS_EU2_CFG[no_cache]="true" ;;
      --with-tags)    _GS_EU2_CFG[with_tags]="true" ;;
      --no-notes)       _GS_EU2_CFG[no_notes]="true" ;;
      --no-drift)       _GS_EU2_CFG[no_drift]="true" ;;
      --apply-resolve)  _GS_EU2_CFG[apply_resolve]="true" ;;
      --force-auto)     _GS_EU2_CFG[force_auto]="true" ;;
      --changes-only)   _GS_EU2_CFG[changes_only]="true" ;;
      --no-fail)        _GS_EU2_CFG[no_fail]="true" ;;
      --profile|--profile=true)  _GS_EU2_CFG[profile]="true" ;;
      --profile=false)           _GS_EU2_CFG[profile]="false" ;;
      --yes)          _GS_EU2_CFG[yes]="true" ;;
      --confirm=*)    _GS_EU2_CFG[confirm]="${1#*=}" ;;
      --backup=*)
        local _bval="${1#*=}"
        _GS_EU2_CFG[backup]="${_bval,,}"
        ;;
      --backup-purge=*)
        local _bpval="${1#*=}"
        _GS_EU2_CFG[backup_purge]="${_bpval,,}"
        ;;
      --backup-suffix=*)  _GS_EU2_CFG[backup_suffix]="${1#*=}" ;;
      --backup-keep=*)
        local _bkval="${1#*=}"
        if [[ ! "${_bkval}" =~ ^[0-9]+$ ]]; then
          printf 'env-update: --backup-keep requires a non-negative integer, got: %s\n' "${_bkval}" >&2
          exit 1
        fi
        _GS_EU2_CFG[backup_keep]="${_bkval}"
        ;;
      --reference)    _GS_EU2_CFG[reference]="true" ;;
      --reference=*)  _GS_EU2_CFG[reference_section]="${1#*=}"; _GS_EU2_CFG[reference]="true" ;;
      --tally)        _GS_EU2_CFG[tally]="auto" ;;
      --tally=*)
        local _tval="${1#*=}"
        if [[ "${_tval}" != "full" && "${_tval}" != "off" && "${_tval}" != "auto" ]]; then
          printf 'env-update: --tally accepts "auto", "full", or "off", got: %q\n' "${_tval}" >&2
          exit 1
        fi
        _GS_EU2_CFG[tally]="${_tval}" ;;
      --stable)     _GS_EU2_CFG[stable]="full" ;;
      --stable=*)
        local _sval="${1#*=}"
        if [[ "${_sval}" != "full" && "${_sval}" != "info" ]]; then
          printf 'env-update: --stable accepts "full" or "info", got: %q\n' "${_sval}" >&2
          exit 1
        fi
        _GS_EU2_CFG[stable]="${_sval}" ;;
      --unstable)     _GS_EU2_CFG[unstable]="full" ;;
      --unstable=*)
        local _uval="${1#*=}"
        if [[ "${_uval}" != "full" && "${_uval}" != "info" ]]; then
          printf 'env-update: --unstable accepts "full" or "info", got: %q\n' "${_uval}" >&2
          exit 1
        fi
        _GS_EU2_CFG[unstable]="${_uval}" ;;
      --jobs=*)
        local _jval="${1#*=}"
        if [[ ! "${_jval}" =~ ^[1-9][0-9]*$ ]]; then
          printf 'env-update: --jobs requires a positive integer, got: %q\n' "${_jval}" >&2
          exit 1
        fi
        _GS_EU2_CFG[jobs]="${_jval}" ;;
      --cache-ttl=*)
        local _ttl="${1#*=}"
        if [[ ! "${_ttl}" =~ ^[0-9]+$ ]]; then
          printf 'env-update: --cache-ttl requires a positive integer, got: %q\n' "${_ttl}" >&2
          exit 1
        fi
        _GS_EU2_CFG[cache_ttl]="${_ttl}" ;;
      *)
        printf 'env-update: unknown option: %s\n' "${1}" >&2
        exit 1
        ;;
    esac
    shift
  done

  [[ -z "${_GS_EU2_CFG[env_file]+set}" ]]  && _GS_EU2_CFG[env_file]="/stack/.env"
  [[ -z "${_GS_EU2_CFG[filter]+set}" ]]    && _GS_EU2_CFG[filter]=""
  [[ -z "${_GS_EU2_CFG[exclude]+set}" ]]   && _GS_EU2_CFG[exclude]=""
  [[ -z "${_GS_EU2_CFG[dump]+set}" ]]      && _GS_EU2_CFG[dump]="false"
  [[ -z "${_GS_EU2_CFG[format]+set}" ]]    && _GS_EU2_CFG[format]="text"
  [[ -z "${_GS_EU2_CFG[dry_run]+set}" ]]   && _GS_EU2_CFG[dry_run]="false"
  [[ -z "${_GS_EU2_CFG[check]+set}" ]]     && _GS_EU2_CFG[check]="false"
  [[ -z "${_GS_EU2_CFG[no_cache]+set}" ]]  && _GS_EU2_CFG[no_cache]="false"
  [[ -z "${_GS_EU2_CFG[with_tags]+set}" ]] && _GS_EU2_CFG[with_tags]="false"
  [[ -z "${_GS_EU2_CFG[apply]+set}" ]]    && _GS_EU2_CFG[apply]="false"
  [[ -z "${_GS_EU2_CFG[scan]+set}" ]]     && _GS_EU2_CFG[scan]="false"
  [[ -z "${_GS_EU2_CFG[cache_ttl]+set}" ]] && _GS_EU2_CFG[cache_ttl]="3600"
  [[ -z "${_GS_EU2_CFG[unstable]+set}" ]]  && _GS_EU2_CFG[unstable]=""
  [[ -z "${_GS_EU2_CFG[stable]+set}" ]]   && _GS_EU2_CFG[stable]=""
  [[ -z "${_GS_EU2_CFG[no_notes]+set}" ]]     && _GS_EU2_CFG[no_notes]="false"
  [[ -z "${_GS_EU2_CFG[no_drift]+set}" ]]     && _GS_EU2_CFG[no_drift]="false"
  [[ -z "${_GS_EU2_CFG[force_auto]+set}" ]]   && _GS_EU2_CFG[force_auto]="false"
  [[ -z "${_GS_EU2_CFG[changes_only]+set}" ]] && _GS_EU2_CFG[changes_only]="false"
  [[ -z "${_GS_EU2_CFG[no_fail]+set}" ]]    && _GS_EU2_CFG[no_fail]="false"
  [[ -z "${_GS_EU2_CFG[yes]+set}" ]]           && _GS_EU2_CFG[yes]="false"
  [[ -z "${_GS_EU2_CFG[confirm]+set}" ]]       && _GS_EU2_CFG[confirm]=""
  [[ -z "${_GS_EU2_CFG[profile]+set}" ]]       && _GS_EU2_CFG[profile]="false"
  [[ -z "${_GS_EU2_CFG[backup]+set}" ]]        && _GS_EU2_CFG[backup]="true"
  [[ -z "${_GS_EU2_CFG[backup_purge]+set}" ]]  && _GS_EU2_CFG[backup_purge]="false"
  [[ -z "${_GS_EU2_CFG[backup_suffix]+set}" ]] && _GS_EU2_CFG[backup_suffix]=".bak"
  [[ -z "${_GS_EU2_CFG[backup_keep]+set}" ]]   && _GS_EU2_CFG[backup_keep]="10"
  [[ -z "${_GS_EU2_CFG[apply_resolve]+set}" ]]      && _GS_EU2_CFG[apply_resolve]="false"
  [[ -z "${_GS_EU2_CFG[reference]+set}" ]]          && _GS_EU2_CFG[reference]="false"
  [[ -z "${_GS_EU2_CFG[reference_section]+set}" ]]  && _GS_EU2_CFG[reference_section]="all"
  [[ -z "${_GS_EU2_CFG[tally]+set}" ]]              && _GS_EU2_CFG[tally]="auto"
  [[ -z "${_GS_EU2_CFG[jobs]+set}" ]]               && _GS_EU2_CFG[jobs]="${_GS_EU2_JOBS_DEFAULT:-8}"

  # Validate --filter regex early: invalid ERE causes per-record bash errors and silent
  # empty output. type: prefixes are not regex — skip validation for those.
  # grep -E exits 0 (match), 1 (no match), or 2 (invalid regex) — we only reject exit 2.
  if [[ -n "${_GS_EU2_CFG[filter]}" && "${_GS_EU2_CFG[filter]}" != type:* ]]; then
    printf '' | grep -E "${_GS_EU2_CFG[filter]}" >/dev/null 2>&1 || {
      local _grep_rc=$?
      if [[ "${_grep_rc}" -ge 2 ]]; then
        printf 'env-update: invalid --filter regex: %s\n' "${_GS_EU2_CFG[filter]}" >&2
        exit 1
      fi
    }
  fi

  # Validate --exclude regex (same pattern: only reject grep exit code ≥ 2).
  if [[ -n "${_GS_EU2_CFG[exclude]}" ]]; then
    printf '' | grep -E "${_GS_EU2_CFG[exclude]}" >/dev/null 2>&1 || {
      local _excl_rc=$?
      if [[ "${_excl_rc}" -ge 2 ]]; then
        printf 'env-update: invalid --exclude regex: %s\n' "${_GS_EU2_CFG[exclude]}" >&2
        exit 1
      fi
    }
  fi

  if [[ "${_GS_EU2_CFG[apply_resolve]:-false}" == "true" && \
        "${_GS_EU2_CFG[apply]:-false}" != "true" ]]; then
    printf 'env-update: --apply-resolve requires --apply\n' >&2
    exit 1
  fi

  if [[ "${_GS_EU2_CFG[dry_run]}" == "true" && "${_GS_EU2_CFG[apply]}" == "true" ]]; then
    printf 'env-update: --dry-run and --apply are mutually exclusive — --apply implies actual writes; omit --dry-run\n' >&2
    exit 1
  fi

  if [[ "${_GS_EU2_CFG[stable]}" == "full" && "${_GS_EU2_CFG[unstable]}" == "full" ]]; then
    printf 'env-update: --stable=full and --unstable=full are mutually exclusive\n' >&2
    exit 1
  fi

  if [[ "${_GS_EU2_CFG[force_auto]}" == "true" && "${_GS_EU2_CFG[apply]}" == "true" ]]; then
    if [[ "${_GS_EU2_CFG[confirm]}" != "Confirm override" ]]; then
      printf 'FATAL: --force-auto --apply requires --confirm="Confirm override" to proceed.\n' >&2
      exit 1
    fi
  fi

  # Advisory: --force-auto has no write effect without --apply.
  # In --check mode it only affects how HOLD/MANUAL records are classified for display.
  # This notice helps users who meant to use --apply --force-auto.
  if [[ "${_GS_EU2_CFG[force_auto]}" == "true" && "${_GS_EU2_CFG[apply]}" != "true" ]]; then
    printf '[WARN] --force-auto has no write effect without --apply; did you mean --apply --dry-run --force-auto?\n' >&2
  fi

  return 0
}
