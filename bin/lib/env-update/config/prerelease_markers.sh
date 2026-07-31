#!/bin/bash
# prerelease_markers.sh — pre-release detection regex for version classifier.
#
# Exports:   _GS_EU2_PRERELEASE_MARKERS (readonly array)
#            _GS_EU2_PRERELEASE_REGEX   (readonly joined ERE string)
# Sources:   none
# Deps:      bash 4.3+
# Env:       none (all output is readonly globals)
#
# PURPOSE
# -------
# _GS_EU2_PRERELEASE_MARKERS is an array of ERE fragments.  They are joined with
# '|' into _GS_EU2_PRERELEASE_REGEX and used (case-insensitively) to decide
# whether a version string is a pre-release.
#
# HOW PRERELEASE DETECTION WORKS
# --------------------------------
# A version is a pre-release if it matches: grep -iE "${_GS_EU2_PRERELEASE_REGEX}"
# Each marker fragment is matched against the full version string.  Fragments
# are anchored implicitly by the context they appear in (e.g. '3.9.0beta1'
# contains 'beta', matching the 'beta[0-9.]*' fragment).
#
# HOW TO ADD A NEW MARKER
# -------------------------
# 1. Add one ERE fragment to _GS_EU2_PRERELEASE_MARKERS below.
#    - Use [0-9.]* to match both "rcX" and "rc.X" variants.
#    - Use [.-] prefix to avoid false positives on substrings (e.g. '[.-]m[0-9]').
#    - Anchor with $ when the marker must appear at the very end ('-ea$' style).
# 2. Run `bash bin/tests/env-update.test.sh` — section 3 covers prerelease detection.
# 3. Add a test case to section 3 for the new marker (at minimum: one version
#    that SHOULD match and one that should NOT).
#
# EXAMPLE ENTRY:
#   '-milestone[0-9]*'   # matches "1.0.0-milestone3" but not "1.milestone.3"

[[ -n "${_GS_EU2_PRERELEASE_MARKERS_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_PRERELEASE_MARKERS_SH_LOADED=1

_GS_EU2_PRERELEASE_MARKERS=(
  # D5: Use [0-9.]* to match both rc1 and rc.1 patterns
  'alpha[0-9.]*' 'beta[0-9.]*' 'rc[0-9.]*' 'preview'
  # 'pre' and 'next' use word-boundary guards to prevent false positives on tags
  # like 'nextcloud-1.0' or '1.0.0-prepare'. Pattern: non-letter (or start) before
  # the word, non-letter (or end) after. [^a-zA-Z] used explicitly for grep -iE safety.
  # Bare 'next' (e.g. GLOBAL_STACK_PHPEDGE_VERSION=next) still matches via ^next$.
  '(^|[^a-zA-Z])pre([^a-zA-Z]|$)' '(^|[^a-zA-Z])next([^a-zA-Z]|$)'
  'nightly' 'edge' 'canary' 'snapshot' 'experimental' 'insiders'
  '\.dev' '-dev([0-9.]|$)'
  '[0-9]a[0-9]' '[0-9]b[0-9]'
  'milestone' '[.-]m[0-9]' '-cr[0-9]' '-ea'
  '-next\.' '-b\.' '-rc\.'
)
readonly _GS_EU2_PRERELEASE_MARKERS

_GS_EU2_PRERELEASE_REGEX="$( IFS='|'; echo "${_GS_EU2_PRERELEASE_MARKERS[*]}" )"
readonly _GS_EU2_PRERELEASE_REGEX
