#!/usr/bin/env bash
# Apply a pending .claude/settings.json change that Claude cannot write itself.
#
# WHY THIS EXISTS: Claude Code's safety classifier blocks Claude from writing `.claude/settings.json`
# (self-modification of its own permission surface). In a remote container the developer has no
# terminal either, so the hand-over has to travel through the repo: Claude commits
# `settings.json.pending`, the developer pulls, runs THIS script on their machine, and pushes the
# result back. Claude then pulls to re-sync.
#
# NOT A LASTING DUPLICATE: on success this script DELETES settings.json.pending, so the repo never
# carries two copies of the settings.
#
# Validation uses `jq`, which is already a hard dependency of this project (bin/env-update.sh) —
# unlike the upstream port's `python3`, which is not guaranteed on a /stack host.
#
# Usage:  bash scripts/claude-bootstrap/apply-pending-settings.sh
set -eEuo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
pending="$here/settings.json.pending"
target="$repo/.claude/settings.json"

cd "$repo"

if [[ ! -f "$pending" ]]; then
  echo "Nothing to apply — ${pending#"$repo"/} does not exist (already applied?)."
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required to validate the settings before applying them." >&2
  exit 1
fi

# Validate BEFORE touching the live file — a malformed settings.json breaks every future session.
jq empty <"$pending" && echo "pending settings: valid JSON"

if [[ -f "$target" ]]; then
  backup="$target.bak.$(date +%s)"
  cp -a "$target" "$backup"
  echo "backup: ${backup#"$repo"/}   (gitignored — never commit one)"
fi

mkdir -p "$repo/.claude"
cp -f "$pending" "$target"
jq empty <"$target" && echo "applied settings: valid JSON"
rm -f "$pending"

echo
echo "--- diff vs HEAD -------------------------------------------------------"
git --no-pager diff --stat -- .claude/settings.json scripts/claude-bootstrap/settings.json.pending || true
echo "-----------------------------------------------------------------------"
echo
echo "Applied. Review the diff, then:"
echo "    git add .claude/settings.json scripts/claude-bootstrap/settings.json.pending"
echo "    git commit -m 'chore(claude): apply the allow-list-only settings + bootstrap hooks'"
echo "    git push -u origin master"
echo
echo "Nothing was staged, committed or pushed by this script."
