#!/bin/bash
# Pre-release version markers — centralized list of regex fragments.
# Each entry is a POSIX ERE fragment joined with | to build the detection regex.
# Add new markers here — they are automatically picked up by _gs_eu_is_prerelease.

set -eEuo pipefail

[[ -n "${_GS_EU_PRERELEASE_MARKERS_SH_LOADED:-}" ]] && return 0
readonly _GS_EU_PRERELEASE_MARKERS_SH_LOADED=1

# Fragments are matched against the LOWERCASED version string.
# Order does not matter — they are ORed together.
_GS_EU_PRERELEASE_MARKERS=(
  # === Standard SemVer / universal ===
  'alpha'
  'beta'
  'rc[0-9]*'
  'preview'
  'pre'
  'nightly'
  'edge'
  'canary'
  'snapshot'
  'experimental'
  'insiders'

  # === Python (PEP 440) ===
  '\.dev'
  '-dev'
  '[0-9]a[0-9]'
  '[0-9]b[0-9]'

  # === Maven / Java ===
  'milestone'
  '[.-]m[0-9]'
  '-cr[0-9]'
  '-ea'

  # === npm / Node.js ===
  '-next\.'
  'next'      # npm `next` dist-tag (standalone)
)
readonly _GS_EU_PRERELEASE_MARKERS

_GS_EU_PRERELEASE_REGEX="$( IFS='|'; echo "${_GS_EU_PRERELEASE_MARKERS[*]}" )"
readonly _GS_EU_PRERELEASE_REGEX
