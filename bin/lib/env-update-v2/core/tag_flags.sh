#!/bin/bash
# tag_flags.sh — apply tag-filter/exclude/strip/extract/replace to a tag list

[[ -n "${_GS_EU2_TAG_FLAGS_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_TAG_FLAGS_SH_LOADED=1

# Apply tag flags to a newline-separated list of tags (reads from stdin).
# Args (positional, all optional/empty):
#   1 tag_filter        — keep only tags matching ERE regex
#   2 tag_exclude       — drop tags matching ERE regex
#   3 tag_strip_prefix  — strip literal prefix
#   4 tag_strip_suffix  — strip literal suffix
#   5 tag_extract       — perl capture group 1; discard non-matching
#   6 tag_replace_from  — literal substring to replace
#   7 tag_replace_to    — replacement string
_gs_eu2_apply_tag_flags() {
  local _tf="${1:-}" _te="${2:-}" _tsp="${3:-}" _tss="${4:-}"
  local _tex="${5:-}" _trf="${6:-}" _trt="${7:-}"
  local _tag

  while IFS= read -r _tag; do
    [[ -z "${_tag}" ]] && continue
    [[ -n "${_tf}"  ]] && { [[ "${_tag}" =~ ${_tf}  ]] || continue; }
    [[ -n "${_te}"  ]] && { [[ "${_tag}" =~ ${_te}  ]] && continue; }
    if [[ -n "${_tex}" ]]; then
      local _x
      _x="$(printf '%s\n' "${_tag}" | \
        perl -ne "if (/${_tex}/) { print \"\$1\n\" }" 2>/dev/null || true)"
      [[ -z "${_x}" ]] && continue
      _tag="${_x}"
    fi
    [[ -n "${_tsp}" ]] && _tag="${_tag#"${_tsp}"}"
    [[ -n "${_tss}" ]] && _tag="${_tag%"${_tss}"}"
    [[ -n "${_trf}" ]] && _tag="${_tag//"${_trf}"/"${_trt}"}"
    [[ -n "${_tag}" ]] && printf '%s\n' "${_tag}"
  done
}

# Convenience: apply tag flags from a record index
# $1 = record_idx, stdin = raw tag list, stdout = filtered list
_gs_eu2_apply_tag_flags_from_record() {
  local _idx="${1}"
  _gs_eu2_apply_tag_flags \
    "$(_gs_eu2_record_get "${_idx}" tag_filter)" \
    "$(_gs_eu2_record_get "${_idx}" tag_exclude)" \
    "$(_gs_eu2_record_get "${_idx}" tag_strip_prefix)" \
    "$(_gs_eu2_record_get "${_idx}" tag_strip_suffix)" \
    "$(_gs_eu2_record_get "${_idx}" tag_extract)" \
    "$(_gs_eu2_record_get "${_idx}" tag_replace_from)" \
    "$(_gs_eu2_record_get "${_idx}" tag_replace_to)"
}
