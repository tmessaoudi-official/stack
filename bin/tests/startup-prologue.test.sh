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

# A pristine PATH, captured before any section runs. §22's sdkman probe sets
# PATH="/usr/bin:/bin" inside a ( ) group, and a later probe that builds its own
# PATH from "${PATH}" is then reading a value shellcheck cannot prove is the
# original (SC2030/SC2031). Reading this snapshot instead is both quieter and
# more honest: a probe wants the environment the SUITE started in, not whatever
# an earlier section happened to leave behind.
PATH0="${PATH}"

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
  local out rc=0
  # `|| rc=$?` — the command under test exiting non-zero is a RED for this
  # assertion, not a harness error. `assert_pass`/`assert_fail` already get this
  # right by testing in an `if`; this helper did not, and an unguarded
  # `out=$(...)` under this suite's `set -euo pipefail` kills the whole RUN.
  # Measured, not assumed [row 35]: renaming `gs_version_gate` in the shipped
  # helper aborted the run at Section 15 with exit 127, no tally line and no ✗ —
  # which reads as a crash, strictly worse than a red. 31 call sites shared it.
  # The code is printed on failure so a 127 (helper missing) is distinguishable
  # from a genuine output mismatch.
  out=$("$@" 2>&1) || rc=$?
  if echo "${out}" | grep -q "${pattern}"; then
    PASS=$((PASS + 1))
    printf '  %b✓%b  %s\n' "${C_GREEN}" "${C_RESET}" "${label}"
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("${label}")
    printf '  %b✗%b  %s  (rc=%s, output: %s)\n' "${C_RED}" "${C_RESET}" "${label}" "${rc}" "${out:0:100}"
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

# Row 25: DISCOVERED, not hardcoded. This was an 8-entry literal list that happened
# to omit caddy-iou.sh, httpd-iou.sh and nginx-iou.sh — the exact three scripts that
# still carried the exit-1 exemption, so §19 could never go red for them and the
# defect survived the 2026-08-29 migration unnoticed. Any script in the three
# web-server trees that defines its own stackCatch is now covered automatically, so
# a new one cannot be invisible to this section.
#
# Row 30: the roots were STILL hardcoded to the three web-server trees, which is
# the same defect one level up — the android handlers are members of the very same
# prologue-exempt family (CLAUDE.md names them in the exclusion list), carried the
# identical exit-1 blindness, and this section could not see them. `android-bin` is
# now a discovery root, and every pattern below tolerates the POSIX `[ ... ]` form
# the android scripts are written in as well as the web servers' `[[ ... ]]`:
# extending the roots alone would have made 19a pass VACUOUSLY on a regex miss.
EXEMPT_SCRIPTS=()
while IFS= read -r -d '' _f; do
  grep -q '^stackCatch() {' "${_f}" || continue
  EXEMPT_SCRIPTS+=("${_f#"${DIST_BIN}/"}")
done < <(find "${DIST_BIN}/caddy-bin" "${DIST_BIN}/nginx-bin" "${DIST_BIN}/httpd-bin" \
              "${DIST_BIN}/android-bin" -name '*.sh' -print0 | sort -z)
printf '  (discovered %d prologue-exempt handlers)\n' "${#EXEMPT_SCRIPTS[@]}"
# Non-vacuity: 11 web-server + 3 android. A typo in a find root would otherwise
# shrink the set silently and every assertion below would pass by not running.
assert_pass "19-guard: discovery covers the whole exempt family (>= 14)" \
  test "${#EXEMPT_SCRIPTS[@]}" -ge 14

# Every STATIC check below reads the handler BODY with comment lines stripped, not
# the whole file. Both directions have already bitten: an explanatory comment that
# quotes the arm it says was removed would red 19a on a correctly-fixed file, and
# android-start.sh's stale-token `rm -f` on line 19 sits OUTSIDE the handler yet
# matches a naive token-write grep (it did, in the first inventory of row 30).
_handler_body() { # $1 = script path
  sed -n '/^stackCatch() {/,/^}/p' "${1}" | grep -v '^[[:space:]]*#'
}

for _ws in "${EXEMPT_SCRIPTS[@]}"; do
  _ws_path="${DIST_BIN}/${_ws}"
  _ws_body="${TMP_DIR}/body-$(basename "${_ws}")"
  _handler_body "${_ws_path}" >"${_ws_body}"
  # Anchor on the closing `]]`: a bare '-ne 1' also matches the '-ne 141'
  # SIGPIPE arm, which must SURVIVE — that pattern can never go green.
  # Row 25: the pattern now tolerates BOTH spellings, `$exit_code` and
  # `"${exit_code}"`. The old fixed-string form only matched the unquoted one, so
  # it silently passed over any handler written the other way — the same
  # can-never-fire defect as the hardcoded script list this section used to carry.
  # Row 30: each pattern now carries a POSIX alternative (`!= "1" ]`) so an android
  # handler cannot satisfy it by simply not matching.
  assert_fail "19a: $(basename "${_ws}") no longer exempts exit code 1" \
    grep -qE '(\$\{?exit_code\}?"? -ne 1 \]\]|!= "1" \])' "${_ws_body}"
  # No closing-bracket anchor on THIS one. `-ne 141` is unambiguous on its own, and
  # requiring the `]]` made the assertion sensitive to where the arm sits in the
  # condition: sabotage S2 (row 30) appended an unrelated arm after it and reddened
  # this check even though the exemption was still there — red for the wrong reason.
  assert_pass "19a: $(basename "${_ws}") keeps the 141 (SIGPIPE) exemption" \
    grep -qE '(-ne 141|!= "141")' "${_ws_body}"
  # Row 30: the handler must write the error token ITSELF. android-start.sh did not,
  # so a failure left tools/errors/ empty and the healthcheck could never go red —
  # the container sat alive-and-silent behind the 24h start_period.
  assert_pass "19b2: $(basename "${_ws}") writes errors/\${GLOBAL_STACK_ERROR_TOKEN}" \
    grep -qE 'GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS\}/\$\{GLOBAL_STACK_ERROR_TOKEN' "${_ws_body}"
  # Both halves, not the bare name: sabotage S5 (row 30) deleted the guard's READ
  # and left the assignment behind, and a `grep -q _STACK_CAUGHT` stayed GREEN on a
  # handler that no longer guards anything. The read is the half that does the work.
  assert_pass "19b: $(basename "${_ws}") reads the _STACK_CAUGHT re-entry guard" \
    grep -q '_STACK_CAUGHT:-' "${_ws_body}"
  assert_pass "19b3: $(basename "${_ws}") sets _STACK_CAUGHT before reporting" \
    grep -q '_STACK_CAUGHT=1' "${_ws_body}"
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

# BEHAVIOURAL, android (row 30). The web-server harness above cannot be reused on
# these: android-start.sh's handler ends in `sleep infinity` — DELIBERATE, its own
# lines 73-74 record that the container must stay reachable for
# `make login-04android` — so _ws_reports would hang the suite forever, and its
# `grep -c 'Error detected!'` does not even match android's "Error detected !!".
# This probe reports what a failure actually LEAVES BEHIND: elapsed lines, error
# token, and whether the process stayed alive. TERM vs KILL was measured before the
# assertions were written — identical on the sleep path — so plain `timeout` here is
# deterministic, not incidental.
_andr_probe() { # $1 = script path, $2 = exit code; echoes "<lines>:<token>:<rc>"
  local src="$1" code="$2" d="${TMP_DIR}/andr" h="${TMP_DIR}/andr-harness.sh" rc
  rm -rf "${d}"
  mkdir -p "${d}/errors"
  {
    printf '#!/bin/bash\nset -eE -o pipefail\n'
    sed -n '/^stackCatch() {/,/^}/p' "${src}"
    printf 'trap %s ERR EXIT\n' "'stackCatch \$? \${LINENO} \"\${BASH_COMMAND}\"'"
    printf '(exit %s)\n' "${code}"
  } >"${h}"
  timeout 3 env GLOBAL_STACK_ERROR_TOKEN=andr-token \
    GLOBAL_STACK_DOCKER_TOOLS_PATH="${d}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${d}/errors" \
    bash "${h}" >/dev/null 2>&1
  rc=$?
  printf '%s:%s:%s' \
    "$([[ -f "${d}/elapsed" ]] && wc -l <"${d}/elapsed" || echo 0)" \
    "$([[ -f "${d}/errors/andr-token" ]] && echo token || echo NONE)" \
    "${rc}"
}
_andr_start="${DIST_BIN}/android-bin/global-stack-android-start.sh"
_andr_setup="${DIST_BIN}/android-bin/global-stack-android-setup.sh"

# rc 124 = the timeout fired, i.e. the handler is still alive. That is the CONTRACT
# for android-start.sh, not a defect: report, mark the container failed, stay up.
_p="$(_andr_probe "${_andr_start}" 1)"
assert_output_contains "19h: android-start exit 1 reports and writes the error token" \
  '^1:token:' printf '%s' "${_p}"
assert_output_contains "19i: android-start exit 1 stays ALIVE for login (sleep infinity)" \
  ':124$' printf '%s' "${_p}"

# 141 is SIGPIPE. Before row 30 this script was the only exempt handler that did not
# exempt it, so a routine broken pipe parked the container in `sleep infinity`.
_p="$(_andr_probe "${_andr_start}" 141)"
assert_output_contains "19j: android-start exit 141 (SIGPIPE) stays exempt and does NOT hang" \
  '^0:NONE:141$' printf '%s' "${_p}"

_p="$(_andr_probe "${_andr_start}" 0)"
assert_output_contains "19k: android-start clean exit writes nothing" \
  '^0:NONE:0$' printf '%s' "${_p}"

# android-setup.sh exits rather than sleeping, so its own `exit 1` re-enters through
# the EXIT trap — exactly the case _STACK_CAUGHT exists for. One line, never two.
_p="$(_andr_probe "${_andr_setup}" 1)"
assert_output_contains "19l: android-setup exit 1 reports and writes the error token" \
  '^1:token:' printf '%s' "${_p}"
_p="$(_andr_probe "${_andr_setup}" 2)"
assert_output_contains "19m: android-setup exit 2 reported exactly once (no EXIT re-entry)" \
  '^1:token:' printf '%s' "${_p}"

# The /new-service scaffold is where the NEXT exempt handler comes from, so a defect
# left there re-enters the tree one service at a time. It shipped the same shape row
# 25 removed: `exit 1` inside a handler armed on EXIT ERR, with no re-entry guard.
# SCRIPT_DIR, not REPO_ROOT: the latter is not defined until §44, far below this.
_NS_SKILL="${SCRIPT_DIR}/../../.claude/skills/new-service/SKILL.md"
assert_pass "19-guard: the new-service skill exists" test -f "${_NS_SKILL}"
assert_pass "19n: the scaffolded handler READS the _STACK_CAUGHT re-entry guard" \
  grep -q '_STACK_CAUGHT:-' "${_NS_SKILL}"
assert_pass "19n3: ...and sets it before reporting" \
  grep -q '_STACK_CAUGHT=1' "${_NS_SKILL}"
# Anchored on the canonical label, never on the word it replaced: the comment added
# beside it names both, so grepping for the old word would match the fix itself.
assert_pass "19n2: the scaffolded elapsed line uses the canonical '** command:' field" \
  grep -qF 'Error - ** line: %s ** ** command: %s **' "${_NS_SKILL}"

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

# ─── Section 26: rust tool version gates (row 18) ─────────────────────────
printf '\n%b── Section 26: rust install-tool gates%b\n' "${C_BOLD}" "${C_RESET}"

# Row 18. All five were exist-only (`"" = "$(command -v X)"`), so a version bump
# did nothing and none kept a marker. They are invoked as bare commands by
# rust-start.sh, so each is its own process and must source the gate helper —
# this is the first row that consumes row 15's extraction.
RUST_BIN="${DIST_BIN}/rust-bin"

for _t in cargo-nextest cargo-outdated cargo-zigbuild jujutsu mergiraf; do
  assert_pass "26a: rust-install-${_t} sources the gate helper ALONE" \
    grep -q '^source global-stack-base-version-gate\.sh$' \
    "${RUST_BIN}/global-stack-rust-install-${_t}.sh"
  assert_fail "26a: rust-install-${_t} does NOT source the full prologue" \
    grep -q 'global-stack-base-prologue\.sh' \
    "${RUST_BIN}/global-stack-rust-install-${_t}.sh"
done

# The cascade fix: these five reached the container only through the 00base image
# ENV, so a .env bump could not be seen at runtime until a rebuild.
for _v in CARGO_NEXTEST CARGO_OUTDATED CARGO_ZIGBUILD JUJUTSU MERGIRAF; do
  assert_pass "26b: 02rust passes GLOBAL_STACK_${_v}_VERSION at runtime" \
    grep -q "GLOBAL_STACK_${_v}_VERSION=\${GLOBAL_STACK_${_v}_VERSION}" \
    "${SCRIPT_DIR}/../../docker/images/02rust/docker-compose.yaml"
done

# _rust_tool_run <tool> <marker_body> <pin> <binary_present> → "<marker>|<forced?>"
_rust_tool_run() {
  local tool="$1" marker_body="$2" pin="$3" bin_present="$4"
  local root="${TMP_DIR}/rusttool" var
  rm -rf "${root}"; mkdir -p "${root}/vers" "${root}/stub" "${root}/run"
  case "${tool}" in
    cargo-nextest)  var=GLOBAL_STACK_CARGO_NEXTEST_VERSION ;;
    cargo-outdated) var=GLOBAL_STACK_CARGO_OUTDATED_VERSION ;;
    cargo-zigbuild) var=GLOBAL_STACK_CARGO_ZIGBUILD_VERSION ;;
    jujutsu)        var=GLOBAL_STACK_JUJUTSU_VERSION ;;
    mergiraf)       var=GLOBAL_STACK_MERGIRAF_VERSION ;;
  esac
  # cargo stub records whether --force was passed; rustup/git/sudo are no-ops.
  { printf '#!/bin/bash\n'
    printf 'for a in "$@"; do [ "$a" = "--force" ] && echo forced > "%s/forced"; done\n' "${root}"
    printf 'exit 0\n'; } >"${root}/stub/cargo"
  for n in rustup git; do printf '#!/bin/bash\nexit 0\n' >"${root}/stub/${n}"; done
  # sudo must really run mkdir/chmod/rm: mergiraf's script does `cd /tmp/mergiraf`
  # right after creating it, and a no-op sudo makes that cd fail under set -e —
  # which looks like a gate defect but is only a blunt stub. chown is skipped
  # because the fixture's user/group do not exist. Only /tmp/mergiraf is touched,
  # and the script itself removes it on the way out.
  { printf '#!/bin/bash\n'
    printf 'case "$1" in chown) exit 0 ;; *) exec "$@" ;; esac\n'; } >"${root}/stub/sudo"
  # the binary-present case: a stub named after the tool's command
  local cmd="${tool}"; [[ "${tool}" == jujutsu ]] && cmd=jj
  [[ "${bin_present}" == "1" ]] && printf '#!/bin/bash\nexit 0\n' >"${root}/stub/${cmd}"
  chmod +x "${root}/stub/"*
  [[ -n "${marker_body}" ]] && printf '%s\n' "${marker_body}" >"${root}/vers/rust.${tool}"

  ( cd "${root}/run" && env \
      PATH="${root}/stub:${DIST_BIN}/base-bin:/usr/bin:/bin" \
      "${var}=${pin}" \
      GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${root}/vers" \
      GLOBAL_STACK_DOCKER_ROOT_PATH="${root}/run" \
      GLOBAL_STACK_DOCKER_USER_ID=u GLOBAL_STACK_DOCKER_GROUP_ID=g \
      bash "${RUST_BIN}/global-stack-rust-install-${tool}.sh" ) >/dev/null 2>&1 || true

  local after="<none>" forced=no
  [[ -f "${root}/vers/rust.${tool}" ]] && after="$(cat "${root}/vers/rust.${tool}")"
  [[ -f "${root}/forced" ]] && forced=yes
  printf '%s|%s' "${after}" "${forced}"
}

for _t in cargo-nextest cargo-outdated cargo-zigbuild jujutsu mergiraf; do
  # first install: marker written, no --force needed
  assert_pass "26c: ${_t} first install writes the marker unforced" \
    test "$(_rust_tool_run "${_t}" "" 1.0.0 0)" = "1.0.0|no"
  # marker matches and the binary is present → skip entirely
  assert_pass "26d: ${_t} marker matching the pin → skip" \
    test "$(_rust_tool_run "${_t}" 1.0.0 1.0.0 1)" = "1.0.0|no"
  # THE DEFECT: a bump used to do nothing. Now it reinstalls, forced, and the
  # marker moves to the new pin.
  assert_pass "26e: ${_t} pin bumped → forced reinstall, marker updated" \
    test "$(_rust_tool_run "${_t}" 1.0.0 1.0.1 1)" = "1.0.1|yes"
done

# ─── Section 27: android SDK component gate (row 19) ──────────────────────
printf '\n%b── Section 27: android SDK component gate%b\n' "${C_BOLD}" "${C_RESET}"

