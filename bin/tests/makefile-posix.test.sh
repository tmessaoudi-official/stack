#!/usr/bin/env bash
# Tests for Makefile recipe portability and self-consistency.
#
# GNU make runs every recipe line with SHELL=/bin/sh, and this Makefile never
# sets SHELL. On this machine /bin/sh is dash, so a bash-only construct in a
# recipe does not fail loudly at parse time — it fails at run time, or worse,
# silently means something else:
#
#   `source f && cmd`  -> dash has no `source` builtin; exit 127, and because
#                         the operator is &&, cmd NEVER RUNS. The target aborts
#                         having done nothing.
#   `cmd &>/dev/null`  -> dash parses this as `cmd &` plus a redirect of an
#                         empty command, i.e. it BACKGROUNDS cmd instead of
#                         silencing it, so the next recipe line races it.
#
# The third check is not portability but truthfulness: an abort message that
# tells the operator to run a target which does not exist sends them in a
# circle at exactly the moment something has already gone wrong.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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

printf '\n%b── Makefile recipe portability ──%b\n' "${C_BOLD}" "${C_RESET}"

# Recipe lines are the TAB-indented ones. local.Makefile is gitignored and
# machine-specific, so it is checked only when present.
MAKEFILES=("${REPO_ROOT}/Makefile")
[[ -f "${REPO_ROOT}/local.Makefile" ]] && MAKEFILES+=("${REPO_ROOT}/local.Makefile")

# Recipe lines whose first non-tab character is '#' are shell comments — make
# still hands them to the shell, but they execute nothing, so a construct named
# inside one is prose. Excluding them keeps the checks about executable code
# (and lets a recipe carry a comment explaining why a construct was removed).
recipe_lines() { command grep -hnP '^\t(?!\s*#)' "${MAKEFILES[@]}" 2>/dev/null || true; }

# ── The shell make will actually use ────────────────────────────────────────
# Recorded rather than asserted: if someone sets SHELL := /bin/bash the two
# checks below become moot, and this line says so in the output.
MAKE_SHELL="$(command grep -hE '^[[:space:]]*SHELL[[:space:]]*[:?]?=' "${MAKEFILES[@]}" 2>/dev/null | tail -1)"
if [[ -z "${MAKE_SHELL}" ]]; then
  ok "SHELL is not overridden — recipes run under /bin/sh ($(readlink -f /bin/sh))"
else
  ok "SHELL is set explicitly: ${MAKE_SHELL}"
fi

# ── `source` is not a /bin/sh builtin ───────────────────────────────────────
hits="$(recipe_lines | command grep -E '(^|[^[:alnum:]_])source[[:space:]]' || true)"
if [[ -z "${hits}" ]]; then
  ok "no recipe uses \`source\` (dash: not found, exit 127)"
else
  ko "recipe uses \`source\`, which dash does not have — the rest of the line never runs:"
  printf '%s\n' "${hits}" | sed 's/^/        /'
fi

# ── `&>` backgrounds under dash instead of redirecting ──────────────────────
hits="$(recipe_lines | command grep -F '&>' || true)"
if [[ -z "${hits}" ]]; then
  ok "no recipe uses \`&>\` (dash: backgrounds the command instead of silencing it)"
else
  ko "recipe uses \`&>\`, which dash treats as \`&\` + redirect — the command is backgrounded:"
  printf '%s\n' "${hits}" | sed 's/^/        /'
fi

# ── Every `make <target>` named in a message must exist ─────────────────────
# The target list comes from make's own database, so $(eval $(call ...))
# generated targets are included — a plain grep of the file would not see them.
printf '\n%b── Makefile message self-consistency ──%b\n' "${C_BOLD}" "${C_RESET}"

db="$(cd "${REPO_ROOT}" && make -p -n help 2>/dev/null || true)"
targets="$(printf '%s\n' "${db}" | command grep -oE '^[a-zA-Z0-9_.\-]+:' | tr -d ':' | sort -u)"

if [[ -z "${targets}" ]]; then
  ko "could not read make's target database — check skipped rather than passing vacuously"
else
  ok "read $(printf '%s\n' "${targets}" | wc -l | tr -d ' ') targets from make's database"
  missing=""
  while IFS= read -r referenced; do
    [[ -z "${referenced}" ]] && continue
    grep -qxF "${referenced}" <<<"${targets}" || missing+="        make ${referenced}"$'\n'
  done < <(recipe_lines | command grep -oE "make [a-zA-Z0-9_.\-]+" | awk '{print $2}' | sort -u)
  if [[ -z "${missing}" ]]; then
    ok "every \`make <target>\` named in a recipe message exists"
  else
    ko "a recipe tells the operator to run a target that does not exist:"
    printf '%s' "${missing}"
  fi
fi

# ── Summary ─────────────────────────────────────────────────────────────────
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
