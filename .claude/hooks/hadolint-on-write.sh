#!/usr/bin/env bash
# PostToolUse hook: runs hadolint on Dockerfiles after Edit/Write
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only act on files named "Dockerfile" (with optional suffix)
[[ "$(basename "$FILE_PATH")" == Dockerfile* ]] || exit 0
[[ -f "$FILE_PATH" ]] || exit 0

command -v hadolint &>/dev/null || exit 0

LINT_OUTPUT=$(hadolint "$FILE_PATH" 2>&1) || true

if [[ -n "$LINT_OUTPUT" ]]; then
  ISSUE_COUNT=$(echo "$LINT_OUTPUT" | wc -l)
  jq -n --arg msg "hadolint found $ISSUE_COUNT issue(s) in $FILE_PATH:
$LINT_OUTPUT" \
    '{ "systemMessage": $msg }'
fi

exit 0
