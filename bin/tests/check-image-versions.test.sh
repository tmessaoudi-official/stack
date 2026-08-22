#!/usr/bin/env bash
# Tests for bin/check-image-versions.sh (checkpoint 5).
# Verifies: in-sync -> silent + exit 0; drift -> WARN + exit 0; internal
# FROM ${GLOBAL_STACK_VERSION} services are NOT checked; missing ARG/env skips
# gracefully; the script never returns non-zero (preflight contract).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/../check-image-versions.sh"

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

# Build an isolated fixture tree: <root>/.env + <root>/docker/images/<svc>/Dockerfile
make_fixture() {
  local root
  root="$(mktemp -d)"
  mkdir -p "${root}/docker/images"
  printf '%s\n' "$root"
}

printf '\n%b── check-image-versions.sh ──%b\n' "${C_BOLD}" "${C_RESET}"

# ── Case 1: in-sync (env == ARG) → no WARN, exit 0 ──────────────────────────
ROOT="$(make_fixture)"
mkdir -p "${ROOT}/docker/images/01foo"
printf 'GLOBAL_STACK_IMAGE_FOO_VERSION=1.2.3\n' >"${ROOT}/.env"
printf 'ARG GLOBAL_STACK_IMAGE_FOO_VERSION=1.2.3\nFROM foo:${GLOBAL_STACK_IMAGE_FOO_VERSION}\n' \
  >"${ROOT}/docker/images/01foo/Dockerfile"
out="$(_GS_CIV_ENV_FILE="${ROOT}/.env" _GS_CIV_IMAGES_DIR="${ROOT}/docker/images" bash "${SUT}" 2>&1)"
rc=$?
[[ $rc -eq 0 ]] && ok "in-sync: exit 0" || ko "in-sync: exit $rc (want 0)"
[[ -z "$out" ]] && ok "in-sync: no WARN emitted" || ko "in-sync: unexpected output: $out"
rm -rf "${ROOT}"

# ── Case 2: drift (env != ARG) → WARN mentioning the service, exit 0 ────────
ROOT="$(make_fixture)"
mkdir -p "${ROOT}/docker/images/01foo"
printf 'GLOBAL_STACK_IMAGE_FOO_VERSION=2.0.0\n' >"${ROOT}/.env"
printf 'ARG GLOBAL_STACK_IMAGE_FOO_VERSION=1.2.3\nFROM foo:${GLOBAL_STACK_IMAGE_FOO_VERSION}\n' \
  >"${ROOT}/docker/images/01foo/Dockerfile"
out="$(_GS_CIV_ENV_FILE="${ROOT}/.env" _GS_CIV_IMAGES_DIR="${ROOT}/docker/images" bash "${SUT}" 2>&1)"
rc=$?
[[ $rc -eq 0 ]] && ok "drift: exit 0 (non-fatal)" || ko "drift: exit $rc (want 0)"
grep -q "01foo" <<<"$out" && grep -qi "stale" <<<"$out" && ok "drift: WARN names service + 'stale'" || ko "drift: WARN missing service/stale: $out"
grep -q "2.0.0" <<<"$out" && grep -q "1.2.3" <<<"$out" && ok "drift: WARN shows both versions" || ko "drift: WARN missing versions: $out"
rm -rf "${ROOT}"

# ── Case 3: internal FROM ${GLOBAL_STACK_VERSION} → NOT checked (no WARN) ────
ROOT="$(make_fixture)"
mkdir -p "${ROOT}/docker/images/03node24"
printf 'GLOBAL_STACK_VERSION=2_0_0_local\n' >"${ROOT}/.env"
# Dockerfile ARG deliberately mismatches .env, but the FROM is internal → ignored.
printf 'ARG GLOBAL_STACK_VERSION=OLD_TAG\nFROM registry/local_global_stack_00base:${GLOBAL_STACK_VERSION}\n' \
  >"${ROOT}/docker/images/03node24/Dockerfile"
out="$(_GS_CIV_ENV_FILE="${ROOT}/.env" _GS_CIV_IMAGES_DIR="${ROOT}/docker/images" bash "${SUT}" 2>&1)"
rc=$?
[[ $rc -eq 0 ]] && ok "internal-FROM: exit 0" || ko "internal-FROM: exit $rc"
[[ -z "$out" ]] && ok "internal-FROM: NOT checked (no WARN)" || ko "internal-FROM: unexpectedly warned: $out"
rm -rf "${ROOT}"

# ── Case 4: env var absent for an upstream service → skip gracefully ────────
ROOT="$(make_fixture)"
mkdir -p "${ROOT}/docker/images/01foo"
printf 'SOMETHING_ELSE=x\n' >"${ROOT}/.env"
printf 'ARG GLOBAL_STACK_IMAGE_FOO_VERSION=1.2.3\nFROM foo:${GLOBAL_STACK_IMAGE_FOO_VERSION}\n' \
  >"${ROOT}/docker/images/01foo/Dockerfile"
