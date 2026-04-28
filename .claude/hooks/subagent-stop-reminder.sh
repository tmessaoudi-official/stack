#!/usr/bin/env bash
# SubagentStop hook: remind the parent agent to verify Phase 7/8 completion
# after global-stack-lead-dev finishes. Stdout is injected as a system message.
set -euo pipefail

INPUT=$(cat 2>/dev/null || true)
AGENT=$(printf '%s' "$INPUT" | jq -r '.agent_name // empty' 2>/dev/null || true)

# Only fire for the infra subagent; approve silently for others
[[ "$AGENT" == "global-stack-lead-dev" ]] || exit 0

cat <<'EOF'
The global-stack-lead-dev subagent is finishing. If it modified shell scripts (.sh), Dockerfiles, YAML files (.yaml/.yml), or env files (.env, .env.local), verify: 1) Phase 7 artifacts were updated or explicitly stated as not needed, 2) Phase 8 Verification Guide was provided (git status, git diff --stat, commit command as text only — never run). If only read/research actions were taken, approve silently. Block only if code was changed without completing mandatory phases.
EOF
