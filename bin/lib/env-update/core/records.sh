#!/bin/bash
# records.sh — indexed flat-variable record model + accessor API for env-update.
#
# Exports:   _gs_eu2_record_fields  _gs_eu2_record_new
#            _gs_eu2_record_set  _gs_eu2_record_get  _gs_eu2_record_count
# Sources:   none
# Deps:      bash 4.3+ (printf -v for dynamic variable assignment)
# Env:       _GS_EU2_REC_COUNT (global counter), _GS_EU2_LAST_IDX (last allocated index)
#
# Storage model: each field of record N is stored as a flat bash variable
#   _GS_EU2_REC_<N>_<field>.  This avoids associative arrays (which have
#   subshell visibility issues) and nested arrays (which bash doesn't support).
#
# Usage:
#   _gs_eu2_record_new          # allocates next index → _GS_EU2_LAST_IDX
#   _gs_eu2_record_set N f val  # write field f of record N
#   _gs_eu2_record_get N f      # echo field f of record N (empty string if unset)
#   _gs_eu2_record_count        # echo total number of records allocated

[[ -n "${_GS_EU2_RECORDS_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_RECORDS_SH_LOADED=1

_GS_EU2_REC_COUNT=0
_GS_EU2_LAST_IDX=0

# _gs_eu2_record_fields — emit the canonical ordered list of record field names.
#
# Args:    none
# Prints:  one field name per line (used by dump.sh to serialize all fields)
# Returns: 0 always
#
# Adding a new field: add one name here + one dispatch line in parse.sh
# (_gs_eu2_dispatch_flag or the inline AWAITING_VARIABLE block).
# version_prefix: re-prepended to proposed_version in dockerhub.sh after
#   tag-strip-prefix removes it.
_gs_eu2_record_fields() {
  printf '%s\n' \
    env_var current_version type identifier major_hint \
    override manual \
    channel skip_reason lock_reason \
    version_prefix \
    prefer_specific check_tags \
    tag_filter tag_exclude tag_strip_prefix tag_strip_suffix \
    tag_channel_prefix \
    tag_extract tag_replace_from tag_replace_to tag_suffix \
    fetch_extract fetch_json \
    url_probe url_probe_depth \
    git_repo depends_on urls \
    git_fallback_url git_fallback_sha \
    hint note line_number raw_annotation \
    proposed_version decision error_message alt_version \
    annotation_sha proposed_sha use_sha \
    proposed_sha_date annotation_sha_date \
    unstable_proposed stable_proposed \
    watch_major_depth latest_unconstrained actual_var_value \
    major_hint_min using_fallback_major \
    replace_targets replace_templates
}

# _gs_eu2_record_new — allocate the next record index.
#
# Args:    none
# Sets:    _GS_EU2_LAST_IDX (new index), _GS_EU2_REC_COUNT (incremented)
# Prints:  nothing
# Returns: 0 always
#
# MUST run in the main shell (not a subshell) so _GS_EU2_REC_COUNT persists.
# Callers retrieve the new index via _GS_EU2_LAST_IDX immediately after.
_gs_eu2_record_new() {
  _GS_EU2_LAST_IDX="${_GS_EU2_REC_COUNT}"
  (( _GS_EU2_REC_COUNT++ )) || true
}

# _gs_eu2_record_set — write a field value to a record.
#
# Args:    $1 index — 0-based record index
#          $2 field — field name (from _gs_eu2_record_fields)
#          $3 value — value to store (may be empty string)
# Prints:  nothing
# Returns: 0 always
# Side fx: writes _GS_EU2_REC_<index>_<field> via printf -v
_gs_eu2_record_set() {
  local _idx="${1}" _field="${2}" _value="${3}"
  printf -v "_GS_EU2_REC_${_idx}_${_field}" '%s' "${_value}"
}

# _gs_eu2_record_get — read a field value from a record.
#
# Args:    $1 index — 0-based record index
#          $2 field — field name (from _gs_eu2_record_fields)
# Prints:  field value, or empty string if never set (silent-empty contract)
# Returns: 0 always
#
# Silent-empty contract: an unset field returns "" with exit 0, not an error.
# Callers use [[ -n "$(...)" ]] to distinguish set-to-empty from never-set.
# This is intentional — record fields are sparse; not all records use all fields.
_gs_eu2_record_get() {
  local _idx="${1}" _field="${2}"
  local _varname="_GS_EU2_REC_${_idx}_${_field}"
  printf '%s' "${!_varname:-}"
}

# _gs_eu2_record_count — return the number of records allocated so far.
#
# Args:    none
# Prints:  _GS_EU2_REC_COUNT (integer)
# Returns: 0 always
_gs_eu2_record_count() {
  printf '%s' "${_GS_EU2_REC_COUNT}"
}
