#!/bin/bash
# Test suite for global-stack-base-prologue.sh (B-1) and GS_STARTUP_DRY_RUN seam (H-3).
# Run: bash bin/tests/startup-prologue.test.sh
#
# Tests:
#   1. Prologue file passes bash -n
#   2. All 50 migrated startup scripts pass bash -n (discovered dynamically)
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
  # Anchored: an unanchored match also hits the prologue's OWN header comment
  # ("#   source global-stack-base-prologue.sh"), inflating the printed count
  # past the number quoted in CLAUDE.md. Section 1 already bash -n's the prologue.
  if grep -q '^source global-stack-base-prologue\.sh$' "${f}"; then
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
# gs_version_gate (the loop-proof lynchpin). Notably python must never compare
# against the empty-at-gate-time $PYENV_VERSION. Un-wired scripts are skipped so
# this section grows coverage across the checkpoint-2 per-runtime commits.
#
# pyenv and rbenv gate on $_python_resolved / $_ruby_resolved since hunt F8: the
# marker holds the manager-RESOLVED version, so comparing the raw pin reinstalled
# every boot for a partial pin. This section asserted the raw pin and was
# therefore GREEN ON THE DEFECT — it is updated, not worked around, and §22 below
# covers the behaviour. The raw pin is still asserted where it belongs: as the
# argument handed to find-latest.
printf '\n%b── Section 9: version-gate wiring (compare target)%b\n' "${C_BOLD}" "${C_RESET}"

