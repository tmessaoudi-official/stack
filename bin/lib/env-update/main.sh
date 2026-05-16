#!/bin/bash
# main.sh — orchestration

[[ -n "${_GS_EU2_MAIN_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_MAIN_SH_LOADED=1

# shellcheck source=./config/defaults.sh
source "$(dirname "${BASH_SOURCE[0]}")/config/defaults.sh"
# shellcheck source=./core/args.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/args.sh"
# shellcheck source=./core/records.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/records.sh"
# shellcheck source=./core/parse.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/parse.sh"
# shellcheck source=./core/cache.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/cache.sh"
# shellcheck source=./core/decide.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/decide.sh"
# shellcheck source=./fetchers/github.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/github.sh"
# shellcheck source=./fetchers/codeberg.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/codeberg.sh"
# shellcheck source=./fetchers/dockerhub.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/dockerhub.sh"
# shellcheck source=./fetchers/quay.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/quay.sh"
# shellcheck source=./fetchers/npm.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/npm.sh"
# shellcheck source=./fetchers/pypi.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/pypi.sh"
# shellcheck source=./fetchers/rubygems.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/rubygems.sh"
# shellcheck source=./fetchers/sdkman.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/sdkman.sh"
# shellcheck source=./fetchers/sdkmanager.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/sdkmanager.sh"
# shellcheck source=./fetchers/pecl.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/pecl.sh"
# shellcheck source=./fetchers/url.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/url.sh"
# shellcheck source=./reporting/help.sh
source "$(dirname "${BASH_SOURCE[0]}")/reporting/help.sh"
# shellcheck source=./reporting/dump.sh
source "$(dirname "${BASH_SOURCE[0]}")/reporting/dump.sh"
# shellcheck source=./reporting/summary.sh
source "$(dirname "${BASH_SOURCE[0]}")/reporting/summary.sh"
# shellcheck source=./core/apply.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/apply.sh"

_gs_eu2_run_check() {
  local _count _i _type
  _count="$(_gs_eu2_record_count)"

  # Propagate cache settings from CFG to env vars consumed by cache.sh
  _GS_EU2_CACHE_TTL="${_GS_EU2_CFG[cache_ttl]:-3600}"

  local _n_auto=0 _n_hold=0 _n_skip=0 _n_error=0 _n_manual=0 _n_sha=0

  # Dynamic column width: pre-scan all env_var names so the → arrow aligns
  # across every record in this run, regardless of variable name length.
  local _max_var_len=40
  local _vl _j _vname _tmpval
  for (( _j = 0; _j < _count; _j++ )); do
    _vname="_GS_EU2_REC_${_j}_env_var"
    _tmpval="${!_vname:-}"
    _vl="${#_tmpval}"
    (( _vl > _max_var_len )) && _max_var_len="${_vl}"
  done

  for (( _i = 0; _i < _count; _i++ )); do
    local _env_var
    _env_var="$(_gs_eu2_record_get "${_i}" env_var)"

    # Progress indicator: show which record is being fetched (to stderr so it
    # doesn't mix with structured stdout, and is visible even when piped)
    printf '\r  [%d/%d] fetching %-55s' \
      "$(( _i + 1 ))" "${_count}" "${_env_var:0:55}" >&2

    # Skip gate: (skip:REASON) annotation forces SKIP before any fetch.
    # Sets decision + error_message on the record; display code below handles output.
    local _skip_reason
    _skip_reason="$(_gs_eu2_record_get "${_i}" skip_reason)"
    if [[ -n "${_skip_reason}" ]]; then
      _gs_eu2_record_set "${_i}" decision      "SKIP"
      _gs_eu2_record_set "${_i}" error_message "skip flag: ${_skip_reason}"
    fi

    _type="$(_gs_eu2_record_get "${_i}" type)"
    # Skip gate fires: bypass all fetcher dispatch and second-pass blocks.
    # The record already has decision=SKIP and error_message set; display code below handles output.
    if [[ -z "${_skip_reason}" ]]; then
      case "${_type}" in
        codeberg)  _gs_eu2_fetch_codeberg  "${_i}" ;;
        dockerhub) _gs_eu2_fetch_dockerhub "${_i}" ;;
        github)    _gs_eu2_fetch_github    "${_i}" ;;
        quay)      _gs_eu2_fetch_quay      "${_i}" ;;
        npm)        _gs_eu2_fetch_npm        "${_i}" ;;
        pypi)       _gs_eu2_fetch_pypi       "${_i}" ;;
        rubygems)   _gs_eu2_fetch_rubygems   "${_i}" ;;
        sdkman)     _gs_eu2_fetch_sdkman     "${_i}" ;;
        sdkmanager) _gs_eu2_fetch_sdkmanager "${_i}" ;;
        pecl)       _gs_eu2_fetch_pecl       "${_i}" ;;
        url)        _gs_eu2_fetch_url        "${_i}" ;;
        # All 11 fetcher types implemented:
        #   codeberg, dockerhub, github, quay   — fetchers/{codeberg,dockerhub,github,quay}.sh
        #   npm, pypi, rubygems                 — fetchers/{npm,pypi,rubygems}.sh
        #   sdkman, sdkmanager                  — fetchers/{sdkman,sdkmanager}.sh
        #   pecl                                — fetchers/pecl.sh (use git:owner/repo flag for SHA tracking)
        #   url                                 — fetchers/url.sh + core/ubuntu.sh
        *)
          _gs_eu2_record_set "${_i}" decision      "SKIP"
          _gs_eu2_record_set "${_i}" error_message "unknown fetcher type '${_type}' — check annotation syntax"
          ;;
      esac

    # --unstable=info second-pass: temporarily swap channel→unstable, re-run the
    # same fetcher (cache hit — no extra HTTP), capture proposed as unstable_proposed,
    # then restore proposed_version and decision to pre-pass values.
    # Only runs when: unstable=info, record channel is not already unstable,
    # and the fetcher type supports channel selection (github/dockerhub/quay/npm/…).
    # Suppressed when --stable=full is active (args.sh already enforces mutual exclusivity,
    # but this belt-and-suspenders guard protects against direct library calls).
    # stable=info is compatible — both second-pass blocks can run independently.
    if [[ "${_GS_EU2_CFG[unstable]:-}" == "info" && "${_GS_EU2_CFG[stable]:-}" != "full" ]]; then
      local _info_chan
      _info_chan="$(_gs_eu2_record_get "${_i}" channel)"
      if [[ "${_info_chan}" != "unstable" ]]; then
        # Save state (all fields that fetchers may overwrite during the second pass)
        local _saved_prop _saved_decision _saved_chan _saved_err
        _saved_prop="$(_gs_eu2_record_get "${_i}" proposed_version)"
        _saved_decision="$(_gs_eu2_record_get "${_i}" decision)"
        _saved_err="$(_gs_eu2_record_get "${_i}" error_message)"
        _saved_chan="${_info_chan}"
        # Temporarily set channel=unstable and re-run fetcher
        _gs_eu2_record_set "${_i}" channel "unstable"
        _gs_eu2_record_set "${_i}" proposed_version ""
        _gs_eu2_record_set "${_i}" decision ""
        _gs_eu2_record_set "${_i}" error_message ""
        case "${_type}" in
          codeberg)  _gs_eu2_fetch_codeberg  "${_i}" ;;
          dockerhub) _gs_eu2_fetch_dockerhub "${_i}" ;;
          github)    _gs_eu2_fetch_github    "${_i}" ;;
          quay)      _gs_eu2_fetch_quay      "${_i}" ;;
          npm)        _gs_eu2_fetch_npm        "${_i}" ;;
          pypi)       _gs_eu2_fetch_pypi       "${_i}" ;;
          rubygems)   _gs_eu2_fetch_rubygems   "${_i}" ;;
          sdkman)     _gs_eu2_fetch_sdkman     "${_i}" ;;
          sdkmanager) _gs_eu2_fetch_sdkmanager "${_i}" ;;
          pecl)       _gs_eu2_fetch_pecl       "${_i}" ;;
          url)        _gs_eu2_fetch_url        "${_i}" ;;
        esac
        local _unstable_ver
        _unstable_ver="$(_gs_eu2_record_get "${_i}" proposed_version)"
        # Restore original state (including error_message to avoid info-pass errors bleeding through)
        _gs_eu2_record_set "${_i}" channel "${_saved_chan}"
        _gs_eu2_record_set "${_i}" proposed_version "${_saved_prop}"
        _gs_eu2_record_set "${_i}" decision "${_saved_decision}"
        _gs_eu2_record_set "${_i}" error_message "${_saved_err}"
        # Store unstable_proposed only if it's a prerelease, different from stable proposed,
        # AND genuinely newer than the stable proposed (not a backward step like stable=3.1.1
        # returning hp=3.0.0-rc.4 — that would be a downgrade, not an advance).
        if [[ -n "${_unstable_ver}" && "${_unstable_ver}" != "${_saved_prop}" ]] && \
           _gs_eu2_is_prerelease "${_unstable_ver}"; then
          local _ui_store="true"
          if [[ -n "${_saved_prop}" ]]; then
            local _ui_cmp
            _ui_cmp="$(_gs_eu2_semver_compare "${_saved_prop}" "${_unstable_ver}")"
            # "older" means stable is older than unstable — i.e. unstable is genuinely newer
            [[ "${_ui_cmp}" != "older" ]] && _ui_store="false"
          fi
          [[ "${_ui_store}" == "true" ]] && \
            _gs_eu2_record_set "${_i}" unstable_proposed "${_unstable_ver}"
        fi
      fi
    fi

    # --stable=info second-pass: temporarily swap channel→stable, re-run the
    # same fetcher (cache hit — no extra HTTP), capture proposed as stable_proposed,
    # then restore proposed_version and decision to pre-pass values.
    # Only runs when: stable=info, record channel is not already stable/empty
    # (a stable channel would make the second pass identical to the main fetch).
    if [[ "${_GS_EU2_CFG[stable]:-}" == "info" ]]; then
      local _si_chan
      _si_chan="$(_gs_eu2_record_get "${_i}" channel)"
      if [[ -n "${_si_chan}" && "${_si_chan}" != "stable" ]]; then
        local _si_saved_prop _si_saved_decision _si_saved_chan _si_saved_err
        _si_saved_prop="$(_gs_eu2_record_get "${_i}" proposed_version)"
        _si_saved_decision="$(_gs_eu2_record_get "${_i}" decision)"
        _si_saved_err="$(_gs_eu2_record_get "${_i}" error_message)"
        _si_saved_chan="${_si_chan}"
        _gs_eu2_record_set "${_i}" channel "stable"
        _gs_eu2_record_set "${_i}" proposed_version ""
        _gs_eu2_record_set "${_i}" decision ""
        _gs_eu2_record_set "${_i}" error_message ""
        case "${_type}" in
          codeberg)   _gs_eu2_fetch_codeberg   "${_i}" ;;
          dockerhub)  _gs_eu2_fetch_dockerhub  "${_i}" ;;
          github)     _gs_eu2_fetch_github     "${_i}" ;;
          quay)       _gs_eu2_fetch_quay       "${_i}" ;;
          npm)        _gs_eu2_fetch_npm        "${_i}" ;;
          pypi)       _gs_eu2_fetch_pypi       "${_i}" ;;
          rubygems)   _gs_eu2_fetch_rubygems   "${_i}" ;;
          sdkman)     _gs_eu2_fetch_sdkman     "${_i}" ;;
          sdkmanager) _gs_eu2_fetch_sdkmanager "${_i}" ;;
          pecl)       _gs_eu2_fetch_pecl       "${_i}" ;;
          url)        _gs_eu2_fetch_url        "${_i}" ;;
        esac
        local _stable_ver
        _stable_ver="$(_gs_eu2_record_get "${_i}" proposed_version)"
        _gs_eu2_record_set "${_i}" channel "${_si_saved_chan}"
        _gs_eu2_record_set "${_i}" proposed_version "${_si_saved_prop}"
        _gs_eu2_record_set "${_i}" decision "${_si_saved_decision}"
        _gs_eu2_record_set "${_i}" error_message "${_si_saved_err}"
        # Store stable_proposed only if it's non-empty, not a prerelease,
        # and different from the main proposed (suppress when identical).
        if [[ -n "${_stable_ver}" && "${_stable_ver}" != "${_si_saved_prop}" ]] && \
           ! _gs_eu2_is_prerelease "${_stable_ver}"; then
          _gs_eu2_record_set "${_i}" stable_proposed "${_stable_ver}"
        fi
      fi
    fi
    fi  # end: if [[ -z "${_skip_reason}" ]] (skip gate — bypass all fetcher dispatch)

    # Apply decision classifier (refines any AUTO decision the fetcher set)
    local _cur _prop _override _manual _major _note _fetcher_decision
    _cur="$(_gs_eu2_record_get "${_i}" current_version)"
    _prop="$(_gs_eu2_record_get "${_i}" proposed_version)"
    _override="$(_gs_eu2_record_get "${_i}" override)"
    _manual="$(_gs_eu2_record_get "${_i}" manual)"
    _major="$(_gs_eu2_record_get "${_i}" major_hint)"
    _note="$(_gs_eu2_record_get "${_i}" note)"
    _fetcher_decision="$(_gs_eu2_record_get "${_i}" decision)"

    if [[ "${_fetcher_decision}" == "AUTO" || -z "${_fetcher_decision}" ]]; then
      local _classified
      # --force-auto: bypass (manual) and (override) annotation flags by passing "" so
      # classify_decision never sees them.  The HOLD gate is handled after classification.
      local _eff_override="${_override}" _eff_manual="${_manual}"
      if [[ "${_GS_EU2_CFG[force_auto]:-false}" == "true" ]]; then
        _eff_override="" _eff_manual=""
      fi
      # (tag-channel-prefix): pre-strip the channel prefix from _cur and _prop so that
      # decide.sh's internal sort -V downgrade check compares pure semver strings.
      # The round-trip prefix is display/storage-only; classify_decision must not see it.
      local _cur_cls="${_cur}" _prop_cls="${_prop}"
      local _tcp_cls
      _tcp_cls="$(_gs_eu2_record_get "${_i}" tag_channel_prefix)"
      if [[ -n "${_tcp_cls}" ]]; then
        _cur_cls="${_cur_cls#v}"; _cur_cls="${_cur_cls#"${_tcp_cls}"}"
        _prop_cls="${_prop_cls#v}"; _prop_cls="${_prop_cls#"${_tcp_cls}"}"
      fi
      _classified="$(_gs_eu2_classify_decision "${_cur_cls}" "${_prop_cls}" "${_eff_override}" "${_eff_manual}" "${_major}" "${_GS_EU2_CFG[unstable]:-}")"
      # --force-auto: upgrade HOLD to AUTO (bypasses major-bump guard / major_hint pin guard)
      if [[ "${_GS_EU2_CFG[force_auto]:-false}" == "true" && "${_classified}" == "HOLD" ]]; then
        _classified="AUTO"
      fi
      _gs_eu2_record_set "${_i}" decision "${_classified}"
    fi

    # SHA classification: independent of version decision.
    # When a repo is tracking HEAD (git:owner/repo flag), the annotation SHA may
    # lag behind even when the version is current.  Upgrade the decision to SHA
    # so the apply step can rewrite the annotation without touching VAR=.
    local _ann_sha _prop_sha _sha_classified
    _ann_sha="$(_gs_eu2_record_get "${_i}" annotation_sha)"
    _prop_sha="$(_gs_eu2_record_get "${_i}" proposed_sha)"
    _sha_classified="$(_gs_eu2_classify_sha_decision "${_ann_sha}" "${_prop_sha}")"
    if [[ "${_sha_classified}" == "SHA" && \
          "$(_gs_eu2_record_get "${_i}" decision)" == "SKIP" ]]; then
      _gs_eu2_record_set "${_i}" decision "SHA"
    fi

    # Annotate SKIP on a floating-reference current with a human-readable reason
    if [[ "$(_gs_eu2_record_get "${_i}" decision)" == "SKIP" && \
          "${_prop}" != "${_cur}" ]] && \
       _gs_eu2_is_unversioned "${_cur}"; then
      _gs_eu2_record_set "${_i}" error_message \
        "floating reference (${_cur}) — pin manually to adopt proposed version"
    fi

    # Annotate SKIP when proposed is prerelease but current is stable
    if [[ "$(_gs_eu2_record_get "${_i}" decision)" == "SKIP" && \
          -z "$(_gs_eu2_record_get "${_i}" error_message)" && \
          -n "${_prop}" && "${_prop}" != "${_cur}" ]] && \
       _gs_eu2_is_prerelease "${_prop}" && ! _gs_eu2_is_prerelease "${_cur}"; then
      _gs_eu2_record_set "${_i}" error_message \
        "proposed is prerelease — pin manually when stable ships"
    fi

    # Stream this record immediately — don't buffer until all fetches complete
    local _decision _err _tag _change _reason
    _decision="$(_gs_eu2_record_get "${_i}" decision)"
    _err="$(_gs_eu2_record_get "${_i}" error_message)"

    case "${_decision}" in
      AUTO)   _tag="[AUTO  ]"; (( ++_n_auto ))   || true ;;
      HOLD)   _tag="[HOLD  ]"; (( ++_n_hold ))   || true ;;
      SKIP)   _tag="[SKIP  ]"; (( ++_n_skip ))   || true ;;
      ERROR)  _tag="[ERROR ]"; (( ++_n_error ))  || true ;;
      MANUAL) _tag="[MANUAL]"; (( ++_n_manual )) || true ;;
      SHA)    _tag="[SHA   ]"; (( ++_n_sha ))    || true ;;
      *)      _tag="[SKIP  ]"; (( ++_n_skip ))   || true ;;
    esac

    # Compute reason label for non-AUTO decisions
    _reason=""
    case "${_decision}" in
      HOLD)
        if [[ -n "${_prop}" ]]; then
          local _delta _cur_maj _prop_maj
          _delta="$(_gs_eu2_semver_delta "${_cur}" "${_prop}")"
          _cur_maj="${_cur#v}"; _cur_maj="${_cur_maj%%.*}"
          _prop_maj="${_prop#v}"; _prop_maj="${_prop_maj%%.*}"
          # Strip path-like prefix from major labels (e.g. "tags/2" → "2")
          _cur_maj="${_cur_maj##*[^0-9]}"
          _prop_maj="${_prop_maj##*[^0-9]}"
          if [[ -n "${_major}" ]]; then
            # Proposed escapes major_hint pin
            _reason="  ← major pin (${_prop_maj}.x available)"
          elif [[ "${_delta}" == "major" ]]; then
            # Unpinned major bump
            _reason="  ← major bump (${_cur_maj}→${_prop_maj})"
          fi
        fi
        ;;
      MANUAL)
        _reason="  ← manual flag"
        ;;
      SKIP)
        # Detect downgrade: proposed non-empty, differs from current, no error yet
        if [[ -z "${_err}" && -n "${_prop}" && "${_prop}" != "${_cur}" ]]; then
          local _tcp_disp
          _tcp_disp="$(_gs_eu2_record_get "${_i}" tag_channel_prefix)"
          local _cur_cmp="${_cur#v}" _prop_cmp="${_prop#v}"
          [[ -n "${_tcp_disp}" ]] && _cur_cmp="${_cur_cmp#"${_tcp_disp}"}"
          [[ -n "${_tcp_disp}" ]] && _prop_cmp="${_prop_cmp#"${_tcp_disp}"}"
          local _oldest
          _oldest="$(printf '%s\n%s\n' "${_cur_cmp}" "${_prop_cmp}" | sort -V | head -1)"
          if [[ "${_oldest}" == "${_prop_cmp}" && "${_oldest}" != "${_cur_cmp}" ]]; then
            _err="would downgrade: current ${_cur_cmp} → stable ${_prop_cmp}"
          fi
        fi
        ;;
    esac

    _change=""
    if [[ "${_decision}" == "SHA" ]]; then
      local _sha_disp_new _sha_disp_ann
      _sha_disp_new="$(_gs_eu2_record_get "${_i}" proposed_sha)"
      _sha_disp_ann="$(_gs_eu2_record_get "${_i}" annotation_sha)"
      _change="  sha:${_sha_disp_ann:0:8} → sha:${_sha_disp_new:0:8}"
    elif [[ "${_decision}" == "SKIP" && -n "${_err}" ]]; then
      _change="  (${_err})"
    elif [[ -n "${_prop}" && "${_prop}" != "${_cur}" ]]; then
      _change="  ${_cur} → ${_prop}${_reason}"
    elif [[ -n "${_err}" ]]; then
      _change="  (${_err})"
    elif [[ "${_decision}" == "SKIP" ]]; then
      if [[ "${_manual}" == "true" || "${_override}" == "true" ]]; then
        _change="  (up to date — manual)"
      else
        _change="  (up to date)"
      fi
    elif [[ -n "${_reason}" ]]; then
      _change="${_reason}"
    fi

    # Clear the progress line then print the result
    # Width: tag(8) + 2 spaces + var field + some margin for change text
    printf '\r%*s\r' "$(( _max_var_len + 20 ))" "" >&2
    printf "%s  %-${_max_var_len}s%s\n" "${_tag}" "${_env_var}" "${_change}"
    [[ -n "${_note}" && "${_GS_EU2_CFG[no_notes]:-false}" != "true" ]] && \
      printf '%10s↳ %s\n' "" "${_note}"

    # (watch-major) sub-line: emit when a new runtime generation is available.
    # Uses latest_unconstrained (set by fetchers from the pre-major-pin tag set),
    # falling back to proposed_version for fetcher types with no major-pin concept.
    # Suppressed when: decision is ERROR/SKIP-unversioned, or no depth set.
    # NOT suppressed by --no-notes — WATCH is a signal, not a note.
    if [[ "${_decision}" != "ERROR" ]]; then
      local _wm_depth_r
      _wm_depth_r="$(_gs_eu2_record_get "${_i}" watch_major_depth)"
      if [[ -n "${_wm_depth_r}" ]]; then
        local _wm_latest
        _wm_latest="$(_gs_eu2_record_get "${_i}" latest_unconstrained)"
        # Fall back to proposed_version for fetchers without major-pin filtering
        [[ -z "${_wm_latest}" ]] && _wm_latest="${_prop}"
        if [[ -n "${_wm_latest}" && -n "${_cur}" ]]; then
          local _wm_cur_pfx _wm_lat_pfx
          _wm_cur_pfx="$(_gs_eu2_version_prefix "${_cur}" "${_wm_depth_r}")"
          _wm_lat_pfx="$(_gs_eu2_version_prefix "${_wm_latest}" "${_wm_depth_r}")"
          if [[ -n "${_wm_cur_pfx}" && -n "${_wm_lat_pfx}" && \
                "${_wm_cur_pfx}" != "${_wm_lat_pfx}" ]]; then
            local _wm_higher
            _wm_higher="$(printf '%s\n%s\n' "${_wm_cur_pfx}" "${_wm_lat_pfx}" | sort -V | tail -1)"
            if [[ "${_wm_higher}" == "${_wm_lat_pfx}" ]]; then
              printf '%10s↳ [WATCH] New generation available: %s (depth %s: %s → %s)\n' \
                "" "${_wm_latest}" "${_wm_depth_r}" "${_wm_cur_pfx}" "${_wm_lat_pfx}"
            fi
          fi
        fi
      fi
    fi

    # SHA sub-line: show short SHA (8 chars) + date for AUTO and SHA decisions
    if [[ "${_decision}" == "AUTO" || "${_decision}" == "SHA" ]]; then
      local _disp_prop_sha _disp_ann_sha _disp_sha_date
      _disp_prop_sha="$(_gs_eu2_record_get "${_i}" proposed_sha)"
      _disp_ann_sha="$(_gs_eu2_record_get "${_i}" annotation_sha)"
      _disp_sha_date="$(_gs_eu2_record_get "${_i}" proposed_sha_date)"
      if [[ -n "${_disp_prop_sha}" && "${_disp_prop_sha}" != "${_disp_ann_sha}" ]]; then
        local _sha_sub="sha: ${_disp_prop_sha:0:8}"
        [[ -n "${_disp_sha_date}" ]] && _sha_sub+=" (${_disp_sha_date})"
        [[ -n "${_disp_ann_sha}" ]] && _sha_sub+="  ← was ${_disp_ann_sha:0:8}"
        printf '%10s↳ %s\n' "" "${_sha_sub}"
      fi
    fi

    # --unstable=info sub-line: show what the unstable version would be (informational only).
    # Only shown when: unstable=info mode, unstable_proposed is set, and it differs from
    # both the stable proposed_version and the current version.
    # Suppressed when --stable=full is active (mutual exclusivity enforced in args.sh).
    # stable=info is compatible — both sub-lines may appear (unstable first, stable second).
    if [[ "${_GS_EU2_CFG[unstable]:-}" == "info" && "${_GS_EU2_CFG[stable]:-}" != "full" ]]; then
      local _unstable_disp
      _unstable_disp="$(_gs_eu2_record_get "${_i}" unstable_proposed)"
      if [[ -n "${_unstable_disp}" && "${_unstable_disp}" != "${_cur}" ]]; then
        printf '%10s↳ [INFO] unstable: %s\n' "" "${_unstable_disp}"
      fi
    fi

    # --stable=info sub-line: show what the stable version would be (informational only).
    # Only shown when: stable=info mode, stable_proposed is set, and it differs from current.
    if [[ "${_GS_EU2_CFG[stable]:-}" == "info" ]]; then
      local _stable_disp
      _stable_disp="$(_gs_eu2_record_get "${_i}" stable_proposed)"
      if [[ -n "${_stable_disp}" && "${_stable_disp}" != "${_cur}" ]]; then
        printf '%10s↳ [INFO] stable: %s\n' "" "${_stable_disp}"
      fi
    fi
  done

  local _total=$(( _n_auto + _n_hold + _n_skip + _n_error + _n_manual + _n_sha ))
  printf '%-80s\n' "──────────────────────────────────────────────────────────────────────────────"
  printf '  Summary: %d AUTO, %d SHA, %d HOLD, %d MANUAL, %d SKIP, %d ERROR  (%d checked)\n' \
    "${_n_auto}" "${_n_sha}" "${_n_hold}" "${_n_manual}" "${_n_skip}" "${_n_error}" "${_total}"
  # Exit non-zero when any ERROR decisions were recorded — callers can detect fetch failures.
  (( _n_error > 0 )) && return 1 || return 0
}

