#!/usr/bin/env bash
# PostToolUse hook: runs yamllint on YAML files after Edit/Write
set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only act on .yaml/.yml files
[[ "$FILE_PATH" == *.yaml || "$FILE_PATH" == *.yml ]] || exit 0
[[ -f "$FILE_PATH" ]] || exit 0

command -v yamllint &>/dev/null || exit 0

LINT_OUTPUT=$(yamllint -f parsable -d relaxed "$FILE_PATH" 2>&1) || true

if [[ -n "$LINT_OUTPUT" ]]; then
  ISSUE_COUNT=$(echo "$LINT_OUTPUT" | wc -l)
  jq -n --arg msg "yamllint found $ISSUE_COUNT issue(s) in $FILE_PATH:
$LINT_OUTPUT" \
    '{ "systemMessage": $msg }'
fi

exit 0
