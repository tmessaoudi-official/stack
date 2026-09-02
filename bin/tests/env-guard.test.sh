#!/usr/bin/env bash
# Tests for .claude/hooks/env-guard-on-write.sh — the advisory PostToolUse hook
# that sanity-checks .env / .env.local after an Edit or Write.
#
# F13, the port check, was wrong in both directions at once:
#
#   Half A — 5 false positives on this repo's own .env.local. The rule was
#   "a set _PORT_ var must end with ':'", but whether it may is a property of
#   the CONSUMER, not of the variable. `local.05…:161` writes
#   `${VAR:-}:${VAR:-}` and `Makefile:170` writes `--publish ${VAR}:5000` —
#   both supply the colon themselves, so a trailing ':' there would be the bug.
#
#   Half B — the one variable that really does concatenate was invisible. The
#   name pattern required '=' right after the digits, so the range-style
#   GLOBAL_STACK_LOCALSTACK_LOCALSTACK_PORT_4510_4559 never matched, and its
#   consumer (01localstack-localstack/docker-compose.yaml:36) is exactly the
#   `${VAR:-}4510-4559` form the check exists to protect.
#
# A guard that cries wolf five times and stays silent on the real case trains
# the reader to ignore it, which is worse than not having it.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/.claude/hooks/env-guard-on-write.sh"

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

command -v jq >/dev/null 2>&1 || {
  printf '\n  jq is not installed — the hook exits 0 without it and every case would be vacuous.\n\n'
  exit 1
}

# run_hook <env-file-path> — sets HOOK_OUT (the systemMessage text, or empty).
run_hook() {
  local _raw
  _raw="$(jq -nc --arg p "${1}" '{tool_input: {file_path: $p}}' | bash "${HOOK}" 2>&1)"
  HOOK_RC=$?
  if [[ -n "${_raw}" ]]; then
    HOOK_OUT="$(jq -r '.systemMessage // empty' <<<"${_raw}" 2>/dev/null || printf '%s' "${_raw}")"
  else
    HOOK_OUT=""
  fi
}

# make_sandbox <env-content> <compose-content>
#   A minimal repo shape: <root>/.env.local plus one consumer compose file. The
#   hook derives the tree from the env file's own directory, so this is enough.
make_sandbox() {
  SBX="$(mktemp -d)"
  SANDBOXES+=("${SBX}")
  mkdir -p "${SBX}/docker/images/01svc"
  printf '%s' "${1}" >"${SBX}/.env.local"
  [[ -n "${2}" ]] && printf '%s' "${2}" >"${SBX}/docker/images/01svc/docker-compose.yaml"
  return 0
}

printf '\n%b── env-guard-on-write.sh ──%b\n' "${C_BOLD}" "${C_RESET}"

# ── Half A: the repo's own files must be clean ──────────────────────────────
printf '\n  %b1. no false alarm on this repo%b\n' "${C_BOLD}" "${C_RESET}"

for f in .env .env.local; do
  if [[ -f "${REPO_ROOT}/${f}" ]]; then
    run_hook "${REPO_ROOT}/${f}"
    n="$(grep -c "does not end with" <<<"${HOOK_OUT}" || true)"
    [[ "${n}" -eq 0 ]] \
      && ok "${f}: no port warning" \
      || ko "${f}: ${n} false port warning(s): $(grep 'does not end with' <<<"${HOOK_OUT}" | tr '\n' '|')"
  else
    ko "${f}: missing from the repo — cannot check for false alarms"
  fi
done

# ── Half B: the concatenating consumer form IS caught ───────────────────────
printf '\n  %b2. the range-style var that really concatenates%b\n' "${C_BOLD}" "${C_RESET}"

CONCAT_COMPOSE='services:
  svc:
    ports:
      - ${GLOBAL_STACK_LOCALSTACK_LOCALSTACK_PORT_4510_4559:-}4510-4559
'
make_sandbox 'GLOBAL_STACK_LOCALSTACK_LOCALSTACK_PORT_4510_4559=42731-42780
' "${CONCAT_COMPOSE}"
run_hook "${SBX}/.env.local"
grep -q 'GLOBAL_STACK_LOCALSTACK_LOCALSTACK_PORT_4510_4559' <<<"${HOOK_OUT}" \
  && ok "range-style var missing its ':' is caught" \
  || ko "range-style var not caught — the _PORT_<n>_<n> name never matched: '${HOOK_OUT}'"