# Row 19. android.sdkmanager holds the sdkmanager BINARY's own version, so it could
# never detect an SDK component bump — the GLOBAL_STACK_ANDROID_* pins were never
# compared to anything. A composite marker now carries the inputs the live install
# actually consumes. Row 33 widened that from 3 to all 12: §47 below derives the set
# from setup.sh rather than trusting a list anyone has to remember to extend.
AND_START="${DIST_BIN}/android-bin/global-stack-android-start.sh"
AND_SETUP="${DIST_BIN}/android-bin/global-stack-android-setup.sh"

assert_pass "27a: android-start sources the gate helper ALONE" \
  grep -q '^source global-stack-base-version-gate\.sh$' "${AND_START}"
assert_fail "27a: android-start does NOT source the prologue" \
  grep -q 'global-stack-base-prologue\.sh' "${AND_START}"
assert_fail "27a: android-setup does NOT source the prologue (stays exempt)" \
  grep -q 'global-stack-base-prologue\.sh' "${AND_SETUP}"

# The four LIVE *_VERSION pins. PLATFORM_TOOLS joined this list in row 33, on the
# reasoning that `_pkgs` installed "platform-tools;${…}" as a real element. Row 36
# measured that id: it installs nothing (single-instance packages take no version).
# It belongs in the set anyway, for the sounder reason — the install id is bare and
# the pin is ASSERTED against the build upstream served, so a bump must change the
# marker or the reinstall that picks up the new build never happens. NDK_BUNDLE has
# no consumer at all, live or asserted, so including it would force a reinstall on a
# bump that changes nothing. §47 checks the whole set both ways; this loop is the
# named-pin regression guard.
for _v in CMDLINE_TOOLS PLATFORM_TOOLS BUILD_TOOLS NDK; do
  assert_pass "27b: composite marker includes ${_v}" \
    grep -q "GS_ANDROID_SDK_WANT=.*GLOBAL_STACK_ANDROID_${_v}_VERSION" "${AND_START}"
done
# `|| true` for the same reason as the harness below: a missing anchor is the
# red-first case, not a harness error, and an unguarded command substitution
# under `set -e` aborts the RUN with no tally instead of redding.
_and_want_line="$(grep -m1 '^GS_ANDROID_SDK_WANT=' "${AND_START}" || true)"
# NDK_BUNDLE is the one consumed-LOOKING name that must stay OUT. Row 33 emptied
# this of its second member (PLATFORM_TOOLS moved to the include loop above), so it
# is no longer a `for`: shellcheck SC2043 objects to a one-element loop, and §47
# covers the general case in both directions anyway.
_v=NDK_BUNDLE
case "${_and_want_line}" in
  *"GLOBAL_STACK_ANDROID_${_v}_VERSION"*)
    FAIL=$((FAIL + 1))
    FAILURES+=("27b: composite wrongly includes ${_v}")
    printf '  %b✗%b  27b: composite wrongly includes %s (comment-only var)\n' "${C_RED}" "${C_RESET}" "${_v}"
    ;;
  *)
    PASS=$((PASS + 1))
    printf '  %b✓%b  27b: composite excludes %s (comment-only var)\n' "${C_GREEN}" "${C_RESET}" "${_v}"
    ;;
esac

# Both the wipe branch and the setup branch must consult the gate, or a component
# bump would clean but not reinstall (or reinstall onto a dirty tree).
_and_gated="$(grep -c '\[ "${_android_gate}" != "skip" \]' "${AND_START}" || true)"
assert_pass "27c: both android branches consult the gate" test "${_and_gated}" = "2"

# Marker-last, and never written from a standalone setup run.
# `> *"`, not `> "`: pinning the redirect's SPACING made this a trap -- shfmt
# prefers `>"`, so a formatting-only pass over dist/bin would red a green test
# for a change that alters nothing [measured, row 32]. The assertion still has
# teeth: it needs a redirect, and a gutted write (`true "${GS_ANDROID_SDK_WANT}"`)
# has none.
assert_pass "27d: android-setup writes the composite marker" \
  grep -q 'GS_ANDROID_SDK_WANT.*> *"\${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/android.sdk"' "${AND_SETUP}"
assert_pass "27d: and only when the compose-time value was exported" \
  grep -q '\[\[ -n "\${GS_ANDROID_SDK_WANT:-}" \]\]' "${AND_SETUP}"

# ── behavioural: the gate block, extracted by pattern (never by line number) ──
#
# The 12 values are SYNTHETIC, mutually distinct, and contain neither `;` nor `=`:
# a fixture copied from .env would pass even when fixture and code were both wrong
# (the no-fixture-leakage rule), and a value carrying the composite's own
# separators would make a field boundary unreadable.
#
# All 12 are pinned EXPLICITLY. This is `env`, not `env -i` — PATH has to survive —
# so any input left unpinned would be inherited from the developer's shell, where
# the /stack vars are commonly exported: green on this machine, red on a clean one.
_and_env=(
  GLOBAL_STACK_ANDROID_SDK_BUILD=synthbuild
  GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION=1.0
  GLOBAL_STACK_ANDROID_PLATFORM_TOOLS_VERSION=2.0
  GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION=3.0
  GLOBAL_STACK_ANDROID_NDK_VERSION=4.0
  GLOBAL_STACK_ANDROID_API_LEVEL_1=5.0
  GLOBAL_STACK_ANDROID_API_LEVEL_2=6.0
  GLOBAL_STACK_ANDROID_API_LEVEL_3=7.0
  GLOBAL_STACK_ANDROID_INSTALL_SYSTEM_IMAGES=synthimages
  GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_TAG=synthtag
  GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_PLAYSTORE_TAG=synthpstag
  GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_ABI=synthabi
)

# The same array with ONE key's value replaced. Bash has no map; this is a prefix
# match on `KEY=`, emitted one assignment per line for `mapfile`.
_and_env_with() {
  local key="$1" val="$2" e
  for e in "${_and_env[@]}"; do
    case "${e}" in
      "${key}="*) printf '%s\n' "${key}=${val}" ;;
      *) printf '%s\n' "${e}" ;;
    esac
  done
}

# The composite the SHIPPED line computes for a given environment. Deriving the
# fixture instead of transcribing it means a change to the marker's FORMAT reds for
# the right reason (the format moved) rather than for transcription drift, and the
# bump cases below stay meaningful without anyone re-typing a 12-field string.
_android_want() {
  local root="${TMP_DIR}/android-want" h
  rm -rf "${root}"
  mkdir -p "${root}"
  h="${root}/want.sh"
  {
    printf '#!/bin/bash\nset -e\n'
    grep -m1 '^GS_ANDROID_SDK_WANT=' "${AND_START}" || true
    printf 'printf "%%s\\n" "${GS_ANDROID_SDK_WANT:-<no-want-line>}"\n'
  } >"${h}"
  env "$@" bash "${h}" 2>/dev/null || true
}

_android_decision() {
  local marker_body="$1"
  shift
  local root="${TMP_DIR}/android" h
  rm -rf "${root}"
  mkdir -p "${root}/vers"
  h="${root}/block.sh"
  {
    printf '#!/bin/bash\nset -e\n'
    printf 'source global-stack-base-version-gate.sh\n'
    # `|| true`: grep exits 1 by contract when the anchor is absent, which is the
    # legitimate red-first case (the gate does not exist yet). Without it this
    # suite's `set -euo pipefail` kills the whole RUN with no tally line instead
    # of redding — the same harness defect §15 has, recorded in the plan's
    # ### Fragile section.
    grep -m1 '^GS_ANDROID_SDK_WANT=' "${AND_START}" || true
    grep -m1 '^_android_gate=' "${AND_START}" || true
    printf 'printf "DECISION=%%s\\n" "${_android_gate:-<no-gate>}"\n'
  } >"${h}"
  if [[ -n "${marker_body}" ]]; then
    printf '%s\n' "${marker_body}" >"${root}/vers/android.sdk"
  fi
  env PATH="${DIST_BIN}/base-bin:${PATH}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${root}/vers" \
    "$@" \
    bash "${h}" 2>/dev/null | sed -n 's/^DECISION=//p' || true
}

_want="$(_android_want "${_and_env[@]}")"

# Non-vacuity for the DERIVED fixture. If the `^GS_ANDROID_SDK_WANT=` anchor stops
# matching, _android_want emits its sentinel and 27e reds correctly — but every 27f
# bump below would then pass VACUOUSLY, because a sentinel that never changes makes
# EVERY value change look like a reinstall. So prove the derived string really
# carries all 12 synthetic values before trusting a single bump result.
_want_missing=""
for _e in "${_and_env[@]}"; do
  case "${_want}" in
    *"${_e#*=}"*) ;;
    *) _want_missing="${_want_missing} ${_e#GLOBAL_STACK_ANDROID_}" ;;
  esac
done
assert_pass "27b2: derived composite carries all 12 synthetic values (missing:${_want_missing:- none})" \
  test -z "${_want_missing}"

assert_pass "27e: no marker → install" \
  test "$(_android_decision "" "${_and_env[@]}")" = "install"
assert_pass "27e: composite matches → skip" \
  test "$(_android_decision "${_want}" "${_and_env[@]}")" = "skip"

# THE DEFECT, at its real width (row 33): the composite carried 3 of the 12 inputs
# setup.sh consumes, so a bump of any of the other NINE was silently never applied
# — gs_version_gate said `skip`, the SDK kept the old component, and nothing
# warned. One case per key, each changing exactly ONE field, so a red names the
# input that stopped being watched rather than reporting a vague mismatch.
for _e in "${_and_env[@]}"; do
  _k="${_e%%=*}"
  mapfile -t _bumped < <(_and_env_with "${_k}" bumpedvalue)
  assert_pass "27f: ${_k#GLOBAL_STACK_ANDROID_} bump → reinstall" \
    test "$(_android_decision "${_want}" "${_bumped[@]}")" = "reinstall"
done

# ─── Section 28: 00base + phpmyadmin gates (row 21, part 1) ───────────────
printf '\n%b── Section 28: 00base install + phpmyadmin gates%b\n' "${C_BOLD}" "${C_RESET}"

# Row 21. The 00base tools (go, zig, hurl, mise) are installed AT RUNTIME by
# global-stack-base-start.sh, not at image build — the 5a audit found them because
# they arrive by image ENV and therefore look build-time. All four were exist-only.
# awscli is deliberately absent: it has no .env version var at all (its guard is
# `! -d`), so there is nothing to gate.
for _t in go zig hurl mise; do
  _f="${DIST_BIN}/base-bin/global-stack-base-install-${_t}.sh"
  assert_pass "28a: base-install-${_t} sources the gate helper ALONE" \
    grep -q '^source global-stack-base-version-gate\.sh$' "${_f}"
  assert_fail "28a: base-install-${_t} does NOT source the prologue" \
    grep -q 'global-stack-base-prologue\.sh' "${_f}"
  assert_pass "28b: base-install-${_t} gates on base.${_t}" \
    grep -q "gs_version_gate .*VERSIONS}/base\.${_t}\"" "${_f}"
  assert_pass "28b: base-install-${_t} writes its marker" \
    grep -q "printf '%s\\\\n'.*VERSIONS}/base\.${_t}\"" "${_f}"
done

assert_fail "28c: awscli is NOT gated (it has no .env version var)" \
  grep -q 'gs_version_gate' "${DIST_BIN}/base-bin/global-stack-base-install-awscli.sh"

# phpmyadmin: three exist-only guards, and a marker write that sat OUTSIDE every
# condition so it was refreshed on every boot and could never be compared.
PMA="${DIST_BIN}/phpmyadmin-bin/global-stack-phpmyadmin-start.sh"
assert_pass "28d: phpmyadmin composes a version+type marker" \
  grep -q '^_pma_want=.*PHPMYADMIN_VERSION.*PHPMYADMIN_TYPE_VERSION' "${PMA}"
_pma_guards="$(grep -c '\[ "${_pma_install}" = "1" \]' "${PMA}" || true)"
assert_pass "28d: all three phpmyadmin branches use the gate decision" \
  test "${_pma_guards}" = "3"
assert_fail "28e: no exist-only phpmyadmin marker guard remains" \
  grep -q '! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin"' "${PMA}"
# the marker write must now be indented INSIDE the install branch, not at column 0
assert_fail "28e: the phpmyadmin marker write is no longer top-level" \
  grep -q '^printf .*VERSIONS}/phpmyadmin"' "${PMA}"

# ── behavioural: the base-install gate decision, extracted by pattern ──
_base_tool_decision() {
  local tool="$1" marker_body="$2" pin="$3" root="${TMP_DIR}/basetool" var
  case "${tool}" in
    go) var=GLOBAL_STACK_GO_VERSION ;; zig) var=GLOBAL_STACK_ZIG_VERSION ;;
    hurl) var=GLOBAL_STACK_HURL_VERSION ;; mise) var=GLOBAL_STACK_MISE_VERSION ;;
  esac
  rm -rf "${root}"; mkdir -p "${root}/vers"
  {
    printf '#!/bin/bash\nset -euo pipefail\n'
    printf 'source global-stack-base-version-gate.sh\n'
    grep -m1 "^_${tool}_gate=" "${DIST_BIN}/base-bin/global-stack-base-install-${tool}.sh" || true
    printf 'printf "DECISION=%%s\\n" "${_%s_gate:-<no-gate>}"\n' "${tool}"
  } >"${root}/block.sh"
  [[ -n "${marker_body}" ]] && printf '%s\n' "${marker_body}" >"${root}/vers/base.${tool}"
  env PATH="${DIST_BIN}/base-bin:${PATH}" "${var}=${pin}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${root}/vers" \
    bash "${root}/block.sh" 2>/dev/null | sed -n 's/^DECISION=//p' || true
}

for _t in go zig hurl mise; do
  assert_pass "28f: ${_t} no marker → install" \
    test "$(_base_tool_decision "${_t}" "" 1.0.0)" = "install"
  assert_pass "28f: ${_t} marker matches → skip" \
    test "$(_base_tool_decision "${_t}" 1.0.0 1.0.0)" = "skip"
  # THE DEFECT: these bumps previously did nothing — the guard only asked whether
  # the binary was on PATH.
  assert_pass "28g: ${_t} pin bumped → reinstall" \
    test "$(_base_tool_decision "${_t}" 1.0.0 1.0.1)" = "reinstall"
done

# ─── Section 29: elasticmq, rbenv plugins, frankenphp (row 21, part 2) ────
printf '\n%b── Section 29: elasticmq / rbenv plugins / frankenphp%b\n' "${C_BOLD}" "${C_RESET}"

SLS="${DIST_BIN}/serverless-bin/global-stack-serverless-framework-start.sh"
RBIOU="${DIST_BIN}/rbenv-bin/global-stack-rbenv-iou.sh"
FRANKEN="${DIST_BIN}/php8.4-bin/global-stack-phpbrew-php8.4-setup-version.sh"

# elasticmq downloads to a FIXED filename, so an exist-only guard pinned the old
# jar forever.
assert_pass "29a: elasticmq is gated" \
  grep -q 'gs_version_gate .*VERSIONS}/serverless\.elasticmq"' "${SLS}"
assert_pass "29a: elasticmq writes its marker" \
  grep -q "printf '%s\\\\n'.*VERSIONS}/serverless\.elasticmq\"" "${SLS}"

# The rbenv plugins must be gated INDEPENDENTLY of the rbenv fresh-clone branch:
# nested inside it, a plugin-only bump did nothing and an rbenv bump re-cloned both.
for _p in ruby-build gemset; do
  assert_pass "29b: rbenv ${_p} plugin is gated" \
    grep -q "gs_version_gate .*VERSIONS}/rbenv\.${_p}\"" "${RBIOU}"
done
# structural: neither plugin clone may sit inside the `! -d ${RBENV_ROOT}/.git` block
_rb_nested="$(awk '
  /^if \[ ! -d "\$\{RBENV_ROOT\}\/\.git" \]; then/ { inblk=1; next }
  inblk && /^fi$/ { inblk=0; next }
  inblk && /plugins\/(ruby-build|rbenv-gemset)/ { n++ }
  END { print n+0 }
' "${RBIOU}")"
assert_pass "29b: no plugin clone remains inside the rbenv fresh-clone branch" \
  test "${_rb_nested}" = "0"

# frankenphp is deliberately NOT gated: its artifact path embeds the version, so a
# bump already downloads a different file. A marker would be redundant state.
assert_fail "29c: frankenphp is deliberately NOT gated (path-keyed by version)" \
  grep -q 'gs_version_gate' "${FRANKEN}"
assert_pass "29c: frankenphp's artifact path still embeds its version" \
  grep -q 'frankenphp-\${GLOBAL_STACK_FRANKENPHP_VERSION}\.tar\.gz' "${FRANKEN}"

