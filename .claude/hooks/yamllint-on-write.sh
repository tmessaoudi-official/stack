#!/usr/bin/env bash
# PostToolUse hook: runs yamllint on YAML files after Edit/Write
set -euo pipefail

_HELPERS="$HOME/.claude/hooks/log-helpers.sh"
# shellcheck disable=SC1090
[[ -f "$_HELPERS" ]] && source "$_HELPERS" 2>/dev/null || true

if ! command -v jq &>/dev/null; then
  log_obs ERROR yamllint-on-write "-stack | jq not found, hook skipped"
  exit 0
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only act on .yaml/.yml files
[[ "$FILE_PATH" == *.yaml || "$FILE_PATH" == *.yml ]] || exit 0
[[ -f "$FILE_PATH" ]] || exit 0

command -v yamllint &>/dev/null || exit 0

LINT_OUTPUT=$(yamllint -f parsable -d relaxed "$FILE_PATH" 2>&1) || true

if [[ -n "$LINT_OUTPUT" ]]; then
  ISSUE_COUNT=$(echo "$LINT_OUTPUT" | wc -l)
  log_obs WARN yamllint-on-write "-stack | $FILE_PATH: $ISSUE_COUNT issue(s)"
  jq -n --arg msg "yamllint found $ISSUE_COUNT issue(s) in $FILE_PATH:
$LINT_OUTPUT" \
    '{ "systemMessage": $msg }'
fi

exit 0
