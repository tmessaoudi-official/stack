/stack subagent context (auto-injected by the SubagentStart hook from this file):
- shellcheck + hadolint + yamllint run automatically on every Edit/Write (PostToolUse hooks)
- Trailing ; in COMPOSE_FILE silently breaks the stack — always check after editing .env
- Port vars must end with : when set (e.g. 42708:); omitting : silently concatenates ports
- core.fileMode=false — chmod changes never appear in git diff/status; note them in commit msgs
- Tier 02 must be healthy before tier 03 can start (file-based health signaling via tools/successes/)