# ── behavioural: elasticmq + both rbenv plugins ──
_r21_decision() {
  local anchor="$1" marker="$2" body="$3" pin="$4" var="$5" file="$6"
  local root="${TMP_DIR}/r21"
  rm -rf "${root}"; mkdir -p "${root}/vers"
  # the anchor carries the source file's indentation; strip it before deriving the
  # variable name, or the generated script references a name containing spaces.
  local varname="${anchor%%=*}"
  varname="${varname#"${varname%%[![:space:]]*}"}"
  { printf '#!/bin/bash\nset -e\n'
    printf 'source global-stack-base-version-gate.sh\n'
    grep -m1 "^${anchor}" "${file}" || true
    printf 'printf "DECISION=%%s\\n" "${%s:-<no-gate>}"\n' "${varname}"
  } >"${root}/block.sh"
  [[ -n "${body}" ]] && printf '%s\n' "${body}" >"${root}/vers/${marker}"
  env PATH="${DIST_BIN}/base-bin:${PATH}" "${var}=${pin}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${root}/vers" \
    bash "${root}/block.sh" 2>/dev/null | sed -n 's/^DECISION=//p' || true
}

assert_pass "29d: elasticmq no marker → install" \
  test "$(_r21_decision '_elasticmq_gate=' serverless.elasticmq "" v1.0 GLOBAL_STACK_SERVERLESS_FRAMEWORK_ELASTICMQ_VERSION "${SLS}")" = "install"
assert_pass "29d: elasticmq marker matches → skip" \
  test "$(_r21_decision '_elasticmq_gate=' serverless.elasticmq v1.0 v1.0 GLOBAL_STACK_SERVERLESS_FRAMEWORK_ELASTICMQ_VERSION "${SLS}")" = "skip"
assert_pass "29e: elasticmq pin bumped → reinstall" \
  test "$(_r21_decision '_elasticmq_gate=' serverless.elasticmq v1.0 v1.1 GLOBAL_STACK_SERVERLESS_FRAMEWORK_ELASTICMQ_VERSION "${SLS}")" = "reinstall"
assert_pass "29f: rbenv ruby-build pin bumped → reinstall" \
  test "$(_r21_decision '  _rb_build_gate=' rbenv.ruby-build v1.0 v1.1 GLOBAL_STACK_RBENV_RUBY_BUILD_VERSION "${RBIOU}")" = "reinstall"
assert_pass "29f: rbenv gemset pin unchanged → skip" \
  test "$(_r21_decision '  _rb_gemset_gate=' rbenv.gemset v2.0 v2.0 GLOBAL_STACK_RBENV_GEMSET_VERSION "${RBIOU}")" = "skip"

# ─── Section 30: web-server gates (row 20) ────────────────────────────────
printf '\n%b── Section 30: web-server version gates%b\n' "${C_BOLD}" "${C_RESET}"

# Row 20, the last Track 5b migration. These 17 sites already compared correctly —
# { ! -e P || $(cat P) != $V } is exactly `gate != skip` — so this row buys the
# WARN and ONE idiom, not new detection. All three servers are prologue-EXEMPT, so
# every one of them sources the helper ALONE: this row is why row 15 existed.
declare -a _WS_FILES=(
  "httpd-bin/global-stack-httpd-start.sh"
  "httpd-bin/global-stack-httpd-iou-common.sh"
  "nginx-bin/global-stack-nginx-start.sh"
  "nginx-bin/global-stack-nginx-iou-common.sh"
  "nginx-bin/global-stack-nginx-iou.sh"
  "caddy-bin/global-stack-caddy-start.sh"
)

for _f in "${_WS_FILES[@]}"; do
  assert_pass "30a: ${_f##*/} sources the gate helper ALONE" \
    grep -q '^source global-stack-base-version-gate\.sh$' "${DIST_BIN}/${_f}"
  assert_fail "30a: ${_f##*/} does NOT source the prologue (stays exempt)" \
    grep -q 'global-stack-base-prologue\.sh' "${DIST_BIN}/${_f}"
  assert_pass "30a: ${_f##*/} still passes bash -n" bash -n "${DIST_BIN}/${_f}"
done

# THE CONVERGENCE: not one hand-rolled marker compare may remain in any of the
# three web-server trees. This is the assertion that makes "one idiom" checkable.
_ws_handrolled=0
while IFS= read -r -d '' _f; do
  _n="$(grep -c 'cat "\${[A-Z_]*VERSION\(S\)\?_PATH}")" !=' "${_f}" || true)"
  _ws_handrolled=$((_ws_handrolled + _n))
done < <(find "${DIST_BIN}/nginx-bin" "${DIST_BIN}/httpd-bin" "${DIST_BIN}/caddy-bin" -name '*.sh' -print0)
assert_pass "30b: zero hand-rolled marker compares remain in the web-server trees" \
  test "${_ws_handrolled}" = "0"

# Each server's own version is gated (these three were missed by an earlier count
# that only matched the singular *_VERSION_PATH spelling).
assert_pass "30c: nginx gates its own version" \
  grep -q 'gs_version_gate "\${NGINX_VERSIONS_PATH}"' "${DIST_BIN}/nginx-bin/global-stack-nginx-start.sh"
assert_pass "30c: httpd gates its own version" \
  grep -q 'gs_version_gate "\${HTTPD_VERSIONS_PATH}"' "${DIST_BIN}/httpd-bin/global-stack-httpd-start.sh"
assert_pass "30c: caddy gates its own version" \
  grep -q 'gs_version_gate "\${CADDY_VERSIONS_PATH}"' "${DIST_BIN}/caddy-bin/global-stack-caddy-start.sh"

# The shared-marker invariant must survive: all three still write ONE
# successes/web-server, and each keeps its own distinct error token (F4).
for _s in caddy nginx httpd; do
  assert_pass "30d: ${_s} still writes the shared successes/web-server marker" \
    grep -q 'SUCCESSES}/web-server' "${DIST_BIN}/${_s}-bin/global-stack-${_s}-start.sh"
done

# ── behavioural: one gate per server, driven from a fixture tree ──
_ws_decision() {
  local anchor="$1" marker="$2" body="$3" pin="$4" var="$5" pathvar="$6" file="$7"
  local root="${TMP_DIR}/ws"
  rm -rf "${root}"; mkdir -p "${root}/vers"
  { printf '#!/bin/bash\nset -e\n'
    printf 'source global-stack-base-version-gate.sh\n'
    printf '%s="%s/vers/%s"\n' "${pathvar}" "${root}" "${marker}"
    grep -m1 "^${anchor}" "${file}" || true
    printf 'printf "DECISION=%%s\\n" "${%s:-<no-gate>}"\n' "${anchor%%=*}"
  } >"${root}/block.sh"
  [[ -n "${body}" ]] && printf '%s\n' "${body}" >"${root}/vers/${marker}"
  env PATH="${DIST_BIN}/base-bin:${PATH}" "${var}=${pin}" \
    bash "${root}/block.sh" 2>/dev/null | sed -n 's/^DECISION=//p' || true
}

assert_pass "30e: nginx unchanged pin → skip" \
  test "$(_ws_decision _ngx_gate nginx 1.0 1.0 GLOBAL_STACK_NGINX_VERSION NGINX_VERSIONS_PATH "${DIST_BIN}/nginx-bin/global-stack-nginx-start.sh")" = "skip"
assert_pass "30e: nginx bumped pin → reinstall" \
  test "$(_ws_decision _ngx_gate nginx 1.0 1.1 GLOBAL_STACK_NGINX_VERSION NGINX_VERSIONS_PATH "${DIST_BIN}/nginx-bin/global-stack-nginx-start.sh")" = "reinstall"
assert_pass "30f: httpd bumped pin → reinstall" \
  test "$(_ws_decision _httpd_gate httpd 2.4.1 2.4.2 GLOBAL_STACK_HTTPD_VERSION HTTPD_VERSIONS_PATH "${DIST_BIN}/httpd-bin/global-stack-httpd-start.sh")" = "reinstall"
assert_pass "30f: caddy no marker → install" \
  test "$(_ws_decision _caddy_gate caddy "" 2.8 GLOBAL_STACK_CADDY_VERSION CADDY_VERSIONS_PATH "${DIST_BIN}/caddy-bin/global-stack-caddy-start.sh")" = "install"

# ─── §31: sdkman guard shape + slot-loop stdin (2026-09-10) ──────────────────
# Two silent-failure regressions found after the first `make hard-restart`.
#
# 31a-c: `sdk use` returns 0 on success; the non-zero that reaches a caller comes from
# __sdkman_path_contains (tools/sdkman/src/sdkman-path-helpers.sh:23) grepping $PATH as a
# boolean, two levels deep inside $(...). Errexit is auto-unset in a command substitution,
# so it is the INHERITED ERR TRAP that fires -- `set +e` leaves the trap armed and never
# suppressed it, which killed 04serverless-framework outright. `set +E` disarms trap
# inheritance while keeping the trap live at the call site, so a genuine failure is still
# reported. A condition context (`if sdk use ...; then :; fi`) also survives the benign
# case but SWALLOWS real failures -- 31c is what reds if anyone "simplifies" it that way.
_sdkman_guard() { # $1=shape(old|new|cond) $2=mode(ok|fail)
  ( set -eE -o pipefail
    _C=0; stackCatch(){ [[ ${_C} = 1 ]] && return; _C=1; echo "TOKEN"; exit 1; }
    trap 'stackCatch' ERR
    source "${REPO_ROOT}/tools/sdkman/src/sdkman-path-helpers.sh"
    HOME=/nonexistent-gs-test; PATH="/usr/bin:/bin"
    _u(){ [[ "$2" = fail ]] && return 1; __sdkman_add_to_path java; }
    case "$1" in
      old)  set +e; _u "$1" "$2"; set -e ;;
      new)  set +E; _u "$1" "$2"; set -E ;;
      cond) if _u "$1" "$2"; then :; fi ;;
    esac
    echo "CONTINUED" ) 2>/dev/null | grep -Eo 'TOKEN|CONTINUED' | head -1
}
assert_pass "31a: benign nested-grep miss -- 'set +e' aborts (the serverless bug)" \
  test "$(_sdkman_guard old ok)" = "TOKEN"
assert_pass "31b: benign nested-grep miss -- 'set +E' continues" \
  test "$(_sdkman_guard new ok)" = "CONTINUED"
assert_pass "31c: a REAL sdk-use failure still reports under 'set +E'" \
  test "$(_sdkman_guard new fail)" = "TOKEN"
assert_pass "31c: a condition context would SWALLOW that real failure -- do not use one" \
  test "$(_sdkman_guard cond fail)" = "CONTINUED"
_SV="${DIST_BIN}/serverless-bin/global-stack-serverless-framework-start.sh"
assert_fail "31d: serverless carries no bare 'set +e' / 'set -e' (must be +E/-E)" \
  grep -Eq '^[[:space:]]*set [+-]e[[:space:]]*$' "${_SV}"
assert_pass "31d: serverless arms the errtrace guard around sdk use" \
  grep -Eq '^[[:space:]]*set \+E[[:space:]]*$' "${_SV}"

# 31e-f: the slot loop fed `compgen | grep | sort | while read`. A prompting child inside
# the loop body inherits the loop's stdin and eats the remaining slot list -- one package
# silently vanished (kotlin, slot 3 of 4) with no error anywhere. Process substitution
# alone is NOT sufficient: the body still inherits that FD. Each eval needs </dev/null.
_SP="${DIST_BIN}/base-bin/global-stack-base-setup-packages.sh"
assert_fail "31e: slot loop is not fed by a pipeline (subshell + stdin theft)" \
  grep -Eq 'compgen -A variable \| grep .* \| sort \| while read' "${_SP}"
assert_pass "31e: slot loop reads from process substitution" \
  grep -Eq 'done < <\(compgen -A variable' "${_SP}"
assert_fail "31f: no eval of a caller command leaves stdin open (all have </dev/null)" \
  bash -c 'grep -E "^[[:space:]]*eval \"\\$\\{(COMMANDS|CLEANUP_COMMAND)" "$1" | grep -qv "</dev/null"' _ "${_SP}"

# ─── §32: the sdk-init patch is actually deployed (2026-09-10) ───────────────
# conf/sdkman/sdk-init/sdkman-init.sh carries an `@changed stack` block sourcing
# ${HOME}/.sdkman/etc/config at INIT time. It is registered in .env as one of three
# hand-patched fork artifacts, but was rsynced nowhere -- so every `sdk` call ran
# __sdkman_update_service_availability (sdkman-main.sh:81) BEFORE either config load
# (:84, :88), i.e. a live curl with connect_timeout=7 / max_time=10 on every call.
# The rsync must land AFTER the conf/sdkman/bin/ rsync (which targets the same dir).
# The installer is idempotent (`if [ -d "$SDKMAN_DIR" ]` -> exit 0), so the second
# installer run cannot undo it.
_SDKI="${DIST_BIN}/sdkman-bin/global-stack-sdkman-start.sh"
assert_pass "32a: sdk-init/ is rsynced into \${SDKMAN_DIR}/bin" \
  grep -Eq 'rsync .*conf/sdkman/sdk-init/ +"\$\{SDKMAN_DIR\}"/bin' "${_SDKI}"
assert_pass "32b: the sdk-init rsync comes AFTER the conf/sdkman/bin/ rsync" \
  bash -c 'b=$(grep -n "conf/sdkman/bin/" "$1" | tail -1 | cut -d: -f1); i=$(grep -n "conf/sdkman/sdk-init/" "$1" | tail -1 | cut -d: -f1); [ -n "$b" ] && [ -n "$i" ] && [ "$i" -gt "$b" ]' _ "${_SDKI}"
assert_pass "32c: the shipped sdk-init still carries the @changed stack block" \
  grep -q '@changed stack' "${REPO_ROOT}/docker/config/dist/conf/sdkman/sdk-init/sdkman-init.sh"
assert_pass "32c: ...and that block sources \${HOME}/.sdkman/etc/config" \
  grep -Eq 'source "\$\{HOME\}/\.sdkman/etc/config"' "${REPO_ROOT}/docker/config/dist/conf/sdkman/sdk-init/sdkman-init.sh"
assert_pass "32d: .env still records sdk-init as a hand-patched fork artifact" \
  grep -q 'conf/sdkman/sdk-init/sdkman-init.sh' "${REPO_ROOT}/.env"
assert_pass "32e: the per-container \${HOME}/.sdkman/etc/config write is still present" \
  grep -Eq 'echo "sdkman_healthcheck_enable=false" > "\$\{HOME\}/\.sdkman/etc/config"' "${_SDKI}"
# §32h: token invariant drift guard for serverless -- the success-write literal must equal
# the GLOBAL_STACK_ERROR_TOKEN declared in its compose file. They agree today; nothing
# pinned them, so a rename in compose would silently leave a permanently-unhealthy-yet-
# functional container, masked by start_period: 24h. Same shape as §21's web-server guard.
_SLS_TOKEN="$(sed -n 's/.*GLOBAL_STACK_ERROR_TOKEN=\([A-Za-z0-9_.-]*\).*/\1/p' \
  "${REPO_ROOT}/docker/images/04serverless-framework/docker-compose.yaml" | head -1)"
assert_pass "32h: serverless compose declares a non-empty GLOBAL_STACK_ERROR_TOKEN" \
  test -n "${_SLS_TOKEN}"
assert_pass "32h: serverless success write uses that exact token (no drift)" \
  grep -Eq "TOOLS_PATH_SUCCESSES\}\"?/${_SLS_TOKEN}\"?\$" \
    "${DIST_BIN}/serverless-bin/global-stack-serverless-framework-start.sh"
assert_pass "32h: serverless healthcheck polls that exact token" \
  grep -q "SUCCESSES}/${_SLS_TOKEN}" "${REPO_ROOT}/docker/images/04serverless-framework/docker-compose.yaml"

# ─── §33: gem install is not run in rubygems debug mode (2026-09-10) ─────────
# `gem --debug` means "Turn on Ruby debugging" (rubygems/command.rb:617) and prints every
# exception rubygems RESCUES -- cache-miss stats in remote_fetcher.rb:288, file-walk misses
# in fileutils.rb. Measured on a healthy run: 15613/19056 log lines in 03ruby3 (81%) and
# 10807/14259 in 03ruby4 (75%) were rescued-exception prints, with both containers healthy
# and their success markers present. That volume buries a real failure.
# `--backtrace` is KEPT: it is "Show stack backtrace on errors" (command.rb:613), which is
# what actually helps when a gem install fails.
_RBE="${DIST_BIN}/rbenv-bin/global-stack-rbenv-start.sh"
assert_fail "33a: gem install does not pass --debug (rescued-exception spam)" \
  grep -Eq "gem[^']*--debug[^']*install" "${_RBE}"
assert_pass "33b: gem install still passes --backtrace (errors stay diagnosable)" \
  grep -Eq "gem[^']*--backtrace[^']*install" "${_RBE}"

# ─── §34: the sdkman lock is UNCONDITIONAL by design (2026-09-10) ────────────
# Every other manager (fvm/nvm/phpbrew/pyenv/rbenv) gates its flock on
# GLOBAL_STACK_USE_LOCKS. sdkman deliberately does NOT: 02sdkman and 03java17/21/26 share
# one ${SDKMAN_DIR} on the tools volume, and installing several java versions at once
# fails -- sdkman errors (developer ruling, 2026-09-10). The guard used to be present as
# COMMENTED-OUT code, which reads as an accident and invites a "fix" that reintroduces the
# breakage. These assertions pin the intent so that cannot happen silently.
_SDKL="${DIST_BIN}/sdkman-bin/global-stack-sdkman-start.sh"
assert_pass "34a: sdkman takes its flock" \
  grep -Eq 'exec 200>"\$\{GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS\}/sdkman\.flock"' "${_SDKL}"
