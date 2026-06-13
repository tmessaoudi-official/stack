#!/usr/bin/env bash
# PostToolUse hook: runs shfmt diff check on .sh files after Edit/Write
set -euo pipefail

_HELPERS="$HOME/.claude/hooks/log-helpers.sh"
# shellcheck disable=SC1090
[[ -f "$_HELPERS" ]] && source "$_HELPERS" 2>/dev/null || true
# Rule 13: never fatal — define a no-op fallback when helpers are absent
declare -F log_obs >/dev/null 2>&1 || log_obs() { :; }

if ! command -v jq &>/dev/null; then
  log_obs ERROR shfmt-on-write "-stack | jq not found, hook skipped" || true
  exit 0
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0

# Only act on .sh files
[[ "$FILE_PATH" == *.sh ]] || exit 0
[[ -f "$FILE_PATH" ]] || exit 0

command -v shfmt &>/dev/null || exit 0

# shfmt -d = diff mode (show what would change, exit 1 if unformatted)
DIFF_OUTPUT=$(shfmt -d -i 2 -ci -bn "$FILE_PATH" 2>&1) || true

if [[ -n "$DIFF_OUTPUT" ]]; then
  DIFF_LINES=$(echo "$DIFF_OUTPUT" | wc -l)
  log_obs WARN shfmt-on-write "-stack | $FILE_PATH: $DIFF_LINES lines differ" || true
  jq -n --arg msg "shfmt: $FILE_PATH has formatting issues ($DIFF_LINES lines differ). Run 'shfmt -w -i 2 -ci -bn $FILE_PATH' to fix." \
    '{ "systemMessage": $msg }'
fi

exit 0
