#!/usr/bin/env bash
# Tests for scripts/claude-bootstrap/install.sh.
#
# Pins the contract ruled on 2026-08-06: THE REPO IS ALWAYS THE TRUTH. The three framework docs plus
# hooks/log-helpers.sh are copied UNCONDITIONALLY, and a pre-existing target that predates the hook is
# snapshotted ONCE to <name>.pre-bootstrap.bak and never re-written.
#
# Both halves need their own assertions, and the never-rewrite half is the subtle one: all five sibling
# repos ship this hook, so opening a sibling installs ITS copy over ours; on the next session the target
# differs from our source again, and a naive snapshot would overwrite the irreplaceable original with a
# sibling's copy. Section 4 covers exactly that.
#
# Run: bash bin/tests/install.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SUT="${REPO_ROOT}/scripts/claude-bootstrap/install.sh"

PASS=0
FAIL=0
FAILURES=()

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_GREEN=$'\033[32m'
  C_RED=$'\033[31m'
  C_BOLD=$'\033[1m'
  C_RESET=$'\033[0m'
else
  C_GREEN='' C_RED='' C_BOLD='' C_RESET=''
fi

ok() {
  PASS=$((PASS + 1))
  printf '  %b✓%b  %s\n' "${C_GREEN}" "${C_RESET}" "$1"
}
ko() {
  FAIL=$((FAIL + 1))
  FAILURES+=("$1")
  printf '  %b✗%b  %s\n' "${C_RED}" "${C_RESET}" "$1"
}

# Run install.sh against a throwaway HOME and a throwaway project dir.
run_install() { # run_install <fake-home> <fake-project>
  HOME="$1" CLAUDE_PROJECT_DIR="$2" bash "${SUT}" >/dev/null 2>&1
}

printf '\n%b── install.sh ──%b\n' "${C_BOLD}" "${C_RESET}"

# ── Section 1: static contract ──────────────────────────────────────────────
bash -n "${SUT}" 2>/dev/null && ok "syntax: bash -n clean" || ko "syntax: bash -n failed"

grep -q 'install_doc' "${SUT}" && ok "install_doc helper present" || ko "install_doc helper missing"

# EVERY scan below strips comments first. This script's header deliberately quotes both the forbidden
# copy-out block AND the superseded `cp -u` behaviour (including its false "never clobbered" claim), in
# past tense, so that neither can be silently reintroduced by someone who does not know the history. A
# naive grep matches those explanations and fails on a correct file. That exact false positive was a
# real bug in the upstream suite this was ported from, and it recurred here on the first run.
CODE_ONLY="$(mktemp)"
sed 's/#.*//' "${SUT}" >"${CODE_ONLY}"

grep -q 'cp -u' "${CODE_ONLY}" && ko "cp -u is still EXECUTED — it was nondeterministic" \
  || ok "no executed cp -u (the repo is the truth, unconditionally)"

grep -qE 'cp -f "\$src" "\$target"' "${CODE_ONLY}" \
  && ok "the copy is unconditional (cp -f) inside install_doc" \
  || ko "install_doc does not perform an unconditional cp -f"

# The false claim may be QUOTED as history, but only alongside its correction.
if grep -q 'never clobbered' "${SUT}"; then
  grep -q 'was FALSE' "${SUT}" \
    && ok "the old 'never clobbered' claim appears only as corrected history" \
    || ko "'never clobbered' is asserted without being marked FALSE"
else
  ok "no 'never clobbered' claim present at all"
fi

grep -q 'THE REPO IS ALWAYS THE TRUTH' "${SUT}" \
  && ok "header states the ruling it implements" || ko "header does not state the repo-is-truth ruling"
if grep -qE 'cp[^\n]*(\$HOME|~)/\.claude(\.json)?[^\n]*(repo|claude-bundle)' "${CODE_ONLY}"; then
  ko "EXECUTABLE copy-out of ~/.claude into the repo is present — credential exfiltration path"
else
  ok "no executable copy-out of ~/.claude (only the header explains why it must not return)"
fi
grep -q 'claude-bundle' "${SUT}" \
  && ok "header still documents the forbidden block (so it cannot be silently reintroduced)" \
  || ko "header no longer warns about the credential copy-out block"
rm -f "${CODE_ONLY}"

# ── Section 2: a clean install ──────────────────────────────────────────────
H="$(mktemp -d)"
P="$(mktemp -d)"
run_install "$H" "$P"
rc=$?
[[ $rc -eq 0 ]] && ok "clean install: exit 0" || ko "clean install: exit $rc"
for f in CLAUDE.md THINKING.md BLAST-RADIUS.md hooks/log-helpers.sh; do
  [[ -f "$H/.claude/$f" ]] && ok "clean install: ~/.claude/$f present" \
    || ko "clean install: ~/.claude/$f MISSING"
