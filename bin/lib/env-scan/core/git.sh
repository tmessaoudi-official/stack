#!/bin/bash
# git.sh — git-state safety check for env-scan write operations
#
# Rule 8: before overwriting a Dockerfile in-place, check whether it is tracked
# by git and has uncommitted changes. If so, skip that file (emit a warning) to
# avoid overwriting in-flight edits.
#
# The check is intentionally narrow:
#   - Not in a git repo → safe (backup phase already handled it via Rule 8B)
#   - In a git repo but file is untracked/gitignored → safe (Rule 8B)
#   - Tracked AND clean → safe
#   - Tracked AND dirty → NOT safe (returns 1 + warning to stderr)

[[ -n "${_GS_ES_GIT_SH_LOADED:-}" ]] && return 0
readonly _GS_ES_GIT_SH_LOADED=1

# _gs_es_check_tracked_file_state FILE
#
# Returns 0 if safe to write, 1 if the file is git-tracked and has uncommitted
# changes. The caller is responsible for deciding whether to skip the file.
#
# Stderr: warning line on return 1.
_gs_es_check_tracked_file_state() {
  local _file="${1}"
  local _file_dir
  _file_dir="$(dirname "${_file}")"

  # Not in a git repo → Rule 8B (backup already handled) → safe
  git -C "${_file_dir}" rev-parse --is-inside-work-tree &>/dev/null || return 0

  # File not tracked by git → Rule 8B (backup already handled) → safe
  git -C "${_file_dir}" ls-files --error-unmatch -- "${_file}" &>/dev/null || return 0

  # File is tracked — check for uncommitted changes (staged or unstaged)
  local _status
  _status="$(git -C "${_file_dir}" status --porcelain -- "${_file}" 2>/dev/null)"
  [[ -z "${_status}" ]] && return 0

  printf '[WARN] env-scan: %s has uncommitted changes (%s). Skipping propagation to this file.\n' \
    "${_file}" "${_status}" >&2
  return 1
}
