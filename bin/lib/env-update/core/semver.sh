#!/bin/bash
# semver.sh — version comparison, pre-release detection, and prefix extraction.
#
# Exports:   _gs_eu2_is_prerelease  _gs_eu2_is_unversioned
#            _gs_eu2_semver_compare  _gs_eu2_semver_delta
#            _gs_eu2_version_prefix  _gs_eu2_version_tag_suffix
#            _gs_eu2_version_keys  _gs_eu2_version_sort  _gs_eu2_version_older
# Sources:   config/prerelease_markers.sh
# Deps:      sort -V (uutils or GNU coreutils — both order '~' first), perl, sed, grep
# Env:       _GS_EU2_PRERELEASE_REGEX, _GS_EU2_PRERELEASE_MARKERS,
#            _GS_EU2_PRERELEASE_RANKS (from prerelease_markers.sh)
#
# All functions are pure (no side effects, no globals written).
# Ordering goes through _gs_eu2_version_sort / _gs_eu2_version_older, never a raw
# `sort -V`: raw sort -V is byte-wise (RC-2 before beta-3) and misorders mixed
# v-prefix/no-prefix inputs (v0.3.0 after 1.0.0). Row 48.

[[ -n "${_GS_EU2_SEMVER_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_SEMVER_SH_LOADED=1

# shellcheck source=./../config/prerelease_markers.sh
source "$(dirname "${BASH_SOURCE[0]}")/../config/prerelease_markers.sh"

# _gs_eu2_is_prerelease — test whether a version string looks like a pre-release.
#
# Args:    $1 version — version string to test (case-insensitively matched)
# Prints:  nothing
# Returns: 0 if the version contains a prerelease marker; 1 otherwise
# Note:    matching is against _GS_EU2_PRERELEASE_REGEX from prerelease_markers.sh
# Note:    a git sha (7-40 hex, bare or after '@') is never a pre-release: the PEP 440
#          markers [0-9]a[0-9] / [0-9]b[0-9] match inside hex (5836579db73ac959b9f…),
#          which classified 5 of the 6 (use-sha) pins as pre-releases (row 48).
_gs_eu2_is_prerelease() {
  local _v="${1,,}"
  [[ "${_v}" =~ (^|@)[0-9a-f]{7,40}$ ]] && return 1
  [[ "${_v}" =~ (${_GS_EU2_PRERELEASE_REGEX}) ]]
}

# _gs_eu2_version_keys — emit a ranked sort key for every version on stdin.
#
# Reads:   newline-separated version strings on stdin (empty lines dropped)
# Prints:  "KEY<TAB>ORIGINAL" per line, input order
# Returns: 0 always
#
# Raw `sort -V` compares bytes, so 6.0.0-RC-2 (R = 0x52) sorted before 6.0.0-beta-3
# (b = 0x62), and lowercasing alone ranks snapshot above rc (row 48). A PRE-RELEASE
# (same test as _gs_eu2_is_prerelease) with a numeric base gets the key
#   base~<tier><lowercased suffix, date+sha tail cut to the date>
# and `sort -V` orders '~' before end-of-string, so every pre-release sorts below its
# own stable base, by tier, then by the rest of the suffix (rc-2 < rc-10). Every
# OTHER string keeps key == input minus a leading 'v', so its order is exactly the
# previous `sort -V` order — t126a pins that. One perl pass; the marker table
# reaches perl through %ENV (never an interpolated regex, never `awk -v`, which
# collapses the '\.' in the fragments; mawk also lacks the {7,40} interval).
_gs_eu2_version_keys() {
  GS_EU2_PR_MARKERS="$(printf '%s\n' "${_GS_EU2_PRERELEASE_MARKERS[@]}")" \
  GS_EU2_PR_RANKS="${_GS_EU2_PRERELEASE_RANKS[*]}" \
    perl -ne '
      BEGIN {
        @q = map { qr/$_/ } split /\n/, $ENV{GS_EU2_PR_MARKERS};
        @r = split / /, $ENV{GS_EU2_PR_RANKS};
      }
      chomp;
      next if $_ eq "";
      my $o = $_;
      (my $key = $o) =~ s/^v//;
      my $l = lc $key;
      if ($l !~ /(^|@)[0-9a-f]{7,40}$/ && $l =~ /^([0-9]+(?:\.[0-9]+)*)[-._]?(.+)$/) {
        my ($base, $suf) = ($1, $2);
        my $rank;
        for my $i (0 .. $#q) {
          $rank = $r[$i] if $l =~ $q[$i] && (!defined $rank || $r[$i] < $rank);
        }
        if (defined $rank) {
          $suf =~ s/(\d{8})[0-9a-f]+$/$1/;
          $key = "$base~$rank$suf";
        }
      }
      print "$key\t$o\n";
    '
}

# _gs_eu2_version_sort — sort versions ascending with pre-release ranking.
#
# Args:    $1 — optional "-u": keep one entry per distinct KEY (1.2.0 == v1.2.0,
#          1.3.0-RC1 == 1.3.0-rc1)
# Reads:   newline-separated version strings on stdin
# Prints:  the ORIGINAL strings, oldest first
# Returns: 0 always
_gs_eu2_version_sort() {
  local _u=()
  [[ "${1:-}" == "-u" ]] && _u=(-u)
  _gs_eu2_version_keys | sort -t $'\t' -k1,1V "${_u[@]}" | cut -f2-
}

# _gs_eu2_version_older — is $1 strictly older than $2 under the ranked order?
#
# Args:    $1 a, $2 b — version strings
# Returns: 0 when a sorts strictly before b; 1 when equal or newer
# Note:    "equal" means equal KEYS, not equal strings: 1.3.0-RC1 and 1.3.0-rc1 (or
#          1.2.0 and v1.2.0) are neither older than the other. Deliberate — they are
#          the same version, which is also why `_gs_eu2_version_sort -u` collapses them.
_gs_eu2_version_older() {
  [[ "${1}" == "${2}" ]] && return 1
  local _keys _ka _kb
  _keys="$(printf '%s\n%s\n' "${1}" "${2}" | _gs_eu2_version_keys | cut -f1)"
  _ka="${_keys%%$'\n'*}"
  _kb="${_keys#*$'\n'}"
  [[ "${_ka}" == "${_kb}" ]] && return 1
  [[ "$(printf '%s\n%s\n' "${_ka}" "${_kb}" | sort -V | head -1)" == "${_ka}" ]]
}

# _gs_eu2_is_unversioned — test whether a version string is a floating alias.
#
# Args:    $1 version — version string to test (case-insensitive)
# Prints:  nothing
# Returns: 0 for floating aliases (nightly, latest, edge, master, next, head,
#          main, stable, lts, current, release); 1 for concrete versions
#
# These floating aliases make semver comparison meaningless — decide.sh emits
# RESOLVED when the current is unversioned and a concrete proposed is available.
_gs_eu2_is_unversioned() {
  local _v="${1,,}"
  [[ "${_v}" =~ ^(nightly|latest|edge|master|next|head|main|stable|lts|current|release)$ ]]
}

# _gs_eu2_semver_compare — compare two version strings.
#
# Args:    $1 ver_a   — first version string
#          $2 ver_b   — second version string
#          $3 tcp     — optional channel prefix to strip before comparison (e.g. "dev-")
# Prints:  "older"  if ver_a < ver_b
#          "newer"  if ver_a > ver_b
#          "equal"  if ver_a == ver_b (after stripping v-prefix and channel prefix)
# Returns: 0 always
#
# Pre-release handling: 1.0.0-rc1 < 1.0.0 (pre-release sorts before stable), and
# markers rank by tier via _gs_eu2_version_older (6.0.0-beta-3 < 6.0.0-RC-2).
# A case/v-prefix variant pair with equal keys (1.3.0-RC1 / 1.3.0-rc1) prints
# "newer" in BOTH directions — the pair is one version; callers test "older".
# v-prefix is stripped before comparison; $3 is backward-compatible (omit → no-op).
_gs_eu2_semver_compare() {
  local _tcp="${3:-}"
  local _a="${1#v}" _b="${2#v}"
  if [[ -n "${_tcp}" ]]; then
    _a="${_a#"${_tcp}"}"
    _b="${_b#"${_tcp}"}"
  fi
  [[ "${_a}" == "${_b}" ]] && { echo "equal"; return 0; }

  local _a_base="${_a}" _b_base="${_b}"
  local _a_pre=false _b_pre=false
  if [[ "${_a}" =~ ^([0-9]+(\.[0-9]+)*)-([a-zA-Z]) ]]; then
    _a_base="${BASH_REMATCH[1]}"; _a_pre=true
  fi
  if [[ "${_b}" =~ ^([0-9]+(\.[0-9]+)*)-([a-zA-Z]) ]]; then
    _b_base="${BASH_REMATCH[1]}"; _b_pre=true
  fi
  if [[ "${_a_base}" == "${_b_base}" ]]; then
    if [[ "${_a_pre}" == "true" && "${_b_pre}" == "false" ]]; then
      echo "older"; return 0
    elif [[ "${_a_pre}" == "false" && "${_b_pre}" == "true" ]]; then
      echo "newer"; return 0
    fi
  fi

  # Ranked, not raw `sort -V`: RC-2 must outrank beta-3 (row 48).
  if _gs_eu2_version_older "${_a}" "${_b}"; then echo "older"; else echo "newer"; fi
}

# _gs_eu2_version_tag_suffix — extract the variant tag suffix from a version string.
#
# Args:    $1 version — version string (e.g. "25.0.1-zulu", "8.5.2-alpine3.21")
# Prints:  the trailing "-SUFFIX" when the version has a non-numeric dash suffix;
#          empty string when no suffix or when only build metadata (+...)
# Returns: 0 always
#
# Used by (watch-major) unconstrained fetch to preserve variant suffixes when
# searching for newer major versions (e.g. always fetch -zulu, not plain).
#
# Examples:
#   "25.0.1-zulu"         → "-zulu"
#   "8.5.2-alpine3.21"   → "-alpine3.21"
#   "25.0.1+9-LTS"       → "" (build metadata, not a tag suffix)
#   "22.15.0"             → ""
_gs_eu2_version_tag_suffix() {
  local _v="${1}"
  # Strip build metadata (everything from +) — build metadata never appears in tag names
  local _no_meta="${_v%%+*}"
  # Extract the leading semver numeric portion: digits, dots, optionally v-prefix
  local _numeric_part
  _numeric_part="$(printf '%s' "${_no_meta}" | grep -oE '^v?[0-9]+(\.[0-9]+)*')"
  if [[ -z "${_numeric_part}" ]]; then
    printf ''
    return
  fi
  # Remainder after numeric part — only return if it starts with -
  local _remainder="${_no_meta#"${_numeric_part}"}"
  if [[ "${_remainder}" == -* ]]; then
    printf '%s' "${_remainder}"
  fi
}

# _gs_eu2_version_prefix — extract the first N dot-separated numeric segments.
#
# Args:    $1 version — version string (e.g. "25.0.1+9-LTS", "8.5.2-alpine3.21")
#          $2 depth   — number of segments to extract (default: 1)
# Prints:  N-segment prefix (e.g. depth=1 → "25"; depth=2 → "8.5"); empty if
#          the version has fewer numeric segments than requested
# Returns: 0 always
#
# Build metadata (+…) is stripped first.  Non-numeric dash suffixes (-LTS, -alpine)
# are stripped so "25.0.1+9-LTS" at depth 1 returns "25".  Date suffixes with
# leading digits (-20260108) are kept as they ARE numeric.
_gs_eu2_version_prefix() {
  local _version="${1}" _depth="${2:-1}"
  # Strip build metadata (everything after +)
  local _clean="${_version%%+*}"
  # Strip leading v-prefix (e.g. v24.14.0 → 24.14.0) so the first segment
  # passes the ^[0-9]+$ check even when the raw tag carries a v.
  _clean="${_clean#v}"
  # Strip pre-release / tag suffix starting with a dash followed by a non-digit
  # e.g. -LTS, -alpine, -rc1 → removed; -20260108 (date) → kept as it IS numeric
  _clean="$(printf '%s' "${_clean}" | sed 's/-[^0-9].*//')"
  # Extract the first _depth dot-separated numeric segments
  local _out="" _seg _remaining="${_clean}" _i=0
  while (( _i < _depth )); do
    _seg="${_remaining%%.*}"
    [[ "${_seg}" =~ ^[0-9]+$ ]] || break
    [[ -n "${_out}" ]] && _out+="."
    _out+="${_seg}"
    (( ++_i )) || true
    if [[ "${_remaining}" == *"."* ]]; then
      _remaining="${_remaining#*.}"
    else
      break
    fi
  done
  # Only output if we got the requested depth
  if (( _i == _depth )); then
    printf '%s' "${_out}"
  fi
}

# _gs_eu2_semver_delta — classify the semantic distance between two versions.
#
# Args:    $1 ver_a — first (current) version string
#          $2 ver_b — second (proposed) version string
# Prints:  "major" | "minor" | "patch" | "unknown"
# Returns: 0 always
#
# Special cases handled:
#   - path-like prefixes (e.g. "tags/2.4.66" → "2.4.66")
#   - codename-date style (e.g. ubuntu "resolute-20260108" → patch/major by codename prefix)
#   - date-SHA style (YYYYMMDD-sha8 or full 40-char SHA → always "patch")
#   - date versions (6+ digit pure numeric major → always "patch" for forward increments)
#   - Ruby underscore separators (3_4_9 → 3.4.9)
_gs_eu2_semver_delta() {
  local _a="${1#v}" _b="${2#v}"
  [[ -z "${_a}" || -z "${_b}" ]] && { echo "unknown"; return; }

  # Strip path-like prefix (e.g. "tags/2.4.66" → "2.4.66", "refs/heads/v3" stays).
  # Matches <word>/<digit-led-version> — git refs style like "tags/", "branches/".
  [[ "${_a}" =~ ^[^0-9/][^/]*/([0-9].*)$ ]] && _a="${BASH_REMATCH[1]}"
  [[ "${_b}" =~ ^[^0-9/][^/]*/([0-9].*)$ ]] && _b="${BASH_REMATCH[1]}"

  # Codename-date style (e.g. ubuntu "resolute-20260108" → "resolute-20260413"):
  # both strings start with an alpha char → extract prefix up to first hyphen.
  # Same prefix (same codename) → patch.  Different prefix → major.
  if [[ "${_a}" =~ ^[^0-9] && "${_b}" =~ ^[^0-9] ]]; then
    local _ap="${_a%%-*}" _bp="${_b%%-*}"
    [[ "${_ap}" == "${_bp}" ]] && { echo "patch"; return; }
    echo "major"; return
  fi

  # Date-SHA style used by SHA-tracking annotations: YYYYMMDD-<sha8>  or full 40-char SHA.
  # Either operand matching means we are in commit-tracking mode — treat all
  # changes as patch so decide.sh emits AUTO instead of HOLD.
  local _date_sha_re='^[0-9]{8}-[0-9a-f]{8}$'
  local _sha40_re='^[0-9a-f]{40}$'
  if [[ "${_a}" =~ ${_date_sha_re} || "${_b}" =~ ${_date_sha_re} \
     || "${_a}" =~ ${_sha40_re}    || "${_b}" =~ ${_sha40_re} ]]; then
    echo "patch"; return
  fi

  # Normalize underscore separators (e.g. Ruby's 3_4_9 style) to dots
  _a="${_a//_/.}" _b="${_b//_/.}"

  local _am="${_a%%.*}" _bm="${_b%%.*}"

  # Date-version guard: if both major components are 6+ digit pure numerics
  # (YYYYMMDD, YYYYMM, or similar monotonic date stamps), treat any forward
  # increment as "patch" — these are not semantic major versions.
  # By the time we reach semver_delta, decide.sh has already verified _b >= _a
  # via _gs_eu2_version_older, so if both components are date-stamps we know it is a forward
  # increment and "patch" is correct.
  if [[ "${_am}" =~ ^[0-9]{6,}$ && "${_bm}" =~ ^[0-9]{6,}$ ]]; then
    echo "patch"; return
  fi

  [[ "${_am}" != "${_bm}" ]] && { echo "major"; return; }
  local _ar="${_a#*.}" _br="${_b#*.}"
  [[ "${_ar%%.*}" != "${_br%%.*}" ]] && { echo "minor"; return; }
  echo "patch"
}