GATE_WIRING=(
  "nvm-bin/global-stack-nvm-start.sh:NODE_VERSION"
  "phpbrew-bin/global-stack-phpbrew-start.sh:PHP_VERSION_NAME"
  "pyenv-bin/global-stack-pyenv-start.sh:_python_resolved"
  "rbenv-bin/global-stack-rbenv-start.sh:_ruby_resolved"
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

# The resolved value must come FROM the raw pin — resolving the wrong input
# would satisfy the loop above while gating on something unrelated.
assert_pass "9: pyenv resolves from \$PYTHON_VERSION" \
  grep -Eq 'pyenv-find-latest\.sh "\$\{PYTHON_VERSION[:}]' \
  "${DIST_BIN}/pyenv-bin/global-stack-pyenv-start.sh"
assert_pass "9: rbenv resolves from \$RUBY_VERSION" \
  grep -Eq 'rbenv-find-latest\.sh "\$\{RUBY_VERSION[:}]' \
  "${DIST_BIN}/rbenv-bin/global-stack-rbenv-start.sh"
# The original contract this section was written for: never the manager's own
# version var, which is empty at gate time.
assert_fail "9: pyenv never gates on the empty-at-gate-time \$PYENV_VERSION" \
  grep -q 'gs_version_gate .*\${PYENV_VERSION' \
  "${DIST_BIN}/pyenv-bin/global-stack-pyenv-start.sh"
assert_fail "9: rbenv never gates on the empty-at-gate-time \$RBENV_VERSION" \
  grep -q 'gs_version_gate .*\${RBENV_VERSION' \
  "${DIST_BIN}/rbenv-bin/global-stack-rbenv-start.sh"

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

# ─── Section 15: php.edge SHA sidecar gate (checkpoint 7) ───────────────────
printf '\n%b── Section 15: php.edge SHA sidecar gate (checkpoint 7)%b\n' "${C_BOLD}" "${C_RESET}"

# The php.edge main marker is invariant ("php-master"), so drift is tracked via a
# SIDECAR (php.edge.build) holding the resolved build ref github.com/php/php-src@<sha>.
# Reuse the Section-8 run_gate runner to prove the sidecar compare has the right
# semantics for a build-ref-shaped value (slashes + '@' + dots).
_pes_ref_a='github.com/php/php-src@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
_pes_ref_b='github.com/php/php-src@bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
_pes_marker="${TMP_DIR}/versions/php.edge.build"

# 15a: sidecar absent → gate returns install (the start script treats this as a forced
# rebuild — see 15e — so the pre-existing php-master is rebuilt to the tracked SHA and the
# sidecar never records an unbuilt ref; fires once per enablement/RELOAD, never a loop).
rm -f "${_pes_marker}"
assert_output_contains "15a: sidecar absent → install" "DECISION=install" run_gate "${_pes_marker}" "${_pes_ref_a}"

# 15b: sidecar equal → skip (no rebuild loop when SHA unchanged)
mkdir -p "$(dirname "${_pes_marker}")"; printf '%s' "${_pes_ref_a}" > "${_pes_marker}"
assert_output_contains "15b: sidecar == build ref → skip" "DECISION=skip" run_gate "${_pes_marker}" "${_pes_ref_a}"

# 15c: sidecar differs (SHA moved) → reinstall + loud WARN
printf '%s' "${_pes_ref_a}" > "${_pes_marker}"
assert_output_contains "15c: sidecar != build ref → reinstall" "DECISION=reinstall" run_gate "${_pes_marker}" "${_pes_ref_b}"
assert_output_contains "15c: sidecar mismatch emits WARN" "WARN" run_gate "${_pes_marker}" "${_pes_ref_b}"

# 15d: GLOB SAFETY (P1 invariant) — the package-marker sweep 'php.edge.pkg.*' must
# NOT remove the php.edge.build sidecar. Getting this wrong destroys drift tracking.
assert_pass "15d: 'php.edge.pkg.*' sweep does not remove php.edge.build sidecar" bash -c '
  d=$(mktemp -d)
  : > "$d/php.edge.build"
  : > "$d/php.edge.pkg.redis"
  : > "$d/php.edge.pkg.xdebug"
  rm -f "$d"/php.edge.pkg.*
  [[ -f "$d/php.edge.build" && ! -e "$d/php.edge.pkg.redis" && ! -e "$d/php.edge.pkg.xdebug" ]]
'

# 15e: STATIC — phpbrew-start.sh wires the three edge constructs.
_pes_start="${DIST_BIN}/phpbrew-bin/global-stack-phpbrew-start.sh"
assert_pass "15e: edge sidecar drift gate present (gs_version_gate on php.edge.build)" \
  grep -Eq 'gs_version_gate "\$\{GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS\}/php\.edge\.build"|_edge_sidecar=.*php\.edge\.build' "${_pes_start}"
assert_pass "15e: success-gated sidecar write present (echo PHP_VERSION > php.edge.build)" \
  grep -Eq 'php\.edge\.build"$' "${_pes_start}"
assert_pass "15e: edge gate is guarded on PHP_VERSION_AS=edge" \
  grep -q '"${PHP_VERSION_AS}" = "edge"' "${_pes_start}"
# force rebuild on NON-skip (absent OR differ) so the sidecar never records an unbuilt ref
assert_pass "15e: edge gate forces rebuild whenever gate != skip (absent or differ)" \
  grep -Eq '\$\{_edge_gate\}" != "skip"' "${_pes_start}"
assert_pass "15e: RELOAD path drops the sidecar for edge" \
  grep -Eq 'PHP_VERSION_AS.*= .edge.*php\.edge\.build|edge.* rm -f .*php\.edge\.build' "${_pes_start}"
# Guard against over-broad glob that would sweep the sidecar: no 'php.edge.*' wildcard.
assert_fail "15e: no over-broad 'php.edge.*' glob that would sweep the sidecar" \
  grep -q 'php\.edge\.\*' "${_pes_start}"

# ─── Section 16: gs_install_retry_purge (download-cache self-heal) ──────────
printf '\n%b── Section 16: gs_install_retry_purge%b\n' "${C_BOLD}" "${C_RESET}"

# 16a: success on first attempt → returns 0, cache untouched.
assert_pass "16a: keeps cache + returns 0 when command succeeds first try" \
  bash -c '
    source "$0"
    trap - ERR EXIT PIPE SIGPIPE SIGHUP
    d=$(mktemp -d); mkdir -p "$d/cache"; : > "$d/cache/keep"
    gs_install_retry_purge "$d/cache" true; rc=$?
    [[ $rc -eq 0 && -f "$d/cache/keep" ]]
  ' "${PROLOGUE}"

# 16b: fail-then-succeed → purges cache, retries once, returns 0, command ran twice.
assert_pass "16b: purges cache + retries once, returns 0 on 2nd-try success" \
  bash -c '
    source "$0"
    trap - ERR EXIT PIPE SIGPIPE SIGHUP
    d=$(mktemp -d); mkdir -p "$d/cache"; : > "$d/cache/poison"
    c="$d/cnt"; echo 0 > "$c"
    ft() { local n; n=$(cat "$c"); n=$((n+1)); echo "$n" > "$c"; [[ "$n" -ge 2 ]]; }
    gs_install_retry_purge "$d/cache" ft; rc=$?
    [[ $rc -eq 0 && ! -e "$d/cache/poison" && "$(cat "$c")" == "2" ]]
  ' "${PROLOGUE}"

# 16c: always-fail → purges cache, returns non-zero (second failure propagates).
assert_pass "16c: purges cache + returns non-zero when both attempts fail" \
  bash -c '
    source "$0"
    trap - ERR EXIT PIPE SIGPIPE SIGHUP
    d=$(mktemp -d); mkdir -p "$d/cache"; : > "$d/cache/poison"
    gs_install_retry_purge "$d/cache" false; rc=$?
    [[ $rc -ne 0 && ! -e "$d/cache/poison" ]]
  ' "${PROLOGUE}"

# 16d: empty cache_dir arg → no purge attempt, still returns the command status (no crash).
assert_pass "16d: empty cache_dir arg is safe (skips purge, still returns fail)" \
  bash -c '
    source "$0"
    trap - ERR EXIT PIPE SIGPIPE SIGHUP
    gs_install_retry_purge "" false; rc=$?
    [[ $rc -ne 0 ]]
  ' "${PROLOGUE}"

# 16e: STATIC — nvm-start.sh wires the helper around `nvm install`.
_nvm_start="${DIST_BIN}/nvm-bin/global-stack-nvm-start.sh"
assert_pass "16e: nvm-start.sh wires gs_install_retry_purge around nvm install" \
  grep -Eq 'gs_install_retry_purge .*nvm install' "${_nvm_start}"

# 16f: LINCHPIN — under the REAL armed stackCatch trap + set -eE, a first-attempt
# failure inside the helper's `if` must NOT fire stackCatch; the retry must run and
# succeed. Proves the fix is not a silent no-op (first failure exiting → retry skipped).
cat >"${TMP_DIR}/test-heal-recover.sh" <<'TESTEOF'
#!/bin/bash
set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh
nvm() { local n; n=$(cat "${HEAL_CNT}"); n=$((n + 1)); echo "${n}" >"${HEAL_CNT}"; [[ "${n}" -ge 2 ]]; }
gs_install_retry_purge "${HEAL_CACHE}" nvm install v1
echo "HEAL_REACHED_END"
TESTEOF
chmod +x "${TMP_DIR}/test-heal-recover.sh"
mkdir -p "${TMP_DIR}/heal-errors" "${TMP_DIR}/heal-cache"
: >"${TMP_DIR}/heal-cache/poison"
echo 0 >"${TMP_DIR}/heal-cnt"
_heal_out=$(
  GLOBAL_STACK_ERROR_TOKEN=heal-token \
    GLOBAL_STACK_DOCKER_TOOLS_PATH="${TMP_DIR}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${TMP_DIR}/heal-errors" \
    HEAL_CNT="${TMP_DIR}/heal-cnt" HEAL_CACHE="${TMP_DIR}/heal-cache" \
    PATH="${DIST_BIN}/base-bin:${PATH}" \
    bash "${TMP_DIR}/test-heal-recover.sh" 2>&1
)
_heal_exit=$?
if [[ "${_heal_exit}" -eq 0 && ! -f "${TMP_DIR}/heal-errors/heal-token" ]] \
  && echo "${_heal_out}" | grep -q "HEAL_REACHED_END" \
  && [[ ! -e "${TMP_DIR}/heal-cache/poison" ]]; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  16f: first failure does NOT trip stackCatch; retry runs + succeeds (no token)\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("16f: first-failure ERR-trap suppression + retry")
  printf '  %b✗%b  16f: first failure does NOT trip stackCatch (exit=%d token=%s)\n' "${C_RED}" "${C_RESET}" "${_heal_exit}" "$([[ -f "${TMP_DIR}/heal-errors/heal-token" ]] && echo present || echo absent)"
fi

# 16g: MIRROR — when BOTH attempts fail, the second failure must propagate loudly:
# stackCatch fires and writes the error token (container fails visibly, not silently).
cat >"${TMP_DIR}/test-heal-fail.sh" <<'TESTEOF'
#!/bin/bash
set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh
nvm() { return 1; }
gs_install_retry_purge "${HEAL_CACHE2}" nvm install v1
echo "SHOULD_NOT_REACH"
TESTEOF
chmod +x "${TMP_DIR}/test-heal-fail.sh"
mkdir -p "${TMP_DIR}/heal-errors2" "${TMP_DIR}/heal-cache2"
GLOBAL_STACK_ERROR_TOKEN=heal-token2 \
  GLOBAL_STACK_DOCKER_TOOLS_PATH="${TMP_DIR}" \
  GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${TMP_DIR}/heal-errors2" \
  HEAL_CACHE2="${TMP_DIR}/heal-cache2" \
  PATH="${DIST_BIN}/base-bin:${PATH}" \
  bash "${TMP_DIR}/test-heal-fail.sh" >/dev/null 2>&1 || true
if [[ -f "${TMP_DIR}/heal-errors2/heal-token2" ]]; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  16g: second (persistent) failure propagates — error token written\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("16g: persistent failure propagates to error token")
  printf '  %b✗%b  16g: second failure did NOT write error token (would mask failure)\n' "${C_RED}" "${C_RESET}"
fi

# ─── Section 17: prologue chain dedup guard (hunt F1) ──────────────────────
# _stack_register_chain must not append a second entry for the same PID. The
# guard READ ${GLOBAL_INTTERNAL_STACK_SCRIPT_CHAIN} — double T, a name nothing
# in the repo ever assigns — so it expanded empty, the test was always true and
# the chain grew one entry per source. The chain is what a crash report prints
# to say which *-start.sh led to the failure, so duplicates corrupt the one
# artefact you read when a container dies.
printf '\n%b── Section 17: prologue chain dedup guard%b\n' "${C_BOLD}" "${C_RESET}"

assert_fail "17a: prologue carries no GLOBAL_INTTERNAL_ typo" \
  grep -q 'GLOBAL_INTTERNAL_' "${PROLOGUE}"

cat >"${TMP_DIR}/test-chain.sh" <<'TESTEOF'
#!/bin/bash
set -eE -o pipefail
source global-stack-base-prologue.sh
source global-stack-base-prologue.sh
printf 'CHAIN=%s\n' "${GLOBAL_INTERNAL_STACK_SCRIPT_CHAIN}"
TESTEOF
chmod +x "${TMP_DIR}/test-chain.sh"
# One entry → no '|' separator. Two entries (guard dead) → exactly one '|'.
_chain_out=$(
  GLOBAL_STACK_DOCKER_TOOLS_PATH="${TMP_DIR}" \
    PATH="${DIST_BIN}/base-bin:${PATH}" \
    bash "${TMP_DIR}/test-chain.sh" 2>/dev/null | grep '^CHAIN=' || true
)
if [[ -n "${_chain_out}" && "${_chain_out}" != *'|'* ]]; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  17b: sourcing twice registers the chain entry once\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("17b: chain entry duplicated on re-source")
  printf '  %b✗%b  17b: chain entry duplicated on re-source (%s)\n' "${C_RED}" "${C_RESET}" "${_chain_out}"
fi

# ─── Section 18: serverless + alltogether error signalling (hunt F5, F6) ───
# F5: 04serverless-framework declares GLOBAL_STACK_ERROR_TOKEN=serverless and a
# marker healthcheck, but armed NO handler — it neither sourced this prologue
# nor defined its own stackCatch. Every failure was invisible: no error token,
# so `ls tools/errors/` (step 1 of the documented runbook) reported nothing
# wrong while the container stayed unhealthy behind the 24h start_period.
# F6: neither serverless nor alltogether cleared a STALE error token, so a
# service that failed once reported unhealthy forever after the cause was fixed
# — `make restart-05stable` could not recover it, only a full `make down`.
printf '\n%b── Section 18: serverless + alltogether error signalling%b\n' "${C_BOLD}" "${C_RESET}"

_sls="${DIST_BIN}/serverless-bin/global-stack-serverless-framework-start.sh"
_alt="${DIST_BIN}/alltogether/global-stack-alltogether-start.sh"

assert_pass "18a: serverless sources the shared prologue" \
  grep -q '^source global-stack-base-prologue.sh$' "${_sls}"

# F6 — assert the LITERAL the convention audit greps for, at both new sites.
_f6_literal='rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"'
assert_pass "18b: serverless clears a stale error token at startup" \
  grep -qF "${_f6_literal}" "${_sls}"
assert_pass "18c: alltogether clears a stale error token at startup" \
  grep -qF "${_f6_literal}" "${_alt}"

# 18d — BEHAVIOURAL: the dry-run seam. Red before the fix (the script had no
# prologue, so it ignored GS_STARTUP_DRY_RUN and ran real work — the hunt repro
# observed `sed: can't read /home/nosuchuser/.bashrc` and exit 2).
# The suite runs under `set -e`, and the pre-fix script exits 2 here — capture
# the status without letting it abort the run.
_sls_dry_exit=0
_sls_dry_out=$(
  GS_STARTUP_DRY_RUN=1 \
    GLOBAL_STACK_ERROR_TOKEN=serverless \
    GLOBAL_STACK_DOCKER_TOOLS_PATH="${TMP_DIR}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${TMP_DIR}/sls-errors" \
    GLOBAL_STACK_DOCKER_USER_ID=nosuchuser \
    GLOBAL_STACK_SHELL_RC_TARGET=.bashrc \
    GLOBAL_STACK_WAIT_FOR_TIMEOUT=2 \
    PATH="${DIST_BIN}/base-bin:${PATH}" \
    bash "${_sls}" 2>&1
) || _sls_dry_exit=$?
if [[ "${_sls_dry_exit}" -eq 0 ]] && ! echo "${_sls_dry_out}" | grep -q "can't read"; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  18d: serverless honours GS_STARTUP_DRY_RUN=1 (exit 0, no work done)\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("18d: serverless honours GS_STARTUP_DRY_RUN=1")
  printf '  %b✗%b  18d: serverless dry-run exit=%d (want 0); ran real work\n' "${C_RED}" "${C_RESET}" "${_sls_dry_exit}"
fi

# 18e — BEHAVIOURAL, the P0 itself: a real failure must write the error token.
# The failing `sed` on line 6 (unreadable shellrc) stands in for any of the
# ~230 lines that can fail. Red before the fix: errors/ stayed empty.
mkdir -p "${TMP_DIR}/sls-errors2"
GLOBAL_STACK_ERROR_TOKEN=serverless \
  GLOBAL_STACK_DOCKER_TOOLS_PATH="${TMP_DIR}" \
  GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${TMP_DIR}/sls-errors2" \
  GLOBAL_STACK_DOCKER_USER_ID=nosuchuser \
  GLOBAL_STACK_SHELL_RC_TARGET=.bashrc \
  GLOBAL_STACK_WAIT_FOR_TIMEOUT=2 \
  PATH="${DIST_BIN}/base-bin:${PATH}" \
  bash "${_sls}" >/dev/null 2>&1 || true
if [[ -f "${TMP_DIR}/sls-errors2/serverless" ]]; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  18e: a serverless failure writes tools/errors/serverless\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("18e: serverless failure writes an error token")
  printf '  %b✗%b  18e: serverless failed SILENTLY — no error token written\n' "${C_RED}" "${C_RESET}"
fi

# ─── Section 19: web-server handlers report exit 1 (hunt F2) ───────────────
# The 8 caddy/nginx/httpd handlers excluded exit code 1 from REPORTING:
# `[[ $exit_code -ne 0 && $exit_code -ne 141 && $exit_code -ne 1 ]]`. Code 1 is
# the most common failure in their own chain (their *-setup.sh and
# *-iou-common.sh both end their error path in a literal `exit 1`), so a real
# failure produced total silence: no message, no tools/elapsed line, no token.
#
# Verified by execution before the fix: dropping the `-ne 1` arm does NOT change
# control flow (set -e already aborts wherever the ERR trap fires) — but it DOES
# make every report fire twice, because that arm was accidentally absorbing the
# EXIT-trap re-entry after the handler's own `exit 1`. The second report carries
# the trap's line number instead of the failure's. Hence the _STACK_CAUGHT
# guard, matching the shared prologue's name.
printf '\n%b── Section 19: web-server handlers report exit 1%b\n' "${C_BOLD}" "${C_RESET}"

WEB_SERVER_SCRIPTS=(
  "caddy-bin/global-stack-caddy-start.sh"
  "caddy-bin/global-stack-caddy-setup.sh"
  "nginx-bin/global-stack-nginx-start.sh"
  "nginx-bin/global-stack-nginx-setup.sh"
  "nginx-bin/global-stack-nginx-iou-common.sh"
  "httpd-bin/global-stack-httpd-start.sh"
  "httpd-bin/global-stack-httpd-setup.sh"
  "httpd-bin/global-stack-httpd-iou-common.sh"
)

for _ws in "${WEB_SERVER_SCRIPTS[@]}"; do
  _ws_path="${DIST_BIN}/${_ws}"
  # Anchor on the closing `]]`: a bare '-ne 1' also matches the '-ne 141'
  # SIGPIPE arm, which must SURVIVE — that pattern can never go green.
  assert_fail "19a: $(basename "${_ws}") no longer exempts exit code 1" \
    grep -q 'exit_code -ne 1 \]\]' "${_ws_path}"
  assert_pass "19a: $(basename "${_ws}") keeps the 141 (SIGPIPE) exemption" \
    grep -q 'exit_code -ne 141 \]\]' "${_ws_path}"
  assert_pass "19b: $(basename "${_ws}") carries the _STACK_CAUGHT re-entry guard" \
    grep -q '_STACK_CAUGHT' "${_ws_path}"
done

# BEHAVIOURAL — extract the SHIPPED handler by PATTERN (never line numbers,
# which rot the moment the guard line is added), arm the same trap, and force a
# failure with a known exit code. Reports are counted, not merely detected:
# "reported once" is the whole contract.
_ws_reports() { # $1 = script path, $2 = exit code to force; echoes the count
  local src="$1" code="$2" h="${TMP_DIR}/ws-harness.sh" out
  {
    printf '#!/bin/bash\nset -eE -o pipefail\n'
    sed -n '/^stackCatch() {/,/^}/p' "${src}"
    printf 'trap %s ERR EXIT\n' "'stackCatch \$? \${LINENO} \"\${BASH_COMMAND}\"'"
    printf '(exit %s)\n' "${code}"
  } >"${h}"
  out=$(
    GLOBAL_STACK_ERROR_TOKEN=ws-token \
      GLOBAL_STACK_DOCKER_TOOLS_PATH="${TMP_DIR}/ws" \
      GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${TMP_DIR}/ws" \
      bash "${h}" 2>&1 || true
  )
  printf '%s' "${out}" | grep -c 'Error detected!' || true
}
mkdir -p "${TMP_DIR}/ws"
_ws_probe="${DIST_BIN}/caddy-bin/global-stack-caddy-start.sh"

_n=$(_ws_reports "${_ws_probe}" 1)
if [[ "${_n}" == "1" ]]; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  19c: exit 1 is reported, exactly once\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("19c: exit 1 reported exactly once (got ${_n})")
  printf '  %b✗%b  19c: exit 1 produced %s reports (want 1)\n' "${C_RED}" "${C_RESET}" "${_n}"
fi

# Regression fence for the naive fix: without the guard this becomes 2.
_n=$(_ws_reports "${_ws_probe}" 2)
if [[ "${_n}" == "1" ]]; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  19d: exit 2 still reported exactly once (no EXIT re-entry)\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("19d: exit 2 reported exactly once (got ${_n})")
  printf '  %b✗%b  19d: exit 2 produced %s reports (want 1)\n' "${C_RED}" "${C_RESET}" "${_n}"
fi

# 141 = SIGPIPE, the one exemption that stays: `caddy stop | head` is routine.
_n=$(_ws_reports "${_ws_probe}" 141)
if [[ "${_n}" == "0" ]]; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  19e: exit 141 (SIGPIPE) stays exempt\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("19e: exit 141 stays exempt (got ${_n})")
  printf '  %b✗%b  19e: exit 141 produced %s reports (want 0)\n' "${C_RED}" "${C_RESET}" "${_n}"
fi

_n=$(_ws_reports "${_ws_probe}" 0)
if [[ "${_n}" == "0" ]]; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  19f: clean exit reports nothing\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("19f: clean exit reports nothing (got ${_n})")
  printf '  %b✗%b  19f: clean exit produced %s reports (want 0)\n' "${C_RED}" "${C_RESET}" "${_n}"
fi

# The token must carry the FAILURE's line, not the trap's re-entry line 1.
if [[ -f "${TMP_DIR}/ws/ws-token" ]] && ! grep -q '^line: 1$' "${TMP_DIR}/ws/ws-token"; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  19g: error token records the failing line, not the re-entry\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("19g: error token records the failing line")
  printf '  %b✗%b  19g: error token missing or overwritten by the EXIT re-entry\n' "${C_RED}" "${C_RESET}"
fi

# ─── Section 20: rbenv version resolver (hunt F7) ──────────────────────────
# global-stack-rbenv-find-latest.sh resolved the newest matching Ruby, then
# tested ${CURRENT_RUBY_VERSION} — missing the RBENV_ prefix, a name set nowhere
# in the repo. The script runs without -u, so it expanded empty, the test was
# always true, and the next line unconditionally overwrote the result with the
# raw pin. The whole `rbenv install --list-all` lookup was dead code, so a
# partial pin (GLOBAL_STACK_RUBY3_VERSION=3.4) — the entire reason the resolver
# and the _AS label scheme exist — reached `rbenv install` verbatim and failed.
printf '\n%b── Section 20: rbenv version resolver%b\n' "${C_BOLD}" "${C_RESET}"

_rb_find="${DIST_BIN}/rbenv-bin/global-stack-rbenv-find-latest.sh"
_py_find="${DIST_BIN}/pyenv-bin/global-stack-pyenv-find-latest.sh"

mkdir -p "${TMP_DIR}/rb/bin" "${TMP_DIR}/rb/root/versions"
printf '#!/bin/bash\nprintf "3.4.8\\n3.4.9\\n3.4.10\\n"\n' >"${TMP_DIR}/rb/bin/rbenv"
printf '#!/bin/bash\nprintf "  3.14.5\\n  3.14.6\\n  3.14.7\\n"\n' >"${TMP_DIR}/rb/bin/pyenv"
chmod +x "${TMP_DIR}/rb/bin/rbenv" "${TMP_DIR}/rb/bin/pyenv"

_rb_out=$(
  env -i PATH="${TMP_DIR}/rb/bin:/usr/bin:/bin" \
    RBENV_ROOT="${TMP_DIR}/rb/root" RUBY_VERSION=3.4 \
    bash "${_rb_find}" 3.4 2>/dev/null | tail -n1
)
if [[ "${_rb_out}" == "3.4.10" ]]; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  20a: a partial pin (3.4) resolves to the newest match (3.4.10)\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("20a: partial pin resolves to newest match (got '${_rb_out}')")
  printf '  %b✗%b  20a: partial pin resolved to %s, want 3.4.10 (result discarded)\n' "${C_RED}" "${C_RESET}" "${_rb_out}"
fi

assert_fail "20b: resolver reads no unprefixed CURRENT_RUBY_VERSION" \
  grep -Eq '\$\{CURRENT_RUBY_VERSION[:}]' "${_rb_find}"

# An already-installed exact version must still short-circuit to itself.
mkdir -p "${TMP_DIR}/rb/root/versions/3.4.9"
_rb_exact=$(
  env -i PATH="${TMP_DIR}/rb/bin:/usr/bin:/bin" \
    RBENV_ROOT="${TMP_DIR}/rb/root" RUBY_VERSION=3.4.9 \
    bash "${_rb_find}" 3.4.9 2>/dev/null | tail -n1
)
assert_pass "20c: an installed exact version short-circuits to itself" \
  test "${_rb_exact}" = "3.4.9"

# Control — the pyenv twin was always correct; it must stay correct.
_py_out=$(
  env -i PATH="${TMP_DIR}/rb/bin:/usr/bin:/bin" \
    PYENV_ROOT="${TMP_DIR}/rb/root" PYTHON_VERSION=3.14 \
    GLOBAL_STACK_PYTHON_STABLE=true \
    bash "${_py_find}" 3.14 2>/dev/null | tail -n1
)
assert_pass "20d: control — the pyenv twin still resolves correctly" \
  test "${_py_out}" = "3.14.7"

# ─── Section 21: web-server per-service error tokens (hunt F4) ─────────────
# caddy, nginx and httpd are interchangeable ALTERNATIVES that all signal the
# same successes/web-server marker, and none of them declared an error token.
# global-stack-base-wait-for.sh derives the error path from the success path, so
# it polled errors/web-server — a path with no producer anywhere in the repo. A
# failed web server therefore hung its three consumers (alltogether, localstack,
# serverless) for the full GLOBAL_STACK_WAIT_FOR_TIMEOUT and then reported a
# timeout against THEMSELVES, pointing the reader at the wrong container.
#
# Fix: each web server declares its own GLOBAL_STACK_ERROR_TOKEN and clears its
# own stale token at startup; wait-for polls all three IN ADDITION to the
# derived path when the dependency is successes/web-server. Poll-all-three needs
# no COMPOSE_FILE introspection: a web server that is not enabled writes
# nothing. The shared SUCCESS marker semantics are deliberately unchanged — this
# is the one documented exception to the token invariant (CLAUDE.md § Gotchas).
printf '\n%b── Section 21: web-server per-service error tokens%b\n' "${C_BOLD}" "${C_RESET}"

WAIT_FOR="${DIST_BIN}/base-bin/global-stack-base-wait-for.sh"
IMAGES_DIR="${SCRIPT_DIR}/../../docker/images"

WEB_SERVER_SERVICES=(01caddy 01nginx 01httpd)
_ws_declared=()

for _svc in "${WEB_SERVER_SERVICES[@]}"; do
  _tok="$(grep -oP 'GLOBAL_STACK_ERROR_TOKEN=\K\S+' \
    "${IMAGES_DIR}/${_svc}/docker-compose.yaml" 2>/dev/null || true)"
  assert_pass "21a: ${_svc} declares its own GLOBAL_STACK_ERROR_TOKEN" \
    test -n "${_tok}"
  # The token must NOT be the shared success marker: that is the whole point of
  # per-service tokens, and reusing it would resurrect the no-producer bug.
  assert_pass "21a: ${_svc} token is not the shared 'web-server' marker" \
    test "${_tok:-web-server}" != "web-server"
  [[ -n "${_tok}" ]] && _ws_declared+=("${_tok}")
done

# Each producer clears its own stale token at startup — byte-matching the
# repo-wide literal the convention audit greps for.
for _svc in caddy nginx httpd; do
  assert_pass "21b: ${_svc}-start.sh clears its own stale error token" \
    grep -qF 'rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"' \
    "${DIST_BIN}/${_svc}-bin/global-stack-${_svc}-start.sh"
done

# Drift guard: wait-for hardcodes three literals that live in three OTHER files.
# Read the tokens from compose and assert wait-for names each one — a rename
# would otherwise uncouple the two sides silently, with every other test green.
# The count assertion keeps the loop below from passing by iterating zero times.
assert_pass "21c: all three web-server tokens were read from compose" \
  test "${#_ws_declared[@]}" -eq 3
for _tok in ${_ws_declared+"${_ws_declared[@]}"}; do
  assert_pass "21c: base-wait-for.sh names the '${_tok}' token from compose" \
    grep -qF "errors/${_tok}" "${WAIT_FOR}"
done

# ── BEHAVIOURAL ──
# _wf_run <dependency-path> → "<rc>|<single-line output>"
_wf_run() {
  local out rc
  out=$(GLOBAL_STACK_WAIT_FOR_TIMEOUT=2 bash "${WAIT_FOR}" "$1" 2>&1) && rc=0 || rc=$?
  printf '%s|%s' "${rc}" "$(printf '%s' "${out}" | tr '\n' ' ')"
}

_wf_tools="${TMP_DIR}/wf"
mkdir -p "${_wf_tools}/successes" "${_wf_tools}/errors"
_wf_dep="${_wf_tools}/successes/web-server"

for _tok in caddy nginx httpd; do
  rm -f "${_wf_tools}/errors/"*
  : >"${_wf_tools}/errors/${_tok}"
  _wf_r="$(_wf_run "${_wf_dep}")"
  if [[ "${_wf_r}" == 1\|*"error token found"*"errors/${_tok}"* ]]; then
    PASS=$((PASS + 1))
    printf '  %b✓%b  21d: waiting on web-server fail-fasts on errors/%s\n' "${C_GREEN}" "${C_RESET}" "${_tok}"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("21d: fail-fast on errors/${_tok} (got ${_wf_r})")
    printf '  %b✗%b  21d: errors/%s did not fail-fast — got %s\n' "${C_RED}" "${C_RESET}" "${_tok}" "${_wf_r}"
  fi
done

# The derived path must SURVIVE for web-server too, so a future errors/web-server
# producer is not silently ignored.
rm -f "${_wf_tools}/errors/"*
: >"${_wf_tools}/errors/web-server"
_wf_r="$(_wf_run "${_wf_dep}")"
assert_pass "21e: the derived errors/web-server path is still honoured" \
  test "${_wf_r#1|}" != "${_wf_r}"

# An unrelated token must NOT fail-fast — poll-all-three must not become
# poll-anything, or every consumer dies on an unrelated service's failure.
rm -f "${_wf_tools}/errors/"*
: >"${_wf_tools}/errors/unrelated"
_wf_r="$(_wf_run "${_wf_dep}")"
if [[ "${_wf_r}" == 1\|*"timed out"* ]]; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  21f: an unrelated error token does not fail-fast\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("21f: unrelated token must not fail-fast (got ${_wf_r})")
  printf '  %b✗%b  21f: unrelated token changed the outcome — got %s\n' "${C_RED}" "${C_RESET}" "${_wf_r}"
fi

# Regression: an ordinary dependency still fail-fasts on its own derived path.
rm -f "${_wf_tools}/errors/"*
: >"${_wf_tools}/errors/nvm"
_wf_r="$(_wf_run "${_wf_tools}/successes/nvm")"
if [[ "${_wf_r}" == 1\|*"errors/nvm"* ]]; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  21g: an ordinary dependency still uses its derived error path\n' "${C_GREEN}" "${C_RESET}"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("21g: derived error path regression (got ${_wf_r})")
  printf '  %b✗%b  21g: derived error path regressed — got %s\n' "${C_RED}" "${C_RESET}" "${_wf_r}"
fi

# Regression: a present success marker still returns 0 with no error files.
rm -f "${_wf_tools}/errors/"*
: >"${_wf_dep}"
_wf_r="$(_wf_run "${_wf_dep}")"
assert_pass "21h: a satisfied dependency still returns 0" \
  test "${_wf_r%%|*}" = "0"
rm -f "${_wf_dep}"

# Each producer's SHIPPED handler must write exactly the token its own compose
# file declares. Extracted by pattern, never by line number.
_ws_token_file() { # $1 = script path, $2 = token → echoes the file it created
  local src="$1" tok="$2" h="${TMP_DIR}/ws-token.sh" d="${TMP_DIR}/ws-token-errors"
  rm -rf "${d}"
  mkdir -p "${d}"
  {
    printf '#!/bin/bash\nset -eE -o pipefail\n'
    sed -n '/^stackCatch() {/,/^}/p' "${src}"
    printf 'trap %s ERR EXIT\n' "'stackCatch \$? \${LINENO} \"\${BASH_COMMAND}\"'"
    printf '(exit 1)\n'
  } >"${h}"
  GLOBAL_STACK_ERROR_TOKEN="${tok}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH="${d}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${d}" \
    bash "${h}" >/dev/null 2>&1 || true
  # find, not `ls | grep`: grep exits 1 on an empty errors dir, which is exactly
  # the pre-fix case this must be able to OBSERVE rather than die on.
  find "${d}" -maxdepth 1 -type f ! -name elapsed -printf '%f\n' 2>/dev/null | head -1
}

for _i in 0 1 2; do
  _svc="${WEB_SERVER_SERVICES[${_i}]}"
  _rt="${_svc#01}"
  _tok="$(grep -oP 'GLOBAL_STACK_ERROR_TOKEN=\K\S+' \
    "${IMAGES_DIR}/${_svc}/docker-compose.yaml" 2>/dev/null || true)"
  _got="$(_ws_token_file "${DIST_BIN}/${_rt}-bin/global-stack-${_rt}-start.sh" "${_tok:-}")"
  assert_pass "21i: ${_rt} writes errors/${_tok:-<none>} on failure" \
    test -n "${_tok}" -a "${_got}" = "${_tok}"
done

# ─── Section 22: resolve-before-gate for partial pins (hunt F8) ────────────
# pyenv and rbenv WRITE the manager-resolved version into tools/versions/ (the
# output of global-stack-{pyenv,rbenv}-find-latest.sh) but GATED on the raw pin.
# For a fully-qualified pin the two are equal, which is why the comment at each
# gate claimed it was safe. For a PARTIAL pin — 3.14 against a marker holding
# 3.14.7, the entire reason find-latest and the _AS label scheme exist — they
# differ on every boot: the gate WARNs "version changed", wipes the version dir
# and every pkg.* marker, and reinstalls the interpreter. Every start. Forever.
#
# Fix: resolve first and gate on the same value the marker write uses. The
# resolved value is REUSED at the install site rather than recomputed, so
# "gate on what gets written" is true by construction, not by two calls
# agreeing. Behaviour change worth naming: a partial pin now re-resolves every
# boot, so a manager upgrade shipping newer definitions triggers a genuine
# reinstall-with-WARN. That is the intent (a version bump must reinstall), not
# a side effect.
#
# nvm is NOT fixed here: `nvm version` needs nvm sourced, which happens ~130
# lines after its gate. Carried in the plan's register with that reason.
printf '\n%b── Section 22: resolve-before-gate for partial pins%b\n' "${C_BOLD}" "${C_RESET}"

# _gate_decision <runtime> <pin> <marker-content> <what find-latest resolves to>
# Extracts the SHIPPED gate block by pattern, stubs the resolver, echoes the
# decision. Never line numbers — the block moves every time it is edited.
_gate_decision() {
  local rt="$1" pin="$2" marker_body="$3" resolved="$4"
  local var root src h stub_dir vers
  case "${rt}" in
    pyenv)
      var=_python
      root=PYENV_ROOT
      src="${DIST_BIN}/pyenv-bin/global-stack-pyenv-start.sh"
      ;;
    rbenv)
      var=_ruby
      root=RBENV_ROOT
      src="${DIST_BIN}/rbenv-bin/global-stack-rbenv-start.sh"
      ;;
  esac
  h="${TMP_DIR}/gate-${rt}.sh"
  stub_dir="${TMP_DIR}/gate-${rt}-bin"
  vers="${TMP_DIR}/gate-${rt}-versions"
  rm -rf "${stub_dir}" "${vers}"
  mkdir -p "${stub_dir}" "${vers}" "${TMP_DIR}/gate-${rt}-root/versions"
  printf '#!/bin/bash\nprintf "%%s\\n" "%s"\n' "${resolved}" \
    >"${stub_dir}/global-stack-${rt}-find-latest.sh"
  chmod +x "${stub_dir}/global-stack-${rt}-find-latest.sh"
  {
    printf '#!/bin/bash\nset -eE -o pipefail\nsource global-stack-base-prologue.sh\n'
    sed -n "/^  ${var}_label=/,/^    rm -f \"\${${var}_marker}\"\$/p" "${src}"
    printf '  fi\n'
    printf 'printf "DECISION=%%s\\n" "${%s_gate}"\n' "${var}"
  } >"${h}"
  # The gate labels the marker with the _AS value, so the file is python.3 / ruby.3.
  local marker_name
  [[ "${rt}" == pyenv ]] && marker_name="python.3" || marker_name="ruby.3"
  [[ -n "${marker_body}" ]] && printf '%s\n' "${marker_body}" >"${vers}/${marker_name}"
  env \
    PATH="${stub_dir}:${DIST_BIN}/base-bin:${PATH}" \
    GLOBAL_STACK_ERROR_TOKEN="gate-token" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH="${TMP_DIR}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${TMP_DIR}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${vers}" \
    "${root}=${TMP_DIR}/gate-${rt}-root" \
    PYTHON_VERSION="${pin}" PYTHON_VERSION_AS=3 \
    RUBY_VERSION="${pin}" RUBY_VERSION_AS=3 \
    bash "${h}" 2>/dev/null | sed -n 's/^DECISION=//p' || true
  # `|| true` because this suite runs under `set -euo pipefail`: without it a
  # harness that crashes (a moved extraction anchor, a prologue that fails to
  # source) propagates through the command substitution and kills the RUN with
  # no summary line, instead of yielding an empty decision and redding 22a.
  # That exact mechanism ate §21's output before the ls|grep here became find.
  # Mirrors §19's _ws_reports, which guards its harness for the same reason.
}

