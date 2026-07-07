#!/bin/bash
# Test suite for global-stack-base-prologue.sh (B-1) and GS_STARTUP_DRY_RUN seam (H-3).
# Run: bash bin/tests/startup-prologue.test.sh
#
# Tests:
#   1. Prologue file passes bash -n
#   2. All 49 migrated startup scripts pass bash -n
#   3. GS_STARTUP_DRY_RUN=1 exits 0 without running install code
#   4. GS_STARTUP_DRY_RUN=0 (default) does not exit early
#   5. stackCatch writes error token on non-zero exit
#   6. stackCatch is a no-op on exit 0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_BIN="${SCRIPT_DIR}/../../docker/config/dist/bin"
PROLOGUE="${DIST_BIN}/base-bin/global-stack-base-prologue.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# ─── colors ────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  C_GREEN='\033[0;32m' C_RED='\033[0;31m' C_RESET='\033[0m' C_BOLD='\033[1m'
else
  C_GREEN='' C_RED='' C_RESET='' C_BOLD=''
fi

PASS=0
FAIL=0
declare -a FAILURES=()

assert_pass() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    printf '  %b✓%b  %s\n' "${C_GREEN}" "${C_RESET}" "${label}"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("${label}")
    printf '  %b✗%b  %s\n' "${C_RED}" "${C_RESET}" "${label}"
  fi
}

assert_fail() {
  local label="$1"
  shift
  if ! "$@" >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    printf '  %b✓%b  %s\n' "${C_GREEN}" "${C_RESET}" "${label}"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("${label}")
    printf '  %b✗%b  %s\n' "${C_RED}" "${C_RESET}" "${label}"
  fi
}

assert_output_contains() {
  local label="$1"
  local pattern="$2"
  shift 2
  local out
  out=$("$@" 2>&1)
  if echo "${out}" | grep -q "${pattern}"; then
    PASS=$((PASS + 1))
    printf '  %b✓%b  %s\n' "${C_GREEN}" "${C_RESET}" "${label}"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("${label}")
    printf '  %b✗%b  %s  (output: %s)\n' "${C_RED}" "${C_RESET}" "${label}" "${out:0:100}"
  fi
}

# ─── Section 1: Prologue syntax ────────────────────────────────────────────
printf '\n%b── Section 1: Prologue syntax%b\n' "${C_BOLD}" "${C_RESET}"

assert_pass "prologue passes bash -n" bash -n "${PROLOGUE}"
assert_pass "prologue passes shellcheck (warning level)" shellcheck --severity=warning "${PROLOGUE}"

# ─── Section 2: Migrated scripts pass bash -n ──────────────────────────────
printf '\n%b── Section 2: Migrated scripts syntax (bash -n)%b\n' "${C_BOLD}" "${C_RESET}"

migrated_count=0
while IFS= read -r -d '' f; do
  if grep -q "source global-stack-base-prologue.sh" "${f}"; then
    assert_pass "bash -n: $(basename "${f}")" bash -n "${f}"
    migrated_count=$((migrated_count + 1))
  fi
done < <(find "${DIST_BIN}" -name "*.sh" -print0 2>/dev/null)
printf '  (checked %d migrated scripts)\n' "${migrated_count}"

# ─── Section 3: GS_STARTUP_DRY_RUN=1 exits 0 (H-3 seam) ─────────────────
printf '\n%b── Section 3: GS_STARTUP_DRY_RUN=1 dry-run seam%b\n' "${C_BOLD}" "${C_RESET}"

# Create a minimal test script that sources the prologue
cat >"${TMP_DIR}/test-script.sh" <<'TESTEOF'
#!/bin/bash
set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh
# If we reach here, the dry-run seam did NOT fire
echo "INSTALL_REACHED"
TESTEOF
chmod +x "${TMP_DIR}/test-script.sh"

# H-3: GS_STARTUP_DRY_RUN=1 must exit 0 before install code
dry_run_out=$(
  GLOBAL_STACK_ERROR_TOKEN=test-prologue \
    GLOBAL_STACK_DOCKER_TOOLS_PATH="${TMP_DIR}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${TMP_DIR}" \
    GS_STARTUP_DRY_RUN=1 \
    PATH="${DIST_BIN}/base-bin:${PATH}" \
    bash "${TMP_DIR}/test-script.sh" 2>&1
)
dry_run_exit=$?

if [[ "${dry_run_exit}" -eq 0 ]]; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  GS_STARTUP_DRY_RUN=1 exits 0\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("GS_STARTUP_DRY_RUN=1 exits 0")
  printf '  %b✗%b  GS_STARTUP_DRY_RUN=1 exits 0 (got exit %d)\n' "${C_RED}" "${C_RESET}" "${dry_run_exit}"
fi

if echo "${dry_run_out}" | grep -q "DRY RUN"; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  GS_STARTUP_DRY_RUN=1 prints [DRY RUN] marker\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("GS_STARTUP_DRY_RUN=1 prints [DRY RUN] marker")
  printf '  %b✗%b  GS_STARTUP_DRY_RUN=1 prints [DRY RUN] marker\n' "${C_RED}" "${C_RESET}"
fi

