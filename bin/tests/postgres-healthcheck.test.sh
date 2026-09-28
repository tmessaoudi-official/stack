#!/usr/bin/env bash
# Tests that 01postgres18 is reported healthy only by the REAL server, and that
# the init-time temp server gets time to stop cleanly under load.
# Run: bash bin/tests/postgres-healthcheck.test.sh   (~20 s; needs docker + the built image)
#
# 2026-09-28 cold start: the image's docker-entrypoint.sh:297 starts a temp server
# with listen_addresses='' (socket only) to run init scripts. The healthcheck was a
# SOCKET pg_isready, so it passed against that temp server and wrote
# successes/01postgres18 before the real server existed; 02sonarqube started, hit
# "the database system is not yet accepting connections", exited 0 and was never
# retried. The temp server's `pg_ctl -m fast -w stop` (:311) then gave up at its 60 s
# default under load ("server does not shut down") and the container restarted.
# Fix: a TCP pg_isready (A), PGCTLTIMEOUT=300 (B), and the stack's patient window,
# because a TCP check fails for the whole init and an 80 s window (30 s + 5 x 10 s)
# would mark Postgres UNHEALTHY and abort its service_healthy dependents.
#
# SECRETS: `docker compose config` expands every value, passwords included. It is
# piped straight into jq and only the keys under test are kept.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SERVICE="01postgres18"

TMP_DIR="$(mktemp -d)"
PROBE_NAME="gs-pg-healthcheck-test-$$"
# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() {
  docker rm -f -v "${PROBE_NAME}" >/dev/null 2>&1 || true
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

PASS=0
FAIL=0
FAILURES=()

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_GREEN=$'\033[32m' C_RED=$'\033[31m' C_BOLD=$'\033[1m' C_RESET=$'\033[0m'
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

# ── Preflight: a missing tool or env file must ABORT, never pass vacuously. ──
for _tool in docker jq; do
  command -v "${_tool}" >/dev/null 2>&1 || {
    printf '\n  %s is not installed — every case below would be vacuous.\n\n' "${_tool}"
    exit 1
  }
done
[[ -f "${REPO_ROOT}/.env.local" ]] || {
  printf '\n  .env.local is missing — make up resolves from it, so this suite has nothing to check.\n\n'
  exit 1
}

