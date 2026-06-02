#!/bin/bash
# passes.sh — shared second-pass fetch helpers for unstable=info and stable=info modes.
#
# Exports:   _gs_eu2_run_second_passes
# Sources:   core/records.sh  core/semver.sh  (resolved at call time via main.sh)
# Deps:      bash 4.3+
# Env:       _GS_EU2_CFG (associative array — read for unstable/stable flags)
#            _GS_EU2_REC_<N>_<field> (record flat vars — read/written via record_get/set)
#
# Design: both the serial path (_gs_eu2_run_check) and the parallel worker
# (_gs_eu2_fetch_one_worker) perform the same two second-pass fetches:
#   1. --unstable=info : swap channel→unstable, refetch, capture unstable_proposed
#   2. --stable=info   : swap channel→stable,   refetch, capture stable_proposed
#
# Extracting here eliminates the duplication while keeping the logic in one place.
# Both callers pass their record index; the function reads/writes record fields
# through the standard record_get/record_set API so the subshell (worker) and
# the parent (serial) context are handled identically.

[[ -n "${_GS_EU2_PASSES_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_PASSES_SH_LOADED=1

# _gs_eu2_run_second_passes — run unstable=info and stable=info second-pass fetches.
#
# Args:    $1 record_index — 0-based record index to process
# Reads:   _GS_EU2_CFG[unstable], _GS_EU2_CFG[stable]
#          record fields: channel, proposed_version, decision, error_message
# Sets:    record fields: unstable_proposed (if applicable), stable_proposed (if applicable)
# Prints:  nothing
# Returns: 0 always
# Side fx: calls _gs_eu2_dispatch_fetcher twice (cache-warm — no extra HTTP on cache hit)
#
# Caller contract:
#   - _gs_eu2_dispatch_fetcher must already be defined (sourced by main.sh / worker inherit)
#   - _gs_eu2_record_get / _gs_eu2_record_set must be defined (sourced from records.sh)
#   - _gs_eu2_is_prerelease / _gs_eu2_semver_compare must be defined (from semver.sh)
_gs_eu2_run_second_passes() {
  local _sp_i="${1}"

  # --unstable=info second-pass: temporarily swap channel→unstable, re-run the
  # same fetcher (cache hit — no extra HTTP), capture proposed as unstable_proposed,
  # then restore proposed_version and decision to pre-pass values.
  # Only runs when: unstable=info, record channel is not already unstable,
  # and --stable=full is not active (mutual exclusivity belt-and-suspenders guard).
  if [[ "${_GS_EU2_CFG[unstable]:-}" == "info" && "${_GS_EU2_CFG[stable]:-}" != "full" ]]; then
    local _sp_ui_chan
    _sp_ui_chan="$(_gs_eu2_record_get "${_sp_i}" channel)"
    if [[ "${_sp_ui_chan}" != "unstable" ]]; then
      local _sp_ui_saved_prop _sp_ui_saved_decision _sp_ui_saved_err
      _sp_ui_saved_prop="$(_gs_eu2_record_get "${_sp_i}" proposed_version)"
      _sp_ui_saved_decision="$(_gs_eu2_record_get "${_sp_i}" decision)"
      _sp_ui_saved_err="$(_gs_eu2_record_get "${_sp_i}" error_message)"
      _gs_eu2_record_set "${_sp_i}" channel          "unstable"
      _gs_eu2_record_set "${_sp_i}" proposed_version ""
      _gs_eu2_record_set "${_sp_i}" decision         ""
      _gs_eu2_record_set "${_sp_i}" error_message    ""
      _gs_eu2_dispatch_fetcher "${_sp_i}"
      local _sp_ui_ver
      _sp_ui_ver="$(_gs_eu2_record_get "${_sp_i}" proposed_version)"
      _gs_eu2_record_set "${_sp_i}" channel          "${_sp_ui_chan}"
      _gs_eu2_record_set "${_sp_i}" proposed_version "${_sp_ui_saved_prop}"
      _gs_eu2_record_set "${_sp_i}" decision         "${_sp_ui_saved_decision}"
      _gs_eu2_record_set "${_sp_i}" error_message    "${_sp_ui_saved_err}"
      # Store unstable_proposed only if it's a prerelease, different from stable proposed,
      # AND genuinely newer than the stable proposed (not a backward step).
      if [[ -n "${_sp_ui_ver}" && "${_sp_ui_ver}" != "${_sp_ui_saved_prop}" ]] && \
         _gs_eu2_is_prerelease "${_sp_ui_ver}"; then
        local _sp_ui_store="true"
        if [[ -n "${_sp_ui_saved_prop}" ]]; then
          local _sp_ui_cmp
          _sp_ui_cmp="$(_gs_eu2_semver_compare "${_sp_ui_saved_prop}" "${_sp_ui_ver}")"
          # "older" means stable is older than unstable — i.e. unstable is genuinely newer
          [[ "${_sp_ui_cmp}" != "older" ]] && _sp_ui_store="false"
        fi
        [[ "${_sp_ui_store}" == "true" ]] && \
          _gs_eu2_record_set "${_sp_i}" unstable_proposed "${_sp_ui_ver}"
      fi
    fi
  fi

  # --stable=info second-pass: temporarily swap channel→stable, re-run the
  # same fetcher (cache hit — no extra HTTP), capture proposed as stable_proposed,
  # then restore proposed_version and decision to pre-pass values.
  # Only runs when: stable=info, record channel is not already stable/empty.
  if [[ "${_GS_EU2_CFG[stable]:-}" == "info" ]]; then
    local _sp_si_chan
    _sp_si_chan="$(_gs_eu2_record_get "${_sp_i}" channel)"
    if [[ -n "${_sp_si_chan}" && "${_sp_si_chan}" != "stable" ]]; then
      local _sp_si_saved_prop _sp_si_saved_decision _sp_si_saved_err
      _sp_si_saved_prop="$(_gs_eu2_record_get "${_sp_i}" proposed_version)"
      _sp_si_saved_decision="$(_gs_eu2_record_get "${_sp_i}" decision)"
      _sp_si_saved_err="$(_gs_eu2_record_get "${_sp_i}" error_message)"
      _gs_eu2_record_set "${_sp_i}" channel          "stable"
      _gs_eu2_record_set "${_sp_i}" proposed_version ""
      _gs_eu2_record_set "${_sp_i}" decision         ""
      _gs_eu2_record_set "${_sp_i}" error_message    ""
      _gs_eu2_dispatch_fetcher "${_sp_i}"
      local _sp_si_ver
      _sp_si_ver="$(_gs_eu2_record_get "${_sp_i}" proposed_version)"
      _gs_eu2_record_set "${_sp_i}" channel          "${_sp_si_chan}"
      _gs_eu2_record_set "${_sp_i}" proposed_version "${_sp_si_saved_prop}"
      _gs_eu2_record_set "${_sp_i}" decision         "${_sp_si_saved_decision}"
      _gs_eu2_record_set "${_sp_i}" error_message    "${_sp_si_saved_err}"
      # Store stable_proposed only if it's non-empty, not a prerelease,
      # and different from the main proposed (suppress when identical).
      if [[ -n "${_sp_si_ver}" && "${_sp_si_ver}" != "${_sp_si_saved_prop}" ]] && \
         ! _gs_eu2_is_prerelease "${_sp_si_ver}"; then
        _gs_eu2_record_set "${_sp_i}" stable_proposed "${_sp_si_ver}"
      fi
    fi
  fi
}