if ! echo "${dry_run_out}" | grep -q "INSTALL_REACHED"; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  GS_STARTUP_DRY_RUN=1 does not reach install code\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("GS_STARTUP_DRY_RUN=1 does not reach install code")
  printf '  %b✗%b  GS_STARTUP_DRY_RUN=1 does not reach install code\n' "${C_RED}" "${C_RESET}"
fi

# ─── Section 4: GS_STARTUP_DRY_RUN=0 reaches install code ────────────────
printf '\n%b── Section 4: GS_STARTUP_DRY_RUN=0 (default) reaches install code%b\n' "${C_BOLD}" "${C_RESET}"

normal_out=$(
  GLOBAL_STACK_ERROR_TOKEN=test-prologue \
    GLOBAL_STACK_DOCKER_TOOLS_PATH="${TMP_DIR}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${TMP_DIR}" \
    GS_STARTUP_DRY_RUN=0 \
    PATH="${DIST_BIN}/base-bin:${PATH}" \
    bash "${TMP_DIR}/test-script.sh" 2>&1
)

if echo "${normal_out}" | grep -q "INSTALL_REACHED"; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  GS_STARTUP_DRY_RUN=0 reaches install code\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("GS_STARTUP_DRY_RUN=0 reaches install code")
  printf '  %b✗%b  GS_STARTUP_DRY_RUN=0 reaches install code\n' "${C_RED}" "${C_RESET}"
fi

# ─── Section 5: stackCatch writes error token on non-zero exit ─────────────
printf '\n%b── Section 5: stackCatch error token behavior%b\n' "${C_BOLD}" "${C_RESET}"

cat >"${TMP_DIR}/test-fail.sh" <<'TESTEOF'
#!/bin/bash
set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh
false
TESTEOF
chmod +x "${TMP_DIR}/test-fail.sh"

mkdir -p "${TMP_DIR}/errors"
GLOBAL_STACK_ERROR_TOKEN=test-token \
  GLOBAL_STACK_DOCKER_TOOLS_PATH="${TMP_DIR}" \
  GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${TMP_DIR}/errors" \
  PATH="${DIST_BIN}/base-bin:${PATH}" \
  bash "${TMP_DIR}/test-fail.sh" 2>/dev/null || true

if [[ -f "${TMP_DIR}/errors/test-token" ]]; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  stackCatch writes error token on non-zero exit\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("stackCatch writes error token on non-zero exit")
  printf '  %b✗%b  stackCatch writes error token on non-zero exit\n' "${C_RED}" "${C_RESET}"
fi

# ─── Section 6: stackCatch is no-op on exit 0 ────────────────────────────
printf '\n%b── Section 6: stackCatch clean exit%b\n' "${C_BOLD}" "${C_RESET}"

cat >"${TMP_DIR}/test-pass.sh" <<'TESTEOF'
#!/bin/bash
set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh
true
TESTEOF
chmod +x "${TMP_DIR}/test-pass.sh"

mkdir -p "${TMP_DIR}/errors2"
GLOBAL_STACK_ERROR_TOKEN=test-pass-token \
  GLOBAL_STACK_DOCKER_TOOLS_PATH="${TMP_DIR}" \
  GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${TMP_DIR}/errors2" \
  PATH="${DIST_BIN}/base-bin:${PATH}" \
  bash "${TMP_DIR}/test-pass.sh" 2>/dev/null

if [[ ! -f "${TMP_DIR}/errors2/test-pass-token" ]]; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  stackCatch does not write error token on clean exit\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("stackCatch does not write error token on clean exit")
  printf '  %b✗%b  stackCatch does not write error token on clean exit\n' "${C_RED}" "${C_RESET}"
fi

# ─── Section 7: atomic shellrc writes (E-4) ─────────────────────────────────
# Each shared-volume *.shellrc writer must publish via a temp file + atomic
# rename (mv tmp -> final) so the host never sources a partially-written file.
# Assert (a) an atomic `mv "<tmp>" "<...shellrc>"` exists, and (b) no bare
# redirect writes the final .shellrc path outside the temp grouping.
printf '\n%b── Section 7: atomic shellrc writes (E-4)%b\n' "${C_BOLD}" "${C_RESET}"

# script:shellrc-basename pairs for the shared-volume writers (Source A only)
ATOMIC_SHELLRC=(
  "nvm-bin/global-stack-nvm-start.sh:nvm.shellrc"
  "phpbrew-bin/global-stack-phpbrew-start.sh:phpbrew.shellrc"
  "fvm-bin/global-stack-fvm-start.sh:fvm.shellrc"
  "pyenv-bin/global-stack-pyenv-start.sh:pyenv.shellrc"
  "rbenv-bin/global-stack-rbenv-start.sh:rbenv.shellrc"
  "sdkman-bin/global-stack-sdkman-start.sh:sdkman.shellrc"
  "base-bin/global-stack-base-install-mise.sh:mise.shellrc"
)