# Resolved from a CLEAN environment: compose prefers the shell's variables over
# --env-file, and an interactive /stack shell carries its own copy of .env.local.
svc_json="$(cd "${REPO_ROOT}" && env -i HOME="${HOME}" PATH="${PATH}" \
  docker compose --env-file .env.local config --format json 2>/dev/null \
  | jq -c --arg s "${SERVICE}" '.name as $p | .services[$s] | {
      healthcheck,
      pgctltimeout: (.environment.PGCTLTIMEOUT // null),
      image: (.image // ($p + "-" + $s))
    }')"
[[ -n "${svc_json}" && "${svc_json}" != "null" ]] || {
  printf '\n  could not resolve %s from docker compose config — nothing to check.\n\n' "${SERVICE}"
  exit 1
}

printf '%b1. Resolved healthcheck and environment%b\n' "${C_BOLD}" "${C_RESET}"

check_cmd="$(jq -r '.healthcheck.test[1] // ""' <<<"${svc_json}")"
# The command after the elapsed wrapper's service argument: what docker really runs.
probe_cmd="${check_cmd#*" ${SERVICE} "}"
if [[ "${probe_cmd}" == pg_isready* ]]; then
  ok "1a: healthcheck runs pg_isready through the elapsed wrapper"
else
  ko "1a: healthcheck no longer ends in 'pg_isready …' — got: ${check_cmd}"
fi

if [[ " ${probe_cmd} " =~ \ -h\ (127\.0\.0\.1|localhost)\  ]]; then
  ok "1b: pg_isready names a TCP host (-h), so the socket-only init server cannot pass it"
else
  ko "1b: pg_isready has no -h host — a socket check passes against the init temp server: ${probe_cmd}"
fi

start_period="$(jq -r '.healthcheck.start_period // ""' <<<"${svc_json}")"
retries="$(jq -r '.healthcheck.retries // 0' <<<"${svc_json}")"
if [[ "${start_period}" == "24h0m0s" && "${retries}" -ge 99999 ]]; then
  ok "1c: patient window (start_period 24h, retries >= 99999), the stack norm"
else
  ko "1c: window too short for a TCP check across init: start_period=${start_period} retries=${retries}"
fi

pgct="$(jq -r '.pgctltimeout // ""' <<<"${svc_json}")"
if [[ "${pgct}" =~ ^[0-9]+$ ]] && ((pgct >= 300)); then
  ok "1d: PGCTLTIMEOUT=${pgct} (>= 300 s) for the init server's pg_ctl -w stop"
else
  ko "1d: PGCTLTIMEOUT missing or below 300 (got '${pgct}'); pg_ctl's default is 60 s"
fi

# ── 2. Behaviour: run the SHIPPED check against a real init, in a throwaway
#    container with an anonymous volume — the stack's own volume is never used. ──
printf '\n%b2. The shipped check against a real init (throwaway container)%b\n' "${C_BOLD}" "${C_RESET}"

image="$(jq -r '.image // ""' <<<"${svc_json}")"
if [[ -z "${image}" ]] || ! docker image inspect "${image}" >/dev/null 2>&1; then
  printf '\n  image %s is not built — the behavioural half cannot run.\n\n' "${image:-<none>}"
  exit 1
fi
[[ "${probe_cmd}" == pg_isready* ]] || probe_cmd="pg_isready -U root"

mkdir -p "${TMP_DIR}/initdb"
# Sourced by the entrypoint under set -e: every status is captured, never left to abort.
cat >"${TMP_DIR}/initdb/00-probe.sh" <<EOF
rc=0; ${probe_cmd} >/dev/null 2>&1 || rc=\$?
echo "PROBE during_init_rc=\${rc}"
echo "PROBE pgctltimeout=\${PGCTLTIMEOUT:-unset}"
EOF
chmod 644 "${TMP_DIR}/initdb/00-probe.sh"

docker run -d --name "${PROBE_NAME}" --entrypoint docker-entrypoint.sh \
  -e POSTGRES_USER=root -e POSTGRES_PASSWORD=probe \
  ${pgct:+-e "PGCTLTIMEOUT=${pgct}"} \
  -v "${TMP_DIR}/initdb:/docker-entrypoint-initdb.d:ro" \
  "${image}" postgres >/dev/null

if ! timeout 120 bash -c "until docker logs '${PROBE_NAME}' 2>&1 | grep -q 'init process complete'; do sleep 1; done"; then
  ko "2a: throwaway init never completed — log tail: $(docker logs --tail 5 "${PROBE_NAME}" 2>&1 | tr '\n' ' ')"
else
  during="$(docker logs "${PROBE_NAME}" 2>&1 | sed -n 's/^PROBE during_init_rc=//p')"
  if [[ -z "${during}" ]]; then
    ko "2a: the probe init script never ran (no PROBE line) — nothing was tested"
  elif [[ "${during}" != 0 ]]; then
    ok "2a: the shipped check FAILS against the init temp server (rc=${during})"
  else
    ko "2a: the shipped check PASSES against the init temp server — it would mark Postgres healthy too early"
  fi

  seen="$(docker logs "${PROBE_NAME}" 2>&1 | sed -n 's/^PROBE pgctltimeout=//p')"
  if [[ -n "${pgct}" && "${seen}" == "${pgct}" ]]; then
    ok "2b: PGCTLTIMEOUT=${seen} reaches the postgres-user process that runs pg_ctl -w stop"
  else
    ko "2b: PGCTLTIMEOUT did not reach the init process (compose '${pgct}', seen '${seen}')"
  fi

  if timeout 60 bash -c "until docker exec '${PROBE_NAME}' ${probe_cmd} >/dev/null 2>&1; do sleep 1; done"; then
    ok "2c: the shipped check PASSES once the real server is up"
  else
    ko "2c: the shipped check never passed against the real server within 60 s"
  fi
fi

printf '\n'
if ((FAIL == 0)); then
  printf '  %bALL PASSED%b   ✓ %d / %d\n' "${C_GREEN}" "${C_RESET}" "${PASS}" "$((PASS + FAIL))"
  exit 0
fi
printf '  %bFAILURES%b      ✓ %d passed   ✗ %d failed   (%d total)\n' "${C_RED}" "${C_RESET}" "${PASS}" "${FAIL}" "$((PASS + FAIL))"
for f in "${FAILURES[@]}"; do printf '    • %s\n' "${f}"; done
exit 1