# The pin is partial; the marker holds what the manager actually resolved it to.
# This is the whole defect: identical state, reported as a version change.
for _rt in pyenv rbenv; do
  _d="$(_gate_decision "${_rt}" 3.14 3.14.7 3.14.7)"
  if [[ "${_d}" == "skip" ]]; then
    PASS=$((PASS + 1))
    printf '  %b✓%b  22a: %s partial pin matching its resolved marker → skip\n' "${C_GREEN}" "${C_RESET}" "${_rt}"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("22a: ${_rt} partial pin → skip (got '${_d}')")
    printf '  %b✗%b  22a: %s partial pin gave %s — spurious reinstall on every boot\n' "${C_RED}" "${C_RESET}" "${_rt}" "${_d:-<none>}"
  fi

  # A partial pin that now resolves HIGHER is a real bump and must reinstall.
  _d="$(_gate_decision "${_rt}" 3.14 3.14.7 3.14.9)"
  assert_pass "22b: ${_rt} partial pin resolving higher → reinstall" \
    test "${_d}" = "reinstall"

  # Regression: the fully-qualified case every pin in .env uses today.
  _d="$(_gate_decision "${_rt}" 3.14.7 3.14.7 3.14.7)"
  assert_pass "22c: ${_rt} fully-qualified pin unchanged → skip" \
    test "${_d}" = "skip"
  _d="$(_gate_decision "${_rt}" 3.14.8 3.14.7 3.14.8)"
  assert_pass "22d: ${_rt} fully-qualified pin bumped → reinstall" \
    test "${_d}" = "reinstall"