out="$(_GS_CIV_ENV_FILE="${ROOT}/.env" _GS_CIV_IMAGES_DIR="${ROOT}/docker/images" bash "${SUT}" 2>&1)"
rc=$?
[[ $rc -eq 0 ]] && ok "missing-env-var: exit 0" || ko "missing-env-var: exit $rc"
[[ -z "$out" ]] && ok "missing-env-var: skipped silently" || ko "missing-env-var: unexpected output: $out"
rm -rf "${ROOT}"

# ── Case 5: real repo tree → must exit 0 (baseline should be in-sync) ───────
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
out="$(_GS_CIV_ENV_FILE="${REPO_ROOT}/.env" _GS_CIV_IMAGES_DIR="${REPO_ROOT}/docker/images" bash "${SUT}" 2>&1)"
rc=$?
[[ $rc -eq 0 ]] && ok "real repo: exit 0" || ko "real repo: exit $rc"

# ── Case 6: defaults resolve from the script, not from $PWD ─────────────────
# A relative default ('docker/images') makes the scan VACUOUS from any other
# cwd: nothing is compared, nothing is printed, exit 0 — the same signature as
# a clean run. Same defect as the hardcoded --env-file fixed in 661cef3.
# Sabotage every upstream pin in a COPY of .env, then run from / with only the
# env-file overridden: the images dir must still be found.
SAB_ENV="$(mktemp)"
sed -E 's/^(GLOBAL_STACK_IMAGE_[A-Z0-9_]+_VERSION=.*)$/\1-sabotage/' "${REPO_ROOT}/.env" >"${SAB_ENV}"
# Guard the guard: a drifted sed pattern would make this test rot silently.
sab_lines="$(diff "${REPO_ROOT}/.env" "${SAB_ENV}" | grep -c '^>' || true)"
[[ "${sab_lines}" -ge 1 ]] && ok "cwd-independent: sabotage changed ${sab_lines} pin(s)" \
  || ko "cwd-independent: sabotage changed NO lines — pattern is stale, test would be vacuous"
out="$(cd / && _GS_CIV_ENV_FILE="${SAB_ENV}" bash "${SUT}" 2>&1)"
rc=$?
[[ $rc -eq 0 ]] && ok "cwd-independent: exit 0" || ko "cwd-independent: exit $rc"
grep -q 'sabotage' <<<"$out" && ok "cwd-independent: scanned the repo tree from a foreign cwd" \
  || ko "cwd-independent: VACUOUS from / — no service compared: '${out}'"
rm -f "${SAB_ENV}"

# ── Case 7: images dir holds no Dockerfile → the check DID NOT RUN ──────────
# Distinct from 'clean': zero comparisons because the tree is missing/renamed
# must be loud, while zero drift stays silent (cases 1/3/4).
ROOT="$(make_fixture)"
printf 'GLOBAL_STACK_IMAGE_FOO_VERSION=1.2.3\n' >"${ROOT}/.env"
out="$(_GS_CIV_ENV_FILE="${ROOT}/.env" _GS_CIV_IMAGES_DIR="${ROOT}/docker/images" bash "${SUT}" 2>&1)"
rc=$?
[[ $rc -eq 0 ]] && ok "no-dockerfiles: exit 0" || ko "no-dockerfiles: exit $rc"
grep -q 'WARN' <<<"$out" && grep -q "${ROOT}/docker/images" <<<"$out" \
  && ok "no-dockerfiles: WARN names the resolved dir" \
  || ko "no-dockerfiles: silent — indistinguishable from clean: '${out}'"
rm -rf "${ROOT}"

# ── Case 8: missing images dir entirely → same loud signal ──────────────────
out="$(_GS_CIV_ENV_FILE="${REPO_ROOT}/.env" _GS_CIV_IMAGES_DIR="/nonexistent-$$" bash "${SUT}" 2>&1)"
rc=$?
[[ $rc -eq 0 ]] && ok "missing-dir: exit 0" || ko "missing-dir: exit $rc"
grep -q 'WARN' <<<"$out" && ok "missing-dir: WARN emitted" \
  || ko "missing-dir: silent — indistinguishable from clean: '${out}'"

printf '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
if [[ "${FAIL}" -eq 0 ]]; then
  printf '  %bALL PASSED%b   ✓ %d / %d\n' "${C_GREEN}" "${C_RESET}" "${PASS}" "$((PASS + FAIL))"
else
  printf '  %bFAILED%b        ✗ %d / %d\n' "${C_RED}" "${C_RESET}" "${FAIL}" "$((PASS + FAIL))"
  for f in "${FAILURES[@]}"; do printf '    - %s\n' "$f"; done
  exit 1
fi
