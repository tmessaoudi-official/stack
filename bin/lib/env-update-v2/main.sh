#!/bin/bash
# main.sh — orchestration

[[ -n "${_GS_EU2_MAIN_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_MAIN_SH_LOADED=1

# shellcheck source=./config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/config/defaults.sh"
# shellcheck source=./core/args.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/args.sh"
# shellcheck source=./core/records.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/records.sh"
# shellcheck source=./core/parse.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/parse.sh"
# shellcheck source=./core/cache.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/cache.sh"
# shellcheck source=./core/decide.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/decide.sh"
# shellcheck source=./fetchers/dockerhub.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/dockerhub.sh"
# shellcheck source=./reporting/help.sh
source "$(dirname "${BASH_SOURCE[0]}")/reporting/help.sh"
# shellcheck source=./reporting/dump.sh
source "$(dirname "${BASH_SOURCE[0]}")/reporting/dump.sh"
# shellcheck source=./reporting/summary.sh
source "$(dirname "${BASH_SOURCE[0]}")/reporting/summary.sh"
# shellcheck source=./reporting/stream.sh
source "$(dirname "${BASH_SOURCE[0]}")/reporting/stream.sh"

_gs_eu2_run_check() {
  local _count _i _type
  _count="$(_gs_eu2_record_count)"

  # Propagate cache settings from CFG to env vars consumed by cache.sh
  _GS_EU2_CACHE_TTL="${_GS_EU2_CFG[cache_ttl]:-3600}"

  for (( _i = 0; _i < _count; _i++ )); do
    _type="$(_gs_eu2_record_get "${_i}" type)"
    case "${_type}" in
      dockerhub) _gs_eu2_fetch_dockerhub "${_i}" ;;
      *)
        _gs_eu2_record_set "${_i}" decision      "SKIP"
        _gs_eu2_record_set "${_i}" error_message "fetcher '${_type}' not yet implemented (Phase 2 supports dockerhub only)"
        ;;
    esac

    # Apply decision classifier (refines any AUTO decision the fetcher set)
    local _cur _prop _override _manual _major _fetcher_decision
    _cur="$(_gs_eu2_record_get "${_i}" current_version)"
    _prop="$(_gs_eu2_record_get "${_i}" proposed_version)"
    _override="$(_gs_eu2_record_get "${_i}" override)"
    _manual="$(_gs_eu2_record_get "${_i}" manual)"
    _major="$(_gs_eu2_record_get "${_i}" major_hint)"
    _fetcher_decision="$(_gs_eu2_record_get "${_i}" decision)"

    if [[ "${_fetcher_decision}" == "AUTO" || -z "${_fetcher_decision}" ]]; then
      local _classified
      _classified="$(_gs_eu2_classify_decision "${_cur}" "${_prop}" "${_override}" "${_manual}" "${_major}")"
      _gs_eu2_record_set "${_i}" decision "${_classified}"
    fi
  done

  _gs_eu2_stream_records
}

_gs_eu2_main() {
  _gs_eu2_parse_args "${@}"

  if [[ "true" == "${_GS_EU2_CFG[dry_run]}" ]]; then
    printf 'env-update-v2: --dry-run active (Phase 2: gates cache writes; no .env writes yet)\n' >&2
  fi

  local _env_file="${_GS_EU2_CFG[env_file]}"
  if [[ ! -f "${_env_file}" ]]; then
    printf 'env-update-v2: env file not found: %s\n' "${_env_file}" >&2
    exit 1
  fi

  _gs_eu2_parse_env_file "${_env_file}" "${_GS_EU2_CFG[filter]}"

  if [[ "true" == "${_GS_EU2_CFG[dump]}" ]]; then
    _gs_eu2_dump_records "${_GS_EU2_CFG[format]}"
  elif [[ "true" == "${_GS_EU2_CFG[check]}" ]]; then
    _gs_eu2_run_check
  else
    _gs_eu2_print_summary "${_env_file}"
  fi
}