done

# The value the gate compares must be the SAME variable the install path writes
# — not a second call to find-latest that happens to agree.
assert_pass "22e: pyenv gates and installs from one resolved value" \
  grep -q 'PYENV_VERSION="\?\${_python_resolved}' \
  "${DIST_BIN}/pyenv-bin/global-stack-pyenv-start.sh"
assert_pass "22e: rbenv gates and installs from one resolved value" \
  grep -q 'RBENV_VERSION="\?\${_ruby_resolved}' \
  "${DIST_BIN}/rbenv-bin/global-stack-rbenv-start.sh"

# Carried, not fixed — pinned so it cannot be silently "fixed" by copying the
# pyenv shape into a script where the resolver is not yet available.
assert_pass "22f: nvm still gates on the raw pin, and says why" \
  grep -q 'resolved early here' \
  "${DIST_BIN}/nvm-bin/global-stack-nvm-start.sh"

# ─── Section 23: gs_version_gate is a standalone sourceable helper ────────
printf '\n%b── Section 23: version-gate helper (prologue-exempt safe)%b\n' "${C_BOLD}" "${C_RESET}"

# Row 15. The gate used to live in the prologue, but caddy/nginx/httpd and
# android-setup are DELIBERATELY prologue-exempt (own stackCatch), so they could
# not reach it without swapping their ERR-trap handling. Extracting it lets them
# source the gate ALONE. See MASTER.plan.md Track 5 "Prologue-exemption collision".
VERSION_GATE="${DIST_BIN}/base-bin/global-stack-base-version-gate.sh"