make_sandbox 'GLOBAL_STACK_LOCALSTACK_LOCALSTACK_PORT_4510_4559=42731-42780:
' "${CONCAT_COMPOSE}"
run_hook "${SBX}/.env.local"
[[ -z "${HOOK_OUT}" ]] \
  && ok "the same var WITH its ':' is silent" \
  || ko "false alarm on a correctly terminated range var: '${HOOK_OUT}'"

# ── The ordinary concatenating form ─────────────────────────────────────────
printf '\n  %b3. the ordinary ${VAR:-}<port> consumer%b\n' "${C_BOLD}" "${C_RESET}"

make_sandbox 'GLOBAL_STACK_MYSQL9_PORT_3306=42708
' 'services:
  svc:
    ports:
      - ${GLOBAL_STACK_MYSQL9_PORT_3306:-}3306
'
run_hook "${SBX}/.env.local"
grep -q 'GLOBAL_STACK_MYSQL9_PORT_3306' <<<"${HOOK_OUT}" \
  && ok "concatenating consumer + no ':' → warned" \
  || ko "the classic 427083306 bug was not caught: '${HOOK_OUT}'"

# ── The consumer that supplies its own colon ────────────────────────────────
printf '\n  %b4. consumers that write the colon themselves%b\n' "${C_BOLD}" "${C_RESET}"

make_sandbox 'GLOBAL_STACK_LOCAL_SVC_PORT_80=41716
' 'services:
  svc:
    ports:
      - ${GLOBAL_STACK_LOCAL_SVC_PORT_80:-}:${GLOBAL_STACK_LOCAL_SVC_PORT_80:-}
'
run_hook "${SBX}/.env.local"
[[ -z "${HOOK_OUT}" ]] \
  && ok '${VAR:-}:${VAR:-} consumer → no warning (the colon would be the bug)' \
  || ko "false alarm on a colon-supplying consumer: '${HOOK_OUT}'"

make_sandbox 'GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000=42728
' 'services:
  svc:
    image: registry:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}/foo
'
run_hook "${SBX}/.env.local"
[[ -z "${HOOK_OUT}" ]] \
  && ok "a var with no concatenating consumer at all → no warning" \
  || ko "false alarm on a var no compose file concatenates: '${HOOK_OUT}'"

# ── Empty value means no host binding ───────────────────────────────────────
make_sandbox 'GLOBAL_STACK_MYSQL9_PORT_3306=
' 'services:
  svc:
    ports:
      - ${GLOBAL_STACK_MYSQL9_PORT_3306:-}3306
'
run_hook "${SBX}/.env.local"
[[ -z "${HOOK_OUT}" ]] \
  && ok "empty value (no host binding) → no warning" \
  || ko "false alarm on an unbound port: '${HOOK_OUT}'"

# ── Vacuity: a check keyed on consumers must say when it found none ─────────
printf '\n  %b5. the check refuses to be silently vacuous%b\n' "${C_BOLD}" "${C_RESET}"

make_sandbox 'GLOBAL_STACK_MYSQL9_PORT_3306=42708
' ''
run_hook "${SBX}/.env.local"
grep -qi 'could not' <<<"${HOOK_OUT}" \
  && ok "no compose tree → says the port check could not run" \
  || ko "silent with nothing to key on — indistinguishable from clean: '${HOOK_OUT}'"

# ── The other two checks still work ─────────────────────────────────────────
printf '\n  %b6. the COMPOSE_FILE checks are untouched%b\n' "${C_BOLD}" "${C_RESET}"

make_sandbox 'COMPOSE_FILE=docker/images/01svc/docker-compose.yaml;
' 'services: {}
'
run_hook "${SBX}/.env.local"
grep -q "ends with ';'" <<<"${HOOK_OUT}" \
  && ok "trailing ';' in COMPOSE_FILE still warns" \
  || ko "trailing ';' regression: '${HOOK_OUT}'"

make_sandbox 'COMPOSE_FILE=docker/images/01svc/docker-compose.yaml;docker/images/99gone/docker-compose.yaml
' 'services: {}
'
run_hook "${SBX}/.env.local"
grep -q '99gone' <<<"${HOOK_OUT}" \
  && ok "a COMPOSE_FILE entry pointing at nothing still warns" \
  || ko "missing-file regression: '${HOOK_OUT}'"

# ── The hook is advisory: it must never block ───────────────────────────────
[[ "${HOOK_RC}" -eq 0 ]] \
  && ok "the hook exits 0 even when warning (advisory only)" \
  || ko "the hook exited ${HOOK_RC} — a PostToolUse guard must never block"

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
