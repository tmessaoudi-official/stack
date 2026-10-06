/stack subagent context (auto-injected by the SubagentStart hook from this file):
- shellcheck + hadolint + yamllint run automatically on every Edit/Write (PostToolUse hooks)
- Trailing ; in COMPOSE_FILE silently breaks the stack — always check after editing .env
- "Whether a port var must end with `:` is a property of its CONSUMER, not of the variable" (CLAUDE.md § Gotchas & Pitfalls): `${VAR:-}3306` needs the trailing `:` (else 427083306), but `${VAR:-}:${VAR:-}` and `--publish ${VAR}:5000` supply the colon themselves, so a trailing `:` there is the bug — check the consumer before "fixing" a var
- core.fileMode=false — chmod changes never appear in git diff/status; note them in commit msgs
- Tier 02 must be healthy before tier 03 can start (file-based health signaling via tools/successes/)