assert_fail "34b: the sdkman flock is NOT gated on GLOBAL_STACK_USE_LOCKS" \
  bash -c 'grep -B3 "exec 200>.*sdkman\.flock" "$1" | grep -q "USE_LOCKS"' _ "${_SDKL}"
assert_fail "34c: no commented-out USE_LOCKS guard is left to look like an accident" \
  grep -Eq '^[[:space:]]*#[[:space:]]*(if \[\[ "true" = "\$\{GLOBAL_STACK_USE_LOCKS\}"|fi)[[:space:]]*$' "${_SDKL}"
assert_pass "34d: the file states WHY it is unconditional (shared SDKMAN_DIR)" \
  grep -q 'UNCONDITIONAL by design' "${_SDKL}"
assert_pass "34d: ...and names the shared-dir reason, not just the word" \
  bash -c 'grep -A4 "UNCONDITIONAL by design" "$1" | grep -q "SDKMAN_DIR"' _ "${_SDKL}"
assert_pass "34e: sibling managers DO honour the flag (rbenv as reference)" \
  bash -c 'grep -B3 "exec 200>.*rbenv\.flock" "$1" | grep -q "USE_LOCKS"' _ "${DIST_BIN}/rbenv-bin/global-stack-rbenv-start.sh"

# ─── §35: container timezones (2026-09-10) ──────────────────────────────────
# Measured on a live stack: every stack container reported CEST except four.
#   it-tools     TZ unset,     tzdata present -> plain UTC
#   oracle       TZ declared,  tzdata ABSENT  -> runs UTC, prints the literal "Europe"
#   mongoclient  TZ declared,  tzdata ABSENT  -> same
#   registry     TZ unset,     tzdata ABSENT, Alpine, no Dockerfile (Makefile docker run)
# The mislabel is worse than plain UTC: "14:17 Europe" reads as local time while the host
# is 16:17 CEST, so anyone correlating tools/elapsed across containers is off by two hours.
# registry is deliberately NOT fixed -- setting TZ without tzdata would turn its honest UTC
# into the mislabelled form. GLOBAL_STACK_TIMEZONE is the canonical var (00base Dockerfile).
_TZ_IT="${REPO_ROOT}/docker/images/00corentinth-it-tools/docker-compose.yaml"
_TZ_OR="${REPO_ROOT}/docker/images/01epiclabs-docker-oracle-xe-11g"
_TZ_MO="${REPO_ROOT}/docker/images/02mongoclient-mongoclient"
assert_pass "35a: it-tools declares TZ from GLOBAL_STACK_TIMEZONE" \
  grep -Eq '^\s*-\s*TZ=\$\{GLOBAL_STACK_TIMEZONE\}' "${_TZ_IT}"
assert_pass "35b: oracle still declares TZ" \
  grep -Eq '^\s*-\s*TZ=\$\{GLOBAL_STACK_TIMEZONE\}' "${_TZ_OR}/docker-compose.yaml"
assert_pass "35b: oracle installs tzdata (in the RUN, not just a comment)" \
  bash -c 'grep -A6 "apt-get install" "$1" | grep -Eq "^\\s*tzdata\\s*\\\\?\\s*$"' _ "${_TZ_OR}/Dockerfile"
assert_pass "35b: oracle reconfigures tzdata non-interactively" \
  bash -c 'grep -q "dpkg-reconfigure tzdata" "$1" && grep -q "DEBIAN_FRONTEND" "$1"' _ "${_TZ_OR}/Dockerfile"
assert_pass "35c: mongoclient still declares TZ" \
  grep -Eq '^\s*-\s*TZ=\$\{GLOBAL_STACK_TIMEZONE\}' "${_TZ_MO}/docker-compose.yaml"
# mongoclient CANNOT install tzdata itself, so it is pinned differently from oracle. Its base
# is Debian 8 jessie: the archived suites 404 on deb.debian.org so `apt-get update` exits 100,
# AND the image was slimmed by deleting /usr/share/zoneinfo without telling dpkg -- which still
# reports tzdata 2019c "install ok installed" owning 1902 files, making `apt-get install tzdata`
# a SILENT no-op. The zone files therefore come from a pinned ubuntu build stage; pin the
# MECHANISM THAT ACTUALLY SHIPS THEM, not the apt spelling that cannot work here.
# Comment lines are stripped in §35c/§35e: both Dockerfiles now EXPLAIN the flag they must not
# use, and a raw grep would match that prose (the self-referential-guard trap).
assert_pass "35c: mongoclient's tzdata_source stage installs tzdata" \
  bash -c 'grep -vE "^[[:space:]]*#" "$1" | grep -A6 "apt-get install" | grep -Eq "^[[:space:]]*tzdata[[:space:]]*.?[[:space:]]*$"' _ "${_TZ_MO}/Dockerfile"
assert_pass "35c: mongoclient copies zoneinfo in from that stage" \
  bash -c 'grep -vE "^[[:space:]]*#" "$1" | grep -qxF "COPY --from=tzdata_source /usr/share/zoneinfo /usr/share/zoneinfo"' _ "${_TZ_MO}/Dockerfile"
assert_pass "35c: that stage is the PINNED ubuntu var, not a floating tag" \
  bash -c 'grep -vE "^[[:space:]]*#" "$1" | grep -qxF "FROM ubuntu:\${GLOBAL_STACK_IMAGE_UBUNTU_VERSION} AS tzdata_source"' _ "${_TZ_MO}/Dockerfile"

# ─── §35e: the two FOREIGN-BASE images predate --allow-releaseinfo-change ────
# 1aa924f copied 00base's apt idiom into the only two images that do NOT descend from 00base.
# Both reject the option outright -- apt 1.2.32 (Ubuntu 16.04 xenial) and apt 1.0.9.8.6
# (Debian 8 jessie) vs the apt 1.9.3 that introduced it -- with
#   E: Command line option --allow-releaseinfo-change is not understood [...]
# exit 100, which stops the whole build. This is a static guard; §35c pins what replaced it.
assert_pass "35e: oracle carries no --allow-releaseinfo-change (apt 1.2.32)" \
  bash -c '! grep -vE "^[[:space:]]*#" "$1" | grep -q -- "--allow-releaseinfo-change"' _ "${_TZ_OR}/Dockerfile"
assert_pass "35e: mongoclient carries no --allow-releaseinfo-change (apt 1.0.9.8.6)" \
  bash -c '! grep -vE "^[[:space:]]*#" "$1" | grep -q -- "--allow-releaseinfo-change"' _ "${_TZ_MO}/Dockerfile"
# Non-vacuity floor: the option is CORRECT on 00base's modern Ubuntu and must still be there.
# If this reds, the comment-stripping grep above stopped matching and both checks are vacuous.
assert_pass "35e: non-vacuity -- 00base DOES still use the option" \
  bash -c 'grep -vE "^[[:space:]]*#" "$1" | grep -q -- "--allow-releaseinfo-change"' _ "${REPO_ROOT}/docker/images/00base/Dockerfile"
assert_pass "35d: GLOBAL_STACK_TIMEZONE is defined in .env" \
  grep -Eq '^GLOBAL_STACK_TIMEZONE=.+' "${REPO_ROOT}/.env"

# ─── §36: the hadolint ignore list is actually honoured (2026-09-10) ─────────
# .hadolint.yaml used the key `ignore:`. hadolint expects `ignored:` and silently accepts
# (and discards) the unknown key, so the documented DL3008/DL3018 ruling was INERT and the
# PostToolUse hook reported them on every parseable Dockerfile. Auto-discovery works once
# the key is right -- `--config` was never the problem. Verified against hadolint 2.15.1:
#   ignore:  -> DL3008 still reported;  ignored: -> suppressed, with and without --config.
_HL="${REPO_ROOT}/.hadolint.yaml"
assert_pass "36a: .hadolint.yaml uses the key hadolint actually reads" \
  grep -Eq '^ignored:' "${_HL}"
assert_fail "36a: ...and not the silently-discarded 'ignore:'" \
  grep -Eq '^ignore:' "${_HL}"
assert_pass "36b: the ruling's codes are LIST ENTRIES, not just mentioned in prose" \
  bash -c 'grep -Eq "^[[:space:]]+-[[:space:]]*DL3008[[:space:]]*$" "$1" \
        && grep -Eq "^[[:space:]]+-[[:space:]]*DL3018[[:space:]]*$" "$1"' _ "${_HL}"
# Functional check: an unpinned apt-get install must lint clean from the repo root.
_hl_probe() {
  local d="${TMP_DIR}/hlprobe"; mkdir -p "${d}"
  cp "${_HL}" "${d}/.hadolint.yaml"
  printf 'FROM ubuntu:24.04\nRUN apt-get update && apt-get install -y curl\n' >"${d}/Dockerfile"
  ( cd "${d}" && hadolint Dockerfile 2>&1 | grep -c 'DL3008' || true )
}
assert_pass "36c: an unpinned apt-get install reports no DL3008 under this config" \
  test "$(_hl_probe)" = "0"

# ─── §37: a hadolint PARSE FAILURE is reported as unchecked (2026-09-10) ─────
# hadolint 2.15.1 cannot parse `FROM ${ALIAS}:${PORT}/img:${VER}` -- 33 of this repo's 43
# Dockerfiles use that shape, and Docker builds them all fine, so this is an upstream
# parser limitation, not a defect in the Dockerfiles. The danger is that a parse failure
# yields ZERO findings, which reads as clean: those 33 files have had no lint coverage at
# all. The hook used to fold it into "hadolint found N issue(s)". It must say the file was
# NOT LINTED. Restructuring the FROM lines is deliberately out of scope (developer ruling).
_HOOK="${REPO_ROOT}/.claude/hooks/hadolint-on-write.sh"
_hook_msg() { # $1 = Dockerfile content
  local d="${TMP_DIR}/hookprobe"; mkdir -p "${d}"
  printf '%s\n' "$1" >"${d}/Dockerfile"
  printf '{"tool_input":{"file_path":"%s/Dockerfile"}}' "${d}" \
    | bash "${_HOOK}" 2>/dev/null || true
}
assert_output_contains "37a: an unparseable FROM is reported as NOT LINTED" "NOT LINTED" \
  _hook_msg 'ARG A=r.local
ARG P=5000
ARG V=1
FROM ${A}:${P}/img:${V}'
assert_pass "37b: a parseable Dockerfile is NOT reported as unlinted" \
  bash -c '! printf "{\"tool_input\":{\"file_path\":\"%s\"}}" "$2" | bash "$1" 2>/dev/null | grep -q "NOT LINTED"' \
    _ "${_HOOK}" "${REPO_ROOT}/docker/images/02mongoclient-mongoclient/Dockerfile"
assert_pass "37c: the hook still reports ordinary findings" \
  grep -q 'issue(s)' "${_HOOK}"

# ─── §38: the home rsync excludes the bind-mounted history files (2026-09-10) ─
# /stack/docker/config/root is bind-mounted BOTH as the rsync source (/stack/dist/home/user)
# and as the two destination files (/home/developer/.bash_history, .zsh_history), so rsync
# copied each history file ONTO ITSELF and failed to rename over its own bind mount:
#   rsync: [receiver] rename ".bash_history.XXXXXX" -> ".bash_history": Device or resource busy
#   rsync error: some files/attrs were not transferred (code 23)
# 28 of 45 running containers emitted that every boot. Verified by inode: the source and
# destination paths are the SAME file (33030169 / 33075857). Shared history comes from the
# BIND MOUNT, not from this rsync -- the rsync of these two files has never once succeeded,
# and sharing works regardless. Excluding them removes an operation that always failed and
# restores meaning to exit 23, which the guard below otherwise swallows wholesale.
_CH="${DIST_BIN}/base-bin/global-stack-base-chown-home.sh"
assert_pass "38a: the home rsync excludes the bind-mounted bash history" \
  grep -Eq -- '--exclude=[^ ]*\.bash_history' "${_CH}"
assert_pass "38a: ...and the zsh history" \
  grep -Eq -- '--exclude=[^ ]*\.zsh_history' "${_CH}"
assert_pass "38b: the narrow code-23 guard is still there as a real safety net" \
  bash -c 'grep -q "_rsync_exit -eq 23" "$1" && grep -q "exit \$_rsync_exit" "$1"' _ "${_CH}"
# Drift guard: the excluded literals must match what compose actually bind-mounts.
_bh="$(sed -n 's/^GLOBAL_STACK_SHELL_HISTORY_TARGET=//p' "${REPO_ROOT}/.env" | head -1)"
_zh="$(sed -n 's/^GLOBAL_STACK_SHELL_ZSH_HISTORY_TARGET=//p' "${REPO_ROOT}/.env" | head -1)"
assert_pass "38c: .env still defines both history targets" \
  bash -c '[ -n "$1" ] && [ -n "$2" ]' _ "${_bh}" "${_zh}"
assert_pass "38c: the excludes match GLOBAL_STACK_SHELL_HISTORY_TARGET" \
  grep -qF -- "--exclude=${_bh}" "${_CH}"
assert_pass "38c: the excludes match GLOBAL_STACK_SHELL_ZSH_HISTORY_TARGET" \
  grep -qF -- "--exclude=${_zh}" "${_CH}"

# ─── §39: caddy plugins are pinned like the core (2026-09-10) ───────────────
# The caddy CORE is pinned (`git clone --branch "${GLOBAL_STACK_CADDY_VERSION}"`) but its
# four plugins were fetched by `caddy add-package <module>` with no version, so Go resolved
# whatever was latest at build time and nothing recorded the result. Measured on the running
# container: http.encoders.br v1.6.0, http.handlers.cache v0.16.0, security v1.1.64, and
# caddy.logging.encoders.transform v0.0.0-20260423033309-ba4124974830 -- a Go PSEUDO-version,
# i.e. that module has no tagged release at all and tracks a commit. Two builds from one
# commit could differ. None of the four had an .env entry, so env-update could not see them.
_CIOU="${DIST_BIN}/caddy-bin/global-stack-caddy-iou.sh"
assert_fail "39a: no add-package call is left unpinned" \
  bash -c 'grep -E "caddy add-package [^@]+$" "$1" | grep -qv "^[[:space:]]*#"' _ "${_CIOU}"
for _p in TRANSFORM_ENCODER BROTLI SECURITY CACHE_HANDLER; do
  assert_pass "39b: .env defines GLOBAL_STACK_CADDY_${_p}_VERSION" \
    grep -Eq "^GLOBAL_STACK_CADDY_${_p}_VERSION=.+" "${REPO_ROOT}/.env"
  assert_pass "39b: ...and it carries an @todo env-update annotation" \
    bash -c 'grep -B1 "^GLOBAL_STACK_CADDY_${2}_VERSION=" "$1" | grep -q "@todo env-update"' \
      _ "${REPO_ROOT}/.env" "${_p}"
  assert_pass "39c: 01caddy plumbs GLOBAL_STACK_CADDY_${_p}_VERSION into the container" \
    grep -q "GLOBAL_STACK_CADDY_${_p}_VERSION=\${GLOBAL_STACK_CADDY_${_p}_VERSION}" \
      "${REPO_ROOT}/docker/images/01caddy/docker-compose.yaml"
done
assert_fail "39d: the caddy script no longer claims to be Httpd" \
  grep -q 'Httpd is already the latest version' "${_CIOU}"

# ─── §40: postgres initialises with a provider Alpine can honour (2026-09-10) ─
# The image is postgres:18.x-ALPINE (musl). glibc locales do not exist there -- localedef is
# absent and /usr/lib/locale is empty -- but the image sets LANG=en_US.utf8, so initdb
# recorded datcollate=en_US.utf8 with the libc provider and then silently degraded to C.
# Proven on the running cluster: ORDER BY returned 'Banana,Zebra,apple,cherry' (code-point
# order), while pg_database claimed en_US.utf8. The metadata LIED.
# Two consequences: sort order differs from any glibc production (a dev/prod divergence that
# hides bugs), and if the effective collation ever changes -- a Debian-based image, locales
# appearing in a rebuild -- every existing text index is silently wrong until REINDEX.
# Fix applies to FRESHLY-INITIALISED clusters only: initdb runs solely on an empty data dir,
# so existing volumes keep the old metadata until they are recreated. Verified in a throwaway
# container: builtin+C.UTF-8 alone leaves datcollate=en_US.utf8 (it comes from LANG); adding
# LANG=C.UTF-8 yields datcollate=C, provider=b, locale=C.UTF-8 with sort order UNCHANGED.
# (--lc-collate=C alongside the builtin provider makes initdb fail outright -- do not add it.)
_PGC="${REPO_ROOT}/docker/images/01postgres18/docker-compose.yaml"
assert_pass "40a: postgres pins the builtin locale provider" \
  grep -Eq 'POSTGRES_INITDB_ARGS=.*--locale-provider=builtin' "${_PGC}"
