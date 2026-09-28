#!/usr/bin/env bash
# Tests docker/config/dist/bin/sonarqube-bin/global-stack-start-sonarqube.sh — that an
# UNREQUESTED SonarQube exit is reported and retried, and a requested stop is not.
# Run: bash bin/tests/sonarqube-start.test.sh   (~15 s; no docker needed; §3 reads the compose file)
#
# 2026-09-28 cold start: SonarQube could not reach Postgres, logged "SonarQube is
# stopped" and exited 0. `restart: on-failure:5` never restarts an exit 0, and the
# script exec'd the upstream entrypoint so nothing wrote an error token: the
# container sat Exited (0) with a healthcheck that could only say "starting".
# The script now runs the entrypoint as a child, forwards a stop to it, and turns
# any exit it did not ask for into an error token plus exit 1.
#
# The stub entrypoint is a bash script started in the BACKGROUND, like the real JVM,
# so it inherits SIGINT as ignored-on-entry (measured: SigIgn 0x6) and cannot trap it
# — the same constraint the JVM has. Forwarding SIGINT would therefore stop nothing;
# a stub that could catch INT would hide exactly that bug.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DIST_BIN="${REPO_ROOT}/docker/config/dist/bin"
SUT="${DIST_BIN}/sonarqube-bin/global-stack-start-sonarqube.sh"
TOKEN="02sonarqube"

TMP_DIR="$(mktemp -d)"
# shellcheck disable=SC2329  # invoked by the EXIT trap below
cleanup() {
  [[ -n "${_bg:-}" ]] && kill -9 "${_bg}" 2>/dev/null
  pkill -9 -f "${TMP_DIR}/" 2>/dev/null
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

[[ -f "${SUT}" ]] || {
  printf '\n  %s is missing — nothing to test.\n\n' "${SUT}"
  exit 1
}

# ── Sandbox: stub collaborators on PATH, the REAL prologue and version gate. ──
STUB_BIN="${TMP_DIR}/bin"
mkdir -p "${STUB_BIN}"
ln -s "${DIST_BIN}/base-bin/global-stack-base-prologue.sh" "${STUB_BIN}/"
ln -s "${DIST_BIN}/base-bin/global-stack-base-version-gate.sh" "${STUB_BIN}/"
printf '#!/bin/bash\nexit 0\n' >"${STUB_BIN}/global-stack-base-wait-for.sh"
printf '#!/bin/bash\nexit 0\n' >"${STUB_BIN}/global-stack-base-init-mkcert.sh"
chmod +x "${STUB_BIN}"/global-stack-base-wait-for.sh "${STUB_BIN}"/global-stack-base-init-mkcert.sh

# Stub upstream entrypoint. STUB_MODE: exit0 | exit3 | serve.
cat >"${TMP_DIR}/entrypoint.sh" <<'EOF'
#!/bin/bash
echo started >"${STUB_STATE}/started"
case "${STUB_MODE}" in
  exit0) sleep 0.3; exit 0 ;;
  exit3) sleep 0.3; exit 3 ;;
  serve)
    trap 'echo INT >>"${STUB_STATE}/signals"; exit 0' INT   # cannot fire: INT ignored on entry
    trap 'echo TERM >>"${STUB_STATE}/signals"; exit 0' TERM
    while :; do sleep 0.1; done ;;
esac
EOF
chmod +x "${TMP_DIR}/entrypoint.sh"

# One run = fresh tools dirs + state dir. Prints nothing; sets RUN_* globals.
_new_run() {
  RUN="${TMP_DIR}/run.$1"
  mkdir -p "${RUN}/tools/errors" "${RUN}/tools/successes" "${RUN}/state"
}
# shellcheck disable=SC2329  # called through declare -f in a bash -c
_env() {
  exec env -i HOME="${RUN}" PATH="${STUB_BIN}:/usr/local/bin:/usr/bin:/bin" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH="${RUN}/tools" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${RUN}/tools/errors" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES="${RUN}/tools/successes" \
    GLOBAL_STACK_ERROR_TOKEN="${TOKEN}" \
    GS_SONARQUBE_ENTRYPOINT="${TMP_DIR}/entrypoint.sh" \
    STUB_STATE="${RUN}/state" STUB_MODE="$1" \
    bash "${SUT}"
}

printf '%b1. SonarQube exits on its own%b\n' "${C_BOLD}" "${C_RESET}"

for mode in exit0 exit3; do
  _new_run "${mode}"
  rc=0
  timeout 20 bash -c "$(declare -f _env); RUN='${RUN}' STUB_BIN='${STUB_BIN}' TOKEN='${TOKEN}' TMP_DIR='${TMP_DIR}' SUT='${SUT}' _env ${mode}" >"${RUN}/log" 2>&1 || rc=$?
  if [[ ! -f "${RUN}/state/started" ]]; then
    ko "1-${mode}: the stub entrypoint never ran — nothing was tested (rc=${rc}; log tail: $(tail -3 "${RUN}/log" | tr '\n' ' '))"
    continue
  fi
  if [[ "${rc}" != 0 && "${rc}" != 124 ]]; then
    ok "1-${mode}: script exits non-zero (rc=${rc}), so on-failure:5 restarts it"
  else
    ko "1-${mode}: script exit status ${rc} — an exit 0 is never restarted by on-failure (124 = hung)"
  fi
  if [[ -s "${RUN}/tools/errors/${TOKEN}" ]]; then
    ok "1-${mode}: error token errors/${TOKEN} written"
  else
    ko "1-${mode}: no error token errors/${TOKEN} — the failure is invisible to the healthcheck"
  fi
done

