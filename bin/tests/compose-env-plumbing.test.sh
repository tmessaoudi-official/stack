#!/usr/bin/env bash
# Tests that env vars the CONTAINERS read at runtime actually reach them.
# Run: bash bin/tests/compose-env-plumbing.test.sh
#
# F3: GLOBAL_STACK_USE_LOCKS was passed to 00base as a BUILD arg
# (00base/docker-compose.yaml:63 → Dockerfile:80 ARG → :156 baked ENV) and
# nowhere else. Six startup scripts read it at runtime — nvm, pyenv, rbenv,
# phpbrew, sdkman, fvm — every one of them expecting it to track .env.local.
# It could not: an image ENV is frozen at build time, so flipping the value in
# .env.local changed nothing and the tier-03 install race could never be
# serialized. The fix puts it in the shared base-env compose fragment, which
# every runtime service inherits through base / base-6vol / <lang>-packages.
#
# SECRETS: `docker compose config` expands every env_file and prints all DB
# passwords to stdout. This suite pipes it straight into jq and keeps ONLY the
# one key under test — the full config is never written to disk, never echoed,
# and never reaches a failure message.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VAR_UNDER_TEST="GLOBAL_STACK_USE_LOCKS"
# A key every base-env inheritor carries, used to identify that set from the
# resolved config without re-deriving the extends chain here.
BASE_ENV_SENTINEL="AWS_ENDPOINT_URL_S3"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

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

# ── Preflight. A missing tool must ABORT, never pass vacuously: "no service was
#    found to be missing the var" and "no service was examined" print the same
#    green otherwise. ────────────────────────────────────────────────────────
for _tool in docker jq git; do
  command -v "${_tool}" >/dev/null 2>&1 || {
    printf '\n  %s is not installed — every case below would be vacuous.\n\n' "${_tool}"
    exit 1
  }
done
[[ -f "${REPO_ROOT}/.env.local" ]] || {
  printf '\n  .env.local is missing — make up resolves from it, so this suite has nothing to check.\n\n'
  exit 1
}

printf '\n%b── compose env plumbing: %s ──%b\n' "${C_BOLD}" "${VAR_UNDER_TEST}" "${C_RESET}"

# ── 1. The variable exists in the env file at all ───────────────────────────
ENV_VALUE="$(sed -n "s/^${VAR_UNDER_TEST}=//p" "${REPO_ROOT}/.env.local" | tail -1)"
if [[ -n "${ENV_VALUE}" ]]; then
  ok "1: ${VAR_UNDER_TEST} is set in .env.local (${ENV_VALUE})"
else
  ko "1: ${VAR_UNDER_TEST} is absent or empty in .env.local — nothing can propagate"
fi

# ── 2. Resolve the config ONCE, keeping only the key under test ─────────────
KEYS_JSON="${TMP_DIR}/keys.json"
if (cd "${REPO_ROOT}" && docker compose --env-file .env.local config --format json 2>/dev/null) \
  | jq --arg v "${VAR_UNDER_TEST}" --arg s "${BASE_ENV_SENTINEL}" \
    '[.services | to_entries[] | {
        name: .key,
        value: (.value.environment[$v] // null),
        base_env: (.value.environment | has($s))
      }]' >"${KEYS_JSON}" 2>/dev/null && [[ -s "${KEYS_JSON}" ]]; then
  ok "2: docker compose resolved the config"
else
  ko "2: docker compose could not resolve the config — the rest cannot run"
  printf '\n  %bFAILED%b  ✗ %d / %d\n\n' "${C_RED}${C_BOLD}" "${C_RESET}" "${FAIL}" "$((PASS + FAIL))"
  exit 1
fi

# ── 3. Every base-env inheritor carries it ──────────────────────────────────
# This is the guarantee the one-line fragment edit actually makes, so it is the
# guarantee the test states. Gated on the inheritor count so a config that
# resolved to nothing reds instead of reporting a clean sweep.
INHERITORS="$(jq -r '[.[] | select(.base_env)] | length' "${KEYS_JSON}")"
if [[ "${INHERITORS}" -gt 0 ]]; then
  ok "3: ${INHERITORS} service(s) inherit the base-env fragment"