assert_pass "40a: ...with the C.UTF-8 builtin locale" \
  grep -Eq 'POSTGRES_INITDB_ARGS=.*--builtin-locale=C\.UTF-8' "${_PGC}"
assert_pass "40b: LANG is overridden so datcollate/datctype are not en_US.utf8" \
  grep -Eq '^\s*-\s*LANG=C\.UTF-8\s*$' "${_PGC}"
assert_fail "40c: --lc-collate is NOT passed (initdb rejects it with builtin)" \
  grep -Eq 'POSTGRES_INITDB_ARGS=.*--lc-collate' "${_PGC}"

# ─── Section 41: the phpbrew ini baseline must pick up NEW extensions ─────
printf '\n%b── Section 41: phpbrew dist-db baseline vs newly added extensions%b\n' \
  "${C_BOLD}" "${C_RESET}"

# copy-dist-conf.sh RESETS var/db to the var/dist-db baseline on every start, and
# the package loop that installs extensions runs BEFORE it (phpbrew-start.sh:148
# sources setup-packages, :161 runs copy-dist-conf). The baseline used to be
# captured once, on the first cold run, and frozen: an extension added to .env
# afterwards was built, had its ini written and ENABLED by phpbrew, and then lost
# it to the reset -- .so on disk, absent from `php -m`, no error token written, so
# the container reported healthy. Silent, the same class as a token mismatch.
# These cases run the SHIPPED script twice against a sandbox tree.
_DDB="${TMP_DIR}/distdb"
_DDB_PHP="${_DDB}/phpbrew/php/php-test"
_DDB_DIST="${_DDB}/dist"
_distdb_run() {
  # `|| true`: this suite runs under `set -e`, so a sandbox that fails to set up
  # must RED the cases below rather than kill the run before it prints a summary.
  # Same guard, and the same reason, as §22's _gate_decision.
  env -i PATH="${DIST_BIN}/base-bin:/usr/bin:/bin" HOME="${_DDB}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH="${_DDB}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${_DDB}" \
    PHPBREW_ROOT="${_DDB}/phpbrew" \
    PHP_VERSION_NAME=php-test PHP_VERSION_AS=9-9 \
    GLOBAL_STACK_DOCKER_ROOT_DIST_PATH="${_DDB_DIST}" \
    bash "${DIST_BIN}/phpbrew-bin/global-stack-phpbrew-copy-dist-conf.sh" \
    >/dev/null 2>&1 || true
}
rm -rf "${_DDB}"
mkdir -p "${_DDB_PHP}/var/db" "${_DDB_PHP}/var/log" "${_DDB_PHP}/etc/fpm" \
  "${_DDB_PHP}/etc/php-fpm.d" "${_DDB_DIST}/conf/phpbrew-conf.d" \
  "${_DDB_DIST}/conf/php9-9-conf.d" "${_DDB_DIST}/conf/phpbrew-php-fpm.d" \
  "${_DDB_DIST}/conf/php9-9-php-fpm.d"
# stands in for the four opt-in inis the repo really ships commented out:
# zephir_parser, phalcon, swoole, xdebug.
printf ';extension=optin.so\n' >"${_DDB_DIST}/conf/phpbrew-conf.d/optin.ini"
printf 'extension=redis.so\n' >"${_DDB_PHP}/var/db/redis.ini"
_distdb_run                                                  # cold: baseline captured
printf 'extension=foo.so\n' >"${_DDB_PHP}/var/db/foo.ini"    # a NEW extension installs
printf 'extension=HAND.so\n' >"${_DDB_PHP}/var/db/redis.ini" # and an old one is hand-edited
_distdb_run                                                  # the next restart

# 41a keeps 41d honest: without it, a sandbox that never ran would leave
# dist-db/optin.ini absent and 41d would pass having tested nothing.
assert_pass "41a: sandbox precondition — the shipped script ran and built a baseline" \
  test -s "${_DDB_PHP}/var/dist-db/redis.ini"
assert_pass "41b: an extension added AFTER the cold run survives the var/db reset" \
  grep -qx 'extension=foo.so' "${_DDB_PHP}/var/db/foo.ini"
assert_pass "41c: a hand-edit to var/db does NOT poison the frozen baseline" \
  grep -qx 'extension=redis.so' "${_DDB_PHP}/var/dist-db/redis.ini"
assert_fail "41d: a repo-owned conf.d ini never enters the baseline" \
  test -e "${_DDB_PHP}/var/dist-db/optin.ini"
assert_pass "41e: an opt-in extension is still commented out after the reset" \
  grep -qx ';extension=optin.so' "${_DDB_PHP}/var/db/optin.ini"
assert_pass "41f: var/db is still reset to the baseline (the hand-edit is reverted)" \
  grep -qx 'extension=redis.so' "${_DDB_PHP}/var/db/redis.ini"

# ─── Section 42: mkcert init reports honestly; the host CA bundle is ro ────
printf '\n%b── Section 42: mkcert init diagnosis + host trust-store mounts%b\n' \
  "${C_BOLD}" "${C_RESET}"

# Of the 31 containers that run init-mkcert, exactly ONE fails: 02sonarqube, the
# only one where mkcert can see a JDK (JAVA_HOME + keytool). mkcert then also
# targets the JAVA truststore, which is root:root 644, and the container runs as
# uid 1000 -- so it shells out to sudo and gets "a password is required". The old
# handler blamed a "busy ca-certificates.crt" instead, a cause that cannot single
# out the one container with a JDK, and swallowed mkcert's two ERROR lines under a
# reassuring WARNING. Containers reach the local CA through ${SSL_CERT_FILE}, which
# a JVM does not read -- that is the real consequence and it must be said.
_MKC="${DIST_BIN}/base-bin/global-stack-base-init-mkcert.sh"
assert_fail "42a: init-mkcert no longer asserts the disproven 'busy ca-certificates.crt' cause" \
  grep -q 'busy ca-certificates.crt' "${_MKC}"

# Behavioural: run the SHIPPED script against a stub mkcert, in a sandbox CAROOT.
_MKC_SB="${TMP_DIR}/mkcert-sb"
_mkcert_run() { # $1 = exit code the stub returns
  rm -rf "${_MKC_SB}"
  mkdir -p "${_MKC_SB}/bin" "${_MKC_SB}/caroot"
  printf 'KEYSTUB\n' >"${_MKC_SB}/caroot/rootCA-key.pem"
  printf 'CERTSTUB\n' >"${_MKC_SB}/caroot/rootCA.pem"
  {
    printf '#!/bin/bash\n'
    if [[ "$1" == 0 ]]; then
      # what mkcert really prints when it has nothing to do
      printf 'echo "The local CA is already installed in the system trust store!"\n'
    else
      # the two lines 02sonarqube really emits
      printf 'echo "ERROR: failed to execute \\"keytool -importcert\\": exit status 1"\n'
      printf 'echo "sudo: a password is required" >&2\n'
    fi
    printf 'exit %s\n' "$1"
  } >"${_MKC_SB}/bin/mkcert"
  chmod +x "${_MKC_SB}/bin/mkcert"
  env PATH="${_MKC_SB}/bin:/usr/bin:/bin" CAROOT="${_MKC_SB}/caroot" \
    bash "${_MKC}" 2>&1
  printf 'RC=%s\n' "$?"
}
_mkc_fail_out="$(_mkcert_run 1 || true)"
_mkc_ok_out="$(_mkcert_run 0 || true)"

assert_output_contains "42b: a failing mkcert has its OWN error surfaced, not swallowed" \
  'keytool -importcert' printf '%s' "${_mkc_fail_out}"
assert_output_contains "42c: the failure names the JVM as the store that stays untrusting" \
  'JVM' printf '%s' "${_mkc_fail_out}"
assert_output_contains "42d: a failing mkcert still exits 0 — 31 containers must not die" \
  'RC=0' printf '%s' "${_mkc_fail_out}"
# Asserts on the diagnosis the SCRIPT adds, never on mkcert's own passthrough
# output — otherwise a stub that prints an error on success would decide it.
assert_fail "42e: a SUCCEEDING mkcert draws no failure diagnosis from the script" \
  bash -c 'printf "%s" "$1" | grep -q "JVM"' _ "${_mkc_ok_out}"
# Non-vacuity for 42e: the success path must have actually run and said something.
assert_output_contains "42f: ...and the success path still passes mkcert's own output through" \
  'already installed' printf '%s' "${_mkc_ok_out}"

# The host's real /etc/ssl/certs/ca-certificates.crt is bind-mounted into 10
# services plus 2 compose fragments. Containers only ever READ it (init-mkcert
# cats it into rootCA-Bundle.pem); the one legitimate writer is Makefile:170,
# which runs on the HOST. An rw mount is a live container→host-trust-store path.
_ca_rw="$(git -C "${REPO_ROOT}" grep -l -E '/etc/ssl/certs/ca-certificates\.crt:/etc/ssl/certs/ca-certificates\.crt:rw' \
  -- 'docker/images/*/docker-compose.yaml' 'docker/config/compose-fragments/*.yaml' 2>/dev/null || true)"
assert_pass "42g: no compose file mounts the host CA bundle read-write" \
  test -z "${_ca_rw}"
# Non-vacuity: the grep must still be able to SEE those mounts at all, so a typo
# in the pattern cannot make 42g pass by matching nothing anywhere.
_ca_any="$(git -C "${REPO_ROOT}" grep -l -E '/etc/ssl/certs/ca-certificates\.crt:/etc/ssl/certs/ca-certificates\.crt:' \
  -- 'docker/images/*/docker-compose.yaml' 'docker/config/compose-fragments/*.yaml' 2>/dev/null | wc -l)"
assert_pass "42h: ...and the 12 mounts are still found by the pattern (42g is not vacuous)" \
  test "${_ca_any}" -eq 12

_SQD="${REPO_ROOT}/docker/images/02sonarqube/Dockerfile"
assert_pass "42i: sonarqube makes the JVM truststore writable by its runtime user" \
  grep -Eq 'chmod .*g\+w .*(cacerts|security)' "${_SQD}"

# ─── Section 43: android — single-sourced API levels / image tag, no sdkmanager ──
printf '\n%b── Section 43: android SDK pins, AVD template and the deprecated sdkmanager%b\n' \
  "${C_BOLD}" "${C_RESET}"

# All three auto-created AVDs were unloadable: conf/android-avd-conf/config-apis.ini
# hardcoded system-images/{androidSystemName}/google_apis/x86_64/ while the setup
# script installed google_apis_ps16k. avdmanager's own verdict was "Missing system
# image android-37.x/google_apis/x86_64" for every one of them. Google ships a plain
# google_apis image for 37.0 ONLY -- 37.1 and 37.2-beta1 have none -- so the template
# was the wrong side. Both now read the tag from .env.
_ANDC="${REPO_ROOT}/docker/config/dist/conf/android-avd-conf/config-apis.ini"
_ANDS="${DIST_BIN}/android-bin/global-stack-android-setup.sh"
_ANDD="${DIST_BIN}/android-bin/global-stack-android-setup-dist.sh"

assert_fail "43a: the AVD template no longer hardcodes a system-image tag" \
  grep -Eq '^(image\.sysdir\.1|tag\.id|tag\.ids)=.*google_apis' "${_ANDC}"
assert_fail "43b: ...nor a hardcoded abi" \
  grep -Eq '^(abi\.type|hw\.cpu\.arch)=x86_64' "${_ANDC}"

# The real drift guard: EVERY placeholder in the template must be substituted by the
# sed in setup-dist.sh. Adding a placeholder and forgetting the sed leaves a literal
# {androidImageTag} in image.sysdir.1 — which fails exactly as silently as the wrong
# tag did. Derived from the files, never from a list written here.
_unsubbed=""
while IFS= read -r _ph; do
  grep -qF -- "s|${_ph}|" "${_ANDD}" || _unsubbed="${_unsubbed} ${_ph}"
done < <(grep -oE '\{[A-Za-z]+\}' "${_ANDC}" | sort -u)
assert_pass "43c: every AVD-template placeholder is substituted by setup-dist.sh" \
  test -z "${_unsubbed}"
# Non-vacuity for 43c: the template must actually contain placeholders to check.
assert_pass "43d: ...and the template really has placeholders (43c is not vacuous)" \
  bash -c '[ "$(grep -ocE "\{[A-Za-z]+\}" "$1")" -ge 6 ]' _ "${_ANDC}"

assert_pass "43e: setup-dist.sh fails loudly on an unsubstituted placeholder" \
  grep -q 'unsubstituted placeholder' "${_ANDD}"

# sdkmanager is deprecated and is now only a shim over `android sdk`.
assert_fail "43f: the setup script no longer invokes the deprecated sdkmanager" \
  grep -Eq '(^|[^a-z-])sdkmanager --sdk_root' "${_ANDS}"
# `--sdk` is a GLOBAL option — `android --sdk=<path> sdk install …`. b2ae4d1 wrote it
# AFTER the subcommand, where picocli rejects it outright (`Unknown option: '--sdk=…'`,
# exit 2), so every install and the verify listing were dead code that had never run:
# gs_version_gate was returning "skip" on a warm tools/ volume, and the marker predates
# the migration by a day. Assert BOTH directions — the correct spelling present and the
# broken one absent — because fixing one of the three call sites and leaving another
# reads as green under a one-directional check.
_ands_code="$(grep -v '^[[:space:]]*#' "${_ANDS}")"
# Counted on the FIXED string including the variable, not on a regex: the FATAL text
# this script prints for the operator spells out `android --sdk=<sdk root> sdk list`,
# which is code, not a comment — a looser pattern counts that help string as a fourth
# call site and the count then survives one real site being reverted. Found by
# sabotage S1, which reddened 43g2 while leaving 43g green.
assert_pass "43g: the setup script puts --sdk= in the GLOBAL position, at all 3 call sites" \
  bash -c 'test "$(printf "%s\n" "$1" | grep -cF "android --sdk=\"\${ANDROID_HOME}\" sdk")" -ge 3' _ "${_ands_code}"
assert_fail "43g2: ...and no subcommand-position --sdk= survives anywhere" \
  bash -c 'printf "%s\n" "$1" | grep -Eq "android sdk (install|list).*--sdk="' _ "${_ands_code}"
# The exit 2 above was invisible because the capture swallowed it twice over: the
# listing came back empty, every grep missed, and the script reported "these packages
# are absent" — blaming the package ids for a broken invocation. Measured on the real
# binary, the correct form exits 0, so neither swallow has a failure mode behind it.
assert_fail "43o: the verify listing is not swallowed by 2>/dev/null or || true" \
  bash -c 'printf "%s\n" "$1" | grep -Eq "sdk list.*(2>/dev/null|\|\| true)"' _ "${_ands_code}"
# The licence feeders caused "echo: write error: Broken pipe" on lines 30/32,
# because line 6 ignores SIGPIPE so the write returns EPIPE instead of dying.
# NOTE: these two must look at CODE only. The comment block in that script quotes
# both the old feeder and --licenses verbatim to explain why they went, so a naive
# grep matches the prose and reds a correct file — the same weak-assertion trap
# that bit 34d/35b/36b earlier. Strip comment lines first.
assert_fail "43h: the yes-feeders that caused the broken-pipe error are gone" \
  bash -c "grep -v '^[[:space:]]*#' \"\$1\" | grep -q \"while true; do echo 'y'\"" _ "${_ANDS}"
assert_fail "43i: ...and so is the --licenses call upstream now calls unnecessary" \
  bash -c "grep -v '^[[:space:]]*#' \"\$1\" | grep -q -- '--licenses'" _ "${_ANDS}"

# `android sdk install` EXITS 0 on "Package <id> not found", so set -e cannot catch
# a renamed package — the most plausible route by which the ps16k rename shipped.
assert_pass "43j: the setup script verifies the packages actually installed" \
  grep -q 'reported success but these packages are absent' "${_ANDS}"

# API levels and the image tag are single-sourced in .env, not literals.
assert_fail "43k: no literal android API level is left in the setup script" \
  grep -Eq '"(platforms|system-images);android-[0-9]' "${_ANDS}"
assert_fail "43l: nor in the AVD creation script" \
  grep -Eq 'system-images;android-[0-9]' "${_ANDD}"
for _v in API_LEVEL_1 API_LEVEL_2 API_LEVEL_3 SYSTEM_IMAGE_TAG SYSTEM_IMAGE_PLAYSTORE_TAG SYSTEM_IMAGE_ABI; do
  assert_pass "43m: .env defines GLOBAL_STACK_ANDROID_${_v}" \
    grep -q "^GLOBAL_STACK_ANDROID_${_v}=" "${REPO_ROOT}/.env"
  assert_pass "43n: 04android plumbs GLOBAL_STACK_ANDROID_${_v}" \
    grep -q "GLOBAL_STACK_ANDROID_${_v}=\${GLOBAL_STACK_ANDROID_${_v}}" \
    "${REPO_ROOT}/docker/images/04android/docker-compose.yaml"
done

