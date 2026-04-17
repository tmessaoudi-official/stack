#!/bin/bash
# Shared tag flag processing helper.
# Applies tag-filter, tag-exclude, tag-strip-prefix, tag-strip-suffix,
# tag-extract, tag-replace-from/to to a newline-separated list of tags.
#
# All fetchers that need tag flag processing should source this file and call
# _gs_eu_apply_tag_flags.

set -eEuo pipefail

# Include guard — safe to source multiple times
[[ -n "${_GS_EU_TAG_FLAGS_SH_LOADED:-}" ]] && return 0
readonly _GS_EU_TAG_FLAGS_SH_LOADED=1

# Apply tag flags to a newline-separated list of tags.
#
# Args (positional):
#   1  tag_filter       — keep only tags matching this ERE regex (empty = keep all)
#   2  tag_exclude      — drop tags matching this ERE regex (empty = drop none)
#   3  tag_strip_prefix — strip this literal prefix from each tag
#   4  tag_strip_suffix — strip this literal suffix from each tag
#   5  tag_extract      — extract capture group 1 via perl; discard non-matching
#   6  tag_replace_from — replace all occurrences of this literal in each tag
#   7  tag_replace_to   — replacement string (used with tag_replace_from)
#
# Reads tags from stdin (one per line), writes processed versions to stdout.
# Empty tags are silently dropped.
#
# Usage:
#   printf '%s\n' "${tags}" | _gs_eu_apply_tag_flags \
#     "${tag_filter}" "${tag_exclude}" "${tag_strip_prefix}" \
#     "${tag_strip_suffix}" "${tag_extract}" \
#     "${tag_replace_from}" "${tag_replace_to}"
_gs_eu_apply_tag_flags() {
  local tag_filter="${1:-}"
  local tag_exclude="${2:-}"
  local tag_strip_prefix="${3:-}"
  local tag_strip_suffix="${4:-}"
  local tag_extract="${5:-}"
  local tag_replace_from="${6:-}"
  local tag_replace_to="${7:-}"

  local tag

  while IFS= read -r tag; do
    [[ -z "${tag}" ]] && continue

    # tag-filter: keep only tags matching REGEX
    if [[ -n "${tag_filter}" ]]; then
      [[ "${tag}" =~ ${tag_filter} ]] || continue
    fi

    # tag-exclude: drop tags matching REGEX
    if [[ -n "${tag_exclude}" ]]; then
      [[ "${tag}" =~ ${tag_exclude} ]] && continue
    fi

    # tag-extract: extract capture group 1 via perl, discard non-matching
    if [[ -n "${tag_extract}" ]]; then
      local extracted
      extracted="$(printf '%s\n' "${tag}" | \
        perl -ne "if (/${tag_extract}/) { print \"\$1\n\" }" 2>/dev/null || true)"
      [[ -z "${extracted}" ]] && continue
      tag="${extracted}"
    fi

    # tag-strip-prefix: strip literal prefix
    if [[ -n "${tag_strip_prefix}" ]]; then
      tag="${tag#"${tag_strip_prefix}"}"
    fi

    # tag-strip-suffix: strip literal suffix
    if [[ -n "${tag_strip_suffix}" ]]; then
      tag="${tag%"${tag_strip_suffix}"}"
    fi

    # tag-replace: replace all occurrences of FROM with TO
    if [[ -n "${tag_replace_from}" ]]; then
      tag="${tag//"${tag_replace_from}"/"${tag_replace_to}"}"
    fi

    [[ -n "${tag}" ]] && printf '%s\n' "${tag}"
  done
}