assert_pass "23a: helper file exists" test -f "${VERSION_GATE}"
assert_pass "23a: helper passes bash -n" bash -n "${VERSION_GATE}"
assert_pass "23b: helper passes shellcheck (warning level)" \
  shellcheck --severity=warning "${VERSION_GATE}"

# The goal's stop condition greps for exactly one definition; pin it here so the
# clause is backed by a test rather than by a one-off command.
_vg_def_files="$(grep -rl '^gs_version_gate() {' "${DIST_BIN}" 2>/dev/null | sort)"
_vg_def_n="$(printf '%s\n' "${_vg_def_files}" | grep -c . || true)"
assert_pass "23c: gs_version_gate is defined in exactly one file" \
  test "${_vg_def_n}" = "1"
assert_pass "23c: that one file is the helper, not the prologue" \
  test "${_vg_def_files}" = "${VERSION_GATE}"

assert_pass "23d: prologue sources the helper" \
  grep -q 'global-stack-base-version-gate\.sh' "${PROLOGUE}"

# The helper must NOT bring the prologue's error handling with it — an exempt
# script sourcing it keeps its own stackCatch.
assert_fail "23e: helper does not define stackCatch" \
  grep -q '^stackCatch() {' "${VERSION_GATE}"
assert_fail "23e: helper registers no traps" \
  grep -q '^trap ' "${VERSION_GATE}"

