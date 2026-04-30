# bundle — Claude Code Config Bundle

`/bundle` bundles the current Claude Code configuration into a portable `.tar.gz`
archive. `/install` installs a bundle onto a new machine or project.

---

## Quick Start

```bash
/bundle                        # project scope (default): LLM-generalized with ADAPT markers
/bundle --scope global         # export ~/.claude/ only
/bundle --scope all            # produce both archives
```

---

## Scopes

| Scope | What is archived |
|---|---|
| `project` (default) | LLM-generalized CLAUDE.md + .claude/ with ADAPT markers — run `/adapt-project` after install |
| `global` | `~/.claude/` — commands, hooks, settings, CLAUDE.md, session-remember pipeline |
| `all` | Both archives in a single run |

---

## Install a bundle

```bash
# Project scope
bash ./claude-import.sh --target /path/to/project
# Then open Claude Code in that project and run:
/adapt-project     # fill ADAPT markers (~2 min)

# Global scope
bash ./claude-import.sh
# Then open Claude Code and run:
/memory-status
/audit --quick
```

---

## .claude.json Export (Global Scope)

`~/.claude.json` holds persistent Claude Code state: OAuth tokens, user identity,
org membership, project UUIDs, and absolute project paths. It is **not included by
default** because it contains sensitive fields that should not be shared across machines
or stored in version control.

### Opt-in flag

```bash
/bundle --scope global --include-claude-json
```

### Scrubbing (default: on)

When `~/.claude.json` is included, sensitive fields are stripped before archiving
via `jq del()`. Removed categories:

| Category | Fields |
|---|---|
| Identity | `oauthAccount`, `userID`, `accountUuid`, `organizationUuid`, `projects`, `firstStartTime` |
| Usage tracking | `skillUsage`, `tipsHistory`, usage counters |
| Caches | `clientDataCache`, `additionalModelCostsCache`, `metricsStatusCache`, … |
| Stale state | `changelogLastFetched`, `lastPlanModeUse`, migration flags |

To disable scrubbing (same-machine backup only — do **not** share the archive):

```bash
/bundle --scope global --include-claude-json --no-scrub-claude-json
```

### On import: conflict handling

If `~/.claude.json` already exists at the destination, the importer does **not**
overwrite it. Instead it:

1. Writes the incoming file as `~/.claude.json.imported`
2. Prints a manual migration guide containing:
   - A `diff ~/.claude.json ~/.claude.json.imported` to review field-by-field
   - A field classification table (safe-to-copy vs machine-specific vs credential)
   - A `jq` merge recipe to selectively apply non-sensitive fields

You must manually reconcile the two files before the import is considered complete.

---

## Security note

Even after scrubbing, `~/.claude.json` may still contain organisation name and team
membership. Use `--no-scrub-claude-json` only for same-machine backups where the
archive stays local and is never shared.