else
  ko "3: no service inherits base-env — the sentinel key '${BASE_ENV_SENTINEL}' moved; this suite is checking nothing"
fi

MISSING="$(jq -r '[.[] | select(.base_env) | select(.value == null) | .name] | join(" ")' "${KEYS_JSON}")"
if [[ -z "${MISSING}" && "${INHERITORS}" -gt 0 ]]; then
  ok "3: every base-env inheritor receives ${VAR_UNDER_TEST} at runtime"
else
  ko "3: base-env inheritors missing ${VAR_UNDER_TEST}: ${MISSING:-<none checked>}"
fi

# ── 4. The value TRACKS the env file (not a hardcoded literal) ──────────────
WRONG="$(jq -r --arg want "${ENV_VALUE}" \
  '[.[] | select(.base_env) | select(.value != null and .value != $want) | .name] | join(" ")' "${KEYS_JSON}")"
if [[ -z "${WRONG}" ]]; then
  ok "4: the resolved value tracks .env.local everywhere it appears"
else
  ko "4: services resolved a value other than '${ENV_VALUE}': ${WRONG}"
fi

# ── 5. Every runtime whose startup script READS it is covered ───────────────
# The reader set is derived from the scripts themselves, never from a list kept
# here — a new reader must not be able to appear without this suite noticing.
READERS=()
while IFS= read -r _f; do
  _rt="$(basename "$(dirname "${_f}")")"
  READERS+=("${_rt%-bin}")
done < <(cd "${REPO_ROOT}" && git grep -l "${VAR_UNDER_TEST}" -- docker/config/dist/bin | sort -u)

if [[ "${#READERS[@]}" -gt 0 ]]; then
  ok "5: ${#READERS[@]} runtime(s) read ${VAR_UNDER_TEST}: ${READERS[*]}"
else
  ko "5: no startup script reads ${VAR_UNDER_TEST} — the variable is dead, or the grep broke"
fi

# The tier-02 manager service is named after its runtime; tier-03 consumers run
# the SAME script, so covering the managers proves the fragment reaches both
# ends of the two-phase model wherever a manager is enabled.
CHECKED=0
for _rt in ${READERS+"${READERS[@]}"}; do
  _svc="02${_rt}"
  _present="$(jq -r --arg s "${_svc}" '[.[] | select(.name == $s)] | length' "${KEYS_JSON}")"
  [[ "${_present}" -eq 0 ]] && continue
  CHECKED=$((CHECKED + 1))
  _val="$(jq -r --arg s "${_svc}" '.[] | select(.name == $s) | .value' "${KEYS_JSON}")"
  if [[ "${_val}" == "${ENV_VALUE}" ]]; then
    ok "5: ${_svc} receives ${VAR_UNDER_TEST}=${_val}"
  else
    ko "5: ${_svc} resolved '${_val}' (want '${ENV_VALUE}')"
  fi
done

if [[ "${CHECKED}" -ge 5 ]]; then
  ok "5: ${CHECKED} tier-02 manager service(s) were actually examined"
else
  ko "5: only ${CHECKED} manager service(s) present in COMPOSE_FILE — too few to certify the fragment"
fi

# ── 6. The build arg stays, as a harmless default ───────────────────────────
# Compose `environment:` overrides image ENV at runtime, so keeping the ARG
# costs nothing and keeps a container started outside compose sane.
assert_grep() {
  if grep -q "$2" "${REPO_ROOT}/$3"; then ok "$1"; else ko "$1"; fi
}
assert_grep "6: 00base still passes it as a build arg" \
  "${VAR_UNDER_TEST}" "docker/images/00base/docker-compose.yaml"
assert_grep "6: the shared base-env fragment declares it" \
  "${VAR_UNDER_TEST}" "docker/config/compose-fragments/base-env.compose.yaml"

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