# ── the guarantee row 15 exists to deliver ──
# A script with its OWN stackCatch, sourcing ONLY the helper (no prologue), gets
# all three decisions AND fires its ERR trap exactly zero times. The counter is a
# FILE, not a variable: the gate is called inside $( ), so a subshell increment
# would never reach the parent and the assertion would pass vacuously.
_vg_harness() {
  local marker_body="$1" expected="$2" vers="${TMP_DIR}/vg-vers" h="${TMP_DIR}/vg-harness.sh"
  local fires="${TMP_DIR}/vg-fires"
  rm -rf "${vers}" "${fires}"
  mkdir -p "${vers}"
  [[ -n "${marker_body}" ]] && printf '%s\n' "${marker_body}" >"${vers}/tool.marker"
  {
    printf '#!/bin/bash\n'
    printf 'set -xeE -o pipefail\n'
    printf 'shopt -s extdebug\n'
    printf "IFS=\$'\\\\n\\\\t'\n"
    # the exempt scripts' shape: their own handler, not the prologue's
    printf 'stackCatch() { echo fire >> "%s"; }\n' "${fires}"
    printf 'trap %s ERR\n' "'stackCatch \"\${?}\" \"\${LINENO}\" \"\${BASH_COMMAND}\" \"\${BASH_SOURCE[0]}\"'"
    printf 'source global-stack-base-version-gate.sh\n'
    printf 'd="$(gs_version_gate "%s/tool.marker" "%s" "tool")"\n' "${vers}" "${expected}"
    printf 'printf "DECISION=%%s\\\\n" "${d}"\n'
  } >"${h}"
  env PATH="${DIST_BIN}/base-bin:${PATH}" bash "${h}" 2>/dev/null |
    sed -n 's/^DECISION=//p' || true
}