# ── Behavioural: run the SHIPPED install+verify block against a stubbed `android` ──
#
# Four guarantees no grep reaches: the flag lands in the GLOBAL position, the verify
# loop covers EVERY id the install asks for, a single-instance id is sent the way the
# real CLI accepts it, and a package that did not install is actually caught.
#
# The stub is a faithful model of `android 1.0.15985488` (the build the pinned
# commandlinetools-linux-15859902_latest.zip yields), measured 2026-09-11:
#   * a --sdk that is not in the global position is rejected with exit 2
#   * `sdk list` prints the install id with ';' -> '/', uniformly
#   * the three SINGLE-INSTANCE packages (platform-tools, ndk-bundle, emulator) take
#     NO version: sent one, the CLI prints "Package <id>/<ver> not found." and EXITS
#     0, installing nothing; installed bare, they are LISTED bare with the version
#     upstream served in column 2
# Only those RULES belong to the test; the ids come from the script itself, so the
# probe cannot pass by agreeing with itself.
#
# That second rule is row 36, and it is the one this stub used to get wrong. It
# recorded every argument it was handed and then re-applied the SCRIPT's own
# "platform-tools;<ver>" -> bare mapping when listing — modelling the bug instead of
# the CLI — so an id that could never install reported itself present, and 43q-43t
# were green on a platform-tools that was absent from every android container. A
# stub that mirrors the code's assumption tests nothing but the mirror.
# $1 = list id to omit ("" = omit none)
# $2 = version the stub reports for platform-tools (default: the pin the probe env
#      sets below, i.e. the matching case). Single-instance packages take no version
#      at install time, so the pin is an EXPECTED version the verify asserts against
#      what upstream actually served -- $2 is how the mismatch arm gets exercised.
# echoes "<rc>|<absent-ids>|<version-warn>"
_andv_probe() {
  local omit="${1}" ptv="${2:-37.0.1}" d="${TMP_DIR}/andv" rc out
  rm -rf "${d}"
  mkdir -p "${d}/bin" "${d}/versions"
  : >"${d}/asked"
  cat >"${d}/bin/android" <<STUB
#!/bin/bash
D="${d}"
OMIT="${omit}"
PTV="${ptv}"
case "\${1}" in
  --version) echo "1.0.0-stub"; exit 0 ;;
  --sdk=*) shift ;;
  *) echo "Unknown option: '\${1}'" >&2; exit 2 ;;
esac
case "\${1}.\${2}" in
  sdk.install)
    shift 2
    # The real CLI rejects a version suffix on a SINGLE-INSTANCE package: it prints
    # "Package <id>/<ver> not found." -- note the ';' is rendered as '/' in the
    # message, which is what a reader greps the logs for -- installs nothing, and
    # EXITS 0. Modelling that is the whole point: the previous stub recorded every
    # argument it was handed and then re-applied the script's own ';'->bare
    # transform when listing, so an id that could never install reported itself
    # present and 43q-43t were green on it for a day [measured 2026-09-11 against
    # android 1.0.15985488: all three of these answer "not found" + exit 0, while
    # multi-instance "build-tools;37.0.0" is accepted].
    for _a in "\$@"; do
      case "\${_a}" in
        platform-tools\\;* | ndk-bundle\\;* | emulator\\;*)
          printf 'Package %s not found.\n' "\${_a//;//}"
          continue ;;
      esac
      printf '%s\n' "\${_a}" >>"\${D}/asked"
    done
    exit 0 ;;
  sdk.list)
    echo "Installed packages:"
    while IFS= read -r p; do
      # Uniform ';'->'/': the single-instance ids are bare on BOTH sides now, so the
      # listing needs no exception. The arm that used to live here mirrored the
      # install bug rather than the CLI.
      id="\${p//;//}"
      [ "\${id}" = "\${OMIT}" ] && continue
      v=1.2.3
      if [ "\${id}" = "platform-tools" ]; then v="\${PTV}"; fi
      printf '  %s  %s  description\n' "\${id}" "\${v}"
    done <"\${D}/asked"
    exit 0 ;;
esac
exit 0
STUB
  chmod +x "${d}/bin/android"
  {
    printf '#!/bin/bash\nset -eEu -o pipefail\n'
    sed -n '/^_pkgs=(/,$p' "${_ANDS}"
  } >"${d}/run.sh"
  # The stub PATH is composed HERE, not inside the command substitution below: a
  # `${PATH}` read in a subshell pairs with an unrelated PATH assignment further up
  # this file and wakes SC2031/SC2030 on both. `env` for the same reason — a bare
  # `PATH=… cmd` prefix is itself a subshell modification.
  # `printenv PATH`, not "${PATH}": a shell-variable READ of PATH anywhere in this file
  # gets paired by shellcheck with the unrelated `PATH="/usr/bin:/bin"` fixture in the
  # sdkman section (SC2030/SC2031) and reports a finding on both lines. PATH is
  # exported, so reading it from the environment is the same value and tracks nothing.
  local probe_path
  probe_path="${d}/bin:$(printenv PATH)"
  out="$(
    env PATH="${probe_path}" \
      ANDROID_HOME="${d}" \
      GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${d}/versions" \
      GS_ANDROID_SDK_WANT="probe" \
      GLOBAL_STACK_ANDROID_INSTALL_SYSTEM_IMAGES=true \
      GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION=23.0 \
      GLOBAL_STACK_ANDROID_PLATFORM_TOOLS_VERSION=37.0.1 \
      GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION=37.0.0 \
      GLOBAL_STACK_ANDROID_NDK_VERSION=30.0.16248370 \
      GLOBAL_STACK_ANDROID_API_LEVEL_1=37.0 \
      GLOBAL_STACK_ANDROID_API_LEVEL_2=37.1 \
      GLOBAL_STACK_ANDROID_API_LEVEL_3=37.2-beta1 \
      GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_TAG=google_apis_ps16k \
      GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_PLAYSTORE_TAG=google_apis_playstore_ps16k \
      GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_ABI=x86_64 \
      bash "${d}/run.sh" 2>&1
  )" && rc=0 || rc=$?
  # Anchor on ^FATAL: / ^WARN: — the extracted block re-enables `set -x`, so the
  # xtrace line for that very printf is also in the stream and would be scraped
  # alongside it. (xtrace lines open with `+`, so the anchor is what excludes them.)
  local warn
  warn="$(printf '%s\n' "${out}" | sed -n 's/^WARN: //p')"
  # `none` rather than empty: a bare empty third field makes "no warning" a SUBSTRING
  # of "some warning", so `assert_output_contains '0||'` could never tell them apart.
  printf '%s|%s|%s' "${rc}" \
    "$(printf '%s\n' "${out}" | sed -n 's/^FATAL:.*these packages are absent://p')" \
    "${warn:-none}"
}

# Non-vacuity: the extraction must actually find the package array. If setup.sh stops
# opening with `_pkgs=(`, every probe below would run an EMPTY script and pass.
assert_pass "43p: the install+verify block is extractable (the probes are not vacuous)" \
  bash -c 'test "$(sed -n "/^_pkgs=(/,\$p" "$1" | wc -l)" -ge 30' _ "${_ANDS}"

# A complete install must NOT report anything missing. This is the assertion that
# catches the platform-tools transform, and — because the stub rejects a non-global
# --sdk with exit 2 under set -e — it is also the behavioural proof of 43g.
assert_output_contains "43q: a complete install verifies clean (no false FATAL)" \
  '0|' _andv_probe ""
# Each of the next three is an id the PRE-FIX loop never checked: a single-instance
# package, an add-on, and a playstore-tag system image. Before the array became the
# single source of truth the loop covered 11 of 24 ids while its own comment claimed
# "every id we asked for".
assert_output_contains "43r: a missing platform-tools is caught" \
  '1| platform-tools' _andv_probe "platform-tools"
assert_output_contains "43s: a missing add-on is caught (was uncovered pre-fix)" \
  '1| add-ons/addon-google_apis-google-24' _andv_probe "add-ons/addon-google_apis-google-24"
assert_output_contains "43t: a missing playstore system image is caught (was uncovered pre-fix)" \
  '1| system-images/android-37.1/google_apis_playstore_ps16k/x86_64' \
  _andv_probe "system-images/android-37.1/google_apis_playstore_ps16k/x86_64"

# ─── the single-instance class (row 36) ────────────────────────────────────
# platform-tools, ndk-bundle and emulator take NO version: the CLI answers
# "Package <id>/<ver> not found." and EXITS 0, so a version suffix installs nothing
# and `set -e` cannot see it. This shipped on platform-tools for a day while the
# verify's own listing exception transformed the id back to bare and reported it
# present -- which is why the check below is STATIC and covers all three, not just
# the member that broke. 43q is the behavioural half; this is the one that names
# the offender.
#
# Comment lines are STRIPPED (the §19 lesson): the class note in setup.sh now spells
# out all three failing ids verbatim as evidence, and an explanatory comment must
# never be able to change what a test demands.
_a43_si_bad="$(grep -v '^[[:space:]]*#' "${_ANDS}" \
  | grep -oE '(platform-tools|ndk-bundle|emulator);' | sort -u | tr '\n' ' ' || true)"
assert_pass "43z: no single-instance package id carries a version suffix (offenders: ${_a43_si_bad:-none})" \
  test -z "${_a43_si_bad}"
# Non-vacuity for 43z: the three ids must actually be present as live install ids. A
# renamed array or a stopped strip would otherwise scan nothing and pass green.
_a43_si_n="$(grep -v '^[[:space:]]*#' "${_ANDS}" \
  | grep -coE '"(platform-tools|ndk-bundle|emulator)"' || true)"
assert_pass "43z2: ...and all three are really installed bare (43z is not vacuous, found ${_a43_si_n})" \
  test "${_a43_si_n}" -ge 3

# A single-instance pin is an EXPECTED version, not a requestable one -- upstream
# serves what it serves. So the verify asserts it and WARNs; it does not FATAL, and
# that is not a swallowed error: the only remedy for a real mismatch is an `.env`
# bump (the pin is env-update-tracked, `@todo env-update sdkmanager:platform-tools`),
# and failing hard would block 04android plus the three consumers behind it on what
# is documentation drift, not a broken SDK.
assert_output_contains "43aa: a matching platform-tools version raises no warning" \
  '0||none' _andv_probe "" "37.0.1"
assert_output_contains "43ab: a platform-tools version adrift from the pin WARNs" \
  '|platform-tools 9.9.9 != pinned 37.0.1' _andv_probe "" "9.9.9"
# ...and the drift is a WARNING only: rc stays 0 and nothing is reported absent.
assert_output_contains "43ac: ...but does not fail the install (WARN, not FATAL)" \
  '0||platform-tools' _andv_probe "" "9.9.9"

# setup-dist.sh's AVD loop is EXECUTED here, not grepped. 43c/43e/43l are static and
# were green both before and after the loop was rewritten from glob-and-reverse-parse
# to tuple iteration, so none of them could have noticed a control-flow change. The
# stub avdmanager only creates the directory the script then writes into — the names,
# the levels, the pixel models and every substitution come from the script itself and
# from the REAL template, so the probe cannot pass by agreeing with a fixture.
_andd_probe() { # echoes "<rc>|<n config.ini>|<leftover placeholders>|<sysdirs>|<avd ids>"
  local d="${TMP_DIR}/andd" rc out inis f all n
  rm -rf "${d}"
  mkdir -p "${d}/bin" "${d}/home/.android/avd"
  cat >"${d}/bin/avdmanager" <<'STUB'
#!/bin/bash
# Models what the script depends on: --name names the .avd directory, and a real
# `avdmanager create` leaves a config.ini inside it. That second half matters — the
# loop this replaced globbed `*.avd/config.ini`, so a stub that created only the
# directory would fail the OLD shape for a reason the real avdmanager never would,
# and the probe's red-first claim would be an artefact of the stub.
name=""
while [ "$#" -gt 0 ]; do
  case "${1}" in
    --name)
      name="${2}"
      shift 2
      ;;
    *) shift ;;
  esac
done
[ -n "${name}" ] || {
  echo "stub avdmanager: create without --name" >&2
  exit 1
}
mkdir -p "${ANDROID_SDK_HOME}/.android/avd/${name}.avd"
: >"${ANDROID_SDK_HOME}/.android/avd/${name}.avd/config.ini"
STUB
  chmod +x "${d}/bin/avdmanager"
  {
    cat <<'PRE'
#!/bin/bash
set -eEu -o pipefail
IFS=$'\n\t'
PRE
    sed -n '/^if \[ "\${GLOBAL_STACK_ANDROID_INSTALL_SYSTEM_IMAGES}"/,$p' "${_ANDD}"
  } >"${d}/run.sh"
  # `printenv PATH`, not "${PATH}" — same SC2030/SC2031 pairing as _andv_probe above.
  local probe_path
  probe_path="${d}/bin:$(printenv PATH)"
  out="$(
    env PATH="${probe_path}" \
      ANDROID_HOME="${d}/sdk" \
      ANDROID_SDK_HOME="${d}/home" \
      GLOBAL_STACK_DOCKER_ROOT_DIST_PATH="${REPO_ROOT}/docker/config/dist" \
      GLOBAL_STACK_ANDROID_INSTALL_SYSTEM_IMAGES=true \
      GLOBAL_STACK_ANDROID_API_LEVEL_1=37.0 \
      GLOBAL_STACK_ANDROID_API_LEVEL_2=37.1 \
      GLOBAL_STACK_ANDROID_API_LEVEL_3=37.2-beta1 \
      GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_TAG=google_apis_ps16k \
      GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_ABI=x86_64 \
      bash "${d}/run.sh" 2>&1
  )" && rc=0 || rc=$?
  inis="$(find "${d}/home/.android/avd" -name config.ini 2>/dev/null | sort)"
  all="${d}/all.ini"
  : >"${all}"
  while IFS= read -r f; do
    [ -n "${f}" ] && cat "${f}" >>"${all}"
  done <<<"${inis}"
  n="$(printf '%s\n' "${inis}" | grep -c . || true)"
  printf '%s|%s|%s|%s|%s' \
    "${rc}" "${n}" \
    "$(grep -o '{[A-Za-z]*}' "${all}" | sort -u | tr '\n' ' ')" \
    "$(sed -n 's/^image\.sysdir\.1=//p' "${all}" | tr '\n' ' ')" \
    "$(sed -n 's/^AvdId=//p' "${all}" | tr '\n' ' ')"
}

# Non-vacuity: if the `if [ "${GLOBAL_STACK_ANDROID_INSTALL_SYSTEM_IMAGES}"` anchor
# ever moves, the extraction yields nothing and every probe below runs an EMPTY
# script — which exits 0 and would read as a pass.
assert_pass "43u: the AVD block is extractable and really creates AVDs (43v-43x are not vacuous)" \
  bash -c 'b="$(sed -n "/^if \[ \"\\\${GLOBAL_STACK_ANDROID_INSTALL_SYSTEM_IMAGES}\"/,\$p" "$1")"
    [ "$(printf "%s\n" "${b}" | wc -l)" -ge 20 ] && printf "%s\n" "${b}" | grep -q "avdmanager create"' _ "${_ANDD}"

# rc 0, three config.ini written, and NO placeholder left behind. The template carries
# eight distinct placeholders (43d); a substitution dropped from the sed leaves one in
# image.sysdir.1 and the script's own guard turns that into rc 1.
assert_output_contains "43v: the AVD loop writes one substituted config.ini per AVD" \
  '0|3||' _andd_probe
# The discriminating level: 37.2-beta1 is the only pin whose value is not a bare X.Y,
# and it is the one a reverse-parse out of the AVD path is most likely to mangle.
assert_output_contains "43w: the beta API level reaches image.sysdir.1 intact" \
  'system-images/android-37.2-beta1/google_apis_ps16k/x86_64/' _andd_probe
# The tuple pairs a level with a pixel model. Nothing else in the loop pins that
# pairing, so a transposed tuple would produce three plausible AVDs and the wrong ones.
assert_output_contains "43x: level 1 is paired with pixel 7, not pixel 9" \
  'global_stack_auto_pixel_7_pro_android_37.0_google_apis' _andd_probe
assert_output_contains "43y: ...and the beta level with pixel 9" \
  'global_stack_auto_pixel_9_pro_android_37.2-beta1_google_apis' _andd_probe

# ─── Section 44: tools/elapsed — shape, docs, and the SECONDS clobber ──────
#
# `tools/elapsed` is a single REGULAR FILE, not a directory. Two artefacts said
# otherwise and one of them was a check that could never fire:
# `ls tools/elapsed/ 2>/dev/null` exits 2 with "Not a directory", the error is
# swallowed, and /stack-health renders "no timing data" on every single run.
#
# The other half is `global-stack-base-print-success.sh`, which assigns to
# SECONDS — a bash SPECIAL variable whose value INCREMENTS after assignment.
# A static lint cannot catch it -- there is no rule for special-variable
# clobber -- so 44b runs the script with a slow `date` on PATH and reads the
# seconds back out of the file it wrote. That is the only guard there can be.
# (This comment deliberately does NOT begin with the linter's own name: a
# comment whose first word is that name is parsed as a DIRECTIVE, and an
# unparseable one aborts analysis of this entire file -- silently.)
printf '\n%b── Section 44: tools/elapsed — shape, docs, SECONDS clobber%b\n' "${C_BOLD}" "${C_RESET}"