printf '\n%b2. A requested stop (docker stop sends SIGINT, a kill sends SIGTERM)%b\n' "${C_BOLD}" "${C_RESET}"

for sig in INT TERM; do
  _new_run "stop-${sig}"
  echo stale >"${RUN}/tools/errors/${TOKEN}"
  # Job control, so the script itself starts with SIGINT at its default disposition,
  # exactly as under docker-init; without it the script could not trap INT at all.
  set -m
  bash -c "$(declare -f _env); RUN='${RUN}' STUB_BIN='${STUB_BIN}' TOKEN='${TOKEN}' TMP_DIR='${TMP_DIR}' SUT='${SUT}' _env serve" >"${RUN}/log" 2>&1 &
  _bg=$!
  set +m
  if ! timeout 10 bash -c "until [[ -f '${RUN}/state/started' ]]; do sleep 0.1; done"; then
    ko "2-${sig}: the stub entrypoint never started — nothing was tested"
    kill -9 "${_bg}" 2>/dev/null
    continue
  fi
  if [[ ! -e "${RUN}/tools/errors/${TOKEN}" ]]; then
    ok "2-${sig}: a stale token from an earlier run is cleared at start"
  else
    ko "2-${sig}: stale errors/${TOKEN} survived the start — the container would stay unhealthy"
  fi
  # _env ends in `exec env … bash`, so the background job IS the script.
  sut_pid="${_bg}"
  kill -s "${sig}" "${sut_pid}"
  rc=0
  timeout 10 bash -c "while kill -0 ${_bg} 2>/dev/null; do sleep 0.1; done" || rc=124
  if [[ "${rc}" == 124 ]]; then
    # Still running: reap it here, or the `wait` below blocks forever and the whole
    # suite hangs with no tally — which would read as "not caught".
    kill -9 "${_bg}" 2>/dev/null
    pkill -9 -f "${TMP_DIR}/entrypoint.sh" 2>/dev/null
  fi
  wait "${_bg}" 2>/dev/null
  _bg=""
  if [[ "${rc}" == 124 ]]; then
    ko "2-${sig}: the script did not stop within 10 s of SIG${sig} — docker would SIGKILL SonarQube mid-write"
  else
    ok "2-${sig}: the script stopped after SIG${sig}"
  fi
  if grep -qx TERM "${RUN}/state/signals" 2>/dev/null; then
    ok "2-${sig}: SonarQube received SIGTERM (the signal it can act on)"
  else
    ko "2-${sig}: SonarQube got no SIGTERM (signals seen: $(tr '\n' ' ' <"${RUN}/state/signals" 2>/dev/null))"
  fi
  if [[ ! -e "${RUN}/tools/errors/${TOKEN}" ]]; then
    ok "2-${sig}: no error token for a requested stop"
  else
    ko "2-${sig}: a requested stop wrote errors/${TOKEN} — a false failure"
  fi
done

printf '\n%b3. Compose: the healthcheck honours the token, and the token invariant holds%b\n' "${C_BOLD}" "${C_RESET}"
# Text-level, so this suite still needs no docker. The token is useless unless the
# healthcheck reads it, and the invariant says the error token and the success
# marker (the elapsed wrapper's service argument) are the SAME identifier.
COMPOSE="${REPO_ROOT}/docker/images/02sonarqube/docker-compose.yaml"
env_token="$(sed -n 's/^[[:space:]]*- GLOBAL_STACK_ERROR_TOKEN=\([^[:space:]]*\).*/\1/p' "${COMPOSE}")"
hc_line="$(grep -E '^[[:space:]]+test:.*healthcheck-elapsed\.sh' "${COMPOSE}")"
wrapper_arg="$(sed -n 's/.*healthcheck-elapsed\.sh \([^ ]*\) .*/\1/p' <<<"${hc_line}")"
# shellcheck disable=SC2016  # matches the literal ${…} text in the compose file
hc_token="$(sed -n 's/.*! test -f \${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}\/\([^ ]*\) &&.*/\1/p' <<<"${hc_line}")"
if [[ -z "${hc_line}" ]]; then
  ko "3a: no elapsed-wrapper healthcheck line found in ${COMPOSE##*/} — nothing to check"
elif [[ "${env_token}" == "${TOKEN}" ]]; then
  ok "3a: compose declares GLOBAL_STACK_ERROR_TOKEN=${TOKEN}"
else
  ko "3a: compose GLOBAL_STACK_ERROR_TOKEN is '${env_token}', expected '${TOKEN}'"
fi
if [[ -n "${hc_token}" && "${hc_token}" == "${env_token}" ]]; then
  ok "3b: the healthcheck fails while errors/${hc_token} exists"
else
  ko "3b: the healthcheck does not test errors/<token> (found '${hc_token}') — a written token would be ignored"
fi
if [[ -n "${wrapper_arg}" && "${wrapper_arg}" == "${env_token}" ]]; then
  ok "3c: success marker (wrapper argument '${wrapper_arg}') and error token are the same identifier"
else
  ko "3c: token invariant broken — success marker '${wrapper_arg}' vs error token '${env_token}'"
fi

printf '\n'
if ((FAIL == 0)); then
  printf '  %bALL PASSED%b   ✓ %d / %d\n' "${C_GREEN}" "${C_RESET}" "${PASS}" "$((PASS + FAIL))"
  exit 0
fi
printf '  %bFAILURES%b      ✓ %d passed   ✗ %d failed   (%d total)\n' "${C_RED}" "${C_RESET}" "${PASS}" "${FAIL}" "$((PASS + FAIL))"
for f in "${FAILURES[@]}"; do printf '    • %s\n' "${f}"; done
exit 1
