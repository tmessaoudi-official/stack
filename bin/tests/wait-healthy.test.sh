#!/usr/bin/env bash
# Tests for the `wait-healthy` Makefile target.
#
# F6: with the stack DOWN the target reported success. `docker compose ps
# --format "{{.Health}}"` prints nothing when no container exists, so
# `grep -q starting` is false, the settle loop is never entered, and the
# errors-dir check passes on a directory that is empty because nothing ever
# ran. The recipe then printed "Stack settled: 0 healthy, 0 failed" and exited
# 0 — a `make up && make wait-healthy` chain where `up` had failed outright
# looked like a healthy stack.
#
# The target is exercised in a copied-tree sandbox with a stub `docker` first on
# PATH: `wait-healthy` needs only the Makefile head and its own recipe, so a
# temp dir holding the Makefile plus a minimal .env.local is a faithful stand-in
# — and `tools/errors/` then resolves inside the sandbox rather than the repo.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PASS=0
FAIL=0
FAILURES=()
SANDBOXES=()

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

cleanup() {
  local _s
  for _s in ${SANDBOXES+"${SANDBOXES[@]}"}; do
    [[ -n "${_s}" && -d "${_s}" ]] && rm -rf "${_s}"
  done
}
trap cleanup EXIT

# make_sandbox <ids-file-content> <health-file-content>
#   The stub docker answers the two shapes the recipe uses: `ps -q` (one
#   container id per line) and `ps --format "{{.Health}}"` (one state per line).
#   Both answers come from files so a case can change them mid-run.
make_sandbox() {
  SBX="$(mktemp -d)"
  SANDBOXES+=("${SBX}")
  mkdir -p "${SBX}/stub" "${SBX}/tools/successes" "${SBX}/tools/errors"
  cp "${REPO_ROOT}/Makefile" "${SBX}/"
  printf 'GLOBAL_STACK_VERSION=test\n' >"${SBX}/.env.local"
  printf '%s' "${1}" >"${SBX}/ids"
  printf '%s' "${2}" >"${SBX}/health"
  cat >"${SBX}/stub/docker" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"${SBX}/docker.log"
for a in "\$@"; do
  if [[ "\${a}" == "-q" ]]; then cat "${SBX}/ids"; exit 0; fi
done
cat "${SBX}/health"
exit 0
EOF
  chmod +x "${SBX}/stub/docker"
  : >"${SBX}/docker.log"
}

# run_target — sets RUN_OUT and RUN_RC.
run_target() {
  RUN_OUT="$(cd "${SBX}" && PATH="${SBX}/stub:${PATH}" timeout 120 make wait-healthy 2>&1)"
  RUN_RC=$?
}

printf '\n%b── make wait-healthy ──%b\n' "${C_BOLD}" "${C_RESET}"

# ── The false OK ────────────────────────────────────────────────────────────
printf '\n  %b1. the stack is not running%b\n' "${C_BOLD}" "${C_RESET}"

make_sandbox '' ''
run_target

[[ "${RUN_RC}" -ne 0 ]] \
  && ok "nothing running → non-zero exit (${RUN_RC})" \
  || ko "nothing running → exit 0: 'settled' with no container is the F6 false OK — ${RUN_OUT}"

grep -qi 'not running' <<<"${RUN_OUT}" \
  && ok "the message says the stack is not running" \
  || ko "no such message; output was: $(tr '\n' '|' <<<"${RUN_OUT}")"

grep -q ' ps -q' "${SBX}/docker.log" \
  && ok "the container count was actually asked for (non-vacuity)" \
  || ko "no 'ps -q' reached docker: $(tr '\n' '|' <"${SBX}/docker.log")"

# ── A running, healthy stack still passes ───────────────────────────────────
printf '\n  %b2. a running healthy stack%b\n' "${C_BOLD}" "${C_RESET}"

make_sandbox 'aaa
bbb
ccc
' 'healthy
healthy
healthy
'
: >"${SBX}/tools/successes/00base"
run_target

[[ "${RUN_RC}" -eq 0 ]] \
  && ok "healthy stack → exit 0" \
  || ko "healthy stack → exit ${RUN_RC}: ${RUN_OUT}"

grep -q 'Stack settled' <<<"${RUN_OUT}" \
  && ok "still reports the settled summary" \
  || ko "summary line lost: $(tr '\n' '|' <<<"${RUN_OUT}")"

# ── A running stack with a failed service still fails ───────────────────────
printf '\n  %b3. a running stack with a failed service%b\n' "${C_BOLD}" "${C_RESET}"

make_sandbox 'aaa
' 'unhealthy
'
: >"${SBX}/tools/errors/03node24"
run_target

[[ "${RUN_RC}" -ne 0 ]] \
  && ok "error token present → non-zero exit (${RUN_RC})" \
  || ko "error token ignored → exit 0: ${RUN_OUT}"

grep -q '03node24' <<<"${RUN_OUT}" \
  && ok "the failed service is named" \
  || ko "failed service not named: $(tr '\n' '|' <<<"${RUN_OUT}")"

# ── The settle loop still waits ─────────────────────────────────────────────
# Guards the other direction: a count guard that returned early, or a loop
# condition that stopped matching, would make wait-healthy stop waiting. The
# stub reports `starting` once and `healthy` afterwards, so a target that waits
# takes one 10s sleep and a target that does not takes none.
printf '\n  %b4. the settle loop is still entered%b\n' "${C_BOLD}" "${C_RESET}"

make_sandbox 'aaa
' 'starting
'
cat >"${SBX}/stub/docker" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"${SBX}/docker.log"
for a in "\$@"; do
  if [[ "\${a}" == "-q" ]]; then printf 'aaa\n'; exit 0; fi
done
if [[ -e "${SBX}/seen" ]]; then printf 'healthy\n'; else : >"${SBX}/seen"; printf 'starting\n'; fi
exit 0
EOF
chmod +x "${SBX}/stub/docker"
_t0=$(date +%s)
run_target
_elapsed=$(($(date +%s) - _t0))

[[ "${RUN_RC}" -eq 0 ]] \
  && ok "settles once nothing is starting → exit 0" \
  || ko "starting→healthy → exit ${RUN_RC}: ${RUN_OUT}"

[[ "${_elapsed}" -ge 9 ]] \
  && ok "waited for the 'starting' state (${_elapsed}s)" \
  || ko "returned in ${_elapsed}s — the settle loop was never entered"

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
