#!/bin/bash
# propagate.sh — Dockerfile ARG propagation (Phase 6 of env-scan pipeline).
#
# Exports:   _gs_es_propagate_to_dockerfiles
# Sources:   core/backup.sh  core/git.sh
# Deps:      bash 4.3+, find, sed, git
# Env:       _GS_ES_CFG (backup, backup_suffix, _backup_ts, dir, quiet, dry_run)
#
# Propagates canonical VAR=value pairs from the source .env file into matching
# "ARG VAR=<value>" lines in Dockerfiles found under docker_search_root.
#
# Source of truth is always the .env file.  Vars whose .env value contains
# "${" are skipped — they depend on shell expansion and cannot be embedded
# literally in a Dockerfile ARG.
#
# Vars matching exclude_pattern are also skipped (protects structural
# divergences such as GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS, which uses
# a shell-expanded form in .env but a literal hostname in Dockerfiles).
# Rule 8: git-tracked Dockerfiles with uncommitted changes are skipped (safe guard).

# Include guard
[[ -n "${_GS_ES_PROPAGATE_SH_LOADED:-}" ]] && return 0
readonly _GS_ES_PROPAGATE_SH_LOADED=1

# shellcheck source=./core/backup.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/backup.sh"
# shellcheck source=./core/git.sh
source "$(dirname "${BASH_SOURCE[0]}")/core/git.sh"