_d="$(_vg_harness "" 1.2.3)"
assert_pass "23f: helper alone, marker absent → install" test "${_d}" = "install"
_d="$(_vg_harness 1.2.3 1.2.3)"
assert_pass "23f: helper alone, marker equal → skip" test "${_d}" = "skip"
_d="$(_vg_harness 1.2.3 1.2.4)"
assert_pass "23f: helper alone, marker differs → reinstall" test "${_d}" = "reinstall"

# Zero ERR fires across the three decisions above (the last run's log; each run
# resets it). A gate that returns non-zero here would write tools/errors/<token>
# in production and mask the container as unhealthy behind the 24h start_period.
# Guarded against vacuity: with no helper the fire log never exists and a bare
# count-is-zero assertion would pass while nothing ran. The decision from the
# same run must therefore also be present.
_vg_fire_n="$(grep -c . "${TMP_DIR}/vg-fires" 2>/dev/null || echo 0)"
assert_pass "23g: helper fires the caller's ERR trap zero times (and did run)" \
  test "${_vg_fire_n}${_d}" = "0reinstall"

# Double-source must be safe, and safe under BOTH set flag regimes: base-* scripts
# run `set -xeEu`, the tier-02/03 scripts run `set -xeE` without -u.
for _u in "-u" ""; do
  _lbl="${_u:-no -u}"
  printf '#!/bin/bash\nset -eE %s\nsource global-stack-base-version-gate.sh\nsource global-stack-base-version-gate.sh\ngs_version_gate /nonexistent x l\n' "${_u}" \
    >"${TMP_DIR}/vg-twice.sh"
  assert_pass "23h: double-source is safe (${_lbl})" \
    env PATH="${DIST_BIN}/base-bin:${PATH}" bash "${TMP_DIR}/vg-twice.sh"
done

# The delivery path the other 23* rows do not exercise: the prologue sourced by an
# EXPLICIT path while base-bin is absent from PATH (how a host-side
# GS_STARTUP_DRY_RUN run behaves if the PATH prepend is forgotten). The sibling
# source must still resolve — it depends on BASH_SOURCE, not on PATH.
printf '#!/bin/bash\nsource %s\ndeclare -F gs_version_gate\n' \
  "$(cd "${DIST_BIN}/base-bin" && pwd)/global-stack-base-prologue.sh" \
  >"${TMP_DIR}/vg-explicit.sh"
assert_output_contains "23j: explicit-path source resolves the helper with base-bin off PATH" \
  "gs_version_gate" \
  env -i PATH=/usr/bin:/bin HOME="${HOME}" bash "${TMP_DIR}/vg-explicit.sh"

# The exemption itself: these must never gain a prologue source line, or the
# extraction was pointless and their stackCatch would be swapped.
for _ex in caddy-bin/global-stack-caddy-start.sh nginx-bin/global-stack-nginx-start.sh \
           httpd-bin/global-stack-httpd-start.sh android-bin/global-stack-android-setup.sh; do
  assert_fail "23i: $(basename "${_ex}") stays prologue-exempt" \
    grep -q '^source global-stack-base-prologue\.sh$' "${DIST_BIN}/${_ex}"
done

# ─── Section 24: nvm-install-tools deno/bun version gate (row 16) ─────────
printf '\n%b── Section 24: nvm-install-tools deno/bun gate%b\n' "${C_BOLD}" "${C_RESET}"

# Row 16, the first Track 5b migration. Both blocks were exist-only
# (`[ -f "${DENO_JS}" ]`), so a GLOBAL_STACK_DENO_VERSION / _BUN_VERSION bump did
# nothing at all and neither tool had a marker. This section is the shape rows
# 17-21 copy: stub curl on PATH, drive the gate from a fixture tools tree.
NVM_TOOLS="${DIST_BIN}/nvm-bin/global-stack-nvm-install-tools.sh"

# _nvm_tools_run <tool> <marker_body> <pin> <binary_present> [curl_fail]
#   echoes: "<decision-ish trace>|<marker content after the run>|<binary present>"
_nvm_tools_run() {
  local tool="$1" marker_body="$2" pin="$3" bin_present="$4" curl_fail="${5:-0}"
  local root="${TMP_DIR}/nvmtools"
  rm -rf "${root}"
  mkdir -p "${root}/vers" "${root}/deno/bin" "${root}/bun/bin" "${root}/stub" \
           "${root}/errors" "${root}/run"

  # curl stub: for deno the script downloads an installer to a file and runs it;
  # for bun it pipes curl's stdout into `bash -s <version>`. Both shapes covered.
  {
    printf '#!/bin/bash\n'
    printf '[ "${CURL_FAIL:-0}" = "1" ] && exit 22\n'
    printf 'out=""; prev=""\n'
    printf 'for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done\n'
    printf 'if [ -n "$out" ]; then\n'
    printf '  printf "#!/bin/bash\\nmkdir -p \\"%%s/bin\\"\\ntouch \\"%%s/bin/deno\\"\\n" "${DENO_INSTALL}" "${DENO_INSTALL}" > "$out"\n'
    printf 'else\n'
    printf '  printf "mkdir -p \\"%%s/bin\\"\\ntouch \\"%%s/bin/bun\\"\\n" "${BUN_INSTALL}" "${BUN_INSTALL}"\n'
    printf 'fi\n'
  } >"${root}/stub/curl"
  chmod +x "${root}/stub/curl"

  [[ -n "${marker_body}" ]] && printf '%s\n' "${marker_body}" >"${root}/vers/nvm.${tool}"
  if [[ "${bin_present}" == "1" ]]; then
    touch "${root}/deno/bin/deno" "${root}/bun/bin/bun"
  else
    rm -f "${root}/deno/bin/deno" "${root}/bun/bin/bun"
  fi

  # Pin the tool under test; give the OTHER tool a matching marker + binary so it
  # is a no-op and cannot pollute the assertion.
  local deno_pin bun_pin
  if [[ "${tool}" == deno ]]; then
    deno_pin="${pin}"; bun_pin="9.9.9"
    printf '9.9.9\n' >"${root}/vers/nvm.bun"; touch "${root}/bun/bin/bun"
  else
    bun_pin="${pin}"; deno_pin="9.9.9"
    printf '9.9.9\n' >"${root}/vers/nvm.deno"; touch "${root}/deno/bin/deno"
  fi

  ( cd "${root}/run" && env \
      PATH="${root}/stub:${DIST_BIN}/base-bin:${PATH}" \
      CURL_FAIL="${curl_fail}" \
      DENO_INSTALL="${root}/deno" \
      BUN_INSTALL="${root}/bun" \
      GLOBAL_STACK_DENO_VERSION="${deno_pin}" \
      GLOBAL_STACK_BUN_VERSION="${bun_pin}" \
      GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${root}/vers" \
      GLOBAL_STACK_DOCKER_TOOLS_PATH="${root}" \
      GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${root}/errors" \
      GLOBAL_STACK_ERROR_TOKEN="nvm-test" \
      bash "${NVM_TOOLS}" >/dev/null 2>&1 ) || true

  local after="<none>"
  [[ -f "${root}/vers/nvm.${tool}" ]] && after="$(cat "${root}/vers/nvm.${tool}")"
  local present=0
  [[ -f "${root}/${tool}/bin/${tool}" ]] && present=1
  printf '%s|%s' "${after}" "${present}"
}

