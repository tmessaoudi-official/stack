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
      --no-cache)     _GS_EU2_CFG[no_cache]="true" ;;
      --cache-ttl=*)  _GS_EU2_CFG[cache_ttl]="${1#*=}" ;;
      *)
        printf 'env-update-v2: unknown option: %s\n' "${1}" >&2
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
  [[ -z "${_GS_EU2_CFG[cache_ttl]+set}" ]] && _GS_EU2_CFG[cache_ttl]="3600"
  return 0
}
