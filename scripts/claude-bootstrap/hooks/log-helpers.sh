#!/usr/bin/env bash
# Shared observability helper (global framework Rule 13). Source this from hooks that need structured
# logging. Never fatal — every write ends in `|| true`, because a logging failure must not take down
# the hook that is logging.
#
# Format: YYYY-MM-DDTHH:MM:SS±ZZ | LEVEL | script | message
#
# DESTINATION: $OBS_LOG, else the IN-REPO `var/claude/logs/hooks-errors.log`.
#
# The in-repo default is the fix for a real bug (ported from rent-watch/twes-in, 2026-08-06): the
# upstream default was `~/.claude/logs/hooks-errors.log`, which is **wiped when the container is
# reclaimed**. Every line a hook logged during a real session was therefore unreadable by the time
# anyone looked — the observability rule was satisfied on paper and useless in practice. `var/` is
# gitignored (blanket `/var` rule), so these logs never reach history either, but they do survive for
# the life of the session, which is what makes them worth writing.
#
# $OBS_LOG is kept as an override so tests can point the log somewhere temporary and assert on it.

umask 077 # hook-created files are owner-only

log_obs() {
  local level="$1" script="$2"
  shift 2
  local dest="${OBS_LOG:-${CLAUDE_PROJECT_DIR:-$PWD}/var/claude/logs/hooks-errors.log}"
  mkdir -p "$(dirname "$dest")" 2>/dev/null || true
  printf '%s | %s | %s | %s\n' "$(date -Iseconds)" "$level" "$script" "$*" >>"$dest" 2>/dev/null || true
}