for pair in "${ATOMIC_SHELLRC[@]}"; do
  script="${pair%%:*}"
  base="${pair##*:}"
  path="${DIST_BIN}/${script}"

  # (a) must publish via temp+atomic-rename: assign a var to the final .shellrc
  # path, redirect the export block to "<var>.tmp", then `mv "<var>.tmp" "<var>"`.
  # Match (i) a "<...>.tmp" redirect target and (ii) an `mv "<...>.tmp" "<...>"`
  # rename — the basename appears in the var assignment, not the mv line.
  if grep -Eq "${base}\"" "${path}" \
    && grep -Eq "mv[[:space:]]+\"[^\"]*\.tmp\"[[:space:]]+\"[^\"]*\"" "${path}" \
    && grep -Eq ">[[:space:]]+\"[^\"]*\.tmp\"" "${path}"; then
    PASS=$((PASS + 1))
    printf '  %b✓%b  %s publishes %s via atomic mv\n' "${C_GREEN}" "${C_RESET}" "${script}" "${base}"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("${script} missing atomic mv for ${base}")
    printf '  %b✗%b  %s missing atomic mv for %s\n' "${C_RED}" "${C_RESET}" "${script}" "${base}"
  fi

  # (b) must NOT write the final .shellrc via a direct redirect (> or >>) to its path
  if grep -Eq ">>?[[:space:]]+\"[^\"]*${base}\"" "${path}"; then
    FAIL=$((FAIL + 1))
    FAILURES+=("${script} still writes ${base} via direct redirect")
    printf '  %b✗%b  %s still redirects directly to %s\n' "${C_RED}" "${C_RESET}" "${script}" "${base}"
  else
    PASS=$((PASS + 1))
    printf '  %b✓%b  %s has no direct redirect to %s\n' "${C_GREEN}" "${C_RESET}" "${script}" "${base}"
  fi
done

# ─── Section 8: gs_version_gate content-compare + ERR-trap safety ───────────
# gs_version_gate <marker> <expected> <label> emits a decision on STDOUT
# (install|skip|reinstall) and, on a real mismatch, a WARN on STDERR. It MUST
# be set -eE / ERR-trap safe: the internal mismatch test returning non-zero must
# never fire stackCatch (which would write tools/errors/<token> and mask the
# container as permanently unhealthy behind the 24h start_period).
printf '\n%b── Section 8: gs_version_gate content-compare + ERR-trap safety%b\n' "${C_BOLD}" "${C_RESET}"

# Runner: sources the prologue under full strict mode + ERR trap, then calls the
# gate exactly as a startup script will (captured into a var). Prints
# "DECISION=<word>" on stdout; any error token lands in ${TMP_DIR}/errors8.
cat >"${TMP_DIR}/test-gate.sh" <<'TESTEOF'
#!/bin/bash
set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh
dec="$(gs_version_gate "${GATE_MARKER}" "${GATE_EXPECTED}" "${GATE_LABEL:-test}")"
printf 'DECISION=%s\n' "${dec}"
TESTEOF
chmod +x "${TMP_DIR}/test-gate.sh"

run_gate() {
  # $1 marker path, $2 expected, returns combined stdout+stderr; error token → errors8/
  local marker="$1" expected="$2"
  rm -rf "${TMP_DIR}/errors8"
  mkdir -p "${TMP_DIR}/errors8"
  GLOBAL_STACK_ERROR_TOKEN=gate-token \
    GLOBAL_STACK_DOCKER_TOOLS_PATH="${TMP_DIR}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${TMP_DIR}/errors8" \
    GATE_MARKER="${marker}" \
    GATE_EXPECTED="${expected}" \
    GATE_LABEL="node.24" \
    PATH="${DIST_BIN}/base-bin:${PATH}" \
    bash "${TMP_DIR}/test-gate.sh" 2>&1
}

errors8_empty() { [[ -z "$(ls -A "${TMP_DIR}/errors8" 2>/dev/null)" ]]; }

# 8a: absent marker → install, exit 0, no error token, no WARN
gate_marker="${TMP_DIR}/versions/node.24"
rm -f "${gate_marker}"
mkdir -p "${TMP_DIR}/versions"
out8a=$(run_gate "${gate_marker}" "v24.18.0") && exit8a=0 || exit8a=$?
if [[ "${exit8a}" -eq 0 ]] && echo "${out8a}" | grep -q "DECISION=install" && errors8_empty; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  absent marker → install, exit 0, no error token\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("gate: absent marker → install")
  printf '  %b✗%b  absent marker → install (exit %d, out: %s)\n' "${C_RED}" "${C_RESET}" "${exit8a}" "${out8a:0:80}"
fi
if ! echo "${out8a}" | grep -q "WARN"; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  absent marker is silent (no WARN)\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("gate: absent marker must be silent")
  printf '  %b✗%b  absent marker emitted WARN\n' "${C_RED}" "${C_RESET}"
fi

# 8b: matching marker → skip, exit 0, no error token, no WARN (equal must not churn)
printf 'v24.18.0' >"${gate_marker}"
out8b=$(run_gate "${gate_marker}" "v24.18.0") && exit8b=0 || exit8b=$?
if [[ "${exit8b}" -eq 0 ]] && echo "${out8b}" | grep -q "DECISION=skip" && errors8_empty; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  equal marker → skip, exit 0, NO error token (ERR-trap safe)\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("gate: equal → skip + errors empty")
  printf '  %b✗%b  equal → skip (exit %d, errors empty=%s, out: %s)\n' "${C_RED}" "${C_RESET}" "${exit8b}" "$(errors8_empty && echo yes || echo NO)" "${out8b:0:80}"
fi

