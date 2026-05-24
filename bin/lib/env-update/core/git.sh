#!/bin/bash
# git.sh — git-state safety check for env-update write operations.
#
# Exports:   _gs_eu2_check_tracked_file_state
# Sources:   none
# Deps:      git
# Env:       none
#
# Rule 8: before overwriting a tracked file, check for uncommitted changes
# to avoid silently overwriting in-flight edits.  The check is narrow and
# intentional:
#   - Not in a git repo → safe (backup phase handles it via Rule 8B)
#   - In a git repo but file is untracked/gitignored → safe (Rule 8B)
#   - Tracked AND clean → safe
#   - Tracked AND dirty → NOT safe (returns 1 + warning to stderr)

[[ -n "${_GS_EU2_GIT_SH_LOADED:-}" ]] && return 0
readonly _GS_EU2_GIT_SH_LOADED=1

# _gs_eu2_check_tracked_file_state — verify it is safe to overwrite a file.
#
# Args:    $1 file — absolute or relative path to the file to be written
# Reads:   git repo state (via git -C, git ls-files, git status)
# Prints:  warning to stderr when return 1
# Returns: 0 if safe to write; 1 if file is git-tracked with uncommitted changes
# Side fx: none (read-only git queries)
_gs_eu2_check_tracked_file_state() {
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

  printf '[WARN] env-update: %s has uncommitted changes (%s). Commit or stash before running.\n' \
    "${_file}" "${_status}" >&2
  return 1
}
