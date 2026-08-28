#!/usr/bin/env bash
# git-strip-coauthored.sh — Remove "Co-Authored-By: Claude*" from all commits in a repo.
#
# Usage:
#   bash git-strip-coauthored.sh                # report only (default)
#   bash git-strip-coauthored.sh --dry-run      # same, stated explicitly
#   bash git-strip-coauthored.sh --apply        # rewrite (prompts on a TTY)
#   bash git-strip-coauthored.sh --apply --yes  # rewrite unattended
#
# Requires: git-filter-repo (pip install git-filter-repo)
# After running on a pushed repo: git push --force-with-lease

set -euo pipefail

usage() {
  cat <<'USAGE'
git-strip-coauthored.sh — remove "Co-Authored-By: Claude*" trailers from all commits.

Usage:
  git-strip-coauthored.sh                Report how many commits are affected. No changes.
  git-strip-coauthored.sh --dry-run      Same as above, stated explicitly.
  git-strip-coauthored.sh --apply        Rewrite history. Prompts for confirmation on a TTY.
  git-strip-coauthored.sh --apply --yes  Rewrite history without prompting (scripts, CI).
  git-strip-coauthored.sh --help         This text.

The rewrite runs `git filter-repo --force`, which is IRREVERSIBLE: it drops
refs/original, expires the reflog and gc's, so there is no ORIG_HEAD to return
to, and every commit SHA in the repo changes. Other clones must recover with
`git fetch && git reset --hard origin/<branch>`.
USAGE
}

# Reporting is the default and the rewrite is opt-in, mirroring env-update's
# self-guarding --apply. The previous handling was a single exact-string test
# against --dry-run with no unknown-argument arm, so `--help`, a typo, or a
# guessed short form all fell through to the irreversible rewrite.
DRY_RUN=0
APPLY=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --apply) APPLY=1 ;;
    --yes | -y) ASSUME_YES=1 ;;
    --help | -h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      echo "Try --help. Nothing was changed." >&2
      exit 2
      ;;
  esac
  shift
done

# No --apply means report only, whether or not --dry-run was passed.
[[ "${APPLY}" -eq 1 ]] || DRY_RUN=1

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
    ((AFFECTED++)) || true
  fi
done < <(git log --all --format="%H")

TOTAL=$(git log --all --format="%H" | wc -l | tr -d ' ')
echo "Commits affected: ${AFFECTED} / ${TOTAL} total"

if [[ "$DRY_RUN" == "1" ]]; then
  echo "(no changes made — re-run with --apply to rewrite history)"
  exit 0
fi

if [[ "$AFFECTED" -eq 0 ]]; then
  echo "Nothing to do."
  exit 0
fi

# ── Confirmation gate ─────────────────────────────────────────────────────────
# The rewrite is irreversible, so it is never reached unattended by accident:
# on a TTY the operator confirms, and off one --yes must have been passed.

if [[ "${ASSUME_YES}" -ne 1 ]]; then
  if [[ -t 0 ]]; then
    printf 'Rewrite %s commit(s) in %s? This is IRREVERSIBLE. [y/N] ' \
      "${AFFECTED}" "${REPO_ROOT}"
    read -r _reply
    if [[ ! "${_reply}" =~ ^[Yy]$ ]]; then
      echo "Aborted. Nothing was changed."
      exit 1
    fi
  else
    echo "ERROR: --apply needs a TTY to confirm on. Pass --yes to rewrite unattended." >&2
    echo "       Nothing was changed." >&2
    exit 1
  fi
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