for _tool in deno bun; do
  # absent marker, absent binary → install, marker written with the pin
  _r="$(_nvm_tools_run "${_tool}" "" 1.2.3 0)"
  assert_pass "24a: ${_tool} first install writes the marker" test "${_r}" = "1.2.3|1"

  # marker == pin, binary present → skip, marker untouched
  _r="$(_nvm_tools_run "${_tool}" 1.2.3 1.2.3 1)"
  assert_pass "24b: ${_tool} marker matching the pin → skip" test "${_r}" = "1.2.3|1"

  # marker != pin → reinstall, marker updated to the new pin. THE DEFECT: before
  # row 16 this did nothing, because the guard only asked whether the binary existed.
  _r="$(_nvm_tools_run "${_tool}" 1.2.3 1.2.4 1)"
  assert_pass "24c: ${_tool} pin bumped → reinstall and marker updated" test "${_r}" = "1.2.4|1"

  # marker says up to date but the artifact is gone (a hand-cleaned tools/ tree):
  # must still install. Preserves the old exist-only behaviour as a floor.
  _r="$(_nvm_tools_run "${_tool}" 1.2.3 1.2.3 0)"
  assert_pass "24d: ${_tool} marker matches but binary missing → still installs" \
    test "${_r}" = "1.2.3|1"

  # a failed download must NOT leave a satisfied marker behind
  _r="$(_nvm_tools_run "${_tool}" "" 1.2.3 0 1)"
  assert_pass "24e: ${_tool} failed install writes no marker" test "${_r}" = "<none>|0"
done

# ─── Section 25: phpbrew-install-tools version gates (row 17) ─────────────
printf '\n%b── Section 25: phpbrew-install-tools gates%b\n' "${C_BOLD}" "${C_RESET}"

# Row 17. Eleven tools. Ten were marker-based but wrote the marker BEFORE
# installing, so a failed install recorded success and every later boot skipped
# it; two of those ten (deployer, symfony-cli) never read their marker at all.
# The eleventh, laravel/installer, was unpinned and followed by a blanket
# `composer global update --with-all-dependencies` that would move any pin back.
#
# COVERAGE HONESTY: one tool (zephir) is covered behaviourally below; the other
# ten are covered STRUCTURALLY by the marker-last invariant. Behavioural cover for
# all eleven would need stubs for composer, git, php, rsync and tar. The
# structural invariant is what the marker-first defect violated, so it is the one
# that matters — but it is a weaker guarantee than §24's per-tool execution.
PHPBREW_TOOLS="${DIST_BIN}/phpbrew-bin/global-stack-phpbrew-install-tools.sh"

assert_pass "25a: phpbrew-install-tools passes bash -n" bash -n "${PHPBREW_TOOLS}"

# Every tool goes through the gate, and every tool writes exactly one marker.
_pt_gates="$(grep -c 'gs_version_gate ' "${PHPBREW_TOOLS}" || true)"
_pt_writes="$(grep -c "printf '%s\\\\n'.*TOOLS_PATH_VERSIONS" "${PHPBREW_TOOLS}" || true)"
assert_pass "25b: 11 gate calls" test "${_pt_gates}" = "11"
assert_pass "25b: 11 marker writes" test "${_pt_writes}" = "11"

# THE DEFECT: the old shape wrote the marker with `echo -e "${X}" > .../versions/`
# as the FIRST statement of the install branch. None may remain.
_pt_first="$(grep -c 'echo -e "\${[A-Z_]*}" > "\${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}' "${PHPBREW_TOOLS}" || true)"
assert_pass "25c: no marker-first writes remain" test "${_pt_first}" = "0"

# Marker-last, structurally: every marker write is the final statement of its
# branch, i.e. the next non-blank line is the closing `fi`. Under `set -e` that is
# what makes a failed install unable to leave a satisfied marker behind.
_pt_bad="$(awk '
  /printf .%s\\n.*TOOLS_PATH_VERSIONS/ { pending=1; next }
  pending && /^[[:space:]]*$/          { next }
  pending                              { if ($0 !~ /^fi$/) bad++; pending=0 }
  END { print bad+0 }
' "${PHPBREW_TOOLS}")"
assert_pass "25d: every marker write is the last statement in its branch" \
  test "${_pt_bad}" = "0"

# laravel/installer: pinned require, and the blanket global update is gone from
# the executable body (it survives only in the comment that explains its removal).
assert_pass "25e: laravel/installer require is pinned to the .env var" \
  grep -q 'composer global require --ignore-platform-reqs "laravel/installer:\${GLOBAL_STACK_LARAVEL_INSTALLER_VERSION}"' \
  "${PHPBREW_TOOLS}"
_pt_upd="$(grep -v '^[[:space:]]*#' "${PHPBREW_TOOLS}" | grep -c 'composer global update' || true)"
assert_pass "25e: no executable 'composer global update' remains" test "${_pt_upd}" = "0"

# The new var must reach the container, or the gate reinstalls every boot.
REPO_ROOT="${SCRIPT_DIR}/../.."
assert_pass "25f: .env pins laravel/installer" \
  grep -q '^GLOBAL_STACK_LARAVEL_INSTALLER_VERSION=' "${REPO_ROOT}/.env"
assert_pass "25f: .env carries its @todo env-update annotation" \
  grep -q '^# @todo env-update github:laravel/installer' "${REPO_ROOT}/.env"
assert_pass "25f: 02phpbrew compose passes it into the container" \
  grep -q 'GLOBAL_STACK_LARAVEL_INSTALLER_VERSION=\${GLOBAL_STACK_LARAVEL_INSTALLER_VERSION}' \
  "${REPO_ROOT}/docker/images/02phpbrew/docker-compose.yaml"

# ── behavioural: zephir, the simplest curl→mv→chmod shape ──
_zephir_run() {
  local marker_body="$1" pin="$2" phar_present="$3" curl_fail="${4:-0}"
  local root="${TMP_DIR}/pbtools"
  rm -rf "${root}"; mkdir -p "${root}/vers" "${root}/bin" "${root}/stub" "${root}/run"
  {
    printf '#!/bin/bash\n'
    printf '[ "${CURL_FAIL:-0}" = "1" ] && exit 22\n'
    printf 'touch zephir.phar\n'
  } >"${root}/stub/curl"
  chmod +x "${root}/stub/curl"
  # every other block must be a no-op: give them matching markers and files
  for t in composer laravel-installer phalcon deployer symfony-cli pickle pie mago castor \
           fabpot-local-php-security-checker; do
    printf 'noop\n' >"${root}/vers/phpbrew.${t}"
  done
  [[ -n "${marker_body}" ]] && printf '%s\n' "${marker_body}" >"${root}/vers/phpbrew.zephir"
  [[ "${phar_present}" == "1" ]] && touch "${root}/bin/zephir"
  # run ONLY the zephir block: extract it by its anchors, never by line number
  awk '/^ZEPHIR_LANG_PHAR_FILE=/,/^rm -rf zephir\.pha\*/' "${PHPBREW_TOOLS}" >"${root}/run/block.sh"
  ( cd "${root}/run" && env \
      PATH="${root}/stub:${DIST_BIN}/base-bin:${PATH}" \
      CURL_FAIL="${curl_fail}" \
      PHPBREW_BIN="${root}/bin" \
      GLOBAL_STACK_ZEPHIR_LANG_VERSION="${pin}" \
      GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${root}/vers" \
      bash -c 'set -e; source global-stack-base-version-gate.sh; source ./block.sh' ) >/dev/null 2>&1 || true
  local after="<none>"
  [[ -f "${root}/vers/phpbrew.zephir" ]] && after="$(cat "${root}/vers/phpbrew.zephir")"
  printf '%s' "${after}"
}

assert_pass "25g: zephir first install writes the marker" \
  test "$(_zephir_run "" 1.0.0 0)" = "1.0.0"
assert_pass "25g: zephir marker matching the pin → skip" \
  test "$(_zephir_run 1.0.0 1.0.0 1)" = "1.0.0"
assert_pass "25g: zephir pin bumped → reinstall, marker updated" \
  test "$(_zephir_run 1.0.0 1.0.1 1)" = "1.0.1"
assert_pass "25h: zephir failed download leaves no satisfied marker" \
  test "$(_zephir_run "" 1.0.0 0 1)" = "<none>"

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
