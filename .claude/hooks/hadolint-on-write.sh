#!/usr/bin/env bash
# PostToolUse hook: runs hadolint on Dockerfiles after Edit/Write
set -euo pipefail

_HELPERS="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/.claude/hooks/log-helpers.sh"
# shellcheck disable=SC1090
[[ -f "$_HELPERS" ]] && source "$_HELPERS" 2>/dev/null || true
# Rule 13: never fatal — define a no-op fallback when helpers are absent
declare -F log_obs >/dev/null 2>&1 || log_obs() { :; }

if ! command -v jq &>/dev/null; then
  log_obs ERROR hadolint-on-write "-stack | jq not found, hook skipped" || true
  exit 0
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0

# Only act on files named "Dockerfile" (with optional suffix)
[[ "$(basename "$FILE_PATH")" == Dockerfile* ]] || exit 0
[[ -f "$FILE_PATH" ]] || exit 0

command -v hadolint &>/dev/null || exit 0

LINT_OUTPUT=$(hadolint "$FILE_PATH" 2>&1) || true

if [[ -n "$LINT_OUTPUT" ]]; then
  ISSUE_COUNT=$(echo "$LINT_OUTPUT" | wc -l)
  log_obs WARN hadolint-on-write "-stack | $FILE_PATH: $ISSUE_COUNT issue(s)" || true
  jq -n --arg msg "hadolint found $ISSUE_COUNT issue(s) in $FILE_PATH:
$LINT_OUTPUT" \
    '{ "systemMessage": $msg }'
fi

exit 0