# 8c: differing marker → reinstall + WARN, exit 0, NO error token (the loop/mask case)
printf 'v24.17.0' >"${gate_marker}"
out8c=$(run_gate "${gate_marker}" "v24.18.0") && exit8c=0 || exit8c=$?
if [[ "${exit8c}" -eq 0 ]] && echo "${out8c}" | grep -q "DECISION=reinstall" && errors8_empty; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  differ marker → reinstall, exit 0, NO error token (ERR-trap safe)\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("gate: differ → reinstall + errors empty")
  printf '  %b✗%b  differ → reinstall (exit %d, errors empty=%s, out: %s)\n' "${C_RED}" "${C_RESET}" "${exit8c}" "$(errors8_empty && echo yes || echo NO)" "${out8c:0:80}"
fi
if echo "${out8c}" | grep -q "WARN"; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  differ marker emits WARN on stderr\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("gate: differ must WARN")
  printf '  %b✗%b  differ marker did not WARN\n' "${C_RED}" "${C_RESET}"
fi

# ─── Section 9: version-gate wiring — correct compare target per runtime ────
# Each wired tier-03 startup script must pass the CORRECT expected version var to
# gs_version_gate (the loop-proof lynchpin). Notably python MUST compare against
# $PYTHON_VERSION, not the empty-at-gate-time $PYENV_VERSION. Un-wired scripts are
# skipped so this section grows coverage across the checkpoint-2 per-runtime commits.
printf '\n%b── Section 9: version-gate wiring (compare target)%b\n' "${C_BOLD}" "${C_RESET}"

GATE_WIRING=(
  "nvm-bin/global-stack-nvm-start.sh:NODE_VERSION"
  "phpbrew-bin/global-stack-phpbrew-start.sh:PHP_VERSION_NAME"
  "pyenv-bin/global-stack-pyenv-start.sh:PYTHON_VERSION"
  "rbenv-bin/global-stack-rbenv-start.sh:RUBY_VERSION"
  "sdkman-bin/global-stack-sdkman-start.sh:JAVA_VERSION"
  "fvm-bin/global-stack-fvm-start.sh:FLUTTER_VERSION"
)

gate_wired_count=0
for pair in "${GATE_WIRING[@]}"; do
  script="${pair%%:*}"
  var="${pair##*:}"
  path="${DIST_BIN}/${script}"
  grep -q "gs_version_gate" "${path}" 2>/dev/null || continue
  gate_wired_count=$((gate_wired_count + 1))
  if grep -Eq "gs_version_gate .*\\\$\\{${var}[:}]" "${path}"; then
    PASS=$((PASS + 1))
    printf '  %b✓%b  %s gates on $%s\n' "${C_GREEN}" "${C_RESET}" "$(basename "${script}")" "${var}"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("${script} wrong gate compare target (expected \$${var})")
    printf '  %b✗%b  %s does NOT gate on $%s\n' "${C_RED}" "${C_RESET}" "$(basename "${script}")" "${var}"
  fi
done
printf '  (checked %d wired runtime scripts)\n' "${gate_wired_count}"

# ─── Section 10: base-setup-packages per-slot marker gate (checkpoint 3a) ───
# The package engine must key markers by INSTALL_PACKAGE SLOT, not package NAME,
# so multiple slots sharing a name (maven_vx1/vx2) get DISTINCT markers and do
# NOT flip-flop-reinstall every boot. It must skip dummy/empty slots, reinstall
# only a bumped slot, and fire --cleanup-command with the OLD version on a bump.
printf '\n%b── Section 10: base-setup-packages per-slot marker gate%b\n' "${C_BOLD}" "${C_RESET}"

cat >"${TMP_DIR}/test-pkg.sh" <<'TESTEOF'
#!/bin/bash
set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh
source global-stack-base-setup-packages.sh
global_stack_base_setup_packages "$@"
TESTEOF
chmod +x "${TMP_DIR}/test-pkg.sh"

PKG_VERSIONS="${TMP_DIR}/pkgversions"
PKG_LOG="${TMP_DIR}/pkg-install.log"
CLEANUP_LOG="${TMP_DIR}/pkg-cleanup.log"

# Runner: synthetic packages via env — two maven slots (same NAME, distinct
# slots), one dummy, one empty-version. Installs append to PKG_LOG, cleanups to
# CLEANUP_LOG. VX1/VX2 overridable per scenario. Extra args ("$@") pass through.
run_pkg() {
  env \
    GLOBAL_STACK_ERROR_TOKEN=pkg-token \
    GLOBAL_STACK_DOCKER_TOOLS_PATH="${TMP_DIR}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${PKG_ERR:-${TMP_DIR}}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${PKG_VERSIONS}" \
    PKG_LOG="${PKG_LOG}" \
    CLEANUP_LOG="${CLEANUP_LOG}" \
    TESTRT_INSTALL_PACKAGE_MAVEN_VX1_VERSION="${VX1:-1.0}" \
    TESTRT_CONFIG_PACKAGE_MAVEN_VX1_NAME=maven \
    TESTRT_INSTALL_PACKAGE_MAVEN_VX2_VERSION="${VX2:-2.0}" \
    TESTRT_CONFIG_PACKAGE_MAVEN_VX2_NAME=maven \
    TESTRT_INSTALL_PACKAGE_DUMMYPKG_VERSION=9.9 \
    TESTRT_CONFIG_PACKAGE_DUMMYPKG_NAME=dummy \
    TESTRT_INSTALL_PACKAGE_EMPTYVER_VERSION="" \
    TESTRT_CONFIG_PACKAGE_EMPTYVER_NAME=someempty \
    PATH="${DIST_BIN}/base-bin:${PATH}" \
    bash "${TMP_DIR}/test-pkg.sh" \
    --prefix=TESTRT \
    "$@" \
    --command='printf "install %s %s\n" "${PACKAGE_NAME}" "${PACKAGE_VERSION}" >> "${PKG_LOG}"'
}