_PS_SH="${REPO_ROOT}/docker/config/dist/bin/base-bin/global-stack-base-print-success.sh"
_SH_SKILL="${REPO_ROOT}/.claude/skills/stack-health/SKILL.md"
_FL_TIP="${REPO_ROOT}/templates/tips/file-layout.md"
_EL_SPEC="${REPO_ROOT}/docs/specs/elapsed-write.md"
_ANDD_44="${REPO_ROOT}/docker/config/dist/bin/android-bin/global-stack-android-setup-dist.sh"

# Non-vacuity: every file 44 asserts against must exist, or the greps below
# would all "pass" by matching nothing.
for _f in "${_PS_SH}" "${_SH_SKILL}" "${_FL_TIP}" "${_EL_SPEC}" "${_ANDD_44}"; do
  assert_pass "44-guard: ${_f##*/} exists" test -f "${_f}"
done

# --- E5: the SECONDS clobber -------------------------------------------------
assert_fail "44a: print-success.sh does not assign to the special variable SECONDS" \
  grep -Eq '^[[:space:]]*SECONDS=' "${_PS_SH}"

# 44b is BEHAVIOURAL. A stub `date` that sleeps 2s makes real time pass between
# the assignment and the read, which is exactly the condition under which a
# clobbered SECONDS drifts. DURATION=5 must be written as "5 seconds"; a
# clobbered SECONDS writes 9.
_ps_seconds_written() {
  local _t
  _t="$(mktemp -d)"
  mkdir -p "${_t}/bin" "${_t}/tools/successes" "${_t}/tools/errors" "${_t}/tools/versions"
  printf '#!/bin/sh\nsleep 2\nexec /usr/bin/env -u PATH /bin/date "$@"\n' > "${_t}/bin/date"
  chmod +x "${_t}/bin/date"
  cp "${_PS_SH}" "${_t}/bin/"
  cp "${REPO_ROOT}/docker/config/dist/bin/base-bin/global-stack-base-prologue.sh" "${_t}/bin/"
  cp "${REPO_ROOT}/docker/config/dist/bin/base-bin/global-stack-base-version-gate.sh" "${_t}/bin/" 2>/dev/null || true
  env "GLOBAL_STACK_DOCKER_TOOLS_PATH=${_t}/tools" \
    "GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES=${_t}/tools/successes" \
    "GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS=${_t}/tools/errors" \
    "GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS=${_t}/tools/versions" \
    "PATH=${_t}/bin:/usr/bin:/bin" \
    bash "${_t}/bin/global-stack-base-print-success.sh" 5 "gs-test" "create" >/dev/null 2>&1 || true
  grep -oE '[0-9]+ seconds elapsed' "${_t}/tools/elapsed" 2>/dev/null | grep -oE '^[0-9]+' | tail -1
  rm -rf "${_t}"
}
_ps_secs="$(_ps_seconds_written)"
if [[ "${_ps_secs}" == "5" ]]; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  %s\n' "${C_GREEN}" "${C_RESET}" \
    "44b: print-success.sh writes DURATION%60 verbatim across a slow date (got 5)"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("44b: print-success.sh writes DURATION%60 verbatim across a slow date")
  printf '  %b✗%b  %s (wrote %s, want 5 — SECONDS drifted)\n' "${C_RED}" "${C_RESET}" \
    "44b: print-success.sh writes DURATION%60 verbatim across a slow date" "${_ps_secs:-<nothing>}"
fi

# --- E1/E2: tools/elapsed is a FILE, and the docs must say so ----------------
assert_fail "44c: /stack-health does not list tools/elapsed as a directory" \
  grep -q 'ls tools/elapsed/' "${_SH_SKILL}"
assert_pass "44d: /stack-health reads tools/elapsed with a FILE reader" \
  grep -q 'cat tools/elapsed' "${_SH_SKILL}"
assert_pass "44d2: file-layout.md documents elapsed as a single file" \
  grep -q 'a single FILE, not a directory' "${_FL_TIP}"
assert_fail "44e: file-layout.md does not list elapsed/ among the marker DIRECTORIES" \
  grep -q 'locks/ elapsed/' "${_FL_TIP}"

# --- E4: the spec premise that produced the two-namespace split --------------
# elapsed-write.md told the implementer to use the compose service name and
# claimed that "matches the format used by Group ✓ containers". It does not:
# 00base carries stack.service "00base" and writes "base". Leaving the claim in
# place invites the next service to be relabelled to match a format nothing uses.
# Anchored on the RULE's shape ("field), which matches the format"), not on the
# bare phrase: the correction block below it QUOTES the removed wording, and a
# grep for the phrase alone would match that quotation the moment the paragraph
# reflows — passing or failing for a reason that has nothing to do with the rule.
assert_fail "44f: the spec no longer claims service names match the Group ✓ format" \
  grep -q 'field), which matches the format' "${_EL_SPEC}"

# --- E6: the error line must name a script that exists -----------------------
assert_fail "44g: the AVD script's error line names no nonexistent setup-dit.sh" \
  grep -q 'global-stack-android-setup-dit\.sh' "${_ANDD_44}"

# ─── Section 45: templates/tips reference docs track the tools ─────────────
#
# CLAUDE.md calls templates/tips/env-scan.md the "Full reference" for
# bin/env-scan.sh. It was missing --reference and --yes: both wired in
# core/args.sh, both advertised by the script's own --help, neither documented.
# 45a derives its expectation from `env-scan.sh --help` at run time rather than
# from a list kept here, so a flag added to the tool and not to the doc reds
# this suite instead of quietly reopening the same gap.
printf '\n%b── Section 45: templates/tips reference docs track the tools%b\n' "${C_BOLD}" "${C_RESET}"

_ES_SH="${REPO_ROOT}/bin/env-scan.sh"
_ES_DOC="${REPO_ROOT}/templates/tips/env-scan.md"
_EU_DOC="${REPO_ROOT}/templates/tips/env-update.md"

assert_pass "45-guard: env-scan.sh and both reference docs exist" \
  test -f "${_ES_SH}" -a -f "${_ES_DOC}" -a -f "${_EU_DOC}"

_es_opts=()
while read -r _o; do
  [[ -n "${_o}" ]] && _es_opts+=("${_o}")
done < <(bash "${_ES_SH}" --help 2>/dev/null |
  grep -oE '^[[:space:]]+--[a-z][a-z0-9-]*' | tr -d ' \t' | sort -u)

# Non-vacuity: if --help returned nothing the loop below would pass by testing
# nothing at all, which is the failure mode this whole suite exists to avoid.
assert_pass "45-guard: env-scan --help advertises a plausible option count (>= 40)" \
  test "${#_es_opts[@]}" -ge 40

# Word-boundary match, not -F: a plain substring test would let a documented
# --backup-keep satisfy an undocumented --backup.
_es_undoc=""
for _o in "${_es_opts[@]}"; do
  if ! grep -qE -- "${_o}([^a-z0-9-]|$)" "${_ES_DOC}"; then
    _es_undoc="${_es_undoc} ${_o}"
  fi
done
if [[ -z "${_es_undoc}" ]]; then
  PASS=$((PASS + 1))
  printf '  %b✓%b  %s\n' "${C_GREEN}" "${C_RESET}" \
    "45a: every option env-scan --help advertises (${#_es_opts[@]}) is in env-scan.md"
else
  FAIL=$((FAIL + 1))
  FAILURES+=("45a: env-scan.md omits options the tool advertises")
  printf '  %b✗%b  %s —%s\n' "${C_RED}" "${C_RESET}" \
    "45a: env-scan.md omits options the tool advertises" "${_es_undoc}"
fi

# env-update.md describes the sdkmanager fetcher as running `sdkmanager --list`.
# That binary is deprecated upstream and is now a shim over `android sdk`; the
# fetcher still resolves correctly THROUGH the shim, so the doc needs a note,
# not a rewrite. Assert the note is there, next to the invocation it qualifies.
# Anchored on the note's ACTIONABLE substance (it must name the replacement
# command), not on the word "deprecated": the note QUOTES upstream's own message,
# which contains that word, so a grep for it alone stays green even when the note
# is gutted -- confirmed by sabotage, which is the only way that shows up.
_eu_note="$(grep -A14 -- 'sdkmanager --sdk_root' "${_EU_DOC}")"
assert_output_contains "45b: env-update.md flags the sdkmanager invocation as deprecated" \
  'DEPRECATED upstream' printf '%s' "${_eu_note}"
# Anchored on the GLOBAL-position spelling, not on the bare words `android sdk list`:
# the note now quotes the WRONG position too, as the counter-example, so the bare form
# would match the very thing the note warns against.
assert_output_contains "45b2: ...and names the replacement command next to it" \
  'android --sdk=' printf '%s' "${_eu_note}"

assert_fail "45c: no 'partitian' typo anywhere under templates/" \
  grep -rqi 'partitian' "${REPO_ROOT}/templates"

# ─── Section 46: no trailing test-led && short-circuit ─────────────────────
#
# A trailing `[[ cond ]] && cmd` makes the FALSE test the script's own exit
# status: bash returns the status of the last command, and a short-circuited
# AND-OR list whose left side failed returns 1. Measured in isolation -- var
# unset -> 1, var set -> 0 -- so the script reports failure for having had
# nothing to do.
#
# Where that status is consumed it is a real fault: nvm-start.sh:143 calls the
# three node *-setup.sh as bare statements under `set -xeEu` with the prologue
# ERR trap, so a false guard aborts the node install and writes an error token.
# android-setup.sh's own instance is unreachable today ONLY because
# android-start.sh:115 exports GS_ANDROID_SDK_WANT before its single call site
# -- an accident of the caller, not a property of the script.
#
# Deliberately narrowed to a TEST-led `&&`. `phpbrew update --old || true` and
# `dig +short "${1}" || echo ""` are legitimate last lines and are present in
# this tree today; so is a real command's `&&`, where a failure SHOULD be the
# status. Only a false TEST becoming the status is the defect. Flagging the
# others would invite "fixing" working code.
#
# KNOWN HOLE, measured rather than assumed: the scan reads the last
# non-comment line, so a backslash-continued `[[ cond ]] && \` + newline +
# `cmd` hides the `&&` on the penultimate line and is NOT caught. No script in
# this tree uses that shape; the sabotage record carries the measurement.
printf '\n%b── Section 46: no trailing test-led && short-circuit%b\n' "${C_BOLD}" "${C_RESET}"

_a10_offenders=""
_a10_scanned=0
while IFS= read -r -d '' _a10_f; do
  _a10_scanned=$((_a10_scanned + 1))
  _a10_last="$(grep -vE '^[[:space:]]*(#|$)' "${_a10_f}" | tail -1)"
  if printf '%s' "${_a10_last}" | grep -qE '^[[:space:]]*\[\[?.*\]\]?[[:space:]]*&&'; then
    _a10_offenders="${_a10_offenders} $(basename "${_a10_f}")"
  fi
done < <(find "${DIST_BIN}" -name '*.sh' -print0 2>/dev/null)

# Non-vacuity: a typo in the find root yields an empty scan, zero offenders and
# a green check -- the same can-never-fire defect §19 carried one level up. 103
# scripts when this was written; the floor sits below that so ordinary growth
# or removal does not red it, while a broken root does.
assert_pass "46a: the scan actually reached the startup scripts (>= 90)" \
  bash -c 'test "$1" -ge 90' _ "${_a10_scanned}"

# Asserts the SET, not a count: a red prints the offending basenames, so a red
# from a broken extraction cannot be mistaken for the defect itself.
assert_output_contains "46b: no startup script ends on a test-led && short-circuit" \
  '^NONE$' printf '%s\n' "${_a10_offenders:-NONE}"

# The behavioural half. Running the whole script is not an option: it dies at
# its `git clone` of rootAVD long before the last line -- which is exactly how
# A10's first evidence came to name the wrong cause. The probe runs the guarded
# write ALONE, extracted by ANCHOR rather than by position: an earlier draft
# took the last executable line, which meant "the marker write" before the fix
# and "fi" after it, and 46c caught that on the first green run.
_a10_tail="$(sed -n '/^if \[\[ -n "\${GS_ANDROID_SDK_WANT:-}" \]\]; then$/,/^fi$/p' \
  "${DIST_BIN}/android-bin/global-stack-android-setup.sh")"

# GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS is set in an ordinary /stack shell and
# tools/versions/android.sdk is a LIVE marker: inheriting it here would overwrite
# it, gs_version_gate would then read a mismatch, and android-start.sh `sudo
# rm -rf`s ANDROID_HOME before reinstalling. The probe pins the variable to its
# own tmpdir and asserts the marker lands THERE.
_a10_probe() {
  local want="$1" d rc marker
  d="$(mktemp -d)"
  mkdir -p "${d}/versions"
  {
    printf '#!/bin/bash\nset -eEu -o pipefail\n'
    printf 'GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS=%q\n' "${d}/versions"
    if [ "${want}" = "set" ]; then
      printf 'GS_ANDROID_SDK_WANT=%q\n' 'cmdline-tools=1;build-tools=2;ndk=3'
    fi
    printf '%s\n' "${_a10_tail}"
  } >"${d}/probe.sh"
  rc=0
  bash "${d}/probe.sh" >/dev/null 2>&1 || rc=$?
  marker=absent
  if [ -f "${d}/versions/android.sdk" ]; then marker=present; fi
  printf '%s|%s' "${rc}" "${marker}"
  rm -rf "${d}"
}

assert_output_contains "46c: non-vacuity -- the extracted block IS the guarded marker write" \
  'GS_ANDROID_SDK_WANT' printf '%s' "${_a10_tail}"
assert_pass "46c2: ...and it is a complete if/fi block, not a fragment" \
  bash -c 'b="$1"; case "${b}" in if*) ;; *) exit 1 ;; esac
    printf "%s" "${b}" | tail -1 | grep -q "^fi$"' _ "${_a10_tail}"
# The fence at setup.sh's tail wants the marker ABSENT standalone so the next
# start reinstalls rather than trusting unverified state. That stays; only the
# exit status changes.
#
# Grading these two honestly [measured, row 32]: 46e reds on an interior
# mutation (`printf … > …/android.sdk` -> `true "${GS_ANDROID_SDK_WANT}"` gives
# `0|present` -> `0|absent`). 46d does NOT and cannot red on the `&&` shape
# returning -- reverting the `if` stops the anchor matching, the block extracts
# empty, and an empty probe exits 0 writing nothing, which is exactly 46d's
# expectation. 46b is the red-first proof of the class; 46c/46c2 catch the
# empty extraction; 46d is a regression guard for the unset branch.
assert_output_contains "46d: var UNSET -> exit 0, and no marker written" \
  '^0|absent$' _a10_probe unset
assert_output_contains "46e: var SET -> exit 0, marker written to the PROBE dir" \
  '^0|present$' _a10_probe set

# ─── Section 47: the android composite is DISCOVERED, not curated (row 33) ───
printf '\n%b── Section 47: android composite ↔ setup.sh consumed set%b\n' "${C_BOLD}" "${C_RESET}"

# Row 33. The composite marker is the ONLY thing that makes an .env bump of an SDK
# input reach the SDK: gs_version_gate compares it, and a mismatch is what drives
# the `sudo rm -rf "${ANDROID_HOME}"` and the reinstall. An input that setup.sh
# CONSUMES but the composite OMITS is therefore a bump that is silently never
# applied — which is what row 19 shipped, covering 3 of 12.
#
# So the set is DISCOVERED from setup.sh rather than listed here: a hardcoded list
# of twelve would be §19's can-never-fire defect a third time, and the list that
# needs extending is precisely the one nobody remembers to extend.
#
# Comment LINES are stripped first (the §19 shape). setup.sh's own prose names
# NDK_BUNDLE_VERSION and PLATFORM_TOOLS_VERSION while explaining what is and is not
# installed — an explanatory comment must never be able to change what this test
# demands, which is §19's other lesson.
#
# BIDIRECTIONAL, deliberately. Consumed-minus-composite catches the row-19 gap.
# Composite-minus-consumed catches its mirror: a var dropped from setup.sh whose
# key lingers in the composite, where a bump would force a full SDK reinstall for a
# value nothing reads any more.
# `|| true` on BOTH: a missing file or a stopped anchor is the red-first case —
# 47a's floor reports `found 0`, 47b reports every input uncovered — not a harness
# error. Without it this suite's `set -euo pipefail` kills the whole RUN at this
# line with no tally, which is strictly worse than a red: it reads as a crash
# rather than as the guard firing. Measured, not assumed [row 33]: pointing
# AND_SETUP at a nonexistent file aborted the run here until this was added.
_a47_consumed="$(grep -v '^[[:space:]]*#' "${AND_SETUP}" \
  | grep -oE 'GLOBAL_STACK_ANDROID_[A-Z0-9_]+' | sort -u || true)"
_a47_want="$(grep -m1 '^GS_ANDROID_SDK_WANT=' "${AND_START}" \
  | grep -oE 'GLOBAL_STACK_ANDROID_[A-Z0-9_]+' | sort -u || true)"

