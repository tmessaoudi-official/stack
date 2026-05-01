#!/bin/bash
# prerelease_markers.sh — pre-release detection regex (ported from v1 verbatim)

[[ -n "${_GS_EU2_PRERELEASE_MARKERS_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_PRERELEASE_MARKERS_SH_LOADED=1

_GS_EU2_PRERELEASE_MARKERS=(
  # D5: Use [0-9.]* to match both rc1 and rc.1 patterns
  'alpha[0-9.]*' 'beta[0-9.]*' 'rc[0-9.]*' 'preview' 'pre'
  'nightly' 'edge' 'canary' 'snapshot' 'experimental' 'insiders'
  '\.dev' '-dev'
  '[0-9]a[0-9]' '[0-9]b[0-9]'
  'milestone' '[.-]m[0-9]' '-cr[0-9]' '-ea'
  '-next\.' 'next'
)
readonly _GS_EU2_PRERELEASE_MARKERS

_GS_EU2_PRERELEASE_REGEX="$( IFS='|'; echo "${_GS_EU2_PRERELEASE_MARKERS[*]}" )"
readonly _GS_EU2_PRERELEASE_REGEX
