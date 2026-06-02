#!/bin/bash
# parallel.sh — background fetch fan-out for env-update check loop.
#
# Exports:   _gs_eu2_fetch_one_worker
#            _GS_EU2_FETCH_OUTPUT_FIELDS (array)
# Sources:   records.sh  cache.sh  fetchers/*  core/channel.sh  core/semver.sh
# Deps:      bash 4.3+, mktemp, printf %q
# Env:       _GS_EU2_CFG (associative array — inherited via fork semantics)
#            _GS_EU2_REC_<N>_<field> (inherited via fork semantics)
#
# Design: each worker runs in a background subshell ( ) & that inherits all
# parent globals at fork time (read-only for the parent's perspective).
# Workers write ONLY the 10 output fields to a per-index result file in a
# shared tmpdir, using _gs_eu2_record_set calls quoted with printf %q so the
# parent can safely source the file back.
#
# Output fields — the complete set that fetchers + second-pass blocks write:
#   proposed_version  decision  error_message  alt_version
#   proposed_sha      proposed_sha_date
#   using_fallback_major  latest_unconstrained
#   unstable_proposed  stable_proposed

[[ -n "${_GS_EU2_PARALLEL_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_PARALLEL_SH_LOADED=1

# Canonical list of fields that fetchers and second-pass blocks write.
# MUST stay in sync with the grep-verified list from records.sh.
_GS_EU2_FETCH_OUTPUT_FIELDS=(
  proposed_version decision error_message alt_version
  proposed_sha proposed_sha_date
  using_fallback_major latest_unconstrained
  unstable_proposed stable_proposed
)

# _gs_eu2_fetch_one_worker — fetch one record and write results to a file.
#
# Args:    $1 record_index — 0-based record index to process
#          $2 result_dir   — directory where "$1.env" will be written
# Reads:   _GS_EU2_REC_<N>_* (all record fields, inherited via fork)
#          _GS_EU2_CFG (associative array, inherited via fork)
# Writes:  "$2/$1.env" — _gs_eu2_record_set calls for each output field
# Returns: 0 always (errors recorded as decision=ERROR in output file)
# Side fx: may write to the shared file cache (_GS_EU2_CACHE_DIR)
#
# Isolation: runs in a background subshell; any record_set calls modify only
# the subshell's own copy of the variables — the parent never sees them
# directly. The result file is the ONLY communication channel.
#
# Tally: suppressed — _GS_EU2_TALLY_ACTIVE is forced to 0 so workers do not
# attempt to draw to stderr (which would interleave with the parent's output).
_gs_eu2_fetch_one_worker() {
  local _wi="${1}"
  local _wr_dir="${2}"
  local _wr_file="${_wr_dir}/${_wi}.env"

  # Never draw tally in a worker — parent owns stderr during fan-out.
  _GS_EU2_TALLY_ACTIVE=0

  # Skip gate: if the record has a skip:REASON annotation, write SKIP and exit.
  # No HTTP fetch needed — the annotation already determined the outcome.
  local _skip_reason
  _skip_reason="$(_gs_eu2_record_get "${_wi}" skip_reason)"
  if [[ -n "${_skip_reason}" ]]; then
    {
      printf '_gs_eu2_record_set %d decision %s\n'      "${_wi}" "$(printf '%q' "SKIP")"
      printf '_gs_eu2_record_set %d error_message %s\n' "${_wi}" "$(printf '%q' "skip flag: ${_skip_reason}")"
    } > "${_wr_file}"
    return 0
  fi

  # Main dispatch — calls the type-specific fetcher (github, dockerhub, etc.).
  _gs_eu2_dispatch_fetcher "${_wi}"

  # --unstable=info second pass: mirror of the same block in _gs_eu2_run_check.
  # Runs in the worker so cache is warm for the second pass regardless of --dry-run.
  if [[ "${_GS_EU2_CFG[unstable]:-}" == "info" && "${_GS_EU2_CFG[stable]:-}" != "full" ]]; then
    local _info_chan
    _info_chan="$(_gs_eu2_record_get "${_wi}" channel)"
    if [[ "${_info_chan}" != "unstable" ]]; then
      local _saved_prop _saved_decision _saved_chan _saved_err
      _saved_prop="$(_gs_eu2_record_get "${_wi}" proposed_version)"
      _saved_decision="$(_gs_eu2_record_get "${_wi}" decision)"
      _saved_err="$(_gs_eu2_record_get "${_wi}" error_message)"
      _saved_chan="${_info_chan}"
      _gs_eu2_record_set "${_wi}" channel         "unstable"
      _gs_eu2_record_set "${_wi}" proposed_version ""
      _gs_eu2_record_set "${_wi}" decision         ""
      _gs_eu2_record_set "${_wi}" error_message    ""
      _gs_eu2_dispatch_fetcher "${_wi}"
      local _unstable_ver
      _unstable_ver="$(_gs_eu2_record_get "${_wi}" proposed_version)"
      _gs_eu2_record_set "${_wi}" channel          "${_saved_chan}"
      _gs_eu2_record_set "${_wi}" proposed_version "${_saved_prop}"
      _gs_eu2_record_set "${_wi}" decision         "${_saved_decision}"
      _gs_eu2_record_set "${_wi}" error_message    "${_saved_err}"
      if [[ -n "${_unstable_ver}" && "${_unstable_ver}" != "${_saved_prop}" ]] && \
         _gs_eu2_is_prerelease "${_unstable_ver}"; then
        local _ui_store="true"
        if [[ -n "${_saved_prop}" ]]; then
          local _ui_cmp
          _ui_cmp="$(_gs_eu2_semver_compare "${_saved_prop}" "${_unstable_ver}")"
          [[ "${_ui_cmp}" != "older" ]] && _ui_store="false"
        fi
        [[ "${_ui_store}" == "true" ]] && \
          _gs_eu2_record_set "${_wi}" unstable_proposed "${_unstable_ver}"
      fi
    fi
  fi

  # --stable=info second pass: mirror of the same block in _gs_eu2_run_check.
  if [[ "${_GS_EU2_CFG[stable]:-}" == "info" ]]; then
    local _si_chan
    _si_chan="$(_gs_eu2_record_get "${_wi}" channel)"
    if [[ -n "${_si_chan}" && "${_si_chan}" != "stable" ]]; then
      local _si_saved_prop _si_saved_decision _si_saved_err
      _si_saved_prop="$(_gs_eu2_record_get "${_wi}" proposed_version)"
      _si_saved_decision="$(_gs_eu2_record_get "${_wi}" decision)"
      _si_saved_err="$(_gs_eu2_record_get "${_wi}" error_message)"
      _gs_eu2_record_set "${_wi}" channel          "stable"
      _gs_eu2_record_set "${_wi}" proposed_version ""
      _gs_eu2_record_set "${_wi}" decision         ""
      _gs_eu2_record_set "${_wi}" error_message    ""
      _gs_eu2_dispatch_fetcher "${_wi}"
      local _stable_ver
      _stable_ver="$(_gs_eu2_record_get "${_wi}" proposed_version)"
      _gs_eu2_record_set "${_wi}" channel          "${_si_chan}"
      _gs_eu2_record_set "${_wi}" proposed_version "${_si_saved_prop}"
      _gs_eu2_record_set "${_wi}" decision         "${_si_saved_decision}"
      _gs_eu2_record_set "${_wi}" error_message    "${_si_saved_err}"
      if [[ -n "${_stable_ver}" && "${_stable_ver}" != "${_si_saved_prop}" ]] && \
         ! _gs_eu2_is_prerelease "${_stable_ver}"; then
        _gs_eu2_record_set "${_wi}" stable_proposed "${_stable_ver}"
      fi
    fi
  fi

  # Serialize all output fields to the result file using printf %q so multi-line
  # values, special chars, and empty strings all survive source() safely.
  {
    local _f _v
    for _f in "${_GS_EU2_FETCH_OUTPUT_FIELDS[@]}"; do
      _v="$(_gs_eu2_record_get "${_wi}" "${_f}")"
      printf '_gs_eu2_record_set %d %s %s\n' "${_wi}" "${_f}" "$(printf '%q' "${_v}")"
    done
  } > "${_wr_file}"
}