# Non-vacuity floor: 12 as of row 33. Without it, a typo'd path or a strip that
# matched nothing would compare two EMPTY sets and report a clean pass.
_a47_n="$(printf '%s\n' "${_a47_consumed}" | grep -c . || true)"
assert_pass "47a: setup.sh consumes >= 12 android inputs (found ${_a47_n})" \
  test "${_a47_n}" -ge 12

_a47_uncovered="$(comm -23 <(printf '%s\n' "${_a47_consumed}") <(printf '%s\n' "${_a47_want}"))"
_a47_u_disp="$(printf '%s' "${_a47_uncovered}" | tr '\n' ' ')"
assert_pass "47b: every input setup.sh consumes is in the composite (uncovered: ${_a47_u_disp:-none})" \
  test -z "${_a47_uncovered}"

_a47_dead="$(comm -13 <(printf '%s\n' "${_a47_consumed}") <(printf '%s\n' "${_a47_want}"))"
_a47_d_disp="$(printf '%s' "${_a47_dead}" | tr '\n' ' ')"
assert_pass "47c: the composite carries no key setup.sh no longer consumes (dead: ${_a47_d_disp:-none})" \
  test -z "${_a47_dead}"

# ─── Section 48: PATH assignments are well-formed (row 35) ─────────────────
# Two silent defects, both shipped, both found by reading rather than by any
# failure they caused — because neither produces an error message:
#
#   (a) an EMPTY PATH element. POSIX says an empty element means the CURRENT
#       DIRECTORY, so a literal `::` puts `.` on PATH for every process the
#       container starts, including anything the host sources out of
#       tools/.shellrc/. Four sites carried `/bin::${ANDROID_HOME}/…` —
#       android-start.sh and alltogether-start.sh, twice each (the live PATH=
#       assignment and the line echoed into the user's shellrc).
#
#   (b) a CONCATENATED re-include. `PATH="${TOOLS}/caddy/bin${PATH}"` (missing
#       colon) does not add the directory at all: it glues it to the front of
#       the first inherited element, so BOTH are lost — caddy/bin is not on PATH
#       and neither is whatever /usr/local/bin-ish entry came first. It shipped
#       in caddy-start.sh:8 while line 15 wrote the CORRECT `caddy/bin:${PATH}`
#       into the shellrc, which is what proved it a typo rather than intent —
#       and since line 15 expands the already-corrupted value, one fix repaired
#       both.
#
# DISCOVERED, never listed: a hardcoded set of four would be Section 19's defect
# again. Comment lines are stripped first (this file's own prose quotes `::`).
# Note the mkcert calls' `::1` is IPv6 localhost and legitimate; it is excluded
# structurally, not by name — those lines carry no `PATH=` at all.
printf '\n%b── Section 48: PATH assignment well-formedness%b\n' "${C_BOLD}" "${C_RESET}"

# The pattern is ANCHORED. A bare `PATH=` also matches every `*_PATH=` variable
# in this tree — CADDY_PATH, MODSECURITY_TMP_PATH, CJOSE_PATH and ~100 more —
# which inflated the corpus from 38 to 138 and made the floor unfalsifiable: the
# real PATH writes could collapse to zero and 48a would still count 100+. It also
# made 48b false-positive on any `FOO_PATH="a::b"`. Measured [row 35]: unanchored
# 138, anchored 38.
_A48_PAT='(^|[^A-Za-z0-9_])PATH='

# `|| true` on all three: an empty result is the red-first case (48a's floor
# reports `found 0`), not a harness error — the class this suite's own
# `assert_output_contains` used to get wrong, see its comment.
_a48_lines="$(find "${DIST_BIN}" -name '*.sh' -type f -print0 \
  | xargs -0 grep -hE "${_A48_PAT}" 2>/dev/null | grep -v '^[[:space:]]*#' || true)"
_a48_n="$(printf '%s\n' "${_a48_lines}" | grep -c . || true)"
assert_pass "48a: >= 30 PATH-writing lines discovered (found ${_a48_n})" \
  test "${_a48_n}" -ge 30

# 48b: no empty PATH element. Reported per-FILE so a red names the offenders.
_a48_empty="$(find "${DIST_BIN}" -name '*.sh' -type f -print0 \
  | xargs -0 grep -lE "${_A48_PAT}" 2>/dev/null \
  | while read -r _f; do
    grep -v '^[[:space:]]*#' "${_f}" | grep -qE "${_A48_PAT}.*::" && basename "${_f}"
  done || true)"
_a48_e_disp="$(printf '%s' "${_a48_empty}" | tr '\n' ' ')"
assert_pass "48b: no '::' empty element in any PATH assignment (offenders: ${_a48_e_disp:-none})" \
  test -z "${_a48_empty}"

# 48c: every re-include of ${PATH} is preceded by ':' or by the start of the
# value — anything else concatenates. The character class permits `:` (the
# correct separator), `=`/quote (value start) and whitespace (a continuation).
_a48_glued="$(find "${DIST_BIN}" -name '*.sh' -type f -print0 \
  | xargs -0 grep -lE "${_A48_PAT}" 2>/dev/null \
  | while read -r _f; do
    grep -v '^[[:space:]]*#' "${_f}" | grep -E "${_A48_PAT}" \
      | grep -qE '[^:="'"'"'[:space:]]\$\{PATH\}' && basename "${_f}"
  done || true)"
_a48_g_disp="$(printf '%s' "${_a48_glued}" | tr '\n' ' ')"
assert_pass "48c: every \${PATH} re-include is colon-separated (offenders: ${_a48_g_disp:-none})" \
  test -z "${_a48_glued}"

# ─── Section 49: positional reads are below the handler (row 35) ───────────
# Under `set -u` a missing argument is a FATAL SHELL ERROR, not a failed
# command. The EXIT/ERR trap is what converts it into an error token — so a
# top-level `${1}` read that executes before the handler is fully in place dies
# writing NOTHING, and the service is unhealthy for the full 24h start_period
# with nothing in tools/errors/ naming the cause. Measured [row 35]: argless,
# eight scripts exited 1 with ZERO token files.
#
# "In place" means BOTH halves, whichever comes last: the `trap` line AND the
# `stackCatch` definition the trap body calls. Half of the family defines the
# function first and traps after; the other half traps first. Getting only one
# right still writes nothing — a read between a `trap` and a later function
# definition dies with `stackCatch: command not found`.
#
# ENUMERATED, not listed. Row 25 fixed this family's sibling defect with a Files
# cell scoped to three directories and missed the rest; row 30 found the android
# handlers the same way; row 35 was FILED as three `*-setup.sh` and the sweep
# found five more `*-iou*.sh`. A hardcoded list would be that mistake a fourth
# time, so the set is discovered from `set -u` + a column-0 positional read.
printf '\n%b── Section 49: positional reads below the handler%b\n' "${C_BOLD}" "${C_RESET}"

# Emits "<file>:<first positional read line>:<last handler line>" per candidate.
# `|| true`: an empty sweep is 49a's red, not a harness abort.
_a49_rows="$(find "${DIST_BIN}" -name '*.sh' -type f | sort | while read -r _f; do
  grep -qE '^set .*-[a-zA-Z]*u' "${_f}" || continue
  _p="$(grep -nE '^[A-Za-z_][A-Za-z0-9_]*="?\$\{?[1-9]' "${_f}" | head -1 | cut -d: -f1)"
  [[ -z "${_p}" ]] && continue
  # last line at which the handler becomes usable: the trap, the close of a local
  # stackCatch, or the prologue source (which installs both at once).
  _t="$(grep -nE "^trap .*(ERR|EXIT)" "${_f}" | tail -1 | cut -d: -f1)"
  _s="$(grep -nE '^source .*prologue' "${_f}" | head -1 | cut -d: -f1)"
  _c=""
  if grep -qE '^stackCatch\(\)' "${_f}"; then
    _c="$(awk '/^stackCatch\(\)/{f=1} f&&/^}$/{print NR; exit}' "${_f}")"
  fi
  _last=0
  for _n in "${_t}" "${_s}" "${_c}"; do
    [[ -n "${_n}" ]] && [[ "${_n}" -gt "${_last}" ]] && _last="${_n}"
  done
  printf '%s:%s:%s\n' "$(basename "${_f}")" "${_p}" "${_last}"
done || true)"

_a49_n="$(printf '%s\n' "${_a49_rows}" | grep -c . || true)"
assert_pass "49a: >= 8 scripts with set -u and a top-level positional read (found ${_a49_n})" \
  test "${_a49_n}" -ge 8

# A candidate with NO handler at all (_last == 0) is reported too: it cannot
# write a token by construction. global-stack-base-dump-pg-project.sh is the one
# such script today and is deliberately EXEMPT — it is a hand-run pg_dump
# utility with zero callers in docker/ or the Makefile, no GLOBAL_STACK_ERROR_TOKEN
# and no role in health signalling, so stderr + exit 1 is the correct contract.
_a49_bad="$(printf '%s\n' "${_a49_rows}" | while IFS=: read -r _n _p _l; do
  [[ -z "${_n}" ]] && continue
  [[ "${_n}" == "global-stack-base-dump-pg-project.sh" ]] && continue
  [[ "${_l}" -eq 0 || "${_p}" -lt "${_l}" ]] && printf '%s(read@%s,handler@%s) ' "${_n}" "${_p}" "${_l}"
done || true)"
assert_pass "49b: every positional read is below its handler (offenders: ${_a49_bad:-none})" \
  test -z "${_a49_bad}"

# ─── Section 50: no comment inside a line continuation (row 36) ────────────
# A `\` at end of line splices the NEXT line on. If that next line is a COMMENT,
# the command ends at its `#` — and every remaining argument line below is then
# executed as its OWN command. Both halves are silent in different ways:
#
#   * the call runs with FEWER arguments than written, doing less than it says
#   * the orphaned argument lines die `command not found`, exit 127
#
# Shipped and measured [row 36, 2026-09-11]: 7e8c0b2 moved an explanatory
# comment about `gem --debug` between the continued arguments of
# rbenv-start.sh's `global_stack_base_setup_packages` call. The call silently
# dropped from five arguments to FOUR — `gem install` was never passed, so no
# ruby gem could ever be installed — and the orphaned `--command='gem ...'` line
# ran as a command, exit 127, killing 03ruby3 and 03ruby4. It went unnoticed for
# a day because those containers had started seven hours BEFORE that commit;
# the developer's next restart is what surfaced it.
#
# The check is narrowed to a comment continuing a LIVE line. A comment line
# whose predecessor is ALSO a comment ending in `\` is an ordinary commented-out
# block — six of those exist in this tree (nginx-iou, httpd-setup, caddy-start,
# phpedge-install-fpm) and they must stay green.
printf '\n%b── Section 50: no comment inside a line continuation%b\n' "${C_BOLD}" "${C_RESET}"

# `|| true`: an empty sweep is 50a's red, not a harness abort.
_a50_cont="$(find "${DIST_BIN}" "${SCRIPT_DIR}/.." -name '*.sh' -type f 2>/dev/null | sort -u \
  | xargs grep -c '\\[[:space:]]*$' 2>/dev/null | awk -F: '{n+=$2} END{print n+0}' || true)"
assert_pass "50a: >= 100 line-continuations discovered to scan (found ${_a50_cont})" \
  test "${_a50_cont:-0}" -ge 100

_a50_bad="$(find "${DIST_BIN}" "${SCRIPT_DIR}/.." -name '*.sh' -type f 2>/dev/null | sort -u \
  | while read -r _f; do
    awk -v F="$(basename "${_f}")" '
      prev ~ /\\[[:space:]]*$/ && prev !~ /^[[:space:]]*#/ && $0 ~ /^[[:space:]]*#/ {
        printf "%s:%d ", F, NR
      } { prev = $0 }' "${_f}"
  done || true)"
assert_pass "50b: no comment line continues a live continued line (offenders: ${_a50_bad:-none})" \
  test -z "${_a50_bad}"

# ─── Section 51: $HOME permissions SUBTRACT, never assign (row 39) ─────────
# global-stack-base-chown-home.sh runs from the entrypoint of EVERY container,
# and its file arm used to be a numeric `chmod 600` — which also removes the
# OWNER's execute bit. Any tool that caches an executable under $HOME is
# therefore disarmed on the next boot. Measured [2026-09-11]: the `android`
# launcher downloads the real CLI to ~/.android/bin/android-cli at 0755 and
# execs it; one restart later it is -rw------- and the SDK reinstall dies with
# `Failed to exec android binary: Permission denied (os error 13)`. Second
# container, same class: serverless v4 caches sf-core.js, esbuild and invoke.py
# under ~/.serverless/releases/<ver>/ at 0755.
#
# The probe extracts ONE LINE, not the block, and that is load-bearing. The
# block runs `sudo chown -R` first, and the kernel drops setuid on chown(2) of a
# regular file — so a 4755 fixture would reach the chmod already at 0755 and the
# `ug-s` clause could never be redded. Whole-block extraction would have made
# 51e a check that cannot fire.
printf '\n%b── Section 51: $HOME permissions subtract, never assign%b\n' "${C_BOLD}" "${C_RESET}"

_CHH="${DIST_BIN}/base-bin/global-stack-base-chown-home.sh"

# Comment lines stripped before every discovery scan (the §19 rule): the block's
# own prose quotes the `chmod 600` it replaced and names `.docker/cli-plugins`,
# and neither may be allowed to decide what this section demands.
_a51_n="$(grep -v '^[[:space:]]*#' "${_CHH}" | grep -cE -- '-type f -exec sudo chmod' || true)"
assert_pass "51a: exactly one file-arm chmod line to extract (found ${_a51_n})" \
  test "${_a51_n}" -eq 1

# Runs the SHIPPED line against a fixture tree, with a `sudo` stub so the suite
# never escalates. Echoes "<name>=<octal mode>" for each fixture.
_chmod_probe() {
  local d="${TMP_DIR}/chh" line f
  rm -rf "${d}"
  mkdir -p "${d}/home/sub" "${d}/bin"
  printf '#!/bin/sh\necho hi\n' >"${d}/home/exec0755" && chmod 0755 "${d}/home/exec0755"
  printf 'x' >"${d}/home/data0644" && chmod 0644 "${d}/home/data0644"
  printf 'x' >"${d}/home/key0600" && chmod 0600 "${d}/home/key0600"
  printf 'x' >"${d}/home/wide0777" && chmod 0777 "${d}/home/wide0777"
  printf 'x' >"${d}/home/suid4755" && chmod 4755 "${d}/home/suid4755"
  printf 'x' >"${d}/home/sub/nested0755" && chmod 0755 "${d}/home/sub/nested0755"
  printf '#!/usr/bin/env bash\nexec "$@"\n' >"${d}/bin/sudo" && chmod 0755 "${d}/bin/sudo"

  line="$(grep -v '^[[:space:]]*#' "${_CHH}" | grep -E -- '-type f -exec sudo chmod' | head -1)"
  # No `|| true`: if the shipped line cannot run, this function aborts under the
  # suite's `set -e`, the mode string is never printed, and all six assertions red
  # with an empty output — which names the situation. Swallowing the status would
  # instead report it as "the modes are wrong", blaming the chmod rule for a
  # broken probe. The output redirect is NOT error suppression: this function's
  # stdout IS the assertion input, so the find's own chatter must stay out of it.
  PATH="${d}/bin:${PATH0}" \
    GLOBAL_STACK_BASE_USER_HOME="${d}/home" \
    bash -c "${line}" >/dev/null 2>&1

  for f in exec0755 data0644 key0600 wide0777 suid4755 sub/nested0755; do
    printf '%s=%s ' "$(basename "${f}")" "$(stat -c '%a' "${d}/home/${f}")"
  done
  printf '\n'
}

# One assertion per property, so a red names WHICH guarantee broke rather than
# printing one long mismatched string (the §27f rule).
assert_output_contains "51b: a cached executable keeps owner-execute" \
  'exec0755=700' _chmod_probe
assert_output_contains "51c: ...including one nested below \$HOME" \
  'nested0755=700' _chmod_probe
assert_output_contains "51d: an ordinary data file is still 0600, exactly as before" \
  'data0644=600' _chmod_probe
assert_output_contains "51e: setuid is cleared even though the owner's bits are kept" \
  'suid4755=700' _chmod_probe
assert_output_contains "51f: a world-open file loses every group and other bit" \
  'wide0777=700' _chmod_probe
assert_output_contains "51g: an already-0600 file is unchanged" \
  'key0600=600' _chmod_probe

# Keeps the deleted exception deleted. It re-added `a+x` to ONE directory —
# this class, noticed once and patched in one place. A second special case for
# ~/.android or ~/.serverless would be the same mistake a third time; the rule
# above covers all of them, so there is nothing left for an exception to do.
_a51_cli="$(grep -v '^[[:space:]]*#' "${_CHH}" | grep -c 'cli_plugins_dir' || true)"
assert_pass "51h: no per-directory a+x exception has returned (found ${_a51_cli})" \
  test "${_a51_cli}" -eq 0

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
