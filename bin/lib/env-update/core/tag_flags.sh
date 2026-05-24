#!/bin/bash
# tag_flags.sh — apply tag annotation flags to a tag list (filter, strip, extract, replace).
#
# Exports:   _gs_eu2_is_floating_tag  _gs_eu2_filter_specific_tags
#            _gs_eu2_apply_tag_flags  _gs_eu2_apply_tag_flags_from_record
# Sources:   none
# Deps:      perl (for tag-extract regex capture groups)
# Env:       none
#
# Tag flags (from @todo annotation, applied in pipeline order):
#   (tag-filter:REGEX)        — keep only tags matching ERE
#   (tag-exclude:REGEX)       — drop tags matching ERE
#   (tag-extract:PERL_REGEX)  — apply perl capture group $1; discard non-matching
#   (tag-strip-prefix:STR)    — strip literal prefix from each tag
#   (tag-strip-suffix:STR)    — strip literal suffix from each tag
#   (tag-replace:FROM:TO)     — replace literal substring in each tag

[[ -n "${_GS_EU2_TAG_FLAGS_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_TAG_FLAGS_SH_LOADED=1

# _gs_eu2_is_floating_tag — test whether a tag's numeric prefix is under-specified.
#
# Args:    $1 tag — tag string to test (e.g. "9.1-alpine3.23", "9.0.4-alpine3.23")
# Prints:  nothing
# Returns: 0 if floating (fewer than 2 dots in numeric prefix); 1 if specific
#
# A floating tag silently re-points when patches are released (e.g. "9.1" always
# points to the latest 9.1.x patch).  This function is used to filter floating
# tags when (prefer-specific) is set on an annotation.
#
# Algorithm: strip from first non-numeric/non-dot char to isolate the numeric
# prefix, then count dots.  Two or more dots → specific (X.Y.Z form).
# Returns 0 if a tag is "floating" — i.e. its numeric prefix has fewer than two
# dots (X or X.Y form), making it a tag that silently re-points when patches
# are released.  X.Y.Z, X.Y.Z-rcN, X.Y.Z-suffix are all specific (not floating).
#
# Algorithm: strip everything from the first non-numeric, non-dot character to
# isolate the numeric prefix, then count dots.  Two or more dots → specific.
# Zero or one dot → floating.
#
# Examples:
#   9.1-alpine3.23      → np=9.1   → 1 dot  → floating  (returns 0)
#   9-alpine3.23        → np=9     → 0 dots → floating  (returns 0)
#   9.0.4-alpine3.23    → np=9.0.4 → 2 dots → specific  (returns 1)
#   9.1.0-rc2-alpine3.23 → np=9.1.0 → 2 dots → specific  (returns 1)
#   9.1                 → np=9.1   → 1 dot  → floating  (returns 0)
#   9.0.4               → np=9.0.4 → 2 dots → specific  (returns 1)
_gs_eu2_is_floating_tag() {
  local _tag="${1}"
  local _np="${_tag%%[!0-9.]*}" # strip from first non-numeric/non-dot char
  _np="${_np%.}"                # strip trailing dot if any
  local _dots="${_np//[^.]/}"   # remove everything except dots
  ((${#_dots} < 2))             # true (returns 0) when fewer than 2 dots → floating
}

# _gs_eu2_filter_specific_tags — filter stdin tag list to only specific (non-floating) tags.
#
# Args:    none (reads from stdin)
# Prints:  tags whose numeric prefix has at least two dots (X.Y.Z form)
# Returns: 0 always
# Side fx: none
#
# Used when the (prefer-specific) annotation flag is set.
_gs_eu2_filter_specific_tags() {
  local _tag
  while IFS= read -r _tag; do
    [[ -z "${_tag}" ]] && continue
    _gs_eu2_is_floating_tag "${_tag}" || printf '%s\n' "${_tag}"
  done
}

# _gs_eu2_apply_tag_flags — apply annotation tag flags to a stdin tag list.
#
# Args:    $1 tag_filter       — ERE: keep only matching tags (empty = no filter)
#          $2 tag_exclude      — ERE: drop matching tags (empty = no exclusion)
#          $3 tag_strip_prefix — literal prefix to strip from each tag
#          $4 tag_strip_suffix — literal suffix to strip from each tag
#          $5 tag_extract      — perl regex: apply capture group 1; discard non-matching
#          $6 tag_replace_from — literal substring to replace
#          $7 tag_replace_to   — replacement string for $6
# Reads:   stdin (newline-separated tag list)
# Prints:  processed tag list (one per line, empty lines discarded)
# Returns: 0 always
#
# Pipeline order: filter → exclude → extract → strip-prefix → strip-suffix → replace.
# Any all-empty-string tag after processing is discarded.
_gs_eu2_apply_tag_flags() {
  local _tf="${1:-}" _te="${2:-}" _tsp="${3:-}" _tss="${4:-}"
  local _tex="${5:-}" _trf="${6:-}" _trt="${7:-}"
  local _tag

  while IFS= read -r _tag; do
    [[ -z "${_tag}" ]] && continue
    [[ -n "${_tf}" ]] && { [[ "${_tag}" =~ ${_tf} ]] || continue; }
    [[ -n "${_te}" ]] && { [[ "${_tag}" =~ ${_te} ]] && continue; }
    if [[ -n "${_tex}" ]]; then
      local _x
      _x="$(printf '%s\n' "${_tag}" \
        | perl -ne "if (/${_tex}/) { print \"\$1\n\" }" 2>/dev/null || true)"
      [[ -z "${_x}" ]] && continue
      _tag="${_x}"
    fi
    [[ -n "${_tsp}" ]] && _tag="${_tag#"${_tsp}"}"
    [[ -n "${_tss}" ]] && _tag="${_tag%"${_tss}"}"
    [[ -n "${_trf}" ]] && _tag="${_tag//"${_trf}"/"${_trt}"}"
    [[ -n "${_tag}" ]] && printf '%s\n' "${_tag}"
  done
}

# _gs_eu2_apply_tag_flags_from_record — apply tag flags using all fields from a record.
#
# Args:    $1 record_idx — 0-based record index
# Reads:   record fields: tag_filter, tag_exclude, tag_strip_prefix,
#          tag_strip_suffix, tag_extract, tag_replace_from, tag_replace_to
#          (reads from stdin, passes to _gs_eu2_apply_tag_flags)
# Prints:  processed tag list (one per line)
# Returns: 0 always
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
