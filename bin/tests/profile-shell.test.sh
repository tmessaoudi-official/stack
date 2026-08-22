#!/usr/bin/env bash
# Tests for templates/shell/profile.sh — the host template deployed to
# /etc/profile.d/stack.sh (see its own header line 2).
#
# What is guarded: this file is sourced by EVERY shell that reads /etc/profile,
# non-interactive ones included (scripts, `bash -c`, tool harnesses, and
# bin/open-all-envs.sh which sources it directly). The SDKMAN installer, `sdk
# use`, the per-package `**** Using ...` echoes, `nvm use` and `phpbrew switch`
# each print a banner — ~90 lines per shell invocation — which is pure noise
# when nobody is watching. `_gs_quiet` drops the output for non-interactive
# shells while keeping every side effect, because it invokes its argument as a
# plain command in THIS shell (PATH/exports still apply).
#
# The two failure modes worth catching: (1) a future chatty call added without
# the wrapper, (2) a wrapper that swallows the side effect along with the noise.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SUT="${REPO_ROOT}/templates/shell/profile.sh"

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

printf '\n%b── templates/shell/profile.sh ──%b\n' "${C_BOLD}" "${C_RESET}"

# ── Case 1: the file still parses ───────────────────────────────────────────
if bash -n "${SUT}" 2>/dev/null; then ok "syntax: bash -n clean"; else ko "syntax: bash -n FAILED"; fi

# ── Case 2: every chatty invocation is wrapped ──────────────────────────────
# Anchored on the call itself, so an unwrapped one added later fails here.
while IFS='|' read -r label pattern; do
  if grep -qE "_gs_quiet[[:space:]]+${pattern}" "${SUT}"; then
    ok "wrapped: ${label}"
  else
    ko "UNWRAPPED (prints on every non-interactive shell): ${label}"
  fi
done <<'CALLS'
sdkman installer|"\$\{GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN\}"/sdkman.installer.sh
sdk use java|sdk use java
per-package sdk echoes|global_stack_base_setup_packages
nvm use|nvm use
phpbrew switch|phpbrew switch
CALLS

# ── Case 3: the helper block is extractable and defines both branches ───────
HELPER="$(sed -n '/# >>> gs-quiet/,/# <<< gs-quiet/p' "${SUT}")"
[[ -n "${HELPER}" ]] && ok "helper: delimited block present" || ko "helper: markers missing — cannot extract"
grep -q 'interactive' <<<"${HELPER}" && ok "helper: keys on shell interactivity" \
  || ko "helper: no interactivity branch: ${HELPER}"

# ── Case 4: non-interactive → silent, side effect SURVIVES ─────────────────
# The point of the wrapper: quiet without breaking PATH/export mutations. Runs
# the REAL extracted bytes, not a re-typed copy.
PROBE="$(mktemp)"
{
  printf '%s\n' "${HELPER}"
  printf '%s\n' 'noisy() { echo "BANNER"; GS_PROBE=touched; }'
  printf '%s\n' '_gs_quiet noisy'
  printf '%s\n' 'echo "PROBE=${GS_PROBE:-unset}"'
} >"${PROBE}"
out="$(bash "${PROBE}" 2>&1)"
# Guard the guard: with no helper defined, the call errors and prints nothing,
# which would make "banner suppressed" pass for the wrong reason.
grep -q 'command not found' <<<"${out}" \
  && ko "non-interactive: _gs_quiet is not defined — the suppression assertions below are vacuous" \
  || ok "non-interactive: _gs_quiet resolved as a command"
grep -q 'BANNER' <<<"${out}" && ko "non-interactive: banner leaked: ${out}" \
  || ok "non-interactive: banner suppressed"
grep -q 'PROBE=touched' <<<"${out}" && ok "non-interactive: side effect survives the wrapper" \
  || ko "non-interactive: side effect LOST — wrapper broke the call: ${out}"
rm -f "${PROBE}"

# ── Case 5: interactive → output preserved (no behaviour change for a human) ─
PROBE_I="$(mktemp)"
{
  printf '%s\n' "${HELPER}"
  printf '%s\n' 'noisy() { echo "BANNER"; }'
  printf '%s\n' '_gs_quiet noisy'
} >"${PROBE_I}"
out="$(bash -i "${PROBE_I}" 2>/dev/null </dev/null || true)"
grep -q 'BANNER' <<<"${out}" && ok "interactive: output preserved" \
  || ko "interactive: banner suppressed too — a human loses the version report: '${out}'"
rm -f "${PROBE_I}"

printf '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
if [[ "${FAIL}" -eq 0 ]]; then
  printf '  %bALL PASSED%b   ✓ %d / %d\n' "${C_GREEN}" "${C_RESET}" "${PASS}" "$((PASS + FAIL))"
else
  printf '  %bFAILED%b        ✗ %d / %d\n' "${C_RED}" "${C_RESET}" "${FAIL}" "$((PASS + FAIL))"
  for f in "${FAILURES[@]}"; do printf '    - %s\n' "$f"; done
  exit 1
fi
