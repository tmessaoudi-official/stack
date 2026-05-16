#!/bin/bash
# args.sh — CLI argument parser; populates _GS_EU2_CFG

[[ -n "${_GS_EU2_ARGS_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_ARGS_SH_LOADED=1

# shellcheck source=./../config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/defaults.sh"
# shellcheck source=./../reporting/help.sh
source "$(dirname "${BASH_SOURCE[0]}")/../reporting/help.sh"

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
      --dump)         _GS_EU2_CFG[dump]="true" ;;
      --format=*)     _GS_EU2_CFG[format]="${1#*=}" ;;
      --dry-run)      _GS_EU2_CFG[dry_run]="true" ;;
      --check)        _GS_EU2_CFG[check]="true" ;;
      --apply)        _GS_EU2_CFG[apply]="true" ;;
      --scan)         _GS_EU2_CFG[scan]="true" ;;
      --no-cache)     _GS_EU2_CFG[no_cache]="true" ;;
      --with-tags)    _GS_EU2_CFG[with_tags]="true" ;;
      --no-notes)     _GS_EU2_CFG[no_notes]="true" ;;
      --force-auto)   _GS_EU2_CFG[force_auto]="true" ;;
      --confirm=*)    _GS_EU2_CFG[confirm]="${1#*=}" ;;
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
  [[ -z "${_GS_EU2_CFG[no_notes]+set}" ]]   && _GS_EU2_CFG[no_notes]="false"
  [[ -z "${_GS_EU2_CFG[force_auto]+set}" ]] && _GS_EU2_CFG[force_auto]="false"
  [[ -z "${_GS_EU2_CFG[confirm]+set}" ]]    && _GS_EU2_CFG[confirm]=""

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

  if [[ "${_GS_EU2_CFG[dry_run]}" == "true" && "${_GS_EU2_CFG[apply]}" == "true" ]]; then
    printf 'env-update: --dry-run and --apply are mutually exclusive\n' >&2
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

  return 0
}
