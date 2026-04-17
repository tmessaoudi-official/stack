#!/usr/bin/env bash
# PostToolUse hook: runs shell-check on .sh files after Edit/Write
# Receives tool call JSON on stdin, outputs system message if lint errors found.
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only act on .sh files
[[ "$FILE_PATH" == *.sh ]] || exit 0

# Only act if file exists (might have been a failed write)
[[ -f "$FILE_PATH" ]] || exit 0

command -v shell-check &>/dev/null || exit 0

# Run shell-check — capture output, don't fail the hook on lint errors
LINT_OUTPUT=$(shell-check -x -S warning -f gcc "$FILE_PATH" 2>&1) || true

if [[ -n "$LINT_OUTPUT" ]]; then
  # Count issues
  ISSUE_COUNT=$(echo "$LINT_OUTPUT" | wc -l)
  jq -n --arg msg "shell-check found $ISSUE_COUNT issue(s) in $FILE_PATH:
$LINT_OUTPUT" \
    '{ "systemMessage": $msg }'
fi

# Exit 0 = success, no blocking
exit 0