pkg_check() {
  # $1 label, $2 = 0/1 condition already evaluated by caller via "$@" test
  local label="$1"
  shift
  if "$@"; then
    PASS=$((PASS + 1))
    printf '  %b✓%b  %s\n' "${C_GREEN}" "${C_RESET}" "${label}"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("${label}")
    printf '  %b✗%b  %s\n' "${C_RED}" "${C_RESET}" "${label}"
  fi
}

# 10a: first run installs both maven slots + writes 2 DISTINCT slot markers
rm -rf "${PKG_VERSIONS}"
mkdir -p "${PKG_VERSIONS}"
: >"${PKG_LOG}"
run_pkg --marker-prefix=test.1 >/dev/null 2>&1 || true
n_first=$(grep -c '^install maven' "${PKG_LOG}" 2>/dev/null || true)
pkg_check "first run installs both maven slots (2 installs)" [ "${n_first}" = "2" ]
pkg_check "slot markers are distinct (maven_vx1 + maven_vx2 both exist)" \
  bash -c '[[ -f "'"${PKG_VERSIONS}"'/test.1.pkg.maven_vx1" && -f "'"${PKG_VERSIONS}"'/test.1.pkg.maven_vx2" ]]'
pkg_check "dummy slot writes no marker" \
  bash -c '[[ ! -f "'"${PKG_VERSIONS}"'/test.1.pkg.dummypkg" ]]'
pkg_check "empty-version slot writes no marker" \
  bash -c '[[ ! -f "'"${PKG_VERSIONS}"'/test.1.pkg.emptyver" ]]'

# 10b (CERTIFICATION): second run, same versions → ZERO reinstalls (no flip-flop)
: >"${PKG_LOG}"
run_pkg --marker-prefix=test.1 >/dev/null 2>&1 || true
n_second=$(grep -c '^install' "${PKG_LOG}" 2>/dev/null || true)
pkg_check "second run with same versions → ZERO reinstalls (slot collision fixed)" \
  [ "${n_second}" = "0" ]

# 10c: bump only VX1 → only that slot reinstalls, marker updated
: >"${PKG_LOG}"
VX1=1.1 run_pkg --marker-prefix=test.1 >/dev/null 2>&1 || true
n_bump=$(grep -c '^install' "${PKG_LOG}" 2>/dev/null || true)
got_bump=$(grep -c '^install maven 1.1' "${PKG_LOG}" 2>/dev/null || true)
pkg_check "bump one slot → exactly one reinstall" [ "${n_bump}" = "1" ]
pkg_check "bump reinstalls the correct (bumped) version" [ "${got_bump}" = "1" ]

# 10d: --cleanup-command fires with OLD version on a bump, NOT on first install
rm -f "${PKG_VERSIONS}/test.2."*
: >"${CLEANUP_LOG}"
VX1=5.0 run_pkg --marker-prefix=test.2 \
  --cleanup-command='printf "cleanup %s %s\n" "${PACKAGE_NAME}" "${PACKAGE_OLD_VERSION}" >> "${CLEANUP_LOG}"' \
  >/dev/null 2>&1 || true
n_clean_first=$(grep -c '^cleanup' "${CLEANUP_LOG}" 2>/dev/null || true)
pkg_check "cleanup-command does NOT fire on first install" [ "${n_clean_first}" = "0" ]
: >"${CLEANUP_LOG}"
VX1=5.1 run_pkg --marker-prefix=test.2 \
  --cleanup-command='printf "cleanup %s %s\n" "${PACKAGE_NAME}" "${PACKAGE_OLD_VERSION}" >> "${CLEANUP_LOG}"' \
  >/dev/null 2>&1 || true
got_clean=$(grep -c '^cleanup maven 5.0' "${CLEANUP_LOG}" 2>/dev/null || true)
pkg_check "cleanup-command fires with OLD version on a bump" [ "${got_clean}" = "1" ]

# 10e: backward compat — no --marker-prefix runs every command, writes no markers
rm -rf "${PKG_VERSIONS}"
mkdir -p "${PKG_VERSIONS}"
: >"${PKG_LOG}"
run_pkg >/dev/null 2>&1 || true
n_compat=$(grep -c '^install maven' "${PKG_LOG}" 2>/dev/null || true)
pkg_check "no --marker-prefix → legacy behavior (both installs run)" [ "${n_compat}" = "2" ]
pkg_check "no --marker-prefix → writes no slot markers" \
  bash -c 'compgen -G "'"${PKG_VERSIONS}"'/*.pkg.*" >/dev/null && exit 1 || exit 0'

