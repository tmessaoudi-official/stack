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
