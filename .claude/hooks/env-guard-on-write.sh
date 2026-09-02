#!/usr/bin/env bash
# PostToolUse hook: sanity-checks .env / .env.local after Edit/Write.
# Catches the three classic silent breakages documented in CLAUDE.md Gotchas:
#   1. trailing ';' in COMPOSE_FILE   2. port vars not ending with ':'
#   3. COMPOSE_FILE entries pointing at missing compose files
# Advisory only — emits a systemMessage warning, never blocks (always exit 0).
set -euo pipefail

_HELPERS="$HOME/.claude/hooks/log-helpers.sh"
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

ENV_DIR=$(dirname "$FILE_PATH")

# 2. Port vars. Whether a value must end with ':' is a property of the CONSUMER,
#    not of the variable. A compose file writing `${VAR:-}3306` concatenates, so
#    the ':' has to be there or the host port becomes 427083306. A compose file
#    writing `${VAR:-}:${VAR:-}`, or a Makefile writing `${VAR}:5000`, supplies
#    the colon itself — a trailing ':' there IS the bug. Keying on the
#    concatenating consumer form is what makes this check right in both
#    directions, and it needs no annotations and no list to maintain.
#    The name pattern also admits range-style _PORT_<n>_<n>
#    (GLOBAL_STACK_LOCALSTACK_LOCALSTACK_PORT_4510_4559), which the old
#    `_PORT_[0-9]+=` shape could never match — and which is the one variable in
#    this repo whose consumer genuinely concatenates.
shopt -s nullglob
_CONSUMERS=("$ENV_DIR"/docker/images/*/docker-compose.yaml)
shopt -u nullglob

_PORT_CANDIDATES=0
while IFS= read -r line; do
  _var="${line%%=*}"
  _val="${line#*=}"
  # Empty value = no host binding at all = correct, nothing to say.
  if [[ -z "$_val" ]]; then continue; fi
  if [[ "$_val" == *: ]]; then continue; fi
  _PORT_CANDIDATES=$((_PORT_CANDIDATES + 1))
  if ((${#_CONSUMERS[@]} == 0)); then continue; fi
  if grep -qE '\$\{'"${_var}"':-\}[0-9]' "${_CONSUMERS[@]}"; then
    WARNINGS+=("${_var} is set but does not end with ':' — its compose consumer appends the container port directly, so the two numbers concatenate.")
  fi
done < <(grep -E '^GLOBAL_STACK[A-Z0-9_]*_PORT_[0-9]+(_[0-9]+)*=' "$FILE_PATH" || true)

# A consumer-keyed check with no consumers to read examined nothing. Reporting
# that as clean is how a guard quietly stops guarding.
if ((_PORT_CANDIDATES > 0)) && ((${#_CONSUMERS[@]} == 0)); then
  WARNINGS+=("port check could not run: no docker/images/*/docker-compose.yaml under $ENV_DIR to identify concatenating consumers ($_PORT_CANDIDATES port var(s) left unchecked).")
fi

# 3. COMPOSE_FILE entries referencing files that don't exist (skip expansion-dependent entries)
COMPOSE_LINE=$(grep -E '^COMPOSE_FILE=' "$FILE_PATH" | tail -1) || COMPOSE_LINE=""
if [[ -n "$COMPOSE_LINE" ]]; then
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
