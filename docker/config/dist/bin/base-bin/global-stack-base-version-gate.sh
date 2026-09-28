#!/bin/bash
# Content-compare version gate — the ONE reinstall-on-bump decision for the stack.
#
# WHY THIS IS NOT IN THE PROLOGUE (do not inline it back):
#   caddy-bin/*, httpd-bin/*, nginx-bin/* and android-bin/global-stack-android-setup*.sh
#   are DELIBERATELY prologue-exempt — they keep their own stackCatch handler. Sourcing
#   the full prologue into them would swap that error handling, and re-implementing the
#   gate inline would give the stack two copies of the decision that must never disagree.
#   Extracting it here lets an exempt script source the gate ALONE.
#   See docs/plans/MASTER.plan.md Track 5, "Prologue-exemption collision rule".
#
# Sourced two ways, both supported:
#   source global-stack-base-version-gate.sh            # via PATH (/usr/local/bin)
#   source "${BASH_SOURCE[0]%/*}/global-stack-base-version-gate.sh"   # sibling, as the prologue does
#
# This file defines a function and nothing else: no `set` flags, no traps, no
# stackCatch. It is safe to source into a script that already has its own.

[[ -n "${_GS_VERSION_GATE_SH_LOADED:-}" ]] && return 0
readonly _GS_VERSION_GATE_SH_LOADED=1

# gs_version_gate <marker_path> <expected_value> [label]
#
# Content-compare gate for tools/versions/<marker> files. Emits ONE decision word
# on STDOUT — install | skip | reinstall — and, only on a real mismatch (marker
# exists but its content differs from <expected_value>), a loud WARN on STDERR.
#
#   install    marker absent            → first install, silent
#   skip       marker == expected       → up to date, silent
#   reinstall  marker != expected       → version changed, WARN + caller reinstalls
#
# What the marker holds is the manager-RESOLVED version, not the raw .env pin, so a
# caller must resolve before gating (pyenv/rbenv do; nvm deliberately does not — its
# resolver needs nvm sourced further down, pinned by startup-prologue.test.sh §22f).
#
# ERR-trap safe by contract: this runs sourced into `set -eE` with an ERR trap armed
# — the prologue's stackCatch, or an exempt script's own. Every path ends in
# `return 0` and the only comparison that can be false lives inside `if`, so the gate
# NEVER returns non-zero for a normal decision — a non-zero return would fire the
# caller's handler, write tools/errors/<token>, and mask the container as permanently
# unhealthy behind the 24h start_period. Pinned by §23g, which asserts zero ERR fires
# across all three decisions.
# Callers capture the decision (e.g. `dec="$(gs_version_gate ...)"`); the WARN
# goes to STDERR so it is never swallowed by the command substitution.
gs_version_gate() {
  local _gvg_marker="${1:-}" _gvg_expected="${2:-}" _gvg_label="${3:-${1:-marker}}"
  local _gvg_current

  if [[ ! -f "${_gvg_marker}" ]]; then
    printf 'install\n'
    return 0
  fi

  _gvg_current="$(cat "${_gvg_marker}" 2>/dev/null || true)"
  if [[ "${_gvg_current}" == "${_gvg_expected}" ]]; then
    printf 'skip\n'
    return 0
  fi

  printf 'WARN: %s version changed (marker=%s expected=%s) — reinstalling\n' \
    "${_gvg_label}" "${_gvg_current}" "${_gvg_expected}" >&2
  printf 'reinstall\n'
  return 0
}

# gs_version_in_use <versions_dir> <runtime> <own_label> <value>
#
# Emits `shared` on STDOUT when a version marker of <runtime> for a label OTHER than
# <own_label> records <value>, else `free`. A runtime's labels can share one install
# tree (fvm keeps flutter.3 and flutter.3.41.9 under one versions/ dir), so a cleanup
# must not drop an old version that another container still runs. pkg.* slot markers
# and the php.edge.build sidecar are not version markers and never count.
#
# Same ERR-trap contract as gs_version_gate: the answer is on STDOUT and every path
# returns 0, so a bare call cannot fire the caller's handler.
gs_version_in_use() {
  local _gviu_dir="${1:-}" _gviu_rt="${2:-}" _gviu_own="${3:-}" _gviu_value="${4:-}" _gviu_m
  for _gviu_m in "${_gviu_dir}/${_gviu_rt}."*; do
    case "${_gviu_m}" in
      "${_gviu_dir}/${_gviu_rt}.${_gviu_own}" | *.pkg.* | *.build) continue ;;
    esac
    if [[ -f "${_gviu_m}" && "$(cat "${_gviu_m}")" == "${_gviu_value}" ]]; then
      printf 'shared\n'
      return 0
    fi
  done
  printf 'free\n'
  return 0
}
