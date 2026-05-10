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
# shellcheck source=./fetchers/pecl_git.sh
source "$(dirname "${BASH_SOURCE[0]}")/fetchers/pecl_git.sh"
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

  local _n_auto=0 _n_hold=0 _n_skip=0 _n_error=0 _n_manual=0

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

    _type="$(_gs_eu2_record_get "${_i}" type)"
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
      pecl-git)   _gs_eu2_fetch_pecl_git   "${_i}" ;;
      url)        _gs_eu2_fetch_url        "${_i}" ;;
      # Phase 3a implemented: codeberg (1), quay (1) — see fetchers/codeberg.sh + fetchers/quay.sh
      # Phase 3b implemented: npm (55), pypi (24), rubygems (4) — see fetchers/{npm,pypi,rubygems}.sh
      # Phase 3c implemented: github (73) — see fetchers/github.sh
      # Phase 3d implemented: pecl-git (100) — see fetchers/pecl.sh + fetchers/pecl_git.sh
      # Phase 3e implemented: sdkman (19), sdkmanager (5) — see fetchers/{sdkman,sdkmanager}.sh
      # Phase 3f implemented: url (8) — see fetchers/url.sh + core/ubuntu.sh
      *)
        _gs_eu2_record_set "${_i}" decision      "SKIP"
        _gs_eu2_record_set "${_i}" error_message "fetcher '${_type}' not yet implemented (see Phase 3f+ TODO above)"
        ;;
    esac

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
      _classified="$(_gs_eu2_classify_decision "${_cur}" "${_prop}" "${_override}" "${_manual}" "${_major}")"
      _gs_eu2_record_set "${_i}" decision "${_classified}"
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
          local _oldest
          _oldest="$(printf '%s\n%s\n' "${_cur#v}" "${_prop#v}" | sort -V | head -1)"
          if [[ "${_oldest}" == "${_prop#v}" && "${_oldest}" != "${_cur#v}" ]]; then
            _err="would downgrade"
          fi
        fi
        ;;
    esac

    _change=""
    if [[ "${_decision}" == "SKIP" && -n "${_err}" ]]; then
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
    [[ -n "${_note}" ]] && printf '%10s↳ %s\n' "" "${_note}"
  done

  local _total=$(( _n_auto + _n_hold + _n_skip + _n_error + _n_manual ))
  printf '%-80s\n' "──────────────────────────────────────────────────────────────────────────────"
  printf '  Summary: %d AUTO, %d HOLD, %d MANUAL, %d SKIP, %d ERROR  (%d checked)\n' \
    "${_n_auto}" "${_n_hold}" "${_n_manual}" "${_n_skip}" "${_n_error}" "${_total}"
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

  if [[ "true" == "${_GS_EU2_CFG[dump]}" ]]; then
    _gs_eu2_dump_records "${_GS_EU2_CFG[format]}"
  elif [[ "true" == "${_GS_EU2_CFG[check]}" ]]; then
    _gs_eu2_run_check

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
  else
    _gs_eu2_print_summary "${_env_file}"
  fi
}