# 10f: ERR-trap safety — package gate runs under set -eE, tools/errors stays empty
pkg_errors_empty() { [[ -z "$(ls -A "${TMP_DIR}/pkgerr" 2>/dev/null)" ]]; }
rm -rf "${PKG_VERSIONS}" "${TMP_DIR}/pkgerr"
mkdir -p "${PKG_VERSIONS}" "${TMP_DIR}/pkgerr"
PKG_ERR="${TMP_DIR}/pkgerr" run_pkg --marker-prefix=test.3 >/dev/null 2>&1 || true
pkg_check "package gate ERR-trap safe (no error token written)" pkg_errors_empty

# ─── Section 11: package loop wired with --marker-prefix (ckpt 3b/3c/3d) ────
# A runtime that installs packages must pass --marker-prefix="<runtime>.<...>" so
# the per-slot gate is active. Scripts not yet wired (still legacy) are skipped so
# this section grows coverage across the checkpoint-3 sub-commits.
printf '\n%b── Section 11: package loop --marker-prefix wiring%b\n' "${C_BOLD}" "${C_RESET}"

PKG_WIRING=(
  "nvm-bin/global-stack-nvm-start.sh:node"
  "phpbrew-bin/global-stack-phpbrew-start.sh:php"
  "pyenv-bin/global-stack-pyenv-start.sh:python"
  "rbenv-bin/global-stack-rbenv-start.sh:ruby"
  "sdkman-bin/global-stack-sdkman-start.sh:java"
)

pkg_wired_count=0
for pair in "${PKG_WIRING[@]}"; do
  script="${pair%%:*}"
  name="${pair##*:}"
  path="${DIST_BIN}/${script}"
  grep -q "global_stack_base_setup_packages" "${path}" 2>/dev/null || continue
  grep -q -- "--marker-prefix" "${path}" 2>/dev/null || continue
  pkg_wired_count=$((pkg_wired_count + 1))
  if grep -Eq -- "--marker-prefix=\"${name}\." "${path}"; then
    PASS=$((PASS + 1))
    printf '  %b✓%b  %s package loop gated with --marker-prefix=%s.*\n' "${C_GREEN}" "${C_RESET}" "$(basename "${script}")" "${name}"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("${script} --marker-prefix not keyed on ${name}.")
    printf '  %b✗%b  %s --marker-prefix not keyed on %s.\n' "${C_RED}" "${C_RESET}" "$(basename "${script}")" "${name}"
  fi
done
printf '  (checked %d package-gated scripts)\n' "${pkg_wired_count}"

# ─── Section 12: python runtime-gate + package-loop composition (ckpt 3c) ──
# Integration of the REAL gs_version_gate (runtime gate) + REAL
# base-setup-packages (relocated package loop) exactly as pyenv-start.sh chains
# them. NOTE: the full startup script cannot be run in this harness — it does
# sed -i / echo >> to a hardcoded /home/<user>/ path and ends in `sleep infinity`
# (that is why Section 2 only bash -n's it). This composes the mechanism the
# relocation depends on; the full-container reinstall path is exercised manually
# / in the bump-versions workflow. Covers the empty-globals P0: a runtime SKIP
# must NOT wipe pkg markers (no recompile); a runtime REINSTALL must wipe them so
# globals repopulate on the fresh interpreter.
printf '\n%b── Section 12: python gate+loop composition (mechanism)%b\n' "${C_BOLD}" "${C_RESET}"

cat >"${TMP_DIR}/test-pyflow.sh" <<'TESTEOF'
#!/bin/bash
set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh
source global-stack-base-setup-packages.sh
_label="${PYTHON_VERSION_AS:-${PYTHON_VERSION}}"
_marker="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python.${_label}"
# --- runtime gate (mirrors pyenv-start.sh checkpoint-2 block) ---
_dec="$(gs_version_gate "${_marker}" "${PYTHON_VERSION}" "python.${_label}")"
if [[ "${_dec}" == "reinstall" ]]; then
  _old="$(cat "${_marker}" 2>/dev/null || true)"
  [[ -n "${_old}" && "${_old}" != "${PYTHON_VERSION}" ]] && rm -rf "${PYENV_ROOT}/versions/${_old}"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python.${_label}.pkg."* || true
  rm -f "${_marker}"
fi
# --- runtime install (fake) writes the marker when absent (mirrors the script) ---
if [[ ! -f "${_marker}" ]]; then
  printf 'pyenv-install %s\n' "${PYTHON_VERSION}" >>"${INSTALL_LOG}"
  echo "${PYTHON_VERSION}" >"${_marker}"
fi
# --- relocated package loop, every boot (mirrors ckpt-3b/3c relocation) ---
global_stack_base_setup_packages \
  --prefix='PYTHON' \
  --marker-prefix="python.${_label}" \
  --command='printf "pip %s %s\n" "${PACKAGE_NAME}" "${PACKAGE_VERSION}" >> "${PIP_LOG}"'
TESTEOF
chmod +x "${TMP_DIR}/test-pyflow.sh"

PYV="${TMP_DIR}/pyversions"
INSTALL_LOG="${TMP_DIR}/py-install.log"
PIP_LOG="${TMP_DIR}/py-pip.log"

