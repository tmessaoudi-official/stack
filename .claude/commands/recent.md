Quick context loader — show recent project state at a glance.

## Steps (run all, report together):
1. **Recent commits**: `git log --oneline -10`
2. **Uncommitted changes**: `git status --short` (if any)
3. **Changed files stats**: `git diff --stat` (if any uncommitted changes)
4. **Health status**: check `tools/errors/` for any failed services, `tools/successes/` for healthy count
5. **Active locks**: check `tools/locks/` for any services with active locks

## Output:
- Compact summary in sections:
  - Last 10 commits (one line each)
  - Working tree status (clean or list of changes)
  - Stack health (X healthy, Y failed, Z locked — or "stack not running" if no markers)
- If there are failed services, show the error token names prominently
- Keep output concise — this is a context snapshot, not a deep analysis

$ARGUMENTS
