#!/usr/bin/env bash
# git-strip-coauthored.sh — Remove "Co-Authored-By: Claude*" from all commits in a repo.
#
# Usage:
#   bash git-strip-coauthored.sh            # rewrite history in-place
#   bash git-strip-coauthored.sh --dry-run  # count affected commits, no changes
#
# Requires: git-filter-repo (pip install git-filter-repo)
# After running on a pushed repo: git push --force-with-lease

set -euo pipefail

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# ── Pre-flight ────────────────────────────────────────────────────────────────

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "ERROR: not inside a git repository" >&2
  exit 1
fi

if ! command -v git-filter-repo >/dev/null 2>&1; then
  echo "ERROR: git-filter-repo not found. Install with: pip install git-filter-repo" >&2
  exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

# Warn about dirty working tree
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: uncommitted changes detected. Commit or stash first." >&2
  exit 1
fi

# ── Remote warning ────────────────────────────────────────────────────────────

REMOTES=$(git remote 2>/dev/null | tr '\n' ' ')
if [[ -n "$REMOTES" ]]; then
  echo "WARNING: repo has remotes: ${REMOTES}"
  echo "         After rewriting, force-push each branch:"
  echo "           git push --force-with-lease"
  echo "         Anyone else with a clone must run:"
  echo "           git fetch && git reset --hard origin/<branch>"
  echo ""
fi

# ── Count affected commits ────────────────────────────────────────────────────

AFFECTED=0
while IFS= read -r sha; do
  if git show -s --format="%B" "$sha" | grep -q "^Co-Authored-By: Claude"; then
    (( AFFECTED++ )) || true
  fi
done < <(git log --all --format="%H")

TOTAL=$(git log --all --format="%H" | wc -l | tr -d ' ')
echo "Commits affected: ${AFFECTED} / ${TOTAL} total"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "(--dry-run: no changes made)"
  exit 0
fi

if [[ "$AFFECTED" -eq 0 ]]; then
  echo "Nothing to do."
  exit 0
fi

# ── Rewrite ───────────────────────────────────────────────────────────────────

echo "Rewriting history..."

git filter-repo --force --message-callback '
import re

# Strip the Co-Authored-By: Claude line, eating the newline that precedes it
message = re.sub(rb"\nCo-Authored-By: Claude[^\n]*", b"", message)

# Collapse 3+ consecutive newlines left by mid-message removal
message = re.sub(rb"\n{3,}", b"\n\n", message)

# Ensure exactly one trailing newline
return message.rstrip(b"\n") + b"\n"
'

echo ""
echo "Done. Verification:"
REMAINING=$(git log --all --format="%B" | grep -c "^Co-Authored-By: Claude" 2>/dev/null || true)
echo "  Co-Authored-By: Claude lines remaining: ${REMAINING}"
if [[ "$REMAINING" -eq 0 ]]; then
  echo "  Clean."
else
  echo "  WARNING: some lines remain — inspect with: git log --all --format='%B' | grep 'Co-Authored'"
fi