run_pyflow() {
  env \
    GLOBAL_STACK_ERROR_TOKEN=py-token \
    GLOBAL_STACK_DOCKER_TOOLS_PATH="${TMP_DIR}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${TMP_DIR}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${PYV}" \
    PYENV_ROOT="${TMP_DIR}/pyenvroot" \
    PYTHON_VERSION="${PYVER:-3.14.6}" \
    PYTHON_VERSION_AS=3 \
    INSTALL_LOG="${INSTALL_LOG}" \
    PIP_LOG="${PIP_LOG}" \
    TESTRT_INSTALL_PACKAGE_UNUSED_VERSION="" \
    PYTHON_INSTALL_PACKAGE_PIPX_VERSION="${PIPX:-1.0}" \
    PYTHON_CONFIG_PACKAGE_PIPX_NAME=pipx \
    PATH="${DIST_BIN}/base-bin:${PATH}" \
    bash "${TMP_DIR}/test-pyflow.sh"
}

# 12a: first boot — runtime installs + pip installs + markers written
rm -rf "${PYV}" "${TMP_DIR}/pyenvroot"
mkdir -p "${PYV}" "${TMP_DIR}/pyenvroot/versions/3.14.6"
: >"${INSTALL_LOG}"
: >"${PIP_LOG}"
run_pyflow >/dev/null 2>&1 || true
n_inst=$(grep -c '^pyenv-install' "${INSTALL_LOG}" 2>/dev/null || true)
n_pip=$(grep -c '^pip pipx' "${PIP_LOG}" 2>/dev/null || true)
pkg_check "first boot: python installed + pip package installed" \
  bash -c '[[ "'"${n_inst}"'" = "1" && "'"${n_pip}"'" = "1" && -f "'"${PYV}"'/python.3" && -f "'"${PYV}"'/python.3.pkg.pipx" ]]'

# 12b (no-recompile trap): second boot, same version → NO pyenv-install, NO pip
: >"${INSTALL_LOG}"
: >"${PIP_LOG}"
run_pyflow >/dev/null 2>&1 || true
n_inst2=$(grep -c '^pyenv-install' "${INSTALL_LOG}" 2>/dev/null || true)
n_pip2=$(grep -c '^pip' "${PIP_LOG}" 2>/dev/null || true)
pkg_check "second boot same version → NO python recompile (skip)" [ "${n_inst2}" = "0" ]
pkg_check "second boot same version → NO pip reinstall (pkg markers preserved)" [ "${n_pip2}" = "0" ]

# 12c (empty-globals P0): runtime bump → python reinstalls AND pip repopulates
: >"${INSTALL_LOG}"
: >"${PIP_LOG}"
PYVER=3.14.7 run_pyflow >/dev/null 2>&1 || true
n_inst3=$(grep -c '^pyenv-install' "${INSTALL_LOG}" 2>/dev/null || true)
n_pip3=$(grep -c '^pip pipx' "${PIP_LOG}" 2>/dev/null || true)
pkg_check "runtime bump → python reinstalls" [ "${n_inst3}" = "1" ]
pkg_check "runtime bump → pip globals repopulate on fresh interpreter (no empty-globals)" [ "${n_pip3}" = "1" ]

# ─── Section 13: --tolerant marker guard (checkpoint 3e) ───────────────────
# Under a tolerant caller (sdkman runs set +E; `sdk install` can fail without
# aborting), a FAILED install must NOT leave a satisfied slot marker — otherwise
# the next boot skips and the package is silently, permanently missing. The guard
# must be opt-in (--tolerant): the set -e callers (node/php/python/ruby) must keep
# fail-loud behavior, NOT be silently disarmed.
printf '\n%b── Section 13: --tolerant marker guard%b\n' "${C_BOLD}" "${C_RESET}"

cat >"${TMP_DIR}/test-tol.sh" <<'TESTEOF'
#!/bin/bash
set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh
source global-stack-base-setup-packages.sh
global_stack_base_setup_packages "$@"
TESTEOF
chmod +x "${TMP_DIR}/test-tol.sh"

TOLV="${TMP_DIR}/tolversions"
run_tol() {
  env \
    GLOBAL_STACK_ERROR_TOKEN=tol-token \
    GLOBAL_STACK_DOCKER_TOOLS_PATH="${TMP_DIR}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${TOL_ERR:-${TMP_DIR}}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${TOLV}" \
    TESTTOL_INSTALL_PACKAGE_FOO_VERSION=1.0 \
    TESTTOL_CONFIG_PACKAGE_FOO_NAME=foo \
    PATH="${DIST_BIN}/base-bin:${PATH}" \
    bash "${TMP_DIR}/test-tol.sh" --prefix=TESTTOL "$@"
}

# 13a: TOLERANT + failing install command → marker NOT written (retry next boot)
rm -rf "${TOLV}"
mkdir -p "${TOLV}"
run_tol --marker-prefix=tol.1 --tolerant --command='false' >/dev/null 2>&1 || true
pkg_check "tolerant + failed install → NO marker written (retryable)" \
  bash -c '[[ ! -f "'"${TOLV}"'/tol.1.pkg.foo" ]]'

# 13b: TOLERANT + command succeeds but --success-check fails → marker NOT written
rm -rf "${TOLV}"
mkdir -p "${TOLV}"
run_tol --marker-prefix=tol.1 --tolerant --success-check='false' --command='true' >/dev/null 2>&1 || true
pkg_check "tolerant + success-check fails → NO marker written" \
  bash -c '[[ ! -f "'"${TOLV}"'/tol.1.pkg.foo" ]]'

