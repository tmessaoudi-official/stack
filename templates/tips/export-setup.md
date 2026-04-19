# export-setup — Claude Code Config Bundle

`/export-setup` bundles the current Claude Code configuration into a portable `.tar.gz`
archive. `/import-setup` installs a bundle onto a new machine or project.

---

## Quick Start

```bash
/export-setup                        # project scope (default): export /stack config
/export-setup --scope global         # export ~/.claude/ only
/export-setup --scope all            # produce both archives
```

---

## Scopes

| Scope | What is archived |
|---|---|
| `project` (default) | `/stack/CLAUDE.md`, `/stack/.claude/` — LLM-generalised with ADAPT markers |
| `global` | `~/.claude/` as-is (agents, hooks, commands, settings, memory) |
| `all` | Both archives in a single run |

---

## .claude.json Export (Global Scope)

`~/.claude.json` holds persistent Claude Code state: OAuth tokens, user identity,
org membership, project UUIDs, and absolute project paths. It is **not included by
default** because it contains sensitive fields that should not be shared across machines
or stored in version control.

### Opt-in flag

```bash
/export-setup --scope global --include-claude-json
```

### Scrubbing (default: on)

When `~/.claude.json` is included, sensitive fields are scrubbed before archiving:

| Field scrubbed | Why |
|---|---|
| `oauthAccount` | OAuth token + email — credential |
| `userID` | Internal Anthropic UUID |
| `projects` | Absolute paths + per-project UUIDs |
| Any UUID-shaped value | Prevents identity linkage |

To disable scrubbing (same-machine backup only — do **not** share the archive):

```bash
/export-setup --scope global --include-claude-json --no-scrub-claude-json
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

Even after scrubbing, `~/.claude.json` may still contain organisation name, team
membership, and non-UUID identifiers. Use `--no-scrub-claude-json` only for
same-machine backups where the archive stays local and is never shared.
