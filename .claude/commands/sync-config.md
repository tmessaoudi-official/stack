# /sync-config — Configuration Drift Detection & Repair

Detect and repair documentation/config drift between what's documented in `CLAUDE.md` + `.claude/`
and what actually exists in the project (files, tools, commands, structure, dependencies).

Run after merges, feature additions, refactors, or any time you suspect the config is stale.
Never self-destructs. Safe to run anytime.

**Modes:**
```
/sync-config              # Scan, present plan, wait for confirmation
/sync-config --check      # Scan only, report drift, no changes (exit 0 = clean, 1 = drift found)
/sync-config --apply      # Scan, present plan, apply all fixable items without prompting
```

---

## Phase 0: Announce scope

State the project root and config files being scanned:
- `CLAUDE.md` (project-level documentation)
- `.claude/commands/*.md` (slash command definitions)
- `.claude/hooks/*.sh` (active hooks)
- `.claude/hooks/*.sh.template` (inactive hook templates)
- `.claude/agents/*.md` (agent definitions)
- `.claude/settings.json` (permissions + hooks config)

---

## Phase 1: Scan for drift

Check all four drift categories systematically. Use parallel Bash lookups where possible.

### MISSING — real thing exists but not documented

**Slash commands**: Find all `.md` files in `.claude/commands/` and check each is listed
in CLAUDE.md under "Slash commands". Ignore `adapt.md` and `sync-config.md` (meta-commands
that manage themselves).
```bash
ls .claude/commands/ 2>/dev/null
grep -n '`/' CLAUDE.md | grep -v '^#'
```

**Hooks**: Find all `.sh` files (not `.sh.template`) in `.claude/hooks/` and check each is:
1. Listed in CLAUDE.md under "Automatic hooks"
2. Present in `.claude/settings.json` PostToolUse entries
```bash
ls .claude/hooks/*.sh 2>/dev/null
grep -n 'hooks' CLAUDE.md
```

**Agents**: Find all `.md` files in `.claude/agents/` and check each is listed in CLAUDE.md
Claude Code Configuration section.

**Tools in allow list**: Check if common project tools are installed but not in settings.json allow:
- Probe `package.json` scripts for linters/formatters mentioned but not in allow list
- Check `Makefile`, `.pre-commit-config.yaml`, CI configs for tool names

**Unregistered hooks**: Find `.sh` files in `.claude/hooks/` present on disk but NOT
in `settings.json` PostToolUse.

### STALE — documented thing has changed

**Common Workflows commands**: For each bash command listed in CLAUDE.md `## Common Workflows`,
verify it still works:
- Makefile targets: `grep -q '^<target>:' Makefile` (or local.Makefile)
- npm scripts: `jq -r '.scripts | keys[]' package.json 2>/dev/null`
- bin/ scripts: `test -f bin/<script>`
- Installed binaries: `which <binary> 2>/dev/null`

**File Layout paths**: For each path listed in CLAUDE.md `## File Layout Quick Reference`,
check `test -e <path>`.

**Architecture component dirs**: For each directory mentioned in `## Architecture`,
check `test -d <dir>`.

**Hook tool availability**: For each hook `.sh` file, extract the tool name from the
`LINTER=` or `FORMATTER=` variable and check `which <tool>`.

**settings.json allow entries**: For each binary in the `allow` list that looks like a tool
(not a path pattern), check `which <binary>`.

### OBSOLETE — documented thing no longer exists

**Slash commands in CLAUDE.md not on disk**: for each `/command` listed, check
`.claude/commands/<command>.md` exists.

**Hooks in CLAUDE.md not on disk**: for each hook listed, check `.claude/hooks/<name>.sh` exists.

**Agents in CLAUDE.md not on disk**: for each agent listed, check `.claude/agents/<name>.md` exists.

**settings.json hook scripts**: for each `"command": ".claude/hooks/<name>.sh"` entry,
check the `.sh` file exists.

**settings.json allow entries that are gone**: binaries listed in allow that return nothing
from `which` AND cannot be found anywhere in the project (`find . -name <binary> -type f`).
Only flag — don't auto-remove (binary might be in PATH on target machine).

### LINGERING — unfilled ADAPT markers

```bash
grep -rn '<!-- ADAPT:' CLAUDE.md .claude/ 2>/dev/null | grep -v '.sh.template'
```

Also check for hook templates never activated:
```bash
find .claude/hooks/ -name '*.sh.template' 2>/dev/null
```

---

## Phase 2: Present the plan

Format the findings as a plan — not just a report. For each finding, state what will
be changed and exactly how. Group by category.

```
SYNC-CONFIG PLAN — /path/to/project (YYYY-MM-DD)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

MISSING (N)
──────────
[M1] CLAUDE.md › Slash commands — /lint not listed
     Fix: add `- \`/lint\` — [description from lint.md first line]` to the list

[M2] settings.json › allow — 'prettier' installed ($(which prettier)) but not in allow list
     Fix: add "Bash(prettier:*)" to settings.json allow array

STALE (N)
─────────
[S1] CLAUDE.md › Common Workflows — `npm test` listed but package.json uses `vitest`
     Fix: replace `npm test` → `npx vitest run` in Common Workflows section

[S2] CLAUDE.md › File Layout — `src/handlers/` listed but directory not found
     Fix: flag for manual review — directory may have been renamed or removed

OBSOLETE (N)
────────────
[O1] CLAUDE.md › Slash commands — `/service-info` listed but .claude/commands/service-info.md missing
     Fix: remove the `/service-info` line from CLAUDE.md slash commands list

[O2] settings.json › PostToolUse — hook '.claude/hooks/old-hook.sh' registered but file missing
     Fix: remove the orphaned PostToolUse entry from settings.json

LINGERING (N)
─────────────
[L1] CLAUDE.md line 45 — `<!-- ADAPT: Describe your project -->` still present
     Fix: manual — run /adapt to fill, or edit CLAUDE.md directly

[L2] .claude/hooks/lint-on-write.sh.template — hook template never activated
     Fix: manual — fill LINTER/EXT and rename to lint-on-write.sh, or run /adapt

────────────────────────────────────────────────
Fixable automatically: M1, M2, S1, O1, O2  (5 items)
Requires manual input:  S2, L1, L2           (3 items)

Apply fixes for M1, M2, S1, O1, O2? (yes / no / [item numbers e.g. M1 O1])
If none of these fit, describe what you want instead.
```

**In `--check` mode**: print the report above, then stop. Return exit-equivalent "found drift"
message if any finding exists.

**In default mode**: print the plan and wait for user confirmation before making any change.

**In `--apply` mode**: print the plan, then immediately apply all automatically-fixable items
(MISSING + fixable STALE + OBSOLETE). Report what was done. Skip LINGERING and manual-only items.

---

## Phase 3: Apply fixes (after confirmation)

Apply only the confirmed items. For each:

### MISSING — add to CLAUDE.md or settings.json

**Adding a command to CLAUDE.md slash commands list**:
Read the first non-empty, non-`#` line of the command's `.md` file as the description.
Append to the slash commands list in alphabetical order.

**Adding to settings.json allow list**:
Read the current `allow` array, append the new entry, write back.
Preserve all existing entries and formatting.

**Adding a hook to CLAUDE.md hooks list**:
Extract the hook's purpose from the `# PostToolUse hook:` comment at the top of the `.sh` file.
Append to the hooks list.

**Registering a hook in settings.json**:
Add a PostToolUse entry. Infer the `matcher` from the hook's extension guard (`EXT` variable).

### STALE — update to match reality

**Workflow command changed** (e.g. `npm test` → `vitest`):
Replace only the specific command in the Common Workflows section. Preserve surrounding context.

**File layout path renamed**: flag as manual — don't auto-rename documentation for structural
changes; the user knows the intent better than the probe does.

### OBSOLETE — remove stale references

**Command removed from disk**: remove its line from CLAUDE.md slash commands list.

**Hook removed from disk**: remove its line from CLAUDE.md hooks list AND remove its
`PostToolUse` entry from `settings.json`.

**Orphaned settings.json hook entry**: remove just that entry from `PostToolUse` array.

### What is NEVER auto-fixed (always manual)

- Architecture section rewrites
- What This Project Is / Gotchas / Credentials sections
- LINGERING ADAPT markers (use `/adapt` for those)
- Tool removals from settings.json allow list (binary might exist on another machine)
- Any section where the correct new content requires domain knowledge

---

## Phase 4: Summary

After applying fixes, report:
```
SYNC-CONFIG COMPLETE
  Applied:  N fixes (list items)
  Skipped:  M items (list with reason)
  Manual:   K items require your attention (list with instructions)
  
Config is now in sync with project state.
```

If nothing was applied and nothing needs attention: "Config is clean — no drift found."