done
cmp -s "${REPO_ROOT}/scripts/claude-bootstrap/CLAUDE-global.md" "$H/.claude/CLAUDE.md" \
  && ok "clean install: CLAUDE.md is byte-identical to the repo source" \
  || ko "clean install: CLAUDE.md differs from the repo source"
[[ -d "$P/var/claude/handoff" ]] && ok "clean install: var/claude/handoff created" \
  || ko "clean install: var/claude/handoff missing"
[[ -d "$P/var/claude/logs" ]] && ok "clean install: var/claude/logs created (log_obs destination)" \
  || ko "clean install: var/claude/logs missing"
# No snapshot should exist when there was nothing to preserve.
[[ ! -e "$H/.claude/CLAUDE.md.pre-bootstrap.bak" ]] \
  && ok "clean install: no spurious .pre-bootstrap.bak when the target did not exist" \
  || ko "clean install: created a backup with nothing to back up"
rm -rf "$H" "$P"

# ── Section 3: THE REPO IS THE TRUTH ────────────────────────────────────────
H="$(mktemp -d)"
P="$(mktemp -d)"
mkdir -p "$H/.claude"
printf 'STALE HAND-EDITED CONTENT\n' >"$H/.claude/CLAUDE.md"
# Make the target NEWER than the source — this is precisely the case cp -u got wrong (it would skip).
touch "$H/.claude/CLAUDE.md"
run_install "$H" "$P"
if cmp -s "${REPO_ROOT}/scripts/claude-bootstrap/CLAUDE-global.md" "$H/.claude/CLAUDE.md"; then
  ok "repo-is-truth: a NEWER differing target is overwritten (cp -u would have skipped)"
else
  ko "repo-is-truth: newer target survived — the repo is not the truth"
fi
[[ -f "$H/.claude/CLAUDE.md.pre-bootstrap.bak" ]] \
  && ok "safety net: the pre-existing target was snapshotted" \
  || ko "safety net: no .pre-bootstrap.bak was taken"
grep -q 'STALE HAND-EDITED CONTENT' "$H/.claude/CLAUDE.md.pre-bootstrap.bak" 2>/dev/null \
  && ok "safety net: the snapshot holds the ORIGINAL content" \
  || ko "safety net: snapshot does not contain the original content"

# ── Section 4: never re-write the snapshot (the multi-repo case) ────────────
# Simulate a sibling repo's SessionStart installing ITS copy over ours.
printf 'A SIBLING REPO CONTENT\n' >"$H/.claude/CLAUDE.md"
run_install "$H" "$P"
grep -q 'STALE HAND-EDITED CONTENT' "$H/.claude/CLAUDE.md.pre-bootstrap.bak" 2>/dev/null \
  && ok "never-rewrite: a second run did NOT overwrite the original snapshot" \
  || ko "never-rewrite: the snapshot was overwritten by a later run — original lost"
grep -q 'A SIBLING REPO CONTENT' "$H/.claude/CLAUDE.md.pre-bootstrap.bak" 2>/dev/null \
  && ko "never-rewrite: the sibling's copy replaced the irreplaceable original" \
  || ok "never-rewrite: the sibling's copy did not become the snapshot"
cmp -s "${REPO_ROOT}/scripts/claude-bootstrap/CLAUDE-global.md" "$H/.claude/CLAUDE.md" \
  && ok "never-rewrite: our copy still wins the target after the sibling's run" \
  || ko "never-rewrite: target is not our copy"
rm -rf "$H" "$P"

# ── Section 5: idempotency ──────────────────────────────────────────────────
H="$(mktemp -d)"
P="$(mktemp -d)"
run_install "$H" "$P"
SUM1=$(cat "$H/.claude/CLAUDE.md" "$H/.claude/THINKING.md" "$H/.claude/BLAST-RADIUS.md" | sha256sum)
run_install "$H" "$P"
rc=$?
SUM2=$(cat "$H/.claude/CLAUDE.md" "$H/.claude/THINKING.md" "$H/.claude/BLAST-RADIUS.md" | sha256sum)
[[ $rc -eq 0 ]] && ok "idempotent: second run exits 0" || ko "idempotent: second run exit $rc"
[[ "$SUM1" == "$SUM2" ]] && ok "idempotent: the same bytes land every time" \
  || ko "idempotent: content changed between identical runs"
[[ ! -e "$H/.claude/CLAUDE.md.pre-bootstrap.bak" ]] \
  && ok "idempotent: no backup taken when the target already equals the source" \
  || ko "idempotent: took a backup of an identical file"
rm -rf "$H" "$P"

printf '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
if [[ "${FAIL}" -eq 0 ]]; then
  printf '  %bALL PASSED%b   ✓ %d / %d\n' "${C_GREEN}" "${C_RESET}" "${PASS}" "$((PASS + FAIL))"
else
  printf '  %bFAILED%b        ✗ %d / %d\n' "${C_RED}" "${C_RESET}" "${FAIL}" "$((PASS + FAIL))"
  for f in "${FAILURES[@]}"; do printf '    - %s\n' "$f"; done
  exit 1
fi
