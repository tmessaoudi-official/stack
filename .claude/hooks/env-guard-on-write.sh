#!/usr/bin/env bash
# PostToolUse hook: sanity-checks .env / .env.local after Edit/Write.
# Catches the three classic silent breakages documented in CLAUDE.md Gotchas:
#   1. trailing ';' in COMPOSE_FILE   2. port vars not ending with ':'
#   3. COMPOSE_FILE entries pointing at missing compose files
# Advisory only — emits a systemMessage warning, never blocks (always exit 0).
set -euo pipefail

_HELPERS="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/.claude/hooks/log-helpers.sh"
# shellcheck disable=SC1090
[[ -f "$_HELPERS" ]] && source "$_HELPERS" 2>/dev/null || true
# Rule 13: never fatal — define a no-op fallback when helpers are absent
declare -F log_obs >/dev/null 2>&1 || log_obs() { :; }

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0

case "$FILE_PATH" in
  */.env | */.env.local) ;;
  *) exit 0 ;;
esac
[[ -f "$FILE_PATH" ]] || exit 0

WARNINGS=()

# 1. Trailing ';' in COMPOSE_FILE breaks Docker Compose silently
if grep -Eq '^COMPOSE_FILE=.*;[[:space:]]*$' "$FILE_PATH"; then
  WARNINGS+=("COMPOSE_FILE ends with ';' — Docker Compose breaks silently on a trailing separator.")
fi

# 2. Port vars with a non-empty value must end with ':' (host half of HOST:CONTAINER);
#    otherwise the numbers concatenate (e.g. 427083306). Empty value = no binding = OK.
while IFS= read -r line; do
  WARNINGS+=("${line%%=*} is set but does not end with ':' — host/container ports will concatenate.")
done < <(grep -E '^GLOBAL_STACK[A-Z0-9_]*_PORT_[0-9]+=.*[^:]$' "$FILE_PATH" || true)

# 3. COMPOSE_FILE entries referencing files that don't exist (skip expansion-dependent entries)
COMPOSE_LINE=$(grep -E '^COMPOSE_FILE=' "$FILE_PATH" | tail -1) || COMPOSE_LINE=""
if [[ -n "$COMPOSE_LINE" ]]; then
  ENV_DIR=$(dirname "$FILE_PATH")
  IFS=';' read -ra _ENTRIES <<<"${COMPOSE_LINE#COMPOSE_FILE=}"
  for entry in "${_ENTRIES[@]}"; do
    [[ -z "$entry" || "$entry" == *'$'* ]] && continue
    [[ -f "$ENV_DIR/$entry" || -f "$entry" ]] || WARNINGS+=("COMPOSE_FILE references a missing file: $entry")
  done
fi

if ((${#WARNINGS[@]} > 0)); then
  MSG=$(printf '%s\n' "${WARNINGS[@]}")
  log_obs WARN env-guard-on-write "-stack | $FILE_PATH: ${#WARNINGS[@]} warning(s)" || true
  jq -n --arg msg "env-guard: potential issue(s) in $FILE_PATH:
$MSG" '{ "systemMessage": $msg }'
fi

exit 0
