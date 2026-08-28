#!/usr/bin/env bash
# Tests for bin/git-strip-coauthored.sh — argument handling and the apply gate.
#
# The script's only job is an IRREVERSIBLE `git filter-repo --force`. `--force`
# exists to bypass git-filter-repo's own "this is not a fresh clone" guard, and
# filter-repo then drops refs/original, expires the reflog and gc's — so there
# is no ORIG_HEAD to go back to. That makes argument handling a safety surface,
# not a convenience: every path that reaches the rewrite must be one the caller
# asked for in so many words.
#
# Every case below runs against a throwaway repo with a STUB git-filter-repo
# first on PATH, so a regression here can never touch real history. The stub
# records its invocation; "did not invoke" is asserted on the marker file, not
# on stdout wording.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/../git-strip-coauthored.sh"

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

# Build a throwaway repo plus a stub git-filter-repo that records its arguments.
# $1: "tainted" (default) seeds a commit carrying a Co-Authored-By trailer;
#     "clean" seeds one without, so the "nothing to do" path can be reached.
make_repo() {
  local kind="${1:-tainted}" root
  root="$(mktemp -d)"
  mkdir -p "${root}/stub" "${root}/repo"
  printf '#!/bin/sh\nprintf "%%s" "$*" > "%s/invoked"\nexit 0\n' "${root}" \
    >"${root}/stub/git-filter-repo"
  chmod +x "${root}/stub/git-filter-repo"
  git -C "${root}/repo" init -q .
  git -C "${root}/repo" config user.email a@b.c
  git -C "${root}/repo" config user.name A
  printf 'x\n' >"${root}/repo/f.txt"
  git -C "${root}/repo" add f.txt
  if [[ "${kind}" == "clean" ]]; then
    git -C "${root}/repo" commit -q -m 'feat: x'
  else
    git -C "${root}/repo" commit -q -F - <<'MSG'
feat: x

Co-Authored-By: Claude <noreply@anthropic.com>
MSG
  fi
  printf '%s\n' "${root}"
}

# Run the script inside the throwaway repo with the stub first on PATH.
# Sets: RC (exit code), OUT (merged stdout+stderr), INVOKED (1 if the stub ran).
run_sut() {
  local root="$1"
  shift
  rm -f "${root}/invoked"
  OUT="$(cd "${root}/repo" && PATH="${root}/stub:${PATH}" bash "${SUT}" "$@" 2>&1)"
  RC=$?
  if [[ -e "${root}/invoked" ]]; then INVOKED=1; else INVOKED=0; fi
}

printf '\n%b── git-strip-coauthored.sh ──%b\n' "${C_BOLD}" "${C_RESET}"

# ── The reported P0: --help rewrote history ────────────────────────────────
# `--help` is the single most likely first thing anyone types at an unfamiliar
# destructive script. It fell through the exact-match test against --dry-run
# straight into the rewrite.
ROOT="$(make_repo)"
run_sut "${ROOT}" --help
[[ "${INVOKED}" -eq 0 ]] && ok "--help does not rewrite history" \
  || ko "--help INVOKED git-filter-repo (irreversible)"
[[ "${RC}" -eq 0 ]] && ok "--help exits 0" || ko "--help exit ${RC} (want 0)"
grep -qi 'usage' <<<"${OUT}" && ok "--help prints usage" \
  || ko "--help printed no usage: ${OUT}"
rm -rf "${ROOT}"

# ── Unknown arguments must be refused, never treated as "rewrite" ──────────
# A typo, a guessed short form, or a different case all silently meant "yes,
# rewrite everything" — the failure mode is indistinguishable from the intent.
for bad in --dryrun -n --dry_run --dry-run=1 --DRY-RUN --appply; do
  ROOT="$(make_repo)"
  run_sut "${ROOT}" "${bad}"
  [[ "${INVOKED}" -eq 0 ]] && ok "unknown arg ${bad} does not rewrite history" \
    || ko "unknown arg ${bad} INVOKED git-filter-repo (irreversible)"
  [[ "${RC}" -eq 2 ]] && ok "unknown arg ${bad} exits 2" \
    || ko "unknown arg ${bad} exit ${RC} (want 2)"
  rm -rf "${ROOT}"