# ── _gs_es_propagate_to_dockerfiles ───────────────────────────────────────────
# Args:
#   env_file          — source of canonical values (typically .env)
#   docker_search_root — directory tree to search for Dockerfiles
#   exclude_pattern   — ERE pattern; matching vars are left untouched
#   dry_run           — "true" → report only, no writes
#
# Output:
#   Prints "[propagate] <dockerfile>: VAR: <old> → <new>" per change.
#   Prints summary: "propagated N values across M files"
_gs_es_propagate_to_dockerfiles() {
  local env_file="${1}"
  local docker_search_root="${2}"
  local exclude_pattern="${3}"
  local dry_run="${4}"

  if [[ ! -f "${env_file}" ]]; then
    printf ' ---- (_gs_es_propagate_to_dockerfiles): env file not found: %s\n' "${env_file}" >&2
    return 1
  fi

  if [[ ! -d "${docker_search_root}" ]]; then
    printf ' ---- (_gs_es_propagate_to_dockerfiles): docker search root not found: %s (skipping)\n' "${docker_search_root}" >&2
    return 0
  fi

  # ── Build env map: VAR → value (skip comments, empty, expansion-dependent) ─
  local -A _prop_env_map
  local _line _var _val
  while IFS= read -r _line; do
    # Skip comment lines and blank lines
    [[ "${_line}" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${_line// /}" ]] && continue
    # Must contain an = sign
    [[ "${_line}" != *=* ]] && continue

    _var="${_line%%=*}"
    _val="${_line#*=}"

    # Skip vars with empty names
    [[ -z "${_var}" ]] && continue
    # Skip vars whose value contains ${ (shell expansion — not safe in Dockerfile)
    [[ "${_val}" == *'${'* ]] && continue
    # Skip vars matching the exclude pattern
    if [[ -n "${exclude_pattern}" ]] && [[ "${_var}" =~ ${exclude_pattern} ]]; then
      continue
    fi

    _prop_env_map["${_var}"]="${_val}"
  done <"${env_file}"

  if [[ ${#_prop_env_map[@]} -eq 0 ]]; then
    return 0
  fi

  # ── Walk all Dockerfiles under docker_search_root ────────────────────────
  local _total_values=0
  local _total_files=0
  local _dockerfile _arg_line _df_var _df_val _env_val _df_raw _df_comment _df_quote
  local _backup_enabled="${_GS_ES_CFG[backup]:-true}"
  local _backup_suffix="${_GS_ES_CFG[backup_suffix]:-.bak}"
  local _backup_ts="${_GS_ES_CFG[_backup_ts]:-}"
  local _backup_dir="${_GS_ES_CFG[dir]:-}"

  while IFS= read -r _dockerfile; do
    local _file_changed=0
    local _file_values=0
    local _file_backed_up=0

    # Rule 8: skip in dry-run (no writes) and skip dirty tracked Dockerfiles.
    if [[ "${dry_run}" != "true" ]]; then
      if ! _gs_es_check_tracked_file_state "${_dockerfile}"; then
        printf ' [propagate] [SKIP] %s — uncommitted changes, skipping\n' "${_dockerfile}" >&2
        continue
      fi
    fi

    while IFS= read -r _arg_line; do
      # Match lines of the form: ARG VAR=value
      if [[ "${_arg_line}" =~ ^ARG[[:space:]]+([A-Za-z0-9_]+)=(.*)$ ]]; then
        _df_var="${BASH_REMATCH[1]}"
        _df_raw="${BASH_REMATCH[2]}"

        # The comparison below must be made against the value BuildKit actually
        # resolves, not the raw token: otherwise a Dockerfile that is already in
        # sync compares unequal forever, and every run reports drift and rewrites
        # it. Both shapes were verified against a real `docker build`
        # (2026-08-28): `ARG X=1.2.3 # note` → `1.2.3`, `ARG X="1.2.3"` →
        # `1.2.3`, while `ARG X=a#b` → `a#b` (a '#' only opens a comment when
        # whitespace precedes it).
        #
        # Both the quote style and the comment are kept aside and re-applied on
        # write, so a rewrite never silently drops a pinning rationale.
        _df_comment=''
        _df_val="${_df_raw}"
        local _scan="${_df_raw}" _seen='' _head _prefix _ws
        while [[ "${_scan}" == *'#'* ]]; do
          _head="${_scan%%#*}"
          if [[ "${_head}" =~ [[:space:]]$ ]]; then
            _prefix="${_seen}${_head}"
            _df_val="${_prefix%"${_prefix##*[![:space:]]}"}"
            _ws="${_prefix:${#_df_val}}"
            _df_comment="${_ws}${_df_raw:${#_prefix}}"
            break
          fi
          _seen="${_seen}${_head}#"
          _scan="${_scan#*#}"
        done

        _df_quote=''
        if [[ "${_df_val}" =~ ^\"(.*)\"$ ]]; then
          _df_quote='"'
          _df_val="${BASH_REMATCH[1]}"
        elif [[ "${_df_val}" =~ ^\'(.*)\'$ ]]; then
          _df_quote="'"
          _df_val="${BASH_REMATCH[1]}"
        fi

        # Only act on vars that are in our env map
        if [[ -n "${_prop_env_map[${_df_var}]+set}" ]]; then
          _env_val="${_prop_env_map[${_df_var}]}"

          if [[ "${_df_val}" != "${_env_val}" ]]; then
            if [[ "${dry_run}" == "true" ]]; then
              printf ' [DRY-RUN] [propagate] %s: %s: '\''%s'\'' → '\''%s'\''\n' "${_dockerfile}" "${_df_var}" "${_df_val}" "${_env_val}"
            else
              printf ' [propagate] %s: %s: '\''%s'\'' → '\''%s'\''\n' "${_dockerfile}" "${_df_var}" "${_df_val}" "${_env_val}"
            fi
            if [[ "${dry_run}" != "true" ]]; then
              # Back up gitignored Dockerfile once before first rewrite
              if [[ "${_file_backed_up}" -eq 0 && "${_backup_enabled}" == "true" && -n "${_backup_ts}" ]]; then
                _gs_es_backup_if_gitignored \
                  "${_dockerfile}" \
                  "${_backup_dir}" \
                  "${_backup_ts}" \
                  "${_backup_suffix}" \
                  "false" \
                  "${_GS_ES_CFG[quiet]:-false}"
                _file_backed_up=1
              fi
              # A1: Escape _env_val for |-delimited sed expression to prevent injection
              local _escaped_val="${_env_val//\\/\\\\}" # escape backslash first
              _escaped_val="${_escaped_val//|/\\|}"     # escape pipe (our delimiter)
              _escaped_val="${_escaped_val//&/\\&}"     # escape & (sed backreference)
              # B3: Preserve original ARG quoting style, detected above.
              local _write_val="${_df_quote}${_escaped_val}${_df_quote}"
              # Carry the trailing comment through the rewrite. It goes through
              # the same escaping as the value: it lands on sed's replacement
              # side, where '\' and '&' are metacharacters.
              local _escaped_comment="${_df_comment//\\/\\\\}"
              _escaped_comment="${_escaped_comment//|/\\|}"
              _escaped_comment="${_escaped_comment//&/\\&}"
              # Rewrite the ARG line in-place. The address must be as tolerant as
              # the detection above (`^ARG[[:space:]]+`): a literal '^ARG ' here
              # silently matched nothing on a tab- or double-space-separated line,
              # so the run reported and counted a propagation it never performed.
              sed -i -E "s|^ARG[[:space:]]+${_df_var}=.*|ARG ${_df_var}=${_write_val}${_escaped_comment}|" \
                "${_dockerfile}"
            fi
            ((_file_values++)) || true
            ((_total_values++)) || true
            _file_changed=1
          fi
        fi
      fi
    done <"${_dockerfile}"

    if [[ "${_file_changed}" -eq 1 ]]; then
      ((_total_files++)) || true
    fi
    # The `Dockerfile*` glob also matches the backups this very function writes
    # next to a gitignored Dockerfile (`Dockerfile.bak.<ts>` — see
    # core/backup.sh). Rewriting those turns the documented rollback path into a
    # no-op: run 1 saves the old value, run 2 walks the backup and updates it to
    # the new one, so restoring it restores nothing. They are also counted as
    # separate "files" in the summary. Exclude anything carrying the backup
    # suffix.
  done < <(find "${docker_search_root}" -type f -name "Dockerfile*" \
    ! -name "*${_backup_suffix}.*" 2>/dev/null | LC_ALL=C sort)

  if [[ "${dry_run}" == "true" ]]; then
    printf ' [propagate] (dry-run) would propagate %d value(s) across %d file(s)\n' "${_total_values}" "${_total_files}"
  else
    printf ' [propagate] propagated %d value(s) across %d file(s)\n' "${_total_values}" "${_total_files}"
  fi
}
