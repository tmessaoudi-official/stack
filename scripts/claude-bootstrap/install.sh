#!/usr/bin/env bash
# /stack Claude-container bootstrap — restores the developer's global reasoning framework into the
# EPHEMERAL remote container (a fresh ~/.claude every session), so the project CLAUDE.md's routing
# reference ("the global reasoning framework defined in ~/.claude/CLAUDE.md") resolves everywhere.
#
# Without this, that reference dangles: verified 2026-08-05 — a fresh container has no
# ~/.claude/CLAUDE.md at all, so every non-/stack task ran with the framework silently missing.
#
# THE REPO IS ALWAYS THE TRUTH (developer ruling, 2026-08-06, ported from rent-watch). The files below
# are copied UNCONDITIONALLY on every run. Idempotent — the same bytes land every time — and
# deterministic, which is the point of the ruling.
#
# This replaced `cp -u`, whose header used to claim "a hand-edited (newer) ~/.claude file on a real
# workstation is never clobbered". That claim was FALSE, and the behaviour was nondeterministic:
# `cp -u` copies when the SOURCE is newer, and a fresh `git clone` stamps every file with the clone
# time — so on a real workstation it clobbered anyway, while after a hand-edit of the target it
# silently did nothing and the repo stopped being the truth. Neither outcome was chosen; both depended
# on mtimes nobody was tracking. `bin/tests/install.test.sh` pins the new contract.
#
# The one thing unconditional copying must not do is destroy a global framework with no way back, so a
# file that predates this hook is snapshotted ONCE to <name>.pre-bootstrap.bak and never touched again.
# That is a safety net, not a second source of truth: it is never read back, and the repo still wins
# every session.
#
# Wired as a SessionStart hook in .claude/settings.json; safe to run by hand.
#
# SCOPE IS DELIBERATELY NARROW: this script copies documentation into ~/.claude and creates two
# directories. It must never copy anything OUT of ~/.claude into the repo — `~/.claude.json` holds the
# OAuth account, userID and machineID, and THIS REPO IS PUBLIC and one `git add -A` away from history.
#
# The upstream port this descends from (phorj) carried, commented out, a block doing exactly that:
#     # cp -R /root/.claude /root/.claude.json <repo>/claude-bundle
#     # git add claude-bundle && commit && push --force-with-lease
# It is absent here by construction and must never be reintroduced, not even commented out: a disabled
# credential-exfiltration path inside a SessionStart hook is one uncomment away from publishing the
# developer's OAuth tokens. phorj deleted its own copy on 2026-08-06 for this reason, having verified it
# never ran. `/claude-bundle/` is additionally gitignored here as a belt-and-braces guard, so even an
# accidental copy cannot be committed.
#
# The repo-native skills (.claude/skills/*) and agents (.claude/agents/*) need NO install — Claude
# Code reads them in place from the clone.
set -eEuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
dest="${HOME}/.claude"

mkdir -p "$dest"

# install_doc <repo-source> <target-relative-name>
#   1. If the target exists, predates this hook, and differs from what we are about to write, take a
#      one-time snapshot. "Predates this hook" is inferred from the absence of the snapshot itself —
#      once it exists we never write it again, so a later run cannot overwrite the original with our
#      own copy. That ordering is the whole trick, and bin/tests/install.test.sh asserts the converse.
#      The never-rewrite half is load-bearing in the MULTI-REPO case: all five sibling repos ship this
#      hook, so opening twes-in installs its copy over ours, and on the next session the target differs
#      from our source again. Without the guard we would snapshot twes-in's copy over the irreplaceable
#      original.
#   2. Copy unconditionally. The repo is the truth.
install_doc() {
  local src="$1" name="$2"
  local target="$dest/$name"
  local backup="$target.pre-bootstrap.bak"

  mkdir -p "$(dirname "$target")"

  if [[ -f "$target" && ! -e "$backup" ]] && ! cmp -s "$src" "$target"; then
    cp -p "$target" "$backup" 2>/dev/null \
      && printf 'claude-bootstrap: kept your previous %s as %s\n' "$name" "${backup##*/}" >&2
  fi

  cp -f "$src" "$target"
}

install_doc "$here/CLAUDE-global.md" CLAUDE.md
install_doc "$here/THINKING.md" THINKING.md
install_doc "$here/BLAST-RADIUS.md" BLAST-RADIUS.md

# The project's five PostToolUse hooks (.claude/hooks/*-on-write.sh) each source
# "$HOME/.claude/hooks/log-helpers.sh" and fall back to a no-op log_obs() when it is missing — which it
# always is in a fresh container, so their Rule 13 logging was silently dead. Installing it restores it.
install_doc "$here/hooks/log-helpers.sh" hooks/log-helpers.sh

# var/claude/ is the in-repo, gitignored home for everything the review skills, the PreCompact handoff
# hook and log_obs write. Created here so nothing has to guess whether it exists. `/var` is already
# covered by .gitignore, so nothing under it can be committed by accident.
mkdir -p "${CLAUDE_PROJECT_DIR:-$repo}/var/claude/handoff" \
  "${CLAUDE_PROJECT_DIR:-$repo}/var/claude/logs"

exit 0
