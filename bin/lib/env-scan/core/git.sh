#!/bin/bash
# git.sh — git-state safety check for env-scan write operations
#
# Exports:   _gs_es_check_tracked_file_state
# Sources:   none
# Deps:      bash 4.3+, git
# Env:       none (all inputs are arguments)
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

# _gs_es_check_tracked_file_state — check if a file is safe to overwrite in-place.
#
# Args:    $1 file — absolute or relative path to the file being checked
# Prints:  [WARN] line to stderr when returning 1
# Returns: 0 if safe to write (not tracked, not dirty, or not in a git repo)
#          1 if file is tracked AND has uncommitted changes
# Side fx: none
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