# 13c: TOLERANT + command + success-check both pass → marker IS written
rm -rf "${TOLV}"
mkdir -p "${TOLV}"
run_tol --marker-prefix=tol.1 --tolerant --success-check='true' --command='true' >/dev/null 2>&1 || true
pkg_check "tolerant + success → marker written" \
  bash -c '[[ -f "'"${TOLV}"'/tol.1.pkg.foo" ]]'

# 13d: NON-tolerant + failing command → aborts under set -e (error token written),
# proving the majority path is NOT silently disarmed
rm -rf "${TOLV}" "${TMP_DIR}/tolerr"
mkdir -p "${TOLV}" "${TMP_DIR}/tolerr"
TOL_ERR="${TMP_DIR}/tolerr" run_tol --marker-prefix=tol.2 --command='false' >/dev/null 2>&1 || true
pkg_check "non-tolerant + failed command → set -e aborts (error token written)" \
  bash -c '[[ -n "$(ls -A "'"${TMP_DIR}"'/tolerr" 2>/dev/null)" ]]'
pkg_check "non-tolerant + failed command → NO marker written" \
  bash -c '[[ ! -f "'"${TOLV}"'/tol.2.pkg.foo" ]]'

# ─── Section 14: ckpt-4 manager/rust version-drift WARN probe wiring ────────
# Each manager + rust script must carry the additive gs_version_gate PROBE (a
# discard-decision `>/dev/null` call whose only effect is the stderr WARN — the
# install condition is untouched). This static check is the Coverage row for
# ckpt 4: the probe is unreachable under GS_STARTUP_DRY_RUN (prologue exits
# first), so bash -n proves parse only. The exact fixed-string fragment pins the
# marker path AND the expected expr — notably the `#v` strip on pyenv/rbenv,
# whose omission would spuriously WARN every boot. The WARN mechanism itself is
# already covered by Section 8.
printf '\n%b── Section 14: ckpt-4 manager/rust WARN probe wiring%b\n' "${C_BOLD}" "${C_RESET}"

PROBE_WIRING=(
  'nvm-bin/global-stack-nvm-start.sh|gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm" "${GLOBAL_STACK_NVM_VERSION}" "nvm" >/dev/null'
  'phpbrew-bin/global-stack-phpbrew-start.sh|gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew" "${GLOBAL_STACK_PHPBREW_VERSION}" "phpbrew" >/dev/null'
  'pyenv-bin/global-stack-pyenv-start.sh|gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/pyenv" "${GLOBAL_STACK_PYENV_VERSION#v}" "pyenv" >/dev/null'
  'rbenv-bin/global-stack-rbenv-start.sh|gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv" "${GLOBAL_STACK_RBENV_VERSION#v}" "rbenv" >/dev/null'
  'sdkman-bin/global-stack-sdkman-start.sh|gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/sdkman" "${GLOBAL_STACK_SDKMAN_VERSION}" "sdkman" >/dev/null'
  'fvm-bin/global-stack-fvm-start.sh|gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/fvm" "${GLOBAL_STACK_FVM_VERSION}" "fvm" >/dev/null'
  'rust-bin/global-stack-rust-start.sh|gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust" "${GLOBAL_STACK_RUST_VERSION}" "rust" >/dev/null'
)

for pair in "${PROBE_WIRING[@]}"; do
  script="${pair%%|*}"
  fragment="${pair#*|}"
  path="${DIST_BIN}/${script}"
  if grep -Fq "${fragment}" "${path}"; then
    PASS=$((PASS + 1))
    printf '  %b✓%b  %s carries correct WARN probe\n' "${C_GREEN}" "${C_RESET}" "$(basename "${script}")"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("${script} missing/incorrect ckpt-4 WARN probe")
    printf '  %b✗%b  %s missing/incorrect WARN probe\n' "${C_RED}" "${C_RESET}" "$(basename "${script}")"
  fi
done

# Exactly-once guarantee for the two-block scripts (pyenv/rbenv/rust): the probe
# fragment must appear exactly ONCE so the WARN does not fire twice per boot.
for pair in "${PROBE_WIRING[@]}"; do
  script="${pair%%|*}"
  fragment="${pair#*|}"
  path="${DIST_BIN}/${script}"
  n="$(grep -Fc "${fragment}" "${path}" 2>/dev/null || echo 0)"
  if [[ "${n}" -eq 1 ]]; then
    PASS=$((PASS + 1))
    printf '  %b✓%b  %s WARN probe appears exactly once\n' "${C_GREEN}" "${C_RESET}" "$(basename "${script}")"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("${script} ckpt-4 WARN probe count=${n} (want 1)")
    printf '  %b✗%b  %s WARN probe count=%s (want 1)\n' "${C_RED}" "${C_RESET}" "$(basename "${script}")" "${n}"
  fi
done

# ─── Summary ──────────────────────────────────────────────────────────────
printf '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
if [[ "${FAIL}" -eq 0 ]]; then
  printf '  %bALL PASSED%b   ✓ %d / %d\n' "${C_GREEN}" "${C_RESET}" "${PASS}" "$((PASS + FAIL))"
else
  printf '  %bFAILED%b        ✗ %d failures / %d total\n' "${C_RED}" "${C_RESET}" "${FAIL}" "$((PASS + FAIL))"
  for f in "${FAILURES[@]}"; do
    printf '    - %s\n' "${f}"
  done
  exit 1
fi
