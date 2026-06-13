#!/usr/bin/env bash
# SubagentStop hook: remind the parent agent to verify Phase 7/8 completion
# after global-stack-lead-dev finishes. ADVISORY ONLY — emits a systemMessage
# JSON object on stdout, never {"decision":"block"}, always exits 0.
set -euo pipefail

# shellcheck source=../../.claude/hooks/log-helpers.sh
_HELPERS="$HOME/.claude/hooks/log-helpers.sh"
# shellcheck disable=SC1090
[[ -f "$_HELPERS" ]] && source "$_HELPERS" 2>/dev/null || true
# Rule 13: never fatal — define a no-op fallback when helpers are absent
declare -F log_obs >/dev/null 2>&1 || log_obs() { :; }

command -v jq &>/dev/null || exit 0

INPUT=$(cat 2>/dev/null || true)

# Log the payload's top-level keys once at INFO so a future session can
# verify the real SubagentStop schema (agent_name vs agent_type, etc.)
PAYLOAD_KEYS=$(printf '%s' "$INPUT" | jq -r 'keys_unsorted | join(", ")' 2>/dev/null) || exit 0
log_obs INFO subagent-stop-reminder "-stack | payload top-level keys: $PAYLOAD_KEYS" || true

AGENT=$(printf '%s' "$INPUT" | jq -r '.agent_type // .agent_name // empty' 2>/dev/null) || exit 0

# Only fire for the infra subagent; stay silent for others
[[ "$AGENT" == "global-stack-lead-dev" ]] || exit 0

log_obs INFO subagent-stop-reminder "-stack | fired for agent $AGENT" || true

MSG="The global-stack-lead-dev subagent is finishing. If it modified shell scripts (.sh), Dockerfiles, YAML files (.yaml/.yml), or env files (.env, .env.local), verify: 1) Phase 7 artifacts were updated or explicitly stated as not needed, 2) Phase 8 Verification Guide was provided (git status, git diff --stat, commit command as text only — never run). If only read/research actions were taken, no follow-up is needed. This reminder is advisory only."
jq -n --arg msg "$MSG" '{ "systemMessage": $msg }'

exit 0