_gs_eu2_main() {
  _gs_eu2_parse_args "${@}"

  if [[ "${_GS_EU2_CFG[dump]}" == "true" && \
        ( "${_GS_EU2_CFG[check]}" == "true" || "${_GS_EU2_CFG[apply]}" == "true" ) ]]; then
    printf 'env-update: --dump is mutually exclusive with --check and --apply\n' >&2
    exit 1
  fi

  # --apply implies --check
  [[ "${_GS_EU2_CFG[apply]}" == "true" ]] && _GS_EU2_CFG[check]="true"

  # Safety guard: --apply (without --dry-run) requires a recent --dry-run in the same session.
  # This prevents the 2026-04-23 incident class (running --apply cold without previewing changes).
  # Marker file: ${_GS_EU2_CACHE_DIR}/last-dry-run-ts (written after every successful --dry-run check)
  if [[ "${_GS_EU2_CFG[apply]}" == "true" && "${_GS_EU2_CFG[dry_run]}" != "true" ]]; then
    local _dry_run_marker="${_GS_EU2_CACHE_DIR:-/tmp/global-stack-env-update-cache}/last-dry-run-ts"
    local _guard_ok=false
    if [[ -f "${_dry_run_marker}" ]]; then
      local _now _mtime _age
      _now="$(date +%s)"
      _mtime="$(stat -c %Y "${_dry_run_marker}" 2>/dev/null \
        || stat -f %m "${_dry_run_marker}" 2>/dev/null \
        || printf '0')"
      _age=$(( _now - _mtime ))
      (( _age < 1800 )) && _guard_ok=true
    fi
    if [[ "${_guard_ok}" != "true" ]]; then
      printf '[WARN] --apply requires a recent --dry-run (within 30 min). Run with --dry-run first.\n' >&2
      exit 1
    fi
  fi

  if [[ "true" == "${_GS_EU2_CFG[dry_run]}" ]]; then
    printf 'env-update: --dry-run active (no writes — cache, .env, and Dockerfile propagation all gated)\n' >&2
  fi

  local _env_file="${_GS_EU2_CFG[env_file]}"
  if [[ ! -f "${_env_file}" ]]; then
    printf 'env-update: env file not found: %s\n' "${_env_file}" >&2
    exit 1
  fi

  _gs_eu2_parse_env_file "${_env_file}" "${_GS_EU2_CFG[filter]}"

  # --unstable full: inject channel=unstable on records that don't already have it.
  # This causes fetchers to return the highest prerelease as proposed_version, and
  # classify_decision will promote stable→prerelease to AUTO (prerelease guard bypassed).
  # Note: --unstable=info does NOT inject here — it does a separate second-pass fetch
  # after each record to populate unstable_proposed without touching the main decision.
  if [[ "${_GS_EU2_CFG[unstable]:-}" == "full" ]]; then
    local _uc _ucount _unstable_overrides
    _unstable_overrides=0
    _ucount="$(_gs_eu2_record_count)"
    for (( _uc = 0; _uc < _ucount; _uc++ )); do
      local _existing_channel
      _existing_channel="$(_gs_eu2_record_get "${_uc}" channel)"
      if [[ -z "${_existing_channel}" || "${_existing_channel}" == "stable" ]]; then
        _gs_eu2_record_set "${_uc}" channel "unstable"
        (( _unstable_overrides++ )) || true
      fi
    done
    if [[ "${_unstable_overrides}" -gt 0 ]]; then
      printf '[UNSTABLE MODE] channel forced unstable for %d record(s)\n' "${_unstable_overrides}" >&2
    fi
  fi

  # --stable: force channel=stable on all records that have an explicit non-stable channel.
  # Overrides channel:rc, channel:beta, channel:alpha, channel:nightly, channel:unstable, etc.
  # Records already at channel="" or channel="stable" are untouched.
  if [[ "${_GS_EU2_CFG[stable]:-}" == "full" ]]; then
    local _sc _scount _stable_overrides
    _stable_overrides=0
    _scount="$(_gs_eu2_record_count)"
    for (( _sc = 0; _sc < _scount; _sc++ )); do
      local _existing_sc_channel
      _existing_sc_channel="$(_gs_eu2_record_get "${_sc}" channel)"
      if [[ -n "${_existing_sc_channel}" && "${_existing_sc_channel}" != "stable" ]]; then
        _gs_eu2_record_set "${_sc}" channel "stable"
        (( _stable_overrides++ )) || true
      fi
    done
    if [[ "${_stable_overrides}" -gt 0 ]]; then
      printf '[STABLE MODE] channel forced stable for %d record(s)\n' "${_stable_overrides}" >&2
    fi
  fi

  # Mode banners always go to stderr — this ensures --format=json output is clean JSON on
  # stdout, parseable directly by jq. Tests that grep for banners use 2>&1 so they still work.
  if [[ "${_GS_EU2_CFG[force_auto]:-false}" == "true" ]]; then
    printf '[FORCE-AUTO MODE] (manual) and (override) gates bypassed\n' >&2
  fi
  if [[ "${_GS_EU2_CFG[no_notes]:-false}" == "true" ]]; then
    printf '[NO-NOTES MODE] note sub-lines suppressed\n' >&2
  fi
  if [[ "${_GS_EU2_CFG[no_cache]:-false}" == "true" ]]; then
    printf '[NO-CACHE] cache bypassed — all fetches hit network\n' >&2
  fi
  if [[ "${_GS_EU2_CFG[with_tags]:-false}" == "true" ]]; then
    printf '[WITH-TAGS] tags API merged for all github records\n' >&2
  fi
  if [[ -n "${_GS_EU2_CFG[filter]:-}" ]]; then
    printf '[FILTER: %s]\n' "${_GS_EU2_CFG[filter]}" >&2
  fi

  if [[ "true" == "${_GS_EU2_CFG[dump]}" ]]; then
    _gs_eu2_dump_records "${_GS_EU2_CFG[format]}"
  elif [[ "true" == "${_GS_EU2_CFG[check]}" ]]; then
    local _check_rc=0
    _gs_eu2_run_check || _check_rc=$?

    # After a successful dry-run check, write the timestamp marker so a subsequent
    # --apply knows a recent preview was done (incident prevention: 2026-04-23).
    if [[ "${_GS_EU2_CFG[dry_run]}" == "true" ]]; then
      local _dry_run_marker="${_GS_EU2_CACHE_DIR:-/tmp/global-stack-env-update-cache}/last-dry-run-ts"
      mkdir -p "$(dirname "${_dry_run_marker}")"
      date +%s > "${_dry_run_marker}"
    fi

    if [[ "${_GS_EU2_CFG[apply]}" == "true" ]]; then
      printf '\n'
      if [[ "${_GS_EU2_CFG[dry_run]}" == "true" ]]; then
        printf 'Apply preview (--dry-run):\n'
        _gs_eu2_apply_updates "${_env_file}" "true"
      else
        local _backup
        _backup="${_env_file}.bak.$(date +%s)"
        if ! cp -a "${_env_file}" "${_backup}"; then
          printf 'env-update: backup failed (%s) — aborting apply to protect source file\n' "${_backup}" >&2
          return 1
        fi
        printf 'Backup: %s\n' "${_backup}" >&2
        _gs_eu2_apply_updates "${_env_file}" "false"
        if [[ "${_GS_EU2_CFG[scan]}" == "true" ]]; then
          local _env_scan
          _env_scan="$(dirname "${BASH_SOURCE[0]}")/../../env-scan.sh"
          if [[ -x "${_env_scan}" ]]; then
            printf 'Running env-scan.sh to propagate changes...\n' >&2
            bash "${_env_scan}" 2>&1 || printf 'WARNING: env-scan failed — .env updated but .env.local and Dockerfiles may be stale. Run bin/env-scan.sh manually.\n' >&2
          else
            printf 'WARNING: --scan requested but env-scan.sh not found at %s\n' "${_env_scan}" >&2
          fi
        else
          printf 'Tip: run bin/env-scan.sh to propagate to .env.local and Dockerfiles (or pass --scan)\n' >&2
        fi
      fi
    fi
    # Propagate non-zero return from _gs_eu2_run_check (errors present) without
    # triggering the ERR trap — the error was already reported in the output.
    return "${_check_rc}"
  else
    _gs_eu2_print_summary "${_env_file}"
  fi
}
