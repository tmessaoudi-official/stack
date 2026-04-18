#!/bin/bash
# records.sh — indexed field record model + accessor API

[[ -n "${_GS_EU2_RECORDS_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_RECORDS_SH_LOADED=1

_GS_EU2_REC_COUNT=0
_GS_EU2_LAST_IDX=0

# Canonical field list — single source of truth.
# Adding a new field: add one name here + one dispatch line in parse.sh.
_gs_eu2_record_fields() {
  printf '%s\n' \
    env_var current_version type identifier major_hint \
    override manual propagate \
    channel skip_reason version_prefix \
    tag_filter tag_exclude tag_strip_prefix tag_strip_suffix \
    tag_extract tag_replace_from tag_replace_to tag_suffix \
    fetch_extract fetch_json \
    url_probe url_probe_depth \
    pecl_ref depends_on urls \
    git_fallback_url git_fallback_sha \
    hint line_number raw_annotation \
    proposed_version decision error_message
}

# Allocate next record index.
# Sets _GS_EU2_LAST_IDX (no subshell — counter increment must stay in main shell).
_gs_eu2_record_new() {
  _GS_EU2_LAST_IDX="${_GS_EU2_REC_COUNT}"
  (( _GS_EU2_REC_COUNT++ )) || true
}

_gs_eu2_record_set() {
  local _idx="${1}" _field="${2}" _value="${3}"
  printf -v "_GS_EU2_REC_${_idx}_${_field}" '%s' "${_value}"
}

_gs_eu2_record_get() {
  local _idx="${1}" _field="${2}"
  local _varname="_GS_EU2_REC_${_idx}_${_field}"
  printf '%s' "${!_varname:-}"
}

_gs_eu2_record_count() {
  printf '%s' "${_GS_EU2_REC_COUNT}"
}
