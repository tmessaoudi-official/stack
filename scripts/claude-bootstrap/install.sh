#!/usr/bin/env bash
# /stack Claude-container bootstrap — restores the developer's global reasoning framework into the
# EPHEMERAL remote container (a fresh ~/.claude every session), so the project CLAUDE.md's routing
# reference ("the global reasoning framework defined in ~/.claude/CLAUDE.md") resolves everywhere.
#
# Without this, that reference dangles: verified 2026-08-05 — a fresh container has no
# ~/.claude/CLAUDE.md at all, so every non-/stack task ran with the framework silently missing.
#
# Idempotent + conservative: `cp -u` copies only when the repo copy is NEWER than the target, so a
# hand-edited (newer) ~/.claude file on a real workstation is never clobbered. Silent no-op when
# already current. Wired as a SessionStart hook in .claude/settings.json; safe to run by hand.
#
# SCOPE IS DELIBERATELY NARROW: this script copies three documentation files INTO ~/.claude and
# creates one directory. It must NEVER copy anything OUT of ~/.claude into the repo — ~/.claude.json
# holds the OAuth account, userID and machineID, and this working tree is one `git add -A` away from
# history. (The upstream port this was adapted from did exactly that behind a commented-out block;
# it is omitted here on purpose, not merely disabled.)
#
# The repo-native skills (.claude/skills/*) and agents (.claude/agents/*) need NO install — Claude
# Code reads them in place from the clone.
set -eEuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
dest="${HOME}/.claude"

mkdir -p "$dest"

cp -u "$here/CLAUDE-global.md" "$dest/CLAUDE.md"
cp -u "$here/THINKING.md" "$dest/THINKING.md"
cp -u "$here/BLAST-RADIUS.md" "$dest/BLAST-RADIUS.md"

# The project's five PostToolUse hooks (.claude/hooks/*-on-write.sh) each source
# "$HOME/.claude/hooks/log-helpers.sh" and fall back to a no-op log_obs() when it is missing — which
# it always is in a fresh container, so their Rule 13 logging was silently dead. Installing it here
# restores it. Same `cp -u` discipline: a newer hand-edited copy is never clobbered.
mkdir -p "$dest/hooks"
cp -u "$here/hooks/log-helpers.sh" "$dest/hooks/log-helpers.sh"

# var/claude/ is the in-repo, gitignored home for everything the review skills and the PreCompact
# handoff hook write. Created here so a skill never has to guess whether it exists. `/var` is already
# covered by .gitignore, so nothing under it can be committed by accident.
mkdir -p "${CLAUDE_PROJECT_DIR:-$repo}/var/claude/handoff"

exit 0
