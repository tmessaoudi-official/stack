#!/usr/bin/env bash
# PostToolUse hook: runs shellcheck on .sh files after Edit/Write
# Receives tool call JSON on stdin, outputs system message if lint errors found.
set -euo pipefail

_HELPERS="$HOME/.claude/hooks/log-helpers.sh"
# shellcheck disable=SC1090
[[ -f "$_HELPERS" ]] && source "$_HELPERS" 2>/dev/null || true

if ! command -v jq &>/dev/null; then
  log_obs ERROR shellcheck-on-write "-stack | jq not found, hook skipped"
  exit 0
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only act on .sh files
[[ "$FILE_PATH" == *.sh ]] || exit 0

# Only act if file exists (might have been a failed write)
[[ -f "$FILE_PATH" ]] || exit 0

command -v shellcheck &>/dev/null || exit 0

# Run shellcheck — capture output, don't fail the hook on lint errors
LINT_OUTPUT=$(shellcheck -x -S warning -f gcc "$FILE_PATH" 2>&1) || true

if [[ -n "$LINT_OUTPUT" ]]; then
  # Count issues
  ISSUE_COUNT=$(echo "$LINT_OUTPUT" | wc -l)
  log_obs WARN shellcheck-on-write "-stack | $FILE_PATH: $ISSUE_COUNT issue(s)"
  jq -n --arg msg "shellcheck found $ISSUE_COUNT issue(s) in $FILE_PATH:
$LINT_OUTPUT" \
    '{ "systemMessage": $msg }'
fi

# Exit 0 = success, no blocking
exit 0
