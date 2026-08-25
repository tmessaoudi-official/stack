#!/bin/bash
# staleness.sh — freshness contract for date-bearing version schemes.
#
# Exports:   _gs_eu2_staleness_parse_days  _gs_eu2_staleness_extract_date
#            _gs_eu2_staleness_verdict  _gs_eu2_staleness_now
# Sources:   none (pure — the clock is injected by the caller)
# Deps:      perl, date (GNU coreutils)
# Env:       _GS_EU2_NOW_EPOCH (test seam — overrides the wall clock)
#
# WHY THIS EXISTS
#
# The downgrade guard in decide.sh only fires when a proposal sorts BELOW the
# current version. That catches an upstream source which falls behind, but it is
# blind to one which freezes AT the current value: proposed == current is
# classified "already latest" and reads as up to date forever, with no signal.
#
# That is not hypothetical. nodejs.org stopped regenerating its HTML directory
# index on 2026-04-17 while the tarballs stayed live; the scraper kept working
# perfectly and kept returning the newest entry the frozen page still listed.
# It surfaced only because the frozen value happened to sort BELOW the pin. Had
# it frozen one day after the pin was written, nothing would have said a word.
#
# The check is OPT-IN via (stale-after:Nd) because it is only meaningful for a
# version scheme that carries its own date — nightly, canary and snapshot
# builds. A stable pin sitting still for months is normal, not stale, so
# applying this by default would flood the report with false positives and train
# the reader to ignore ERROR.
#
# No new I/O: the date is already inside the version string, and decide.sh
# already parses that exact shape to sort nightlies correctly.

[[ -n "${_GS_EU2_STALENESS_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_STALENESS_SH_LOADED=1

# _gs_eu2_staleness_now — current epoch seconds, honouring the test seam.
#
# Args:    none
# Reads:   _GS_EU2_NOW_EPOCH
# Prints:  epoch seconds
# Returns: 0 always
#
# A fixture's dates age in real time, so any test asserting freshness would
# eventually fail on a clock it does not control. The seam makes that
# impossible rather than unlikely.
_gs_eu2_staleness_now() {
  if [[ -n "${_GS_EU2_NOW_EPOCH:-}" ]]; then
    printf '%s' "${_GS_EU2_NOW_EPOCH}"
    return 0
  fi
  date +%s
}

# _gs_eu2_staleness_parse_days — validate a (stale-after:) value and return days.
#
# Args:    $1 value — the flag value, e.g. "7d"
# Prints:  the day count on success; nothing on failure
# Returns: 0 when valid, 1 when malformed
#
# Only whole days, only a positive count. "0d" is REFUSED rather than treated as
# "always stale" or "disabled": a freshness contract that can never hold, or can
# never fire, is a disabled feature wearing a configured one's clothes. Same
# asymmetry the (skip:)/(lock:) empty-reason parse error already applies.
_gs_eu2_staleness_parse_days() {
  local _v="${1}"
  [[ "${_v}" =~ ^[1-9][0-9]*d$ ]] || return 1
  printf '%s' "${_v%d}"
}

# _gs_eu2_staleness_extract_date — pull the YYYYMMDD a version string carries.
#
# Args:    $1 version — e.g. "v27.0.0-nightly202608254b5e86c4e2"
# Prints:  the 8-digit date on success; nothing when the string carries none
# Returns: 0 when a date was found AND is a real calendar date, 1 otherwise
#
# Deliberately reuses decide.sh's anchored shape — 8 digits followed by a hex
# run to end of string — rather than scanning for any 8 digits. A bare scan
# would match the "20260825" inside an unrelated build number, and one
# date-shape with one implementation is the whole point.
#
# `date -d` is the validator: a capture that is not a real calendar date (a
# 13th month, a 32nd day) is treated as "no date", which routes to the
# undateable ERROR rather than silently computing an age from nonsense.
_gs_eu2_staleness_extract_date() {
  local _ver="${1}" _d
  _d="$(printf '%s' "${_ver}" | perl -ne 'print "$1\n" if /(\d{8})[0-9a-fA-F]+$/' 2>/dev/null || true)"
  [[ -n "${_d}" ]] || return 1
  date -d "${_d}" +%s >/dev/null 2>&1 || return 1
  printf '%s' "${_d}"
}

# _gs_eu2_staleness_verdict — decide whether a proposed version is too old.
#
# Args:    $1 stale_after — raw flag value (e.g. "7d"); empty means no contract
#          $2 proposed    — proposed_version (may be empty)
#          $3 now_epoch   — current time, injected so this stays pure
# Prints:  empty when fresh or not applicable; the error message when stale or
#          when the contract cannot be evaluated
# Returns: 0 always (the message, not the exit code, is the signal)
#
# Empty proposed is NOT stale: that record's fetch failed and already carries
# its own error. Reporting a freeze on top would misdiagnose a transport
# failure as an upstream one.
#
# A future-dated version is fresh (negative age). The bias is always toward not
# firing — a false ERROR trains the reader to ignore the channel, which costs
# more than the missed detection it was meant to prevent.
_gs_eu2_staleness_verdict() {
  local _stale_after="${1}" _proposed="${2}" _now="${3}"
  local _days _date _then _age

  [[ -n "${_stale_after}" ]] || return 0
  [[ -n "${_proposed}" ]] || return 0

  if ! _days="$(_gs_eu2_staleness_parse_days "${_stale_after}")"; then
    printf 'stale-after: malformed threshold %s (expected Nd, e.g. 7d)' "${_stale_after}"
    return 0
  fi

  if ! _date="$(_gs_eu2_staleness_extract_date "${_proposed}")"; then
    printf 'stale-after: %s declares a freshness contract but %s carries no date — the version scheme changed, or the flag is on the wrong record' \
      "${_stale_after}" "${_proposed}"
    return 0
  fi

  _then="$(date -d "${_date}" +%s)"
  _age=$(((_now - _then) / 86400))

  if ((_age > _days)); then
    printf 'upstream appears frozen: newest is %s, %s days old (threshold %s) — the source is still answering, so this is not a fetch failure' \
      "${_date}" "${_age}" "${_stale_after}"
  fi
  return 0
}
