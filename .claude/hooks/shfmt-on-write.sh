#!/usr/bin/env bash
# PostToolUse hook: runs shfmt diff check on .sh files after Edit/Write
set -euo pipefail

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only act on .sh files
[[ "$FILE_PATH" == *.sh ]] || exit 0
[[ -f "$FILE_PATH" ]] || exit 0

command -v shfmt &>/dev/null || exit 0

# shfmt -d = diff mode (show what would change, exit 1 if unformatted)
DIFF_OUTPUT=$(shfmt -d -i 2 -ci -bn "$FILE_PATH" 2>&1) || true

if [[ -n "$DIFF_OUTPUT" ]]; then
  DIFF_LINES=$(echo "$DIFF_OUTPUT" | wc -l)
  jq -n --arg msg "shfmt: $FILE_PATH has formatting issues ($DIFF_LINES lines differ). Run 'shfmt -w -i 2 -ci -bn $FILE_PATH' to fix." \
    '{ "systemMessage": $msg }'
fi

exit 0