done

# ── The default must be the safe one ───────────────────────────────────────
# Mirrors env-update, whose --apply is self-guarding: reporting is free, and
# the destructive half is opt-in.
ROOT="$(make_repo)"
run_sut "${ROOT}"
[[ "${INVOKED}" -eq 0 ]] && ok "no arguments does not rewrite history" \
  || ko "no arguments INVOKED git-filter-repo (irreversible)"
[[ "${RC}" -eq 0 ]] && ok "no arguments exits 0" || ko "no arguments exit ${RC} (want 0)"
grep -q -- '--apply' <<<"${OUT}" && ok "no arguments names --apply as the way to proceed" \
  || ko "no arguments did not mention --apply: ${OUT}"
rm -rf "${ROOT}"

# ── --dry-run keeps working exactly as documented ──────────────────────────
ROOT="$(make_repo)"
run_sut "${ROOT}" --dry-run
[[ "${INVOKED}" -eq 0 ]] && ok "--dry-run does not rewrite history" \
  || ko "--dry-run INVOKED git-filter-repo"
[[ "${RC}" -eq 0 ]] && ok "--dry-run exits 0" || ko "--dry-run exit ${RC} (want 0)"
grep -q 'Commits affected: 1 / 1' <<<"${OUT}" && ok "--dry-run counts the affected commit" \
  || ko "--dry-run miscounted: ${OUT}"
rm -rf "${ROOT}"

# ── --apply is the only path to the rewrite, and needs --yes when not a TTY ─
# The suite is never a TTY, so this asserts the non-interactive half of the
# gate; the TTY half prompts instead.
ROOT="$(make_repo)"
run_sut "${ROOT}" --apply
[[ "${INVOKED}" -eq 0 ]] && ok "--apply without --yes does not rewrite (non-TTY)" \
  || ko "--apply without --yes INVOKED git-filter-repo unattended"
[[ "${RC}" -ne 0 ]] && ok "--apply without --yes exits non-zero (non-TTY)" \
  || ko "--apply without --yes exited 0 having done nothing"
rm -rf "${ROOT}"

ROOT="$(make_repo)"
run_sut "${ROOT}" --apply --yes
[[ "${INVOKED}" -eq 1 ]] && ok "--apply --yes performs the rewrite" \
  || ko "--apply --yes did NOT invoke git-filter-repo: ${OUT}"
[[ "${RC}" -eq 0 ]] && ok "--apply --yes exits 0" || ko "--apply --yes exit ${RC} (want 0)"
rm -rf "${ROOT}"

# ── Nothing to strip: the rewrite must not run at all ──────────────────────
# A no-op filter-repo still rewrites every SHA in the repo, so "0 affected"
# has to short-circuit before the call, not rely on the callback being a no-op.
ROOT="$(make_repo clean)"
run_sut "${ROOT}" --apply --yes
[[ "${INVOKED}" -eq 0 ]] && ok "no affected commits: does not rewrite history" \
  || ko "no affected commits: INVOKED git-filter-repo anyway (all SHAs change)"
[[ "${RC}" -eq 0 ]] && ok "no affected commits: exits 0" \
  || ko "no affected commits: exit ${RC} (want 0)"
rm -rf "${ROOT}"

# ── Summary ────────────────────────────────────────────────────────────────
TOTAL=$((PASS + FAIL))
printf '\n'
if [[ "${FAIL}" -eq 0 ]]; then
  printf '  %bALL PASSED   ✓ %d / %d%b\n\n' "${C_GREEN}${C_BOLD}" "${PASS}" "${TOTAL}" "${C_RESET}"
  exit 0
fi
printf '  %bFAILED       ✗ %d / %d%b\n' "${C_RED}${C_BOLD}" "${FAIL}" "${TOTAL}" "${C_RESET}"
for f in "${FAILURES[@]}"; do
  printf '    • %s\n' "${f}"
done
printf '\n'
exit 1
