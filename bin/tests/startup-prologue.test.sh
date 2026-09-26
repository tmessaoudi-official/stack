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
  'fvm-bin/global-stack-fvm-start.sh|_fvm_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/fvm" "${GLOBAL_STACK_FVM_VERSION}" "fvm")"'
  'rust-bin/global-stack-rust-iou.sh|_rust_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rust" "${GLOBAL_STACK_RUST_VERSION}" "rust")"'
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
    # Ends at the gate's own closing `  fi` (2-space indent: the first one after the
    # label line). It used to end on the in-block `rm -f "${marker}"`, which tranche 1
    # step 6 moved to after the install — see §57.
    sed -n "/^  ${var}_label=/,/^  fi\$/p" "${src}"
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

# ─── Section 24: nvm-install-tools deno/bun version gate (row 16) — RETIRED ──
# Row 16 made both blocks content-compared (they had been exist-only). Its stub curl
# modelled the two installer scripts, deno's downloaded install.sh and bun's piped
# `curl | bash`. Tranche 3 step 19 removed both installers, so that model no longer
# describes anything shipped. Its five properties (first install, skip, bump, a marker
# that outlives its binary, no marker after a failed install) are now proven
# behaviourally in §71 against the real release layouts.

# ─── Section 25: phpbrew-install-tools version gates (row 17) ─────────────
printf '\n%b── Section 25: phpbrew-install-tools gates%b\n' "${C_BOLD}" "${C_RESET}"

# Row 17. Eleven tools. Ten were marker-based but wrote the marker BEFORE
# installing, so a failed install recorded success and every later boot skipped
# it; two of those ten (deployer, symfony-cli) never read their marker at all.
# The eleventh, laravel/installer, was unpinned and followed by a blanket
# `composer global update --with-all-dependencies` that would move any pin back.
#
# All eleven are covered behaviourally: §66 (composer, laravel), §67 (zephir, phalcon,
# deployer, pickle, pie, castor) and §68 (symfony, mago, fabpot). The structural checks
# below still pin the marker-last invariant the marker-first defect violated.
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

# Behavioural cover moved to §66 (composer, laravel) and §67 (zephir, phalcon, deployer,
# pickle, pie): pin tranche 2 step 15. The zephir-only 25g/25h it replaces extracted the
# block by its `rm -rf zephir.pha*` anchor, which step 15b deleted with the other globs;
# each of their four properties (first install, skip, bump, failed download → no marker)
# is asserted there for all five tools.

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

# Row 19. android.sdkmanager (android.cli since row 46) held the CLI BINARY's own version, so it could
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
# All 14 are pinned EXPLICITLY (12 at row 33; the two BUILD_TOOLS_VERSION_PREV_*
# compat slots joined at row 41). This is `env`, not `env -i` — PATH has to survive —
# so any input left unpinned would be inherited from the developer's shell, where
# the /stack vars are commonly exported: green on this machine, red on a clean one.
_and_env=(
  GLOBAL_STACK_ANDROID_SDK_BUILD=synthbuild
  GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION=1.0
  GLOBAL_STACK_ANDROID_PLATFORM_TOOLS_VERSION=2.0
  GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION=3.0
  GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION_PREV_1=3.1
  GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION_PREV_2=3.2
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
assert_pass "27b2: derived composite carries all 14 synthetic values (missing:${_want_missing:- none})" \
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
# Tranche 3 step 21 moved the wipe and the build into the iou (checked in a temp dir,
# §73), so start.sh keeps ONE gated branch: the iou call and the marker write after it.
_pma_guards="$(grep -c '\[ "${_pma_install}" = "1" \]' "${PMA}" || true)"
assert_pass "28d: start.sh's one phpmyadmin install branch uses the gate decision" \
  test "${_pma_guards}" = "1"
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
# Since tranche 3 step 22 there is no add-package at all (xcaddy builds the plugins in),
# so 39a can no longer fire; 74j asserts add-package is gone and §74 covers the pins.
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
# $3 = padding lines the listing prints AFTER the real ids (default 0). See 43ad.
# echoes "<rc>|<absent-ids>|<version-warn>"
_andv_probe() {
  local omit="${1}" ptv="${2:-37.0.1}" pad="${3:-0}" d="${TMP_DIR}/andv" rc out
  rm -rf "${d}"
  mkdir -p "${d}/bin" "${d}/versions"
  : >"${d}/asked"
  cat >"${d}/bin/android" <<STUB
#!/bin/bash
D="${d}"
OMIT="${omit}"
PTV="${ptv}"
PAD="${pad}"
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
    for ((i = 0; i < PAD; i++)); do
      printf '  pad/%s  0.0.0  a listing line past the 64 KiB pipe buffer\n' "\${i}"
    done
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
      GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION_PREV_1=36.1.0 \
      GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION_PREV_2=36.0.0 \
      GLOBAL_STACK_ANDROID_NDK_VERSION=30.0.16248370 \
      GLOBAL_STACK_ANDROID_API_LEVEL_1=37.0 \
      GLOBAL_STACK_ANDROID_API_LEVEL_2=37.1 \
      GLOBAL_STACK_ANDROID_API_LEVEL_3=37.2 \
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
# bump (the pin is env-update-tracked, `@todo env-update androidsdk:platform-tools`),
# and failing hard would block 04android plus the three consumers behind it on what
# is documentation drift, not a broken SDK.
assert_output_contains "43aa: a matching platform-tools version raises no warning" \
  '0||none' _andv_probe "" "37.0.1"
assert_output_contains "43ab: a platform-tools version adrift from the pin WARNs" \
  '|platform-tools 9.9.9 != pinned 37.0.1' _andv_probe "" "9.9.9"
# ...and the drift is a WARNING only: rc stays 0 and nothing is reported absent.
assert_output_contains "43ac: ...but does not fail the install (WARN, not FATAL)" \
  '0||platform-tools' _andv_probe "" "9.9.9"
# A present package must never read as absent. The verify used to test each id with
# `printf '%s\n' "${_installed}" | grep -qF` under pipefail: grep -q exits on its first
# match, a printf still writing then dies of SIGPIPE (PIPESTATUS "141 0"), and pipefail
# turns that into "absent" -- a FATAL on a good SDK. It hit only when grep won the race,
# so 43q/43ac went red at random under load (`1| ndk-bundle|none` on 2026-09-24 and
# 2026-09-26; 4 in 3000 in isolation). A listing longer than the pipe buffer after the
# real ids makes the race certain, so this reds on every run of the piped shape.
assert_output_contains "43ad: a present package is never reported absent, however long the listing (no SIGPIPE)" \
  '0||none' _andv_probe "" "" 3000
# The version read one screen down had the same shape: `printf | awk '… { print $2; exit }'`
# inside $(…) under set -e, so a SIGPIPE there ABORTED setup outright. mawk reads its input
# in large blocks, so 3000 lines never overflowed them; 60000 did [measured: rc 141 on 3/3,
# host and 04android image alike, mawk 1.3.4].
assert_output_contains "43ae: ...nor does reading the platform-tools version abort setup (no SIGPIPE)" \
  '0||none' _andv_probe "" "" 60000

# setup-dist.sh's AVD loop is EXECUTED here, not grepped. 43c/43e/43l are static and
# were green both before and after the loop was rewritten from glob-and-reverse-parse
# to tuple iteration, so none of them could have noticed a control-flow change. The
# stub avdmanager only creates the directory the script then writes into — the names,
# the levels, the pixel models and every substitution come from the script itself and
# from the REAL template, so the probe cannot pass by agreeing with a fixture.
#
# Row 47: the real avdmanager is the VERSIONED one, cmdline-tools/<ver>/bin. The
# unversioned bootstrap copy in cmdline-tools/bin derives its SDK root as
# APP_HOME/../.. = /stack/tools and printed ~380 package.xml/devices.xml warnings per
# boot. So the stub lives at the versioned path and a DECOY that exits 99 sits first on
# PATH, modelling the bootstrap copy: a script that calls a bare `avdmanager` reaches the
# decoy and 43v reds. The version is pinned here (this is `env`, not `env -i`, so an
# unpinned value would be inherited from the developer's shell).
# $1 = "nostub" leaves the versioned binary absent (43u2).
_andd_probe() { # echoes "<rc>|<n config.ini>|<leftover placeholders>|<sysdirs>|<avd ids>"
  local d="${TMP_DIR}/andd" rc out inis f all n vbin
  rm -rf "${d}"
  vbin="${d}/sdk/cmdline-tools/9.9/bin"
  mkdir -p "${d}/bin" "${d}/home/.android/avd" "${vbin}"
  printf '#!/bin/bash\necho "decoy: unversioned avdmanager reached" >&2\nexit 99\n' >"${d}/bin/avdmanager"
  chmod +x "${d}/bin/avdmanager"
  cat >"${vbin}/avdmanager" <<'STUB'
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
  chmod +x "${vbin}/avdmanager"
  [ "${1:-}" = "nostub" ] && rm -f "${vbin}/avdmanager"
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
      GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION=9.9 \
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
  [ "${1:-}" = "nostub" ] && printf '%s\n' "${out}"
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
    [ "$(printf "%s\n" "${b}" | wc -l)" -ge 20 ] && printf "%s\n" "${b}" | grep -q "create avd --force"' _ "${_ANDD}"
# A missing versioned avdmanager must fail LOUDLY and by name, before any AVD is
# touched -- not fall back to whatever `avdmanager` PATH happens to offer.
assert_output_contains "43u2: a missing versioned avdmanager is a named FATAL, rc 1, no AVD written" \
  'FATAL: avdmanager not executable at .*/cmdline-tools/9\.9/bin/avdmanager' _andd_probe nostub
assert_output_contains "43u3: ...and it exits 1 with zero config.ini" \
  '^1|0|' _andd_probe nostub

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

# env-update.md §7.9 documents the androidsdk fetcher. Until row 41 it described a
# `sdkmanager --list` invocation and this check pinned a "deprecated upstream" note
# beside it (anchored on the replacement command, not the word "deprecated", which
# upstream's own quoted message contains). Row 41 rewrote the fetcher to read
# Google's repository XML — no binary, no invocation to flag — so the check pins
# the new facts instead: the source URL and the offset-bearing cache key, which
# is the guard against three same-identifier slots sharing one cache entry.
# `|| true` on the anchor grep: it exits 1 when the
# §7.9 heading is gone, and under this suite's `set -euo pipefail` an unguarded
# miss killed the RUN at this line with no tally [measured 2026-09-12: the old
# anchor did exactly that after the doc rewrite, and two sabotage runs read as
# "not caught" until the 667-line log was opened — §47 had simply never run].
# Bounded by the NEXT heading, not by a line count. A fixed -A40 window made the
# check depend on the section's LENGTH: row 43 added prose above the cache-key
# line and pushed it out of view, redding a guard whose subject had not changed.
# A window that ordinary growth can invalidate reports drift that is not there,
# which is the mirror of the can-never-fire defect and costs the same trust.
_eu_note="$(awk '/^### 7\.9 androidsdk/{f=1} f&&/^### /&&!/7\.9 androidsdk/{exit} f' "${_EU_DOC}" || true)"
assert_output_contains "45b: env-update.md §7.9 names the repository XML as the androidsdk source" \
  'repository2-3.xml' printf '%s' "${_eu_note}"
assert_output_contains "45b2: ...and documents the offset-bearing cache key" \
  'androidsdk:component:channel:offN' printf '%s' "${_eu_note}"

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

# Non-vacuity floor: 14 as of row 41 (12 at row 33). Without it, a typo'd path or a strip that
# matched nothing would compare two EMPTY sets and report a clean pass.
_a47_n="$(printf '%s\n' "${_a47_consumed}" | grep -c . || true)"
assert_pass "47a: setup.sh consumes >= 14 android inputs (found ${_a47_n})" \
  test "${_a47_n}" -ge 14

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

# ─── Section 52: every `cargo install` under rust-bin is --locked ──────────
#
# `cargo install` IGNORES the committed/packaged Cargo.lock by default and
# re-resolves every dependency to the newest semver-compatible release at
# install time. Pinning a --tag therefore pins only OUR source, never the
# dependency set that tag was tested against, so any upstream break inside the
# range takes the install down with it.
#
# Measured 2026-09-12: `cargo install --git .../cargo-outdated --tag v0.19.0`
# with no --locked resolved `jiff 0.2.36` -- published 15:13 and YANKED the
# same day, superseded by 0.2.37 at 15:39. That release's Cargo.toml include
# list packages `/*.md`, which is PACKAGE-root relative, while src/lib.rs's
# ungated `pub mod _documentation` does include_str!("../../../../CHANGELOG.md"),
# three levels ABOVE the package root. The .crate archive carries 104 entries
# and not one .md, so the published crate cannot compile at all: `couldn't read
# .../CHANGELOG.md`, rustc exit 101. 02rust exhausted its on-failure:5 budget
# and 03python3 + 05edge stayed in `created` behind it. v0.19.0's own
# Cargo.lock pins jiff 0.2.23, which builds.
#
# Note the shape of the trap: 0.2.36 is yanked now, so an UNLOCKED install
# today resolves 0.2.37 and succeeds. A green 02rust is therefore NOT evidence
# that this is fixed -- only the resolved jiff version in the build log is.
#
# The convention was already established in this directory: nextest, zigbuild,
# jujutsu and mergiraf all carry --locked and cargo-outdated was the single
# omission, so this is an outlier restored to the local rule, not a new policy.
# DISCOVERED rather than listed -- a sixth install site added without --locked
# reds here instead of waiting for the next upstream break to find it.
#
# Comment lines are stripped first: cargo-nextest.sh explains its --force in a
# comment that contains the literal `cargo install`, and counting that would
# seat a permanently un-fixable offender in the corpus (the §19 shape).
printf '\n%b── Section 52: every cargo install under rust-bin is --locked%b\n' "${C_BOLD}" "${C_RESET}"

_a52_offenders=""
_a52_scanned=0
while IFS= read -r -d '' _a52_f; do
  while IFS= read -r _a52_line; do
    _a52_scanned=$((_a52_scanned + 1))
    case "${_a52_line}" in
    *--locked*) ;;
    *) _a52_offenders="${_a52_offenders} $(basename "${_a52_f}")" ;;
    esac
  done < <(grep -v '^[[:space:]]*#' "${_a52_f}" | grep 'cargo install' || true)
done < <(find "${DIST_BIN}/rust-bin" -name '*.sh' -print0 2>/dev/null)

# Non-vacuity: a typo in the find root yields an empty scan, zero offenders and
# a green check -- the can-never-fire defect §19 carried one level up. Five
# install sites when this was written; the floor sits at five so removing one
# is a deliberate act that reds rather than silently shrinking the guard.
assert_pass "52a: the scan actually reached the rust install sites (>= 5)" \
  bash -c 'test "$1" -ge 5' _ "${_a52_scanned}"

# Asserts the SET, not a count, so a red names the offending script rather than
# reporting a bare number that a broken extraction could also produce.
assert_output_contains "52b: no cargo install under rust-bin omits --locked" \
  '^NONE$' printf '%s\n' "${_a52_offenders:-NONE}"

# ─── Section 53: android.sdkmanager -> android.cli marker, migrated ───────
printf '\n%b── Section 53: android CLI marker rename (row 46)%b\n' "${C_BOLD}" "${C_RESET}"

# Row 46. The marker that records `android --version` was still named after the
# deprecated sdkmanager. It is only an existence flag, but a bare rename is NOT
# safe: start.sh treats an ABSENT marker as "never installed" and answers with
# `sudo rm -rf "${ANDROID_HOME}"` plus a 15-minute SDK reinstall. So start.sh
# carries a migration that moves the old file into place BEFORE the gate reads it.
# The block is extracted by its sentinel comments, never by line numbers.
_a53_block="$(awk '/^# >>> android-marker-migration/{f=1; next} /^# <<< android-marker-migration/{f=0} f' "${AND_START}" || true)"

# Non-vacuity: an anchor that stops matching yields an empty script, which exits
# 0 and would make every probe below read as a pass.
assert_pass "53a: start.sh carries the marker migration block (and it really moves the file)" \
  bash -c 'grep -q "mv " <<<"$1" && grep -q "android\.sdkmanager" <<<"$1" && grep -q "android\.cli" <<<"$1"' _ "${_a53_block}"

# Runs the SHIPPED block against a tmpdir. The VERSIONS pin is load-bearing: the
# variable is set in an ordinary /stack shell, and a probe inheriting it would move
# the live tools/versions marker (the §46 lesson).
_a53_probe() {
  local _d _rc=0
  _d="$(mktemp -d)"
  case "$1" in
    old) printf 'old-build\n' >"${_d}/android.sdkmanager" ;;
    both)
      printf 'old-build\n' >"${_d}/android.sdkmanager"
      printf 'new-build\n' >"${_d}/android.cli"
      ;;
  esac
  GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${_d}" bash -eu -c "${_a53_block}" >/dev/null 2>&1 || _rc=$?
  printf 'rc=%s old=%s new=%s\n' "${_rc}" \
    "$(cat "${_d}/android.sdkmanager" 2>/dev/null || echo -)" \
    "$(cat "${_d}/android.cli" 2>/dev/null || echo -)"
  rm -rf "${_d}"
}
assert_output_contains "53b: an old marker is MOVED to android.cli, content intact (no reinstall)" \
  '^rc=0 old=- new=old-build$' _a53_probe old
assert_output_contains "53c: no marker stays no marker (a fresh volume still installs)" \
  '^rc=0 old=- new=-$' _a53_probe none
assert_output_contains "53d: a newer android.cli is never overwritten; the stale old one goes" \
  '^rc=0 old=- new=new-build$' _a53_probe both

# Outside the migration block, and outside comments, nothing may still read or
# write the old name -- a gate left on android.sdkmanager would see the moved
# file as absent and wipe the SDK on every boot.
_a53_live_old="$(awk '/^# >>> android-marker-migration/{f=1} /^# <<< android-marker-migration/{f=0; next} !f' "${AND_START}" "${AND_SETUP}" \
  | grep -v '^[[:space:]]*#' | grep -c 'android\.sdkmanager' || true)"
assert_pass "53e: no live android.sdkmanager reference outside the migration (found ${_a53_live_old})" \
  test "${_a53_live_old}" -eq 0
_a53_gate_new="$(grep -v '^[[:space:]]*#' "${AND_START}" | grep -c 'VERSIONS}/android\.cli' || true)"
assert_pass "53f: the gate conditions and the wipe read android.cli (>= 3, found ${_a53_gate_new})" \
  test "${_a53_gate_new}" -ge 3
assert_pass "53g: setup.sh records the CLI version into android.cli" \
  grep -qE '^android --version > "\$\{GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS\}/android\.cli"$' "${AND_SETUP}"

# ─── Section 54: android PATH order, dead entries, licence guard ─────────
printf '\n%b── Section 54: android PATH order + sdkmanager licence guard (row 47)%b\n' "${C_BOLD}" "${C_RESET}"

# Row 47. Two copies of cmdline-tools exist: the unversioned bootstrap in
# cmdline-tools/bin (its launcher resolves the SDK root to /stack/tools) and the
# versioned cmdline-tools/<ver>/bin (resolves it correctly). Whichever comes first on
# PATH answers a bare avdmanager/sdkmanager, so the VERSIONED one must come first.
# The unversioned one stays: a reinstall's bare `android` needs it before <ver> exists.
# The sites are DISCOVERED (anchored PATH=, the §48 shape, comments stripped) across
# dist/bin AND the host template, never listed.
_a54_lines="$({
  find "${DIST_BIN}" -name '*.sh' -type f -print0 | xargs -0 grep -HnE '(^|[^A-Za-z0-9_])PATH=.*cmdline-tools' || true
  grep -HnE '(^|[^A-Za-z0-9_])PATH=.*cmdline-tools' "${REPO_ROOT}/templates/shell/profile.sh" || true
} | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
_a54_n=0
_a54_order=""
_a54_dead=""
while IFS= read -r _l; do
  [ -n "${_l}" ] || continue
  _a54_n=$((_a54_n + 1))
  _f="${_l%%:*}"
  _r="${_l#*:}"
  _where="$(basename "${_f}"):${_r%%:*}"
  IFS=':' read -r -a _els <<<"${_r#*:}"
  _vi=-1
  _ui=-1
  for _i in "${!_els[@]}"; do
    # shellcheck disable=SC2016 # literal ${...} text, matched verbatim
    case "${_els[${_i}]}" in
      '${ANDROID_HOME}/cmdline-tools/${GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION}/bin') _vi=${_i} ;;
      '${ANDROID_HOME}/cmdline-tools/bin') _ui=${_i} ;;
      '${ANDROID_HOME}/cmdline-tools/tools/bin' | '${ANDROID_HOME}/tools' | '${ANDROID_HOME}/tools/bin') _a54_dead+="${_where} " ;;
    esac
  done
  if [ "${_vi}" -lt 0 ] || { [ "${_ui}" -ge 0 ] && [ "${_ui}" -lt "${_vi}" ]; }; then
    _a54_order+="${_where} "
  fi
done <<<"${_a54_lines}"
# Non-vacuity: 4 dist/bin lines (android-start x2, alltogether-start x2) + profile.sh.
assert_pass "54a: android PATH sites discovered (>= 5, found ${_a54_n})" test "${_a54_n}" -ge 5
assert_pass "54b: versioned cmdline-tools precedes the unversioned one everywhere (offenders: ${_a54_order:-none})" \
  test -z "${_a54_order}"
assert_pass "54c: no dead legacy SDK entries on PATH (offenders: ${_a54_dead:-none})" \
  test -z "${_a54_dead}"

# `flutter doctor --android-licenses` shells out to the deprecated sdkmanager and
# prints two deprecation lines. It runs only when no licence is on disk yet. Exactly
# one live call, and the shipped line itself is EXECUTED against a stub flutter.
_a54_lic="$(grep -v '^[[:space:]]*#' "${AND_START}" | grep -e '--android-licenses' || true)"
assert_pass "54d: exactly one live --android-licenses line in start.sh" \
  test "$(printf '%s\n' "${_a54_lic}" | grep -c . || true)" -eq 1
_a54_probe() { # $1 = with|without licence file; echoes called|skipped
  local _d
  _d="$(mktemp -d)"
  mkdir -p "${_d}/bin" "${_d}/sdk"
  printf '#!/bin/bash\n: >"%s/called"\n' "${_d}" >"${_d}/bin/flutter"
  chmod +x "${_d}/bin/flutter"
  if [ "$1" = with ]; then
    mkdir -p "${_d}/sdk/licenses"
    printf 'x\n' >"${_d}/sdk/licenses/android-sdk-license"
  fi
  env PATH="${_d}/bin:$(printenv PATH)" ANDROID_HOME="${_d}/sdk" bash -eE -o pipefail -c "${_a54_lic}" >/dev/null 2>&1 || true
  if [ -e "${_d}/called" ]; then echo called; else echo skipped; fi
  rm -rf "${_d}"
}
assert_output_contains "54e: a licence already on disk -> flutter doctor --android-licenses is NOT run" \
  '^skipped$' _a54_probe with
assert_output_contains "54f: no licence on disk (fresh install) -> it still runs" \
  '^called$' _a54_probe without

# ─── Section 55: phpbrew tool pins reach their gates (tranche 1 step 5) ──
printf '\n%b── Section 55: phpbrew install-tools.sh runs on every install-mode boot (pin-audit A2)%b\n' "${C_BOLD}" "${C_RESET}"
# install-tools.sh holds 12 correct per-tool gates (composer, laravel, symfony,
# mago, castor, …) but its only caller sat INSIDE the phpbrew-version check, so a
# bump of any tool pin alone never reached them. The unit under test is the CALL
# SITE's reachability, not the tool gates (those are equality-based and skip
# without network). The region runs from the phpbrew gate line to the setup
# block, an anchor pair that brackets the call both before and after the fix.
_P55_START="${DIST_BIN}/phpbrew-bin/global-stack-phpbrew-start.sh"
_p55_region="$(awk '
  index($0, "gs_version_gate \"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew\"") == 1 { f = 1 }
  f && /^if \[ "\$\{PHPBREW_MODE\}" = "setup" \]; then$/ { exit }
  f { print }' "${_P55_START}")"
assert_pass "55a: extracted install-mode region calls both install-tools.sh and iou.sh (non-vacuity)" \
  bash -c 'grep -q "global-stack-phpbrew-install-tools.sh" <<<"$1" && grep -q "global-stack-phpbrew-iou.sh" <<<"$1"' _ "${_p55_region}"
_p55_run() { # $1 = phpbrew pin, $2 = phpbrew marker content → echoes the ordered calls
  local _d
  _d="$(mktemp -d)"
  mkdir -p "${_d}/bin" "${_d}/versions"
  printf '%s\n' "$2" >"${_d}/versions/phpbrew"
  for _s in global-stack-phpbrew-install-tools.sh global-stack-phpbrew-iou.sh; do
    printf '#!/bin/sh\necho %s >>"%s/calls"\n' "${_s%.sh}" "${_d}" >"${_d}/bin/${_s}"
    chmod +x "${_d}/bin/${_s}"
  done
  env -i PATH="${_d}/bin:/usr/bin:/bin" GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${_d}/versions" \
    GLOBAL_STACK_PHPBREW_VERSION="$1" GLOBAL_STACK_RELOAD_PHPBREW=false PHPBREW_MODE=install \
    bash -c "set -eE; source '${DIST_BIN}/base-bin/global-stack-base-version-gate.sh'; $(printf '%s' "${_p55_region}")" >/dev/null 2>&1 || true
  if [[ -f "${_d}/calls" ]]; then tr '\n' ' ' <"${_d}/calls"; else echo none; fi
  rm -rf "${_d}"
}
assert_output_contains "55b: phpbrew current (a tool pin bumped alone) -> install-tools.sh still runs" \
  'global-stack-phpbrew-install-tools' _p55_run 2.2.0 2.2.0
assert_fail "55c: phpbrew current -> iou.sh is NOT run (the phpbrew pin is locked to 2.2.0 by design)" \
  bash -c 'grep -q iou <<<"$1"' _ "$(_p55_run 2.2.0 2.2.0)"
assert_output_contains "55d: phpbrew mismatch -> install-tools.sh runs BEFORE iou.sh (iou needs composer)" \
  '^global-stack-phpbrew-install-tools global-stack-phpbrew-iou $' _p55_run 9.9.9 2.2.0

# ─── Section 56: pyenv/rbenv follow their pin both ways (tranche 1 step 6) ──
# pin-audit A1. `*-iou.sh` cloned only when `${ROOT}/.git` was absent, and was itself
# called only on a manager-marker mismatch — so a PYENV/RBENV bump, up or down, never
# moved the checkout (the marker then recorded `--version`, i.e. the OLD tag, and the
# mismatch repeated every boot), and the rbenv plugin gates inside iou (row 21) were
# unreachable whenever rbenv itself was current. Two halves: reachability (the start
# script calls iou on EVERY install-mode boot) and behaviour against REAL git (iou
# moves an existing clone to the pin's tag in either direction, and touches the
# network only when the checkout is not already at that tag).
printf '\n%b── Section 56: pyenv/rbenv managers follow their pin both ways (pin-audit A1)%b\n' "${C_BOLD}" "${C_RESET}"

_p56_region() { # $1 = pyenv|rbenv → the shipped install-mode manager block (gate line .. before the closing fi)
  P56_ANCHOR="gs_version_gate \"\${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/$1\"" awk '
    index($0, ENVIRON["P56_ANCHOR"]) { f = 1 }
    f && /^fi$/ { exit }
    f { print }' "${DIST_BIN}/$1-bin/global-stack-$1-start.sh"
}
_p56_run() { # $1 = pyenv|rbenv, $2 = pin, $3 = manager marker → "iou" when iou ran, else "none"
  local up d
  up="$(tr '[:lower:]' '[:upper:]' <<<"$1")"
  d="$(mktemp -d)"
  mkdir -p "${d}/bin" "${d}/versions"
  printf '%s\n' "$3" >"${d}/versions/$1"
  printf '#!/bin/sh\necho iou >>"%s/calls"\n' "${d}" >"${d}/bin/global-stack-$1-iou.sh"
  chmod +x "${d}/bin/global-stack-$1-iou.sh"
  env -i PATH="${d}/bin:/usr/bin:/bin" GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${d}/versions" \
    "GLOBAL_STACK_${up}_VERSION=$2" "GLOBAL_STACK_RELOAD_${up}=false" "${up}_MODE=install" \
    bash -c "set -eE; source '${DIST_BIN}/base-bin/global-stack-base-version-gate.sh'; $(_p56_region "$1")" >/dev/null 2>&1 || true
  if [[ -f "${d}/calls" ]]; then tr -d '\n' <"${d}/calls"; else echo none; fi
  rm -rf "${d}"
}
for _rt in pyenv rbenv; do
  assert_pass "56a: ${_rt} extracted install-mode manager block calls ${_rt}-iou.sh (non-vacuity)" \
    grep -q "global-stack-${_rt}-iou.sh" <<<"$(_p56_region "${_rt}")"
  assert_pass "56b: ${_rt} marker current (a plugin/tag state to reconcile) -> iou.sh still runs" \
    test "$(_p56_run "${_rt}" v1.3.0 1.3.0)" = "iou"
  assert_pass "56c: ${_rt} marker stale -> iou.sh runs" \
    test "$(_p56_run "${_rt}" v1.3.0 1.2.0)" = "iou"
done

# ── behaviour: the shipped iou against a real upstream repo ──
_P56="${TMP_DIR}/p56"
mkdir -p "${_P56}/errors" "${_P56}/versions"
(
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=master -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
  g init -q "${_P56}/upstream"
  printf '/versions\n/plugins\n' >"${_P56}/upstream/.gitignore"
  printf 'one\n' >"${_P56}/upstream/f"
  g -C "${_P56}/upstream" add -A && g -C "${_P56}/upstream" commit -qm one
  g -C "${_P56}/upstream" tag -a v1.0.0 -m v1.0.0
  printf 'two\n' >"${_P56}/upstream/f"
  g -C "${_P56}/upstream" commit -qam two
  g -C "${_P56}/upstream" tag -a v1.1.0 -m v1.1.0
) >/dev/null 2>&1
_P56_C1="$(git -C "${_P56}/upstream" rev-parse 'v1.0.0^{commit}' 2>/dev/null || true)"
_P56_C2="$(git -C "${_P56}/upstream" rev-parse 'v1.1.0^{commit}' 2>/dev/null || true)"
assert_pass "56d: upstream fixture has two distinct tagged commits (non-vacuity)" \
  bash -c '[[ -n "$1" && -n "$2" && "$1" != "$2" ]]' _ "${_P56_C1}" "${_P56_C2}"

_p56_clone() { # $1 = dest, $2 = tag to start at; an ignored versions/ tree stands in for installed runtimes
  rm -rf "$1"
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -c advice.detachedHead=false clone -q --branch "$2" "${_P56}/upstream" "$1" >/dev/null 2>&1
  mkdir -p "$1/versions/3.14.7" "$1/plugins/ruby-build"
  : >"$1/versions/3.14.7/keep"
}
_p56_iou() { # $1 = pyenv|rbenv, $2 = root, $3 = pin → echoes "<rc> <HEAD>"
  local up rc=0
  up="$(tr '[:lower:]' '[:upper:]' <<<"$1")"
  env -i PATH="${DIST_BIN}/base-bin:/usr/bin:/bin" HOME="${_P56}" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GLOBAL_STACK_ERROR_TOKEN=p56-token GLOBAL_STACK_DOCKER_TOOLS_PATH="${_P56}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${_P56}/errors" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${_P56}/versions" \
    "${up}_ROOT=$2" "GLOBAL_STACK_${up}_VERSION=$3" \
    GLOBAL_STACK_RBENV_RUBY_BUILD_VERSION= GLOBAL_STACK_RBENV_GEMSET_VERSION= \
    bash "${DIST_BIN}/$1-bin/global-stack-$1-iou.sh" >/dev/null 2>&1 || rc=$?
  printf '%s %s' "${rc}" "$(git -C "$2" rev-parse HEAD 2>/dev/null || echo none)"
}
for _rt in pyenv rbenv; do
  _r="${_P56}/${_rt}-root"
  _p56_clone "${_r}" v1.0.0
  assert_pass "56e: ${_rt} existing clone at v1.0.0, pin bumped to v1.1.0 -> checkout moves UP" \
    test "$(_p56_iou "${_rt}" "${_r}" v1.1.0)" = "0 ${_P56_C2}"
  assert_pass "56f: ${_rt} ignored versions/ tree survives the move (installed runtimes kept)" \
    test -f "${_r}/versions/3.14.7/keep"
  _p56_clone "${_r}" v1.1.0
  assert_pass "56g: ${_rt} existing clone at v1.1.0, pin moved back to v1.0.0 -> checkout moves DOWN" \
    test "$(_p56_iou "${_rt}" "${_r}" v1.0.0)" = "0 ${_P56_C1}"
  _p56_clone "${_r}" v1.1.0
  git -C "${_r}" remote set-url origin "${_P56}/no-such-remote"
  assert_pass "56h: ${_rt} checkout already at the pin -> no fetch (origin unreachable, still rc 0)" \
    test "$(_p56_iou "${_rt}" "${_r}" v1.1.0)" = "0 ${_P56_C2}"
  _p56_clone "${_r}" v1.0.0
  _o="$(_p56_iou "${_rt}" "${_r}" v9.9.9)"
  assert_pass "56i: ${_rt} pin with no such tag upstream -> fails loud, checkout left at v1.0.0" \
    bash -c '[[ "${1%% *}" != 0 && "${1#* }" == "$2" ]]' _ "${_o}" "${_P56_C1}"
done

# ─── Section 57: resolver fails fast; nothing deleted until the new install succeeds ──
# pin-audit A1, second half. find-latest fell back to the RAW pin when the manager knew
# no matching definition, and the gate then deleted the working interpreter, every pkg
# marker and the version marker BEFORE `pyenv install` / `rbenv install` ran — so a pin
# the manager could not build left the runtime gone. The resolver now exits non-zero
# with no output (the prologue's ERR trap writes the error token, the old runtime is
# untouched), and the reinstall deletes the old version dir and wipes pkg.* only after
# the new interpreter installed; the marker is rewritten by the existing write below.
printf '\n%b── Section 57: resolver fail-fast + delete-after-install (pin-audit A1)%b\n' "${C_BOLD}" "${C_RESET}"

_p57_find() { # $1 = pyenv|rbenv, $2 = pin (no versions/<pin> dir) → echoes "<rc>:<stdout>"
  local rc=0 out root="${TMP_DIR}/p57-find-root"
  rm -rf "${root}"
  mkdir -p "${root}/versions"
  if [[ "$1" == pyenv ]]; then
    out="$(env -i PATH="${TMP_DIR}/rb/bin:/usr/bin:/bin" PYENV_ROOT="${root}" PYTHON_VERSION="$2" \
      GLOBAL_STACK_PYTHON_STABLE=true bash "${_py_find}" "$2" 2>/dev/null)" || rc=$?
  else
    out="$(env -i PATH="${TMP_DIR}/rb/bin:/usr/bin:/bin" RBENV_ROOT="${root}" RUBY_VERSION="$2" \
      bash "${_rb_find}" "$2" 2>/dev/null)" || rc=$?
  fi
  printf '%s:%s' "${rc}" "${out}"
}
# §20's stubs list 3.14.5-3.14.7 (pyenv) and 3.4.8-3.4.10 (rbenv); these pins match none.
assert_pass "57a: pyenv resolver, pin unknown to the definitions -> non-zero exit, no output" \
  bash -c '[[ "${1%%:*}" != 0 && -z "${1#*:}" ]]' _ "$(_p57_find pyenv 3.15)"
assert_pass "57b: rbenv resolver, pin unknown to the definitions -> non-zero exit, no output" \
  bash -c '[[ "${1%%:*}" != 0 && -z "${1#*:}" ]]' _ "$(_p57_find rbenv 3.5)"

# The gate block alone, on a real reinstall decision (marker 3.14.7 → resolved 3.14.8):
# it must DECIDE, not delete.
_p57_gate() { # $1 = pyenv|rbenv → "dir=<0|1> pkg=<0|1> marker=<content>" after the gate block ran
  local rt="$1" var root src d
  if [[ "${rt}" == pyenv ]]; then var=_python root=PYENV_ROOT; else var=_ruby root=RBENV_ROOT; fi
  src="${DIST_BIN}/${rt}-bin/global-stack-${rt}-start.sh"
  d="$(mktemp -d)"
  mkdir -p "${d}/bin" "${d}/versions" "${d}/root/versions/3.14.7"
  printf '#!/bin/bash\necho 3.14.8\n' >"${d}/bin/global-stack-${rt}-find-latest.sh"
  chmod +x "${d}/bin/global-stack-${rt}-find-latest.sh"
  local lbl
  [[ "${rt}" == pyenv ]] && lbl=python.3 || lbl=ruby.3
  printf '3.14.7\n' >"${d}/versions/${lbl}"
  : >"${d}/versions/${lbl}.pkg.1"
  {
    printf '#!/bin/bash\nset -eE -o pipefail\nsource global-stack-base-prologue.sh\n'
    sed -n "/^  ${var}_label=/,/^  fi\$/p" "${src}"
  } >"${d}/gate.sh"
  env PATH="${d}/bin:${DIST_BIN}/base-bin:${PATH}" GLOBAL_STACK_ERROR_TOKEN=p57-token \
    GLOBAL_STACK_DOCKER_TOOLS_PATH="${d}" GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${d}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${d}/versions" "${root}=${d}/root" \
    PYTHON_VERSION=3.14.8 PYTHON_VERSION_AS=3 RUBY_VERSION=3.14.8 RUBY_VERSION_AS=3 \
    bash "${d}/gate.sh" >/dev/null 2>&1 || true
  printf 'dir=%s pkg=%s marker=%s' \
    "$([[ -d "${d}/root/versions/3.14.7" ]] && echo 1 || echo 0)" \
    "$([[ -f "${d}/versions/${lbl}.pkg.1" ]] && echo 1 || echo 0)" \
    "$(cat "${d}/versions/${lbl}" 2>/dev/null || echo none)"
  rm -rf "${d}"
}
for _rt in pyenv rbenv; do
  assert_pass "57c: ${_rt} gate on a reinstall decision leaves old dir, pkg markers and marker in place" \
    test "$(_p57_gate "${_rt}")" = "dir=1 pkg=1 marker=3.14.7"
done

# The post-install cleanup: extracted by its own `if` (4-space indent, inside the install branch).
_p57_cleanup_block() { # $1 = pyenv|rbenv
  local var
  [[ "$1" == pyenv ]] && var=_python || var=_ruby
  sed -n "/^    if \[\[ \"\\\${${var}_gate}\" == \"reinstall\" \]\]; then\$/,/^    fi\$/p" \
    "${DIST_BIN}/$1-bin/global-stack-$1-start.sh"
}
_p57_cleanup() { # $1 = pyenv|rbenv, $2 = "installed" | "absent" (the new version dir) → "rc=<0|1> old=<0|1> new=<0|1> pkg=<0|1>"
  local rt="$1" var root lbl d rc=0
  if [[ "${rt}" == pyenv ]]; then var=_python root=PYENV_ROOT lbl=python.3; else var=_ruby root=RBENV_ROOT lbl=ruby.3; fi
  d="$(mktemp -d)"
  mkdir -p "${d}/versions" "${d}/root/versions/3.14.7"
  [[ "$2" == installed ]] && mkdir -p "${d}/root/versions/3.14.8"
  : >"${d}/versions/${lbl}.pkg.1"
  { printf '#!/bin/bash\nset -eE -o pipefail\n'; _p57_cleanup_block "${rt}"; } >"${d}/c.sh"
  env -i PATH="/usr/bin:/bin" GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${d}/versions" "${root}=${d}/root" \
    "${var}_gate=reinstall" "${var}_old=3.14.7" "${var}_resolved=3.14.8" "${var}_label=3" \
    bash "${d}/c.sh" >/dev/null 2>&1 || rc=1
  printf 'rc=%s old=%s new=%s pkg=%s' "${rc}" \
    "$([[ -d "${d}/root/versions/3.14.7" ]] && echo 1 || echo 0)" \
    "$([[ -d "${d}/root/versions/3.14.8" ]] && echo 1 || echo 0)" \
    "$([[ -f "${d}/versions/${lbl}.pkg.1" ]] && echo 1 || echo 0)"
  rm -rf "${d}"
}
for _rt in pyenv rbenv; do
  if [[ "${_rt}" == pyenv ]]; then
    _inst='global-stack-pyenv-python${PYTHON_VERSION_AS}-install-version.sh'
  else
    _inst='rbenv install --verbose --skip-existing --keep'
  fi
  _src="${DIST_BIN}/${_rt}-bin/global-stack-${_rt}-start.sh"
  assert_pass "57d: ${_rt} post-install cleanup block exists (non-vacuity)" \
    grep -q 'rm -rf' <<<"$(_p57_cleanup_block "${_rt}")"
  assert_pass "57e: ${_rt} cleanup after a successful install drops the OLD dir and pkg markers, keeps the new" \
    test "$(_p57_cleanup "${_rt}" installed)" = "rc=0 old=0 new=1 pkg=0"
  # `source <shellrc> && <install>`: set -e does not fire on a failing NON-final member
  # of an && list, so a failed `source` skips the install and falls through. The
  # cleanup must refuse to drop the old version when the new one is not on disk.
  assert_pass "57h: ${_rt} new version dir absent at cleanup -> non-zero, old dir and pkg markers kept" \
    test "$(_p57_cleanup "${_rt}" absent)" = "rc=1 old=1 new=0 pkg=1"
  # Order is the guarantee: under set -e a failed install aborts before the cleanup line.
  _l_inst="$(grep -nF "${_inst}" "${_src}" | head -n1 | cut -d: -f1 || true)"
  _l_clean="$(grep -nE "^    if \[\[ \"\\\$\{_(python|ruby)_gate\}\" == \"reinstall\" \]\]; then\$" "${_src}" | head -n1 | cut -d: -f1 || true)"
  # `|| true` on the three lookups: a line that is not there must red 57f, not abort
  # the run under set -euo pipefail (a missing tally line reads as "not caught").
  _l_pkgs="$(grep -nF 'source /usr/local/bin/global-stack-base-setup-packages.sh' "${_src}" | head -n1 | cut -d: -f1 || true)"
  assert_pass "57f: ${_rt} order is install < cleanup < package loop" \
    bash -c '[[ -n "$1" && -n "$2" && -n "$3" ]] && (( $1 < $2 && $2 < $3 ))' _ "${_l_inst}" "${_l_clean}" "${_l_pkgs}"
  # Every runtime-marker-absent trigger in setup mode must also fire on a reinstall
  # decision, because the marker is no longer deleted up front.
  _n_trig="$(grep -cE '^  if \[\[ ! -f "\$\{GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS\}/(python|ruby)\.' "${_src}" || true)"
  _n_miss="$(grep -E '^  if \[\[ ! -f "\$\{GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS\}/(python|ruby)\.' "${_src}" | grep -vc '_gate}" == "reinstall"' || true)"
  assert_pass "57g: ${_rt} every setup-mode install trigger also fires on reinstall (${_n_trig} found, >= 2)" \
    bash -c '(( $1 >= 2 && $2 == 0 ))' _ "${_n_trig}" "${_n_miss}"
done

# ─── Section 58: rustup-init honours its pin both ways (tranche 1 step 7) ──
# pin-audit pass 2. rust-iou.sh sed-patched the downloaded installer's URL to pin
# rustup-init; at tag 1.29.1 upstream builds that URL from a RUSTUP_VERSION env var
# over three lines, so the sed matched nothing and rustup floated to latest while
# the rust-init marker (written BEFORE any install, from the pin) claimed the pin.
# And the whole script ran only on a RUST mismatch, so a RUSTUP_INIT bump alone was
# never reached. Measured 2026-09-24 against the real installers (scratch homes):
# re-running the install replaces rustup in EITHER direction; `rustup toolchain install`
# with auto-self-update left enabled self-updates rustup to latest (observed 1.28.2 ->
# 1.29.1: "info: downloading self-update"); the setting persists in settings.toml.
printf '\n%b── Section 58: rustup-init honours its pin both ways (pin-audit pass 2)%b\n' "${C_BOLD}" "${C_RESET}"

# Tranche 3 step 20 (2026-09-26): the installer script is gone. rust-iou.sh now fetches
# the pinned rustup-init BINARY + its .sha256 from static.rust-lang.org and checks both
# (and the binary's own --version) BEFORE anything is wiped. The stubs model what was
# MEASURED for 1.29.1: the .sha256 line is `<hex> *./rustup-init`; `rustup-init --version`
# prints `rustup-init 1.29.1 (d95a37b6a 2026-08-13)`; run with -y it installs itself as
# ${CARGO_HOME}/bin/rustup (so rustup reports rustup-init's version) and writes
# ${CARGO_HOME}/env; re-running it over an install replaces rustup and keeps toolchains.
_P58="${TMP_DIR}/p58"
mkdir -p "${_P58}/tpl" "${_P58}/fix"
cat >"${_P58}/tpl/curl" <<'STUB'
#!/bin/bash
out="" url="" fail=0
while (($#)); do
  case "$1" in
    -o) out="$2"; shift ;;
    --connect-timeout|--max-time) shift ;;
    -*) [[ "$1" == --* ]] || [[ "$1" != *f* ]] || fail=1 ;;
    *) url="$1" ;;
  esac
  shift
done
echo curl >>"${P58_LOG}"
src="${P58_FIX}/${url#https://static.rust-lang.org/rustup/archive/}"
src="${src/\/x86_64-unknown-linux-gnu\//\/}"
if [[ -f "${src}" ]]; then cat "${src}" >"${out}"; exit 0; fi
((fail)) && exit 22
printf '<html>404</html>\n' >"${out}"
STUB
cat >"${_P58}/tpl/rustup" <<'STUB'
#!/bin/bash
case "$1 $2" in
  "--version "*) echo "rustup $(cat "${CARGO_HOME}/bin/.ver") (stub 2026-01-01)"; exit 0 ;;
  "set auto-self-update") echo "$3" >"${RUSTUP_HOME}/auto_self_update"; echo "asu:$3" >>"${P58_LOG}"; exit 0 ;;
  "toolchain install")
    echo "toolchain:$3" >>"${P58_LOG}"
    [ "$(cat "${RUSTUP_HOME}/auto_self_update" 2>/dev/null)" = disable ] || echo 9.9.9 >"${CARGO_HOME}/bin/.ver"
    mkdir -p "${RUSTUP_HOME}/toolchains/$3"
    printf '#!/bin/sh\necho "rustc %s (stub 2026-01-01)"\n' "${P58_RUSTC:-$3}" >"${CARGO_HOME}/bin/rustc"
    chmod +x "${CARGO_HOME}/bin/rustc"
    exit 0 ;;
  "default "*) echo "default:$2" >>"${P58_LOG}"; exit 0 ;;
esac
echo "rustup:$*" >>"${P58_LOG}"
STUB
chmod +x "${_P58}/tpl/"*
# _p58_ri <version> <what --version reports> <sha: ok|bad|unlisted>
_p58_ri() {
  local d="${_P58}/fix/$1"
  mkdir -p "${d}"
  cat >"${d}/rustup-init" <<STUB
#!/bin/bash
if [ "\$1" = --version ]; then echo "rustup-init $2 (d95a37b6a 2026-08-13)"; exit 0; fi
echo "rustup-init:$1:\$(IFS=_; echo "\$*")" >>"\${P58_LOG}"
mkdir -p "\${CARGO_HOME}/bin" "\${RUSTUP_HOME}"
cp "\${P58_TPL}/rustup" "\${CARGO_HOME}/bin/rustup"
chmod +x "\${CARGO_HOME}/bin/rustup"
printf '%s\n' "$1" >"\${CARGO_HOME}/bin/.ver"
: >"\${CARGO_HOME}/env"
STUB
  case "$3" in
    ok) printf '%s *./rustup-init\n' "$(sha256sum "${d}/rustup-init" | awk '{ print $1 }')" >"${d}/rustup-init.sha256" ;;
    bad) printf '%064d *./rustup-init\n' 0 >"${d}/rustup-init.sha256" ;;
    unlisted) printf '%s *./rustup-init.exe\n' "$(sha256sum "${d}/rustup-init" | awk '{ print $1 }')" >"${d}/rustup-init.sha256" ;;
  esac
}
_p58_ri 1.28.2 1.28.2 ok
_p58_ri 1.29.1 1.29.1 ok
_p58_ri 1.29.2 1.29.20 ok   # reports another version: the space after the version is checked
_p58_ri 1.29.3 1.29.3 bad
_p58_ri 1.29.4 1.29.4 unlisted
# 1.29.5 is not published (curl -f exits 22).

# _p58_run <rustup pin> <rust-init marker|""> <installed rustup|""> <rust marker|""> [rust pin] [RELOAD_RUST]
#   → "rc=<n> rustup=<ver|none> init=<marker|none> rust=<marker|none> rustc=<ver|none> jj=<kept|gone>
#      token=<0|1> fatal=<n> calls=<a,b,...>"
# An installed rustup comes with a planted ${CARGO_HOME}/bin/jj (a cargo-installed tool) and an
# old toolchain dir: a RUST wipe must take both, anything else must leave them.
_p58_run() {
  local d rc=0
  d="$(mktemp -d)"
  mkdir -p "${d}/bin" "${d}/tools" "${d}/versions" "${d}/errors" "${d}/cargo" "${d}/rustup" "${d}/tmp"
  cp "${_P58}/tpl/curl" "${d}/bin/curl"
  [[ -n "$2" ]] && printf '%s\n' "$2" >"${d}/versions/rust-init"
  [[ -n "$4" ]] && printf '%s\n' "$4" >"${d}/versions/rust"
  if [[ -n "$3" ]]; then
    mkdir -p "${d}/cargo/bin" "${d}/rustup/toolchains/old"
    cp "${_P58}/tpl/rustup" "${d}/cargo/bin/rustup"
    printf '%s\n' "$3" >"${d}/cargo/bin/.ver"
    printf '#!/bin/sh\necho jj\n' >"${d}/cargo/bin/jj"
    : >"${d}/cargo/env"
  fi
  : >"${d}/log"
  env -i PATH="${d}/bin:${d}/tools:${d}/cargo/bin:${DIST_BIN}/base-bin:/usr/bin:/bin" HOME="${d}" TMPDIR="${d}/tmp" \
    P58_LOG="${d}/log" P58_TPL="${_P58}/tpl" P58_FIX="${_P58}/fix" P58_RUSTC="${P58_RUSTC:-}" \
    CARGO_HOME="${d}/cargo" RUSTUP_HOME="${d}/rustup" \
    GLOBAL_STACK_ERROR_TOKEN=p58-token GLOBAL_STACK_DOCKER_TOOLS_PATH="${d}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${d}/errors" GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN="${d}/tools" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${d}/versions" GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES="${d}/successes" \
    GLOBAL_STACK_RUSTUP_INIT_VERSION="$1" GLOBAL_STACK_RUST_VERSION="${5:-1.98.1}" GLOBAL_STACK_RELOAD_RUST="${6:-false}" \
    bash "${DIST_BIN}/rust-bin/global-stack-rust-iou.sh" >"${d}/out" 2>&1 || rc=$?
  printf 'rc=%s rustup=%s init=%s rust=%s rustc=%s jj=%s token=%s fatal=%s tmp=%s calls=%s' "${rc}" \
    "$(cat "${d}/cargo/bin/.ver" 2>/dev/null || echo none)" \
    "$(cat "${d}/versions/rust-init" 2>/dev/null || echo none)" \
    "$(cat "${d}/versions/rust" 2>/dev/null || echo none)" \
    "$({ "${d}/cargo/bin/rustc" --version 2>/dev/null || true; } | awk '{ print $2 }' | grep . || echo none)" \
    "$(if [[ -e "${d}/cargo/bin/jj" && -d "${d}/rustup/toolchains/old" ]]; then echo kept; else echo gone; fi)" \
    "$(if [[ -e "${d}/errors/p58-token" ]]; then echo 1; else echo 0; fi)" \
    "$(grep -c '^FATAL: ' "${d}/out" || true)" "$(ls -A "${d}/tmp" | wc -l)" \
    "$(paste -sd, "${d}/log")"
  rm -rf "${d}"
}
_p58_field() { # $1 = field name, $2 = _p58_run output
  local f
  for f in $2; do [[ "${f%%=*}" == "$1" ]] && { printf '%s' "${f#*=}"; return 0; }; done
  return 0
}

assert_fail "58a: rust-iou.sh no longer sed-patches anything it downloads" \
  grep -q 'sed -i' "${DIST_BIN}/rust-bin/global-stack-rust-iou.sh"

# RUSTUP_INIT bumped ALONE (rust current, rustup 1.28.2 installed and recorded).
_o="$(_p58_run 1.29.1 1.28.2 1.28.2 1.98.1)"
assert_pass "58b: rustup-init pin bumped alone -> installed rustup moves UP to the pin, the toolchain and jj kept (got: ${_o})" \
  test "$(_p58_field rustup "${_o}")/$(_p58_field init "${_o}")/$(_p58_field rc "${_o}")/$(_p58_field jj "${_o}")/$(_p58_field tmp "${_o}")" = "1.29.1/1.29.1/0/kept/0"
assert_pass "58c: ... by running the checked rustup-init binary at the pin with the installer's arguments" \
  grep -q 'rustup-init:1.29.1:-y_--profile_default_--default-toolchain_none' <<<"$(_p58_field calls "${_o}")"
# Rolled back.
_o="$(_p58_run 1.28.2 1.29.1 1.29.1 1.98.1)"
assert_pass "58d: rustup-init pin moved back -> installed rustup moves DOWN to the pin (got: ${_o})" \
  test "$(_p58_field rustup "${_o}")/$(_p58_field init "${_o}")/$(_p58_field rc "${_o}")/$(_p58_field jj "${_o}")" = "1.28.2/1.28.2/0/kept"
# Steady state: no network.
_o="$(_p58_run 1.29.1 1.29.1 1.29.1 1.98.1)"
assert_fail "58e: rustup-init current and rustup present -> no download, no rustup-init run (got: ${_o})" \
  grep -Eq 'curl|rustup-init' <<<"$(_p58_field calls "${_o}")"
# The marker is not trusted on its own: marker current + installed rustup stale must still reinstall.
_o="$(_p58_run 1.29.1 1.29.1 1.28.2 1.98.1)"
assert_pass "58k: marker says the pin but the installed rustup differs -> reinstall to the pin (got: ${_o})" \
  test "$(_p58_field rustup "${_o}")/$(_p58_field rc "${_o}")" = "1.29.1/0"
# A rustup-init whose --version is not the pin is refused before it runs.
_o="$(_p58_run 1.29.2 1.28.2 1.28.2 1.98.1)"
assert_pass "58f: the downloaded rustup-init reports 1.29.20 for pin 1.29.2 -> FATAL + token, never run, rustup and marker untouched (got: ${_o})" \
  test "$(_p58_field rc "${_o}")/$(_p58_field rustup "${_o}")/$(_p58_field init "${_o}")/$(_p58_field token "${_o}")/$(_p58_field fatal "${_o}")/$(_p58_field jj "${_o}")" = "1/1.28.2/1.28.2/1/1/kept"
# Fresh install (no markers, no rustup): toolchain installed, and rustup still at the pin
# afterwards — i.e. auto-self-update was disabled BEFORE the toolchain install.
_o="$(_p58_run 1.29.1 "" "" "")"
assert_pass "58g: fresh install -> rustup at the pin, toolchain 1.98.1 installed + default, rustc checked, rust marker written (got: ${_o})" \
  test "$(_p58_field rustup "${_o}")/$(_p58_field rust "${_o}")/$(_p58_field rustc "${_o}")/$(_p58_field rc "${_o}")" = "1.29.1/1.98.1/1.98.1/0"
assert_pass "58h: ... auto-self-update disabled before the toolchain install" \
  bash -c 'c="$1"; [[ "${c}" == *asu:disable*toolchain:1.98.1* && "${c}" == *default:1.98.1* ]]' _ "$(_p58_field calls "${_o}")"

# Reachability: rust-start.sh calls iou on every boot, not only on a RUST mismatch.
_p58_region() {
  awk '
    index($0, "mkdir -p \"${RUSTUP_HOME}\" \"${CARGO_HOME}\"") == 1 { f = 1; next }
    f && index($0, "source \"${CARGO_HOME}/env\"") == 1 { exit }
    f { print }' "${DIST_BIN}/rust-bin/global-stack-rust-start.sh"
}
assert_pass "58i: extracted rust-start region calls rust-iou.sh (non-vacuity)" \
  grep -q 'global-stack-rust-iou.sh' <<<"$(_p58_region)"
_p58_reach() { # → "iou" when iou ran with the rust marker current
  local d
  d="$(mktemp -d)"
  mkdir -p "${d}/bin" "${d}/versions"
  printf '1.98.1\n' >"${d}/versions/rust"
  printf '#!/bin/sh\necho iou >>"%s/calls"\n' "${d}" >"${d}/bin/global-stack-rust-iou.sh"
  chmod +x "${d}/bin/global-stack-rust-iou.sh"
  env -i PATH="${d}/bin:/usr/bin:/bin" GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${d}/versions" \
    GLOBAL_STACK_RUST_VERSION=1.98.1 GLOBAL_STACK_RELOAD_RUST=false \
    bash -c "set -eE; $(_p58_region)" >/dev/null 2>&1 || true
  if [[ -f "${d}/calls" ]]; then tr -d '\n' <"${d}/calls"; else echo none; fi
  rm -rf "${d}"
}
assert_pass "58j: rust marker current (a rustup-init-only bump) -> rust-iou.sh still runs" \
  test "$(_p58_reach)" = "iou"

# ─── Section 59: no ordered version comparison decides an install (tranche 1 step 8) ──
# Ruling 2026-09-24 14:35: a pin can move up OR down, and every reinstall path installs
# exactly the pin. An equality gate (gs_version_gate, `!=`) does that by construction;
# an ordered one (`sort -V`, a semver-lt helper, `-lt/-gt/-le/-ge` on a version) makes
# a rollback a silent no-op (a string `<`/`>` inside `[[ ]]` on a version counts too). Two sites are exempt BY NAME, each for a stated reason:
#   - templates/shell/global-unu.sh `_gs_semver_lt` (host Claude Code): upgrade-only on
#     purpose — the host keeps Claude Code's auto-update (ruling 15:05);
#   - 00base install-tools.sh sonar-scanner `-ge 6`: picks the ARCHIVE NAME by major
#     (6+ carries an arch suffix), never whether to install — correct in both directions.
# The exemptions double as the non-vacuity floor: if the scan stops finding THEM, the
# pattern or a root broke and "no offenders" would mean nothing.
printf '\n%b── Section 59: no ordered version comparison decides an install%b\n' "${C_BOLD}" "${C_RESET}"

_P59_ROOTS=("${DIST_BIN}" "${SCRIPT_DIR}/../../docker/images" "${SCRIPT_DIR}/../../templates/shell")
_p59_hits="$(
  grep -rnE --include='*.sh' --include='Dockerfile*' \
    '_gs_semver_lt|sort -V|version_compare|compare-versions|-(lt|gt|le|ge) |\[\[ [^]]* (<|>) ' "${_P59_ROOTS[@]}" 2>/dev/null |
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' |
    awk -F: '
      /_gs_semver_lt|sort -V|version_compare|compare-versions/ { print; next }
      { line = $0; sub(/^[^:]+:[0-9]+:/, "", line); if (line ~ /VERSION/) print }' || true
)"
_p59_semver="$(grep -c 'templates/shell/global-unu\.sh:.*_gs_semver_lt' <<<"${_p59_hits}" || true)"
_p59_sonar="$(grep -c 'global-stack-base-install-tools\.sh:.*SONAR_SCANNER_CLI_VERSION' <<<"${_p59_hits}" || true)"
assert_pass "59a: the scan finds both named exemptions (non-vacuity: semver-lt ${_p59_semver} >= 2, sonar ${_p59_sonar} >= 1)" \
  bash -c '(( $1 >= 2 && $2 >= 1 ))' _ "${_p59_semver}" "${_p59_sonar}"
_p59_off="$(
  grep -vE 'templates/shell/global-unu\.sh:[0-9]+:.*(_gs_semver_lt|sort -V \| head -1\)" == "\$v1")' <<<"${_p59_hits}" |
    grep -vE 'global-stack-base-install-tools\.sh:[0-9]+:.*SONAR_SCANNER_CLI_VERSION' |
    grep -v '^$' | sed -E 's|^.*/(docker/[^:]+\|templates/[^:]+):([0-9]+):.*|\1:\2|' | tr '\n' ' ' || true
)"
assert_pass "59b: no other ordered version comparison in an install path (offenders: ${_p59_off:-none})" \
  test -z "${_p59_off}"

# ─── Section 60: runtimes delete the old version only after the new one installed (tranche 2 step 11) ──
# pin-audit tranche 2. The nvm / phpbrew / sdkman / fvm gates deleted the old version dir,
# every pkg.* marker and the version marker BEFORE the install ran, so a pin the upstream
# could not deliver (a 404, a failed build) left the runtime gone. Same shape as §57: the
# gate only decides, every setup-mode install trigger also fires on `reinstall`, and a
# cleanup block right after the install proves the new binary is on disk (FATAL, exit 1
# otherwise — the prologue's EXIT trap writes the error token) before it drops the old
# version and wipes pkg.*. A version another label still records is kept (fvm's flutter.3
# and flutter.3.41.9 share one versions/ dir), which gs_version_in_use decides.
# php.edge is NOT covered: it always builds into php-master (see the edge branch).
printf '\n%b── Section 60: runtimes delete-after-install (tranche 2 step 11)%b\n' "${C_BOLD}" "${C_RESET}"

# rt | script | var | label | root var | dir template (<v> = version) | old | new | install anchor (grep -F) | after anchor (grep -F) | trigger count | pkg.* left after cleanup (flutter has no package loop, so nothing to wipe)
_P60_TABLE=(
  'node|nvm-bin/global-stack-nvm-start.sh|_node|24|NVM_DIR|versions/node/<v>/bin/node|v24.1.0|v24.2.0|gs_install_retry_purge "${NVM_DIR}/.cache/src/node-|source /usr/local/bin/global-stack-base-setup-packages.sh|2|0'
  'php|phpbrew-bin/global-stack-phpbrew-start.sh|_php|8.4|PHPBREW_ROOT|php/<v>/bin/php|php-8.4.1|php-8.4.2|    global-stack-phpbrew-php-install-version.sh|source /usr/local/bin/global-stack-base-setup-packages.sh|3|0'
  'java|sdkman-bin/global-stack-sdkman-start.sh|_java|21|SDKMAN_DIR|candidates/java/<v>/bin/java|21.0.1-zulu|21.0.2-zulu|sdk install java "${JAVA_VERSION}"|source /usr/local/bin/global-stack-base-setup-packages.sh|0|0'
  'flutter|fvm-bin/global-stack-fvm-start.sh|_flutter|3|FVM_CACHE_PATH|versions/<v>/bin/flutter|3.1.0|3.2.0|fvm install "${FLUTTER_VERSION:-}"|echo "${FLUTTER_VERSION:-}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter.|1|1'
)
_P60_VG="${DIST_BIN}/base-bin/global-stack-base-version-gate.sh"

# The n-th `if [[ "${<var>_gate}" == "reinstall" ]]; then` (either bracket style) through
# the `fi` at the same indentation. n=1 is the gate, n=2 the post-install cleanup.
# The regex goes through `awk -v` (which processes escapes); the doubled backslashes are
# deliberate, and S2/S6 (mutations INSIDE block 2, both caught) prove it lands on block 2.
_p60_block() { # $1 = script, $2 = var, $3 = n
  awk -v want="$3" -v pat="^ *if \\[\\[? \"\\\\\$\\{$2_gate\\}\" ==? \"reinstall\" \\]\\]?; then\$" '
    n < want && $0 ~ pat { n++; if (n == want) { match($0, /^ */); ind = substr($0, 1, RLENGTH); on = 1 } }
    on { print; if ($0 == ind "fi") exit }' "$1"
}
_p60_gate_block() { # $1 = script, $2 = var: from `<var>_marker=` to the first 2-space `fi`
  sed -n "/^  $2_marker=/,/^  fi\$/p" "$1"
}
_p60_env() { # $1 = rt, $2 = label → the label/pin variables every block reads
  case "$1" in
    node) printf '%s\n' "_node_version_label=$2" ;;
    php) printf '%s\n' "PHP_VERSION_AS=$2" ;;
    java) printf '%s\n' "_java_label=$2" ;;
    flutter) printf '%s\n' "_flutter_label=$2" ;;
  esac
}
_p60_pin() { # $1 = rt, $2 = value → the pin variable the gate compares
  case "$1" in
    node) printf 'NODE_VERSION=%s' "$2" ;;
    php) printf 'PHP_VERSION_NAME=%s' "$2" ;;
    java) printf 'JAVA_VERSION=%s' "$2" ;;
    flutter) printf 'FLUTTER_VERSION=%s' "$2" ;;
  esac
}
_p60_mkver() { # $1 = root, $2 = dir template, $3 = version → an installed version (executable binary)
  local b="$1/${2//<v>/$3}"
  mkdir -p "${b%/*}"
  printf '#!/bin/sh\n' >"${b}"
  chmod +x "${b}"
}
_p60_verdir() { # $1 = root, $2 = dir template, $3 = version → the version's top dir
  local rel="${2//<v>/$3}"
  printf '%s/%s' "$1" "${rel%%/bin/*}"
}

# Gate: on a real reinstall decision it must DECIDE, not delete.
_p60_gate() { # table row → "dir=<0|1> pkg=<0|1> marker=<content>"
  local rt script var label rootv tpl old new d
  IFS='|' read -r rt script var label rootv tpl old new _ _ _ _ <<<"$1"
  d="$(mktemp -d)"
  mkdir -p "${d}/versions"
  _p60_mkver "${d}/root" "${tpl}" "${old}"
  printf '%s\n' "${old}" >"${d}/versions/${rt}.${label}"
  : >"${d}/versions/${rt}.${label}.pkg.1"
  {
    printf '#!/bin/bash\nset -eE -o pipefail\nsource global-stack-base-prologue.sh\n'
    _p60_gate_block "${DIST_BIN}/${script}" "${var}"
  } >"${d}/gate.sh"
  env PATH="${DIST_BIN}/base-bin:${PATH}" GLOBAL_STACK_ERROR_TOKEN=p60-token \
    GLOBAL_STACK_DOCKER_TOOLS_PATH="${d}" GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${d}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${d}/versions" "${rootv}=${d}/root" \
    "$(_p60_env "${rt}" "${label}")" "$(_p60_pin "${rt}" "${new}")" \
    bash "${d}/gate.sh" >/dev/null 2>&1 || true
  printf 'dir=%s pkg=%s marker=%s' \
    "$([[ -d "$(_p60_verdir "${d}/root" "${tpl}" "${old}")" ]] && echo 1 || echo 0)" \
    "$([[ -f "${d}/versions/${rt}.${label}.pkg.1" ]] && echo 1 || echo 0)" \
    "$(cat "${d}/versions/${rt}.${label}" 2>/dev/null || echo none)"
  rm -rf "${d}"
}

# Cleanup: $2 = installed | absent | shared (another label's marker records the old version).
# The own marker and a pkg marker both hold the OLD value in every case: neither may count
# as "another label still uses it", or the old version could never be dropped.
_p60_cleanup() { # table row, scenario → "rc=<0|1> old=<0|1> new=<0|1> pkg=<0|1>"
  local rt script var label rootv tpl old new d rc=0
  IFS='|' read -r rt script var label rootv tpl old new _ _ _ _ <<<"$1"
  d="$(mktemp -d)"
  mkdir -p "${d}/versions" "${d}/bin"
  _p60_mkver "${d}/root" "${tpl}" "${old}"
  [[ "$2" != absent ]] && _p60_mkver "${d}/root" "${tpl}" "${new}"
  printf '%s\n' "${old}" >"${d}/versions/${rt}.${label}"
  printf '%s\n' "${old}" >"${d}/versions/${rt}.${label}.pkg.1"
  [[ "$2" == shared ]] && printf '%s\n' "${old}" >"${d}/versions/${rt}.${label}.9"
  { printf '#!/bin/bash\nset -eE -o pipefail\nsource "%s"\n' "${_P60_VG}"; _p60_block "${DIST_BIN}/${script}" "${var}" 2; } >"${d}/c.sh"
  env -i PATH="/usr/bin:/bin" GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${d}/versions" \
    "${rootv}=${d}/root" PHPBREW_BIN="${d}/bin" GLOBAL_STACK_FRANKENPHP_VERSION=1.0.0 \
    "$(_p60_env "${rt}" "${label}")" "$(_p60_pin "${rt}" "${new}")" \
    "${var}_gate=reinstall" "${var}_old=${old}" "${var}_new=${new}" \
    bash "${d}/c.sh" >/dev/null 2>&1 || rc=1
  printf 'rc=%s old=%s new=%s pkg=%s' "${rc}" \
    "$([[ -d "$(_p60_verdir "${d}/root" "${tpl}" "${old}")" ]] && echo 1 || echo 0)" \
    "$([[ -d "$(_p60_verdir "${d}/root" "${tpl}" "${new}")" ]] && echo 1 || echo 0)" \
    "$([[ -f "${d}/versions/${rt}.${label}.pkg.1" ]] && echo 1 || echo 0)"
  rm -rf "${d}"
}

for _row in "${_P60_TABLE[@]}"; do
  IFS='|' read -r _rt _script _var _label _rootv _tpl _old _new _inst _after _ntrig _pkgleft <<<"${_row}"
  _src="${DIST_BIN}/${_script}"
  # A gate block that stops matching deletes nothing and would read as "decides only".
  assert_pass "60a: ${_rt} gate block extracted (non-vacuity: it calls gs_version_gate)" \
    grep -q 'gs_version_gate' <<<"$(_p60_gate_block "${_src}" "${_var}")"
  assert_pass "60b: ${_rt} gate on a reinstall decision leaves old dir, pkg markers and marker in place" \
    test "$(_p60_gate "${_row}")" = "dir=1 pkg=1 marker=${_old}"
  assert_pass "60c: ${_rt} post-install cleanup block exists (non-vacuity)" \
    grep -q 'rm -rf' <<<"$(_p60_block "${_src}" "${_var}" 2)"
  assert_pass "60d: ${_rt} cleanup after a successful install drops the OLD dir and pkg markers, keeps the new" \
    test "$(_p60_cleanup "${_row}" installed)" = "rc=0 old=0 new=1 pkg=${_pkgleft}"
  assert_pass "60e: ${_rt} new binary absent at cleanup -> non-zero, old dir and pkg markers kept" \
    test "$(_p60_cleanup "${_row}" absent)" = "rc=1 old=1 new=0 pkg=1"
  assert_pass "60f: ${_rt} old version still recorded by another label -> old dir kept, pkg wiped" \
    test "$(_p60_cleanup "${_row}" shared)" = "rc=0 old=1 new=1 pkg=${_pkgleft}"
  # `|| true` on the lookups: a missing line must red 60g, not abort the run under pipefail.
  _l_inst="$(grep -nF "${_inst}" "${_src}" | head -n1 | cut -d: -f1 || true)"
  _l_clean="$(grep -nE "^ *if \[\[? \"\\\$\{${_var}_gate\}\" ==? \"reinstall\" \]\]?; then\$" "${_src}" | sed -n 2p | cut -d: -f1 || true)"
  _l_after="$(grep -nF "${_after}" "${_src}" | head -n1 | cut -d: -f1 || true)"
  assert_pass "60g: ${_rt} order is install < cleanup < ${_after:0:40}" \
    bash -c '[[ -n "$1" && -n "$2" && -n "$3" ]] && (( $1 < $2 && $2 < $3 ))' _ "${_l_inst}" "${_l_clean}" "${_l_after}"
  # Every setup-mode `! -f <rt>.<label>` trigger must also fire on reinstall, because the
  # marker is no longer deleted up front. java installs unconditionally (0 triggers).
  _trig_re="^  if \[\[? ! -f \"\\\$\{GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS\}/${_rt}\."
  _n_trig="$(grep -cE "${_trig_re}" "${_src}" || true)"
  _n_miss="$(grep -E "${_trig_re}" "${_src}" | grep -vcE "${_var}_gate\}\" ==? \"reinstall\"" || true)"
  assert_pass "60h: ${_rt} setup-mode install triggers also fire on reinstall (${_n_trig} found, want ${_ntrig}, ${_n_miss} missing)" \
    bash -c '(( $1 == $2 && $3 == 0 ))' _ "${_n_trig}" "${_ntrig}" "${_n_miss}"
done

# php: the frankenphp binary is built per php name, so the old one goes with the old php —
# including one built by an OLDER frankenphp pin (both pins bumped in the same boot).
_p60_franken() { # → "old=<0|1> oldfv=<0|1> new=<0|1>"
  local d
  d="$(mktemp -d)"
  mkdir -p "${d}/versions" "${d}/bin"
  _p60_mkver "${d}/root" 'php/<v>/bin/php' php-8.4.1
  _p60_mkver "${d}/root" 'php/<v>/bin/php' php-8.4.2
  : >"${d}/bin/frankenphp-1.0.0-php-8.4.1"
  : >"${d}/bin/frankenphp-0.9.0-php-8.4.1"
  : >"${d}/bin/frankenphp-1.0.0-php-8.4.2"
  { printf '#!/bin/bash\nset -eE -o pipefail\nsource "%s"\n' "${_P60_VG}"; _p60_block "${DIST_BIN}/phpbrew-bin/global-stack-phpbrew-start.sh" _php 2; } >"${d}/c.sh"
  env -i PATH="/usr/bin:/bin" GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${d}/versions" PHPBREW_ROOT="${d}/root" \
    PHPBREW_BIN="${d}/bin" GLOBAL_STACK_FRANKENPHP_VERSION=1.0.0 PHP_VERSION_AS=8.4 PHP_VERSION_NAME=php-8.4.2 \
    _php_gate=reinstall _php_old=php-8.4.1 _php_new=php-8.4.2 bash "${d}/c.sh" >/dev/null 2>&1 || true
  printf 'old=%s oldfv=%s new=%s' "$([[ -e "${d}/bin/frankenphp-1.0.0-php-8.4.1" ]] && echo 1 || echo 0)" \
    "$([[ -e "${d}/bin/frankenphp-0.9.0-php-8.4.1" ]] && echo 1 || echo 0)" \
    "$([[ -e "${d}/bin/frankenphp-1.0.0-php-8.4.2" ]] && echo 1 || echo 0)"
  rm -rf "${d}"
}
assert_pass "60i: php cleanup drops the old php's frankenphp binaries (any frankenphp pin), keeps the new one's" \
  test "$(_p60_franken)" = "old=0 oldfv=0 new=1"

# nvm resolves the installed version the way the marker write does (`nvm version`), so a
# partial pin proves the directory nvm actually installed, not a literal `v24`.
assert_pass "60j: nvm cleanup compares the nvm-resolved version, not the raw pin" \
  grep -qE '^    _node_new="\$\(nvm version "\$\{NODE_VERSION:-\}"' "${DIST_BIN}/nvm-bin/global-stack-nvm-start.sh"

# ─── Section 61: a package slot drops its OLD version only after the NEW one installed (tranche 2 step 12) ──
# pin-audit tranche 2. base-setup-packages.sh ran --cleanup-command (`gem uninstall` /
# `sdk uninstall` of the old version) BEFORE the install commands, so a gem or sdkman
# candidate that failed to install left the slot with neither version. The cleanup now
# runs in the success branch, right before the marker write: non-tolerant callers after
# the commands (set -e aborts first on a failure), tolerant callers only when every
# command exited 0 and --success-check passed. Both directions: a pin moved DOWN
# installs the lower version, then drops the higher one. Runs the REAL engine.
printf '\n%b── Section 61: package slots delete-after-install (tranche 2 step 12)%b\n' "${C_BOLD}" "${C_RESET}"

_P61_ENGINE="${DIST_BIN}/base-bin/global-stack-base-setup-packages.sh"
# $1 = tolerant (0|1), $2 = slot A marker (or none), $3 = slot A pin,
# $4 = ok | cmdfail | checkfail, $5 = with-b (slot B, first install) or ""
# → "rc=<0|1> log=<entries joined by ,> marker=<slot A marker content>"
_p61_run() {
  local d rc=0 extra=() log
  d="$(mktemp -d)"
  mkdir -p "${d}/versions"
  [[ "$2" != none ]] && printf '%s\n' "$2" >"${d}/versions/rt.1.pkg.a"
  [[ "$1" == 1 ]] && extra+=(--tolerant)
  [[ "$4" == checkfail ]] && extra+=('--success-check=false')
  [[ "$4" == cmdfail ]] && extra+=('--command=false')
  {
    printf '#!/bin/bash\nset -eE -o pipefail\nsource %q\nsource %q\n' "${_P60_VG}" "${_P61_ENGINE}"
    printf 'P61_INSTALL_PACKAGE_A_VERSION=%q\nP61_CONFIG_PACKAGE_A_NAME=pkga\n' "$3"
    [[ "$5" == with-b ]] && printf 'P61_INSTALL_PACKAGE_B_VERSION=3.0\nP61_CONFIG_PACKAGE_B_NAME=pkgb\n'
    printf 'global_stack_base_setup_packages --prefix=P61 --marker-prefix=rt.1'
    printf ' %q' "--cleanup-command=printf 'cleanup:%s:%s\n' \"\${PACKAGE_NAME}\" \"\${PACKAGE_OLD_VERSION}\" >>\"\${P61_LOG}\"" \
      "--command=printf 'install:%s:%s\n' \"\${PACKAGE_NAME}\" \"\${PACKAGE_VERSION}\" >>\"\${P61_LOG}\"" "${extra[@]}"
    printf '\n'
  } >"${d}/run.sh"
  env -i PATH=/usr/bin:/bin GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${d}/versions" P61_LOG="${d}/log" \
    bash "${d}/run.sh" >/dev/null 2>&1 || rc=1
  log="$(if [[ -f "${d}/log" ]]; then paste -sd, "${d}/log"; else echo none; fi)"
  printf 'rc=%s log=%s marker=%s' "${rc}" "${log}" "$(cat "${d}/versions/rt.1.pkg.a" 2>/dev/null || echo none)"
  rm -rf "${d}"
}
assert_pass "61a: non-tolerant bump -> install new, THEN clean up old, marker = new" \
  test "$(_p61_run 0 1.0 2.0 ok '')" = "rc=0 log=install:pkga:2.0,cleanup:pkga:1.0 marker=2.0"
assert_pass "61b: pin moved DOWN -> install the lower version, then clean up the higher one" \
  test "$(_p61_run 0 2.0 1.0 ok '')" = "rc=0 log=install:pkga:1.0,cleanup:pkga:2.0 marker=1.0"
assert_pass "61c: non-tolerant install fails -> aborts, old version NOT cleaned up, marker still old" \
  test "$(_p61_run 0 1.0 2.0 cmdfail '')" = "rc=1 log=install:pkga:2.0 marker=1.0"
assert_pass "61d: tolerant, a command fails -> no cleanup, marker still old" \
  test "$(_p61_run 1 1.0 2.0 cmdfail '')" = "rc=0 log=install:pkga:2.0 marker=1.0"
assert_pass "61e: tolerant, commands pass but --success-check fails -> no cleanup, marker still old" \
  test "$(_p61_run 1 1.0 2.0 checkfail '')" = "rc=0 log=install:pkga:2.0 marker=1.0"
assert_pass "61f: tolerant success -> install new, then clean up old, marker = new" \
  test "$(_p61_run 1 1.0 2.0 ok '')" = "rc=0 log=install:pkga:2.0,cleanup:pkga:1.0 marker=2.0"
assert_pass "61g: first install (no marker) -> no cleanup" \
  test "$(_p61_run 0 none 2.0 ok '')" = "rc=0 log=install:pkga:2.0 marker=2.0"
# Slot A reinstalls, slot B (sorted after A) is a first install: B must not inherit A's
# PACKAGE_OLD_VERSION and fire a cleanup of its own.
assert_pass "61h: a first-install slot after a reinstalled one fires no cleanup of its own" \
  test "$(_p61_run 0 1.0 2.0 ok with-b)" = "rc=0 log=install:pkga:2.0,cleanup:pkga:1.0,install:pkgb:3.0 marker=2.0"

# ─── Section 62: rbenv plugins follow their pin in place (tranche 2 step 13) ──
# ruby-build and rbenv-gemset are git clones at a tag, like rbenv itself. Their arms in
# rbenv-iou.sh used to `rm -rf` the plugin and re-clone it from github, so a clone that
# failed (an unknown tag, no network) left rbenv with no ruby-build at all. An existing
# clone now moves in place, as §56 pins for rbenv. github.com is redirected through
# git's command-scoped config (GIT_CONFIG_COUNT ... insteadOf), either to a local mirror
# of §56's fixture or to a path that does not exist: a case that must NOT re-clone
# proves it by succeeding with github unreachable, and the shipped URLs are exercised
# with no network at all.
printf '\n%b── Section 62: rbenv plugins follow their pin in place (tranche 2 step 13)%b\n' "${C_BOLD}" "${C_RESET}"

_P62="${TMP_DIR}/p62"
mkdir -p "${_P62}/errors" "${_P62}/versions" "${_P62}/gh/sstephenson" "${_P62}/gh/jf"
for _m in sstephenson/ruby-build jf/rbenv-gemset; do
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git clone -q --bare "${_P56}/upstream" "${_P62}/gh/${_m}.git" >/dev/null 2>&1 || true
done
assert_pass "62a: github mirrors of the §56 fixture hold both tags (non-vacuity)" \
  bash -c 'for m in sstephenson/ruby-build jf/rbenv-gemset; do
    [[ "$(git -C "$1/gh/${m}.git" rev-parse "v1.1.0^{commit}" 2>/dev/null)" == "$2" ]] || exit 1; done' _ "${_P62}" "${_P56_C2}"
_p56_clone "${_P62}/root" v1.1.0 # rbenv itself sits at its pin, so its own block is a no-fetch no-op

_p62_plugin() { # $1 = plugin dir, $2 = none|empty|junk|<tag>, $3 = marker file, $4 = marker content|none
  local d="${_P62}/root/plugins/$1"
  rm -rf "${d}"
  case "$2" in
    none) ;;
    empty) mkdir -p "${d}" ;;
    junk) mkdir -p "${d}" && : >"${d}/keep" ;;
    *) GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -c advice.detachedHead=false clone -q --branch "$2" "${_P56}/upstream" "${d}" >/dev/null 2>&1 ;;
  esac
  rm -f "${_P62}/versions/$3"
  [[ "$4" == none ]] || printf '%s\n' "$4" >"${_P62}/versions/$3"
}
_p62_iou() { # $1 = plugin dir, $2 = RUBY_BUILD|GEMSET, $3 = marker file, $4 = pin, $5 = mirror|dead → "<rc> <HEAD|nogit> <marker|none> <token|-> <keep|->"
  local rc=0 gh="${_P62}/gh/" d="${_P62}/root/plugins/$1"
  [[ "$5" == dead ]] && gh="${_P62}/no-such-github/"
  rm -f "${_P62}/errors/p62-token"
  env -i PATH="${DIST_BIN}/base-bin:/usr/bin:/bin" HOME="${_P62}" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=1 \
    "GIT_CONFIG_KEY_0=url.${gh}.insteadOf" GIT_CONFIG_VALUE_0=https://github.com/ \
    GLOBAL_STACK_ERROR_TOKEN=p62-token GLOBAL_STACK_DOCKER_TOOLS_PATH="${_P62}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${_P62}/errors" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${_P62}/versions" \
    RBENV_ROOT="${_P62}/root" GLOBAL_STACK_RBENV_VERSION=v1.1.0 \
    GLOBAL_STACK_RBENV_RUBY_BUILD_VERSION= GLOBAL_STACK_RBENV_GEMSET_VERSION= "GLOBAL_STACK_RBENV_$2_VERSION=$4" \
    bash "${DIST_BIN}/rbenv-bin/global-stack-rbenv-iou.sh" >/dev/null 2>&1 || rc=$?
  printf '%s %s %s %s %s' "${rc}" \
    "$(if [[ -d "${d}/.git" ]]; then git -C "${d}" rev-parse HEAD; else echo nogit; fi)" \
    "$(cat "${_P62}/versions/$3" 2>/dev/null || echo none)" \
    "$(if [[ -f "${_P62}/errors/p62-token" ]]; then echo token; else echo -; fi)" \
    "$(if [[ -f "${d}/keep" ]]; then echo keep; else echo -; fi)"
}
for _pl in 'ruby-build RUBY_BUILD rbenv.ruby-build' 'rbenv-gemset GEMSET rbenv.gemset'; do
  read -r _pd _pv _pm <<<"${_pl}"
  _p62_plugin "${_pd}" none "${_pm}" none
  assert_pass "62b: ${_pd} absent -> cloned at the pin from its shipped github URL" \
    test "$(_p62_iou "${_pd}" "${_pv}" "${_pm}" v1.1.0 mirror)" = "0 ${_P56_C2} v1.1.0 - -"
  _p62_plugin "${_pd}" empty "${_pm}" none
  assert_pass "62c: ${_pd} left as an empty dir -> cloned into it at the pin" \
    test "$(_p62_iou "${_pd}" "${_pv}" "${_pm}" v1.1.0 mirror)" = "0 ${_P56_C2} v1.1.0 - -"
  _p62_plugin "${_pd}" v1.0.0 "${_pm}" v1.0.0
  assert_pass "62d: ${_pd} at v1.0.0, pin bumped to v1.1.0, github unreachable -> moves UP in place" \
    test "$(_p62_iou "${_pd}" "${_pv}" "${_pm}" v1.1.0 dead)" = "0 ${_P56_C2} v1.1.0 - -"
  _p62_plugin "${_pd}" v1.1.0 "${_pm}" v1.1.0
  assert_pass "62e: ${_pd} at v1.1.0, pin moved back to v1.0.0, github unreachable -> moves DOWN in place" \
    test "$(_p62_iou "${_pd}" "${_pv}" "${_pm}" v1.0.0 dead)" = "0 ${_P56_C1} v1.0.0 - -"
  _p62_plugin "${_pd}" v1.1.0 "${_pm}" v1.0.0
  git -C "${_P62}/root/plugins/${_pd}" remote set-url origin "${_P62}/no-such-remote"
  assert_pass "62f: ${_pd} stale marker but HEAD already at the pin -> no fetch, marker rewritten" \
    test "$(_p62_iou "${_pd}" "${_pv}" "${_pm}" v1.1.0 dead)" = "0 ${_P56_C2} v1.1.0 - -"
  _p62_plugin "${_pd}" v1.1.0 "${_pm}" v1.1.0
  git -C "${_P62}/root/plugins/${_pd}" remote set-url origin "${_P62}/no-such-remote"
  assert_pass "62g: ${_pd} current -> nothing touched (no network, rc 0)" \
    test "$(_p62_iou "${_pd}" "${_pv}" "${_pm}" v1.1.0 dead)" = "0 ${_P56_C2} v1.1.0 - -"
  _p62_plugin "${_pd}" v1.0.0 "${_pm}" v1.0.0
  _o="$(_p62_iou "${_pd}" "${_pv}" "${_pm}" v9.9.9 dead)"
  assert_pass "62h: ${_pd} pin with no such tag -> fails loud, still at v1.0.0, marker kept, token written" \
    bash -c '[[ "${1%% *}" != 0 && "${1#* }" == "$2 v1.0.0 token -" ]]' _ "${_o}" "${_P56_C1}"
  _p62_plugin "${_pd}" junk "${_pm}" none
  _o="$(_p62_iou "${_pd}" "${_pv}" "${_pm}" v1.1.0 mirror)"
  assert_pass "62i: ${_pd} non-empty dir that is not a clone -> fails loud, nothing deleted" \
    bash -c '[[ "${1%% *}" != 0 && "${1#* }" == "nogit none token keep" ]]' _ "${_o}"
done
# Cold start: rbenv is freshly cloned and plugins/ is gitignored upstream, so the parent
# does not exist yet. The old arm ran `mkdir -p`; `git clone` creates it on its own.
for _pl in 'ruby-build RUBY_BUILD rbenv.ruby-build' 'rbenv-gemset GEMSET rbenv.gemset'; do
  read -r _pd _pv _pm <<<"${_pl}"
  rm -rf "${_P62}/root/plugins"
  rm -f "${_P62}/versions/${_pm}"
  assert_pass "62b2: ${_pd} cold start (plugins/ absent) -> cloned at the pin" \
    test "$(_p62_iou "${_pd}" "${_pv}" "${_pm}" v1.1.0 mirror)" = "0 ${_P56_C2} v1.1.0 - -"
done
assert_fail "62j: no plugin arm deletes its plugin dir before installing" \
  grep -qE 'rm -rf .*plugins/' "${DIST_BIN}/rbenv-bin/global-stack-rbenv-iou.sh"

# ─── Section 63: go/zig are checked BEFORE the wipe, then installed fresh (tranche 2 step 14a) ──
# Both installers extracted the new archive OVER the old tree, so every file the old
# version shipped and the new one does not survived, in either direction; nothing
# checked the download, and the marker was written whatever the binary turned out to
# be. Now (ruling 2026-09-25 09:58): download to a temp dir, check the upstream SHA-256
# and that the archive holds the binary, and only then wipe and unpack fresh; the
# marker follows a version check. go's GOPATH lives INSIDE GOROOT, so it is renamed
# to the sibling go.gopath-aside for the wipe (ruling 10:07) and must come back
# untouched — including its file modes, which the old `chmod -R a+rwx` rewrote.
# curl and sudo are stubs; the fixture archives mirror the real member paths, listed
# from the real 1.27.1 / 0.16.0 archives on 2026-09-25.
printf '\n%b── Section 63: go/zig check first, then wipe and unpack fresh (tranche 2 step 14a)%b\n' "${C_BOLD}" "${C_RESET}"

_P63="${TMP_DIR}/p63"
mkdir -p "${_P63}/stub" "${_P63}/up/go" "${_P63}/up/zig" "${_P63}/build" "${_P63}/work" "${_P63}/versions"
cat >"${_P63}/stub/curl" <<'EOF'
#!/bin/bash
# Serves the fixture upstream. -f semantics: an unknown URL exits 22, like a 404.
out="" dash_o=0 url=""
while (($#)); do
  case "$1" in
    --connect-timeout | --max-time) shift ;;
    -o) out="$2"; shift ;;
    --*) ;;
    -*) [[ "$1" == *O* ]] && dash_o=1 ;;
    http*) url="$1" ;;
  esac
  shift
done
printf '%s\n' "${url}" >>"${P63}/curl.log"
case "${url}" in
  https://go.dev/dl/* | https://dl.google.com/go/*) f="${P63}/up/go/${url##*/}" ;;
  https://ziglang.org/download/index.json) f="${P63}/up/zig/index.json" ;;
  https://ziglang.org/download/*) f="${P63}/up/zig/${url##*/}" ;;
  *) exit 22 ;;
esac
[[ -f "${f}" ]] || exit 22
if [[ -n "${out}" ]]; then cp "${f}" "${out}"; elif ((dash_o)); then cp "${f}" "./${url##*/}"; else cat "${f}"; fi
EOF
cat >"${_P63}/stub/sudo" <<'EOF'
#!/bin/bash
if [[ "$1" == chown && -n "${P63_FAIL_CHOWN:-}" ]]; then exit 1; fi
exec "$@"
EOF
chmod +x "${_P63}/stub/curl" "${_P63}/stub/sudo"

_p63_mk() { # $1 = go|zig, $2 = version archived, $3 = version the binary prints, $4 = full|nobin
  local w="${_P63}/build/$1-$2" a
  rm -rf "${w}"
  if [[ "$1" == go ]]; then
    mkdir -p "${w}/go/bin" "${w}/go/src"
    printf '#!/bin/sh\necho "go version go%s linux/amd64"\n' "$3" >"${w}/go/bin/go"
    printf 'go%s\n' "$2" >"${w}/go/VERSION"
    : >"${w}/go/src/only-in-$2"
    [[ "$4" == nobin ]] && rm -f "${w}/go/bin/go"
    chmod -R a+rx "${w}"
    a="${_P63}/up/go/go$2.linux-amd64.tar.gz"
    tar -C "${w}" -czf "${a}" go
    sha256sum <"${a}" | cut -d' ' -f1 >"${a}.sha256"
  else
    local d="zig-x86_64-linux-$2"
    mkdir -p "${w}/${d}/lib"
    printf '#!/bin/sh\necho "%s"\n' "$3" >"${w}/${d}/zig"
    : >"${w}/${d}/lib/only-in-$2"
    [[ "$4" == nobin ]] && rm -f "${w}/${d}/zig"
    chmod -R a+rx "${w}"
    a="${_P63}/up/zig/${d}.tar.xz"
    tar -C "${w}" -cJf "${a}" "${d}"
    printf '%s %s\n' "$2" "$(sha256sum <"${a}" | cut -d' ' -f1)" >>"${_P63}/up/zig/shas"
  fi
}
# 1.0.0/1.1.0 good; 1.2.0 published with a wrong checksum; 1.3.0 archive without the
# binary; 1.4.0 whose binary reports 1.4.00 (a prefix match without the trailing
# space would accept it); 1.5.0 not published at all.
for _t in go zig; do
  _p63_mk "${_t}" 1.0.0 1.0.0 full
  _p63_mk "${_t}" 1.1.0 1.1.0 full
  _p63_mk "${_t}" 1.2.0 1.2.0 full
  _p63_mk "${_t}" 1.3.0 1.3.0 nobin
  _p63_mk "${_t}" 1.4.0 1.4.00 full
done
printf '%064d\n' 0 >"${_P63}/up/go/go1.2.0.linux-amd64.tar.gz.sha256"
sed -i 's/^1\.2\.0 .*/1.2.0 '"$(printf '%064d' 0)"'/' "${_P63}/up/zig/shas"
awk 'BEGIN { printf "{" } NR > 1 { printf "," }
  { printf "\"%s\":{\"x86_64-linux\":{\"tarball\":\"https://ziglang.org/download/%s/zig-x86_64-linux-%s.tar.xz\",\"shasum\":\"%s\"}}", $1, $1, $1, $2 }
  END { print "}" }' "${_P63}/up/zig/shas" >"${_P63}/up/zig/index.json"

assert_pass "63a: fixture archives carry the real member paths and a matching checksum (non-vacuity)" \
  bash -c 'tar -tzf "$1/up/go/go1.1.0.linux-amd64.tar.gz" | grep -qx go/bin/go \
    && tar -tJf "$1/up/zig/zig-x86_64-linux-1.1.0.tar.xz" | grep -qx zig-x86_64-linux-1.1.0/zig \
    && [[ "$(sha256sum <"$1/up/go/go1.1.0.linux-amd64.tar.gz" | cut -d" " -f1)" == "$(cat "$1/up/go/go1.1.0.linux-amd64.tar.gz.sha256")" ]] \
    && jq -e ".\"1.1.0\".\"x86_64-linux\".shasum | length == 64" "$1/up/zig/index.json" >/dev/null' _ "${_P63}"

_p63_prep() { # $1 = go|zig, $2 = installed version|none, $3 = marker|none — go also gets a GOPATH file at mode 600
  local t="${_P63}/tools/$1"
  rm -rf "${t}" "${_P63}/tools/go.gopath-aside" "${_P63}/versions/base.$1"
  if [[ "$2" != none ]]; then
    mkdir -p "${t}"
    if [[ "$1" == go ]]; then
      tar -C "${t}" --strip-components=1 -xzf "${_P63}/up/go/go$2.linux-amd64.tar.gz"
      mkdir -p "${t}/home/pkg"
      printf 'k\n' >"${t}/home/pkg/keep"
      chmod 600 "${t}/home/pkg/keep"
    else
      tar -C "${t}" --strip-components=1 -xJf "${_P63}/up/zig/zig-x86_64-linux-$2.tar.xz"
    fi
  fi
  [[ "$3" == none ]] || printf '%s\n' "$3" >"${_P63}/versions/base.$1"
}
_p63_run() { # $1 = go|zig, $2 = pin → "rc=<0|fail> ver=<v|none> marker=<m|none> files=<only-in-*>" (+ go: " gopath=<mode|none> aside=<yes|no>")
  local rc=0 t="${_P63}/tools/$1" ver files
  rm -f "${_P63}/curl.log"
  (cd "${_P63}/work" && env -i HOME="${_P63}" P63="${_P63}" P63_FAIL_CHOWN="${P63_FAIL_CHOWN:-}" \
    PATH="${_P63}/stub:${_P63}/tools/go/bin:${_P63}/tools/zig:${DIST_BIN}/base-bin:/usr/bin:/bin" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH="${_P63}/tools" GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${_P63}/versions" \
    GLOBAL_STACK_DOCKER_USER_ID="$(id -un)" GLOBAL_STACK_DOCKER_GROUP_ID="$(id -gn)" \
    GOROOT="${_P63}/tools/go" GOPATH="${_P63}/tools/go/home" GLOBAL_STACK_GO_VERSION="$2" \
    GLOBAL_STACK_ZIGPATH="${_P63}/tools/zig" GLOBAL_STACK_ZIG_VERSION="$2" \
    bash "${DIST_BIN}/base-bin/global-stack-base-install-$1.sh") >"${_P63}/last.log" 2>&1 || rc=fail
  if [[ "$1" == go ]]; then
    ver="$("${t}/bin/go" version 2>/dev/null | awk '{ sub(/^go/, "", $3); print $3 }')"
    files="$(find "${t}/src" -name 'only-in-*' -printf '%f\n' 2>/dev/null | sort | paste -sd, -)"
  else
    ver="$("${t}/zig" version 2>/dev/null)"
    files="$(find "${t}/lib" -name 'only-in-*' -printf '%f\n' 2>/dev/null | sort | paste -sd, -)"
  fi
  printf 'rc=%s ver=%s marker=%s files=%s' "${rc}" "${ver:-none}" \
    "$(cat "${_P63}/versions/base.$1" 2>/dev/null || echo none)" "${files:-none}"
  if [[ "$1" == go ]]; then
    printf ' gopath=%s aside=%s' "$(stat -c %a "${t}/home/pkg/keep" 2>/dev/null || echo none)" \
      "$(if [[ -e "${_P63}/tools/go.gopath-aside" ]]; then echo yes; else echo no; fi)"
  fi
}
_p63_curls() { if [[ -f "${_P63}/curl.log" ]]; then wc -l <"${_P63}/curl.log" | tr -d ' '; else echo 0; fi; }

for _t in go zig; do
  _g=""
  [[ "${_t}" == go ]] && _g=" gopath=600 aside=no"
  _p63_prep "${_t}" none none
  _o="$(_p63_run "${_t}" 1.1.0)"
  assert_pass "63b: ${_t} first install -> the pin, marker written" \
    test "${_o% gopath=*}" = "rc=0 ver=1.1.0 marker=1.1.0 files=only-in-1.1.0"
  _p63_prep "${_t}" 1.0.0 1.0.0
  assert_pass "63c: ${_t} 1.0.0 -> pin 1.1.0: clean tree of the new version, nothing of the old left" \
    test "$(_p63_run "${_t}" 1.1.0)" = "rc=0 ver=1.1.0 marker=1.1.0 files=only-in-1.1.0${_g}"
  _p63_prep "${_t}" 1.1.0 1.1.0
  assert_pass "63d: ${_t} 1.1.0 -> pin moved back to 1.0.0: clean tree of the old version" \
    test "$(_p63_run "${_t}" 1.0.0)" = "rc=0 ver=1.0.0 marker=1.0.0 files=only-in-1.0.0${_g}"
  _p63_prep "${_t}" 1.0.0 1.0.0
  assert_pass "63e: ${_t} download fails its upstream checksum -> FATAL, old tool and marker untouched" \
    test "$(_p63_run "${_t}" 1.2.0)" = "rc=fail ver=1.0.0 marker=1.0.0 files=only-in-1.0.0${_g}"
  _p63_prep "${_t}" 1.0.0 1.0.0
  assert_pass "63f: ${_t} archive without the binary -> FATAL, old tool and marker untouched" \
    test "$(_p63_run "${_t}" 1.3.0)" = "rc=fail ver=1.0.0 marker=1.0.0 files=only-in-1.0.0${_g}"
  _p63_prep "${_t}" 1.0.0 1.0.0
  assert_pass "63g: ${_t} pin not published (download fails) -> FATAL, old tool and marker untouched" \
    test "$(_p63_run "${_t}" 1.5.0)" = "rc=fail ver=1.0.0 marker=1.0.0 files=only-in-1.0.0${_g}"
  _p63_prep "${_t}" 1.0.0 1.0.0
  _o="$(_p63_run "${_t}" 1.4.0)"
  assert_pass "63h: ${_t} installed binary reports 1.4.00 for pin 1.4.0 -> FATAL, marker not written" \
    bash -c '[[ "$1" == "rc=fail ver=1.4.00 marker=1.0.0 files=only-in-1.4.0$2" ]]' _ "${_o}" "${_g}"
  _p63_prep "${_t}" 1.1.0 1.1.0
  _o="$(_p63_run "${_t}" 1.1.0)"
  assert_pass "63k: ${_t} current -> nothing downloaded, nothing touched" \
    bash -c '[[ "$1" == "rc=0 ver=1.1.0 marker=1.1.0 files=only-in-1.1.0$2" && "$3" == 0 ]]' _ "${_o}" "${_g}" "$(_p63_curls)"
done

# go only: GOPATH set aside and back. A leftover aside (the container was killed mid-
# reinstall) is restored when GOPATH is absent, FATAL when both exist, never deleted.
_p63_prep go 1.0.0 1.0.0
mv "${_P63}/tools/go/home" "${_P63}/tools/go.gopath-aside"
assert_pass "63i: go leftover aside and no GOPATH -> aside restored, even on a current pin" \
  test "$(_p63_run go 1.0.0)" = "rc=0 ver=1.0.0 marker=1.0.0 files=only-in-1.0.0 gopath=600 aside=no"
_p63_prep go 1.0.0 1.0.0
mkdir -p "${_P63}/tools/go.gopath-aside/pkg"
: >"${_P63}/tools/go.gopath-aside/pkg/other"
_o="$(_p63_run go 1.1.0)"
assert_pass "63j: go leftover aside AND a GOPATH -> FATAL, both kept, nothing installed" \
  bash -c '[[ "$1" == "rc=fail ver=1.0.0 marker=1.0.0 files=only-in-1.0.0 gopath=600 aside=yes" && -f "$2/tools/go.gopath-aside/pkg/other" ]]' _ "${_o}" "${_P63}"
# On a CURRENT pin nothing is moved, so `mv -T` never gets the chance to refuse: only
# the explicit check stops a stale aside from lingering unnoticed on every boot.
_p63_prep go 1.0.0 1.0.0
mkdir -p "${_P63}/tools/go.gopath-aside/pkg"
: >"${_P63}/tools/go.gopath-aside/pkg/other"
_o="$(_p63_run go 1.0.0)"
assert_pass "63j2: go leftover aside AND a GOPATH on a current pin -> still FATAL (and says why), both kept" \
  bash -c '[[ "$1" == "rc=fail ver=1.0.0 marker=1.0.0 files=only-in-1.0.0 gopath=600 aside=yes" && -f "$2/tools/go.gopath-aside/pkg/other" ]] \
    && grep -q "^FATAL: both .* exist" "$2/last.log"' _ "${_o}" "${_P63}"
# The shape a killed reinstall really leaves on the next boot: base-start.sh runs
# create-directories.sh (which mkdirs GOPATH) BEFORE install-go.sh, so GOPATH exists but
# is EMPTY while the real one sits in the aside. That is not a conflict to merge by hand.
_p63_prep go 1.0.0 1.0.0
mv "${_P63}/tools/go/home" "${_P63}/tools/go.gopath-aside"
mkdir -p "${_P63}/tools/go/home"
assert_pass "63j3: go leftover aside and an EMPTY GOPATH (create-directories.sh) -> empty dir dropped, aside restored" \
  test "$(_p63_run go 1.0.0)" = "rc=0 ver=1.0.0 marker=1.0.0 files=only-in-1.0.0 gopath=600 aside=no"
_p63_prep go 1.0.0 1.0.0
_o="$(P63_FAIL_CHOWN=1 _p63_run go 1.1.0)"
assert_pass "63m: go failure while GOPATH is aside (chown fails) -> GOPATH restored by the EXIT trap, marker kept" \
  bash -c '[[ "$1" == rc=fail\ *\ marker=1.0.0\ *\ gopath=600\ aside=no ]]' _ "${_o}"

# ─── Section 64: mise is checked BEFORE its data is wiped (tranche 2 step 14b) ──
# install-mise.sh removed mise's four data dirs and THEN piped https://mise.run into sh,
# so a failed download left mise with no data, and a remote script ran unchecked. Now
# (ruling 2026-09-25 09:58) the pinned release binary and the release's SHASUMS256.txt
# land in a temp dir; the checksum and `--version` are checked first — with every
# MISE_*_DIR pointed into the temp dir, because `--version` migrates whatever data dir
# it is given — and only then are the data dirs wiped, the binary installed, the
# installed copy checked, `mise use -g usage` run, and the marker written. A `usage`
# failure stays fatal (64h): a mise without `usage` is broken, so a marker would lie.
# The fixture mirrors the real release: SHASUMS256.txt names assets as
# `<sha>  ./mise-<v>-linux-x64`, and `--version` prints `<v without the leading v> linux-x64 (<date>)`
# [measured on v2026.9.11, 2026-09-25].
printf '\n%b── Section 64: mise checked first, then data wiped and installed (tranche 2 step 14b)%b\n' "${C_BOLD}" "${C_RESET}"

_P64="${TMP_DIR}/p64"
mkdir -p "${_P64}/stub" "${_P64}/up" "${_P64}/work"
cat >"${_P64}/stub/curl" <<'EOF'
#!/bin/bash
out="" dash_o=0 url=""
while (($#)); do
  case "$1" in
    --connect-timeout | --max-time) shift ;;
    -o) out="$2"; shift ;;
    --*) ;;
    -*) [[ "$1" == *O* ]] && dash_o=1 ;;
    http*) url="$1" ;;
  esac
  shift
done
printf '%s\n' "${url}" >>"${P64}/curl.log"
case "${url}" in
  https://github.com/jdx/mise/releases/download/*) f="${P64}/up/${url#https://github.com/jdx/mise/releases/download/}" ;;
  *) exit 22 ;;
esac
[[ -f "${f}" ]] || exit 22
if [[ -n "${out}" ]]; then cp "${f}" "${out}"; elif ((dash_o)); then cp "${f}" "./${url##*/}"; else cat "${f}"; fi
EOF
chmod +x "${_P64}/stub/curl"

_p64_mk() { # $1 = tag (v1.0.0), $2 = version the binary prints (without v)
  local d="${_P64}/up/$1" a="mise-$1-linux-x64"
  mkdir -p "${d}"
  cat >"${d}/${a}" <<EOF
#!/bin/bash
case "\$1" in
  --version) printf '%s\n' "\${MISE_DATA_DIR}" >>"\${P64}/version-data-dirs"; echo "$2 linux-x64 (2026-09-18)" ;;
  use) printf '%s\n' "\$*" >>"\${P64}/use.log"; [[ -z "\${P64_FAIL_USE:-}" ]] || exit 1; mkdir -p "\${MISE_DATA_DIR}/installs/usage" ;;
esac
EOF
  chmod +x "${d}/${a}"
  (cd "${d}" && sha256sum "./${a}" >SHASUMS256.txt)
}
# v1.0.0/v1.1.0 good; v1.2.0 published with a wrong checksum; v1.4.0 reports 1.4.00;
# v1.5.0 not published.
_p64_mk v1.0.0 1.0.0
_p64_mk v1.1.0 1.1.0
_p64_mk v1.2.0 1.2.0
_p64_mk v1.4.0 1.4.00
printf '%064d  ./mise-v1.2.0-linux-x64\n' 0 >"${_P64}/up/v1.2.0/SHASUMS256.txt"
assert_pass "64a: fixture SHASUMS256.txt uses the real './<asset>' naming and verifies (non-vacuity)" \
  bash -c 'cd "$1/up/v1.1.0" && grep -qE "^[0-9a-f]{64}  \./mise-v1\.1\.0-linux-x64$" SHASUMS256.txt && sha256sum -c --quiet SHASUMS256.txt' _ "${_P64}"

_p64_prep() { # $1 = installed tag|none (binary + a stale data file + marker)
  rm -rf "${_P64}/tools" "${_P64}/version-data-dirs" "${_P64}/use.log"
  mkdir -p "${_P64}/tools/bin" "${_P64}/tools/versions" "${_P64}/tools/shellrc"
  if [[ "$1" != none ]]; then
    cp "${_P64}/up/$1/mise-$1-linux-x64" "${_P64}/tools/bin/mise"
    mkdir -p "${_P64}/tools/mise/share/installs/stale-from-$1" "${_P64}/tools/mise/state" "${_P64}/tools/mise/config" "${_P64}/tools/mise/cache"
    printf '%s\n' "$1" >"${_P64}/tools/versions/base.mise"
  fi
}
_p64_run() { # $1 = pin → "rc=<0|fail> ver=<v|none> marker=<m|none> data=<share/installs entries|none>"
  local rc=0 t="${_P64}/tools" ver data
  rm -f "${_P64}/curl.log"
  (cd "${_P64}/work" && env -i HOME="${_P64}" P64="${_P64}" P64_FAIL_USE="${P64_FAIL_USE:-}" \
    PATH="${_P64}/stub:${t}/bin:${DIST_BIN}/base-bin:/usr/bin:/bin" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${t}/versions" GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC="${t}/shellrc" \
    GLOBAL_STACK_MISE_VERSION="$1" GLOBAL_STACK_BASE_INSTALL_TOOLS=true \
    MISE_VERSION="$1" MISE_DEBUG=0 MISE_QUIET=1 MISE_INSTALL_PATH="${t}/bin/mise" \
    MISE_DATA_DIR="${t}/mise/share" MISE_STATE_DIR="${t}/mise/state" \
    MISE_CONFIG_DIR="${t}/mise/config" MISE_CACHE_DIR="${t}/mise/cache" \
    bash "${DIST_BIN}/base-bin/global-stack-base-install-mise.sh") >"${_P64}/last.log" 2>&1 || rc=fail
  # A missing binary or installs/ dir is a state to report, not a suite error.
  ver="$({ "${t}/bin/mise" --version 2>/dev/null || true; } | awk '{ print $1 }')"
  data="$({ find "${t}/mise/share/installs" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null || true; } | sort | paste -sd, -)"
  printf 'rc=%s ver=%s marker=%s data=%s' "${rc}" "${ver:-none}" \
    "$(cat "${t}/versions/base.mise" 2>/dev/null || echo none)" "${data:-none}"
}
_p64_curls() { if [[ -f "${_P64}/curl.log" ]]; then wc -l <"${_P64}/curl.log" | tr -d ' '; else echo 0; fi; }

_p64_prep none
assert_pass "64b: first install -> the pinned binary, usage installed, marker written" \
  test "$(_p64_run v1.1.0)" = "rc=0 ver=1.1.0 marker=v1.1.0 data=usage"
_p64_prep v1.0.0
assert_pass "64c: v1.0.0 -> pin v1.1.0: new binary, data wiped then usage reinstalled" \
  test "$(_p64_run v1.1.0)" = "rc=0 ver=1.1.0 marker=v1.1.0 data=usage"
_p64_prep v1.1.0
assert_pass "64d: v1.1.0 -> pin moved back to v1.0.0: old binary, data wiped then usage reinstalled" \
  test "$(_p64_run v1.0.0)" = "rc=0 ver=1.0.0 marker=v1.0.0 data=usage"
_p64_prep v1.0.0
assert_pass "64e: checksum mismatch -> FATAL, old binary, data and marker untouched" \
  test "$(_p64_run v1.2.0)" = "rc=fail ver=1.0.0 marker=v1.0.0 data=stale-from-v1.0.0"
_p64_prep v1.0.0
assert_pass "64f: downloaded binary reports 1.4.00 for pin v1.4.0 -> FATAL, old binary, data and marker untouched" \
  test "$(_p64_run v1.4.0)" = "rc=fail ver=1.0.0 marker=v1.0.0 data=stale-from-v1.0.0"
_p64_prep v1.0.0
assert_pass "64g: pin not published (download fails) -> FATAL, old binary, data and marker untouched" \
  test "$(_p64_run v1.5.0)" = "rc=fail ver=1.0.0 marker=v1.0.0 data=stale-from-v1.0.0"
_p64_prep v1.0.0
_o="$(P64_FAIL_USE=1 _p64_run v1.1.0)"
assert_pass "64h: \`mise use -g usage\` fails -> FATAL, marker NOT written (a mise without usage is broken)" \
  test "${_o}" = "rc=fail ver=1.1.0 marker=v1.0.0 data=none"
_p64_prep v1.0.0
_p64_run v1.1.0 >/dev/null || true
assert_pass "64i: the pre-wipe --version check never touches the live data dir" \
  bash -c '[[ -s "$1/version-data-dirs" ]] && ! grep -qxF "$1/tools/mise/share" <(head -1 "$1/version-data-dirs")' _ "${_P64}"
_p64_prep v1.1.0
_o="$(_p64_run v1.1.0)"
assert_pass "64j: current -> nothing downloaded, nothing touched" \
  bash -c '[[ "$1" == "rc=0 ver=1.1.0 marker=v1.1.0 data=stale-from-v1.1.0" && "$2" == 0 ]]' _ "${_o}" "$(_p64_curls)"
assert_fail "64k: no remote script is piped into a shell" \
  grep -qE '\|[[:space:]]*(ba)?sh\b' "${DIST_BIN}/base-bin/global-stack-base-install-mise.sh"

# ─── Section 65: hurl is compiled in the 00base image, then copied into tools/ (tranche 2 step 14c) ──
# hurl's only Linux x86_64 build links libxml2.so.2, absent on Ubuntu 26.04 (libxml2.so.16),
# so the downloaded binary could never run — in 00base or on the host [measured 2026-09-25].
# The image now compiles the pinned release (ruling 09:58); install-hurl.sh checks that the
# image's hurl IS the pin (an image older than the pin is FATAL: rebuild), wipes tools/hurl,
# copies hurl + hurlfmt in, re-checks, and writes the marker last. An installed hurl that
# cannot run is itself a reinstall trigger — the live tools/hurl is exactly that today,
# with a marker equal to the pin, so without it the gate would skip it forever.
printf '\n%b── Section 65: hurl compiled in the image, copied into tools/ (tranche 2 step 14c)%b\n' "${C_BOLD}" "${C_RESET}"

_P65="${TMP_DIR}/p65"
mkdir -p "${_P65}/stub" "${_P65}/work"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >>"%s/curl.log"\nexit 22\n' "${_P65}" >"${_P65}/stub/curl"
printf '#!/bin/bash\nexec "$@"\n' >"${_P65}/stub/sudo"
chmod +x "${_P65}/stub/curl" "${_P65}/stub/sudo"
_p65_bin() { # $1 = dir, $2 = version printed, $3 = ok|broken → fake hurl + hurlfmt
  mkdir -p "$1"
  if [[ "$3" == broken ]]; then
    printf '#!/bin/sh\necho "hurl: error while loading shared libraries: libxml2.so.2" >&2\nexit 127\n' >"$1/hurl"
  else
    printf '#!/bin/sh\necho "hurl %s (x86_64-pc-linux-gnu) libcurl/8.18.0 OpenSSL/3.5.3 zlib/1.3.1 libxml2/2.15.2"\necho "Features (libcurl):  alt-svc AsynchDNS HTTP2 IPv6 Largefile libz SSL UnixSockets"\n' "$2" >"$1/hurl"
  fi
  printf '#!/bin/sh\necho "hurlfmt %s"\n' "$2" >"$1/hurlfmt"
  chmod +x "$1/hurl" "$1/hurlfmt"
}
_p65_prep() { # $1 = image hurl version|none, $2 = installed version|none|broken, $3 = marker|none
  rm -rf "${_P65}/image" "${_P65}/tools" "${_P65}/curl.log"
  mkdir -p "${_P65}/tools/versions"
  [[ "$1" == none ]] || _p65_bin "${_P65}/image/bin" "$1" ok
  case "$2" in
    none) ;;
    broken) _p65_bin "${_P65}/tools/hurl/bin" "$3" broken && : >"${_P65}/tools/hurl/stale" ;;
    *) _p65_bin "${_P65}/tools/hurl/bin" "$2" ok && : >"${_P65}/tools/hurl/stale" ;;
  esac
  [[ "$3" == none ]] || printf '%s\n' "$3" >"${_P65}/tools/versions/base.hurl"
}
_p65_run() { # $1 = pin → "rc=<0|fail> ver=<v|none> fmt=<v|none> marker=<m|none> stale=<yes|no>"
  local rc=0 t="${_P65}/tools/hurl"
  # tools/hurl/bin is on PATH exactly as the image ENV puts it there (Dockerfile PATH=).
  (cd "${_P65}/work" && env -i HOME="${_P65}" PATH="${_P65}/stub:${t}/bin:${DIST_BIN}/base-bin:/usr/bin:/bin" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${_P65}/tools/versions" GLOBAL_STACK_HURLPATH="${t}" \
    GLOBAL_STACK_HURL_BUILD_PATH="${_P65}/image" GLOBAL_STACK_HURL_VERSION="$1" \
    GLOBAL_STACK_DOCKER_USER_ID="$(id -un)" GLOBAL_STACK_DOCKER_GROUP_ID="$(id -gn)" \
    bash "${DIST_BIN}/base-bin/global-stack-base-install-hurl.sh") >"${_P65}/last.log" 2>&1 || rc=fail
  local ver fmt
  ver="$({ "${t}/bin/hurl" --version 2>/dev/null || true; } | awk 'NR == 1 { print $2 }')"
  fmt="$({ "${t}/bin/hurlfmt" --version 2>/dev/null || true; } | awk '{ print $2 }')"
  printf 'rc=%s ver=%s fmt=%s marker=%s stale=%s' "${rc}" "${ver:-none}" "${fmt:-none}" \
    "$(cat "${_P65}/tools/versions/base.hurl" 2>/dev/null || echo none)" \
    "$(if [[ -e "${t}/stale" ]]; then echo yes; else echo no; fi)"
}

_p65_prep 1.1.0 none none
assert_pass "65b: first install -> the image's hurl and hurlfmt copied in, marker written" \
  test "$(_p65_run 1.1.0)" = "rc=0 ver=1.1.0 fmt=1.1.0 marker=1.1.0 stale=no"
_p65_prep 1.1.0 1.0.0 1.0.0
assert_pass "65c: 1.0.0 -> pin 1.1.0 (image rebuilt): tools/hurl wiped and replaced" \
  test "$(_p65_run 1.1.0)" = "rc=0 ver=1.1.0 fmt=1.1.0 marker=1.1.0 stale=no"
assert_pass "65i: that reinstall downloaded nothing (the binary comes from the image)" \
  test ! -s "${_P65}/curl.log"
_p65_prep 1.0.0 1.1.0 1.1.0
assert_pass "65d: 1.1.0 -> pin moved back to 1.0.0 (image rebuilt): wiped and replaced" \
  test "$(_p65_run 1.0.0)" = "rc=0 ver=1.0.0 fmt=1.0.0 marker=1.0.0 stale=no"
_p65_prep 1.0.0 1.0.0 1.0.0
_o="$(_p65_run 1.1.0)"
assert_pass "65e: image older than the pin (not rebuilt) -> FATAL naming the rebuild, old hurl untouched" \
  bash -c '[[ "$1" == "rc=fail ver=1.0.0 fmt=1.0.0 marker=1.0.0 stale=yes" ]] && grep -q "^FATAL: .*rebuild 00base" "$2/last.log"' _ "${_o}" "${_P65}"
_p65_prep none 1.0.0 1.0.0
_o="$(_p65_run 1.1.0)"
assert_pass "65f: image carries no compiled hurl -> WARN naming the rebuild, boot continues, old hurl untouched (ruling 2026-09-25)" \
  bash -c '[[ "$1" == "rc=0 ver=1.0.0 fmt=1.0.0 marker=1.0.0 stale=yes" ]] && grep -q "^WARN: .*rebuild 00base" "$2/last.log"' _ "${_o}" "${_P65}"
# Today's exact transition: the pre-14c image (no compiled hurl) over the broken download.
_p65_prep none broken 1.1.0
_o="$(_p65_run 1.1.0)"
assert_pass "65f2: pre-14c image over the broken download -> WARN, boot continues, nothing wiped" \
  bash -c '[[ "$1" == "rc=0 ver=none fmt=1.1.0 marker=1.1.0 stale=yes" ]] && grep -q "^WARN: .*rebuild 00base" "$2/last.log"' _ "${_o}" "${_P65}"
_p65_prep 1.1.0 broken 1.1.0
assert_pass "65g: installed hurl cannot run, marker == pin (today's live state) -> reinstalled from the image" \
  test "$(_p65_run 1.1.0)" = "rc=0 ver=1.1.0 fmt=1.1.0 marker=1.1.0 stale=no"
_p65_prep 1.1.0 1.1.0 1.1.0
assert_pass "65h: current and runnable -> nothing touched" \
  test "$(_p65_run 1.1.0)" = "rc=0 ver=1.1.0 fmt=1.1.0 marker=1.1.0 stale=yes"

# The image side (SYNTAX-ONLY surface — a real build certifies it, see the plan's 14c AS BUILT).
_D00="${SCRIPT_DIR}/../../docker/images/00base"
assert_pass "65j: 00base has a hurl-build stage that compiles hurl AND hurlfmt at the pin, --locked" \
  bash -c 'grep -qE "^FROM ubuntu:\\\$\{GLOBAL_STACK_IMAGE_UBUNTU_VERSION\} AS hurl-build$" "$1" \
    && grep -qE "cargo\" install --locked --root /opt/hurl \"hurl@\\\$\{GLOBAL_STACK_HURL_VERSION\}\" \"hurlfmt@\\\$\{GLOBAL_STACK_HURL_VERSION\}\"" "$1"' _ "${_D00}/Dockerfile"
assert_pass "65k: the final stage copies the compiled binaries and names their path for install-hurl.sh" \
  bash -c 'grep -qx "COPY --from=hurl-build /opt/hurl/bin/ /opt/hurl/bin/" "$1" && grep -q "GLOBAL_STACK_HURL_BUILD_PATH=\"/opt/hurl\"" "$1"' _ "${_D00}/Dockerfile"
assert_pass "65l: the stage's Rust pins reach the build (compose build args)" \
  bash -c 'for v in GLOBAL_STACK_RUST_VERSION GLOBAL_STACK_RUSTUP_INIT_VERSION GLOBAL_STACK_HURL_VERSION; do
    grep -qE "^ +${v}: \\\$\{${v}\}$" "$1" || exit 1; done' _ "${_D00}/docker-compose.yaml"
assert_fail "65m: no host shell template puts HURLPATH itself (not its bin/) on PATH" \
  grep -rqE 'PATH="?\$\{GLOBAL_STACK_HURLPATH\}:' "${SCRIPT_DIR}/../../templates/shell"

# ─── Section 66: composer is built and checked BEFORE the old one goes (tranche 2 step 15a) ──
# phpbrew-install-tools.sh removed composer's source and bootstrap phar FIRST and then
# cloned, so a clone or install that failed left no composer at all; and the bootstrap
# came from composer-setup.php with no --version, i.e. whatever composer was latest.
# Now (ruling 2026-09-25): the pinned composer.phar is downloaded with its published
# sha256 and version-checked; the source is cloned at the tag, overlaid and
# `composer install`ed in a temp dir and version-checked; only then are the old source
# and phar replaced. laravel/installer is version-checked before its marker. The whole
# SHIPPED script runs (prologue included) with the other nine tools held current.
# Formats measured 2026-09-25: `Composer version 2.10.3 2026-08-27 13:34:23`,
# `Laravel Installer 5.32.0`, `<sha>  composer.phar`.
printf '\n%b── Section 66: composer built and checked first, then replaced (tranche 2 step 15a)%b\n' "${C_BOLD}" "${C_RESET}"

_P66="${TMP_DIR}/p66"
mkdir -p "${_P66}/stub" "${_P66}/up/dl" "${_P66}/gh/composer" "${_P66}/overlay/src" "${_P66}/work"
: >"${_P66}/overlay/src/overlay-applied"
cat >"${_P66}/stub/curl" <<'EOF'
#!/bin/bash
out="" url="" remote=0 fail=0
while (($#)); do
  case "$1" in
    --connect-timeout | --max-time) shift ;;
    -o) out="$2"; shift ;;
    --*) ;;
    -*)
      [[ "$1" == *O* ]] && remote=1
      [[ "$1" == *f* ]] && fail=1 ;;
    http*) url="$1" ;;
  esac
  shift
done
printf '%s\n' "${url}" >>"${P66}/curl.log"
f=""
case "${url}" in
  https://getcomposer.org/download/*) f="${P66}/up/dl/${url#https://getcomposer.org/download/}" ;;
  https://github.com/*/releases/download/*)
    r="${url#https://github.com/*/}"
    f="${P66}/up/gh/${r%%/*}/${r#*/releases/download/}" ;;
esac
# -O writes the remote name into the CURRENT directory, as the real curl does.
((remote)) && out="${url##*/}"
[[ -n "${out}" ]] || exit 2
if [[ -z "${f}" || ! -f "${f}" ]]; then
  # Not published. With -f curl fails (22); WITHOUT it the 404 page lands as the output
  # file and curl exits 0 - deployer's old `curl -LO` did exactly that.
  ((fail)) && exit 22
  printf '<html>404 Not Found</html>\n' >"${out}"
  exit 0
fi
cp "${f}" "${out}"
EOF
# php runs a fixture "phar" (a bash script) as the real php would run the real phar.
# `php -r '<new Phar …>' <file>` is the script's Phar open; it models what PHP 8.5.4 did
# in the 02phpbrew image [measured 2026-09-25]: a file opens only when it is named
# *.phar, carries __HALT_COMPILER(); and ends with the GBMB signature magic. A truncated
# file, an HTML page and a copy without the .phar name were all refused.
cat >"${_P66}/stub/php" <<'EOF'
#!/bin/bash
if [[ "$1" == -r ]]; then
  [[ "$2" == *"new Phar"* && "$3" == *.phar && -f "$3" ]] || exit 1
  grep -q '__HALT_COMPILER();' "$3" && [[ "$(tail -c 4 "$3")" == GBMB ]]
  exit $?
fi
if [[ -f "$1" ]]; then exec bash "$@"; fi
exit 1
EOF
# _p66_gh <repo> <tag> <file> ok|html|trunc [<version line>]: a GitHub release asset.
# ok = a "phar" that opens; with a version line it answers --version like deployer/pie,
# without one it cannot run under the image's php, like zephir/phalcon/pickle.
_p66_gh() {
  local d="${_P66}/up/gh/$1/$2"
  mkdir -p "${d}"
  if [[ "$4" == html ]]; then
    printf '<html>Not Found</html>\n' >"${d}/$3"
    return 0
  fi
  {
    printf '#!/bin/bash\n# id=%s@%s\n' "$1" "$2"
    if [[ -n "${5:-}" ]]; then
      printf 'if [[ "$1" == --version ]]; then echo "%s"; fi\nexit 0\n' "$5"
    else
      printf 'echo "Box Requirements Checker"\nexit 1\n'
    fi
    printf '# __HALT_COMPILER(); ?>\n'
    [[ "$4" == trunc ]] || printf 'GBMB'
  } >"${d}/$3"
}
printf '#!/bin/bash\nexec "$@"\n' >"${_P66}/stub/sudo"
chmod +x "${_P66}/stub/curl" "${_P66}/stub/php" "${_P66}/stub/sudo"

_p66_phar() { # $1 = tag, $2 = version printed, $3 = ok|failinstall → the bootstrap composer.phar for that tag
  mkdir -p "${_P66}/up/dl/$1"
  cat >"${_P66}/up/dl/$1/composer.phar" <<EOF
#!/bin/bash
case "\$1" in
  --version) echo "Composer version $2 2026-08-27 13:34:23" ;;
  install) [[ "$3" == ok ]] || exit 1; mkdir -p vendor && echo '<?php' >vendor/autoload.php ;;
esac
EOF
  (cd "${_P66}/up/dl/$1" && sha256sum composer.phar >composer.phar.sha256sum)
}
# The composer source repo: bin/composer answers --version and the two `global` verbs
# the script uses; `global require` installs a laravel that prints its version (1.4.0
# prints 1.4.00, to be refused).
(
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
  r="${_P66}/src-repo"
  g init -q "${r}" && mkdir -p "${r}/bin"
  for v in 1.0.0 1.1.0 1.2.0 1.4.0 1.5.0 1.7.0; do
    pv="${v}"; [[ "${v}" == 1.7.0 ]] && pv=1.7.1
    cat >"${r}/bin/composer" <<EOF
#!/bin/bash
case "\$1" in
  --version) echo "Composer version ${pv} 2026-08-27 13:34:23" ;;
  global)
    case "\$2" in
      require)
        lv="\${4#laravel/installer:}"; lv="\${lv#v}"; [[ "\${lv}" == 1.4.0 ]] && lv=1.4.00
        mkdir -p "\${COMPOSER_HOME}/vendor/bin"
        printf '#!/bin/bash\necho "Laravel Installer %s"\n' "\${lv}" >"\${COMPOSER_HOME}/vendor/bin/laravel"
        chmod +x "\${COMPOSER_HOME}/vendor/bin/laravel" ;;
      show) [[ -f "\${COMPOSER_HOME}/vendor/bin/laravel" ]] ;;
    esac ;;
esac
EOF
    chmod +x "${r}/bin/composer"
    g -C "${r}" add -A && g -C "${r}" commit -qm "${v}" && g -C "${r}" tag "${v}"
  done
  g clone -q --bare "${r}" "${_P66}/gh/composer/composer.git"
) >/dev/null 2>&1
# 1.0.0/1.1.0 good; 1.2.0 phar published with a wrong sha256; 1.3.0 phar fine but no
# such tag to clone; 1.4.0 phar reports 1.4.00; 1.5.0 `composer install` fails; 1.7.0
# phar is right but the source at that tag builds a composer reporting 1.7.1.
_p66_phar 1.0.0 1.0.0 ok
_p66_phar 1.1.0 1.1.0 ok
_p66_phar 1.2.0 1.2.0 ok
_p66_phar 1.3.0 1.3.0 ok
_p66_phar 1.4.0 1.4.00 ok
_p66_phar 1.5.0 1.5.0 failinstall
_p66_phar 1.7.0 1.7.0 ok
printf '%064d  composer.phar\n' 0 >"${_P66}/up/dl/1.2.0/composer.phar.sha256sum"
assert_pass "66a: fixture — repo tags, real sha256sum format, the redirect reaches the repo (non-vacuity)" \
  bash -c 'cd "$1/up/dl/1.1.0" && grep -qE "^[0-9a-f]{64}  composer\.phar$" composer.phar.sha256sum && sha256sum -c --quiet composer.phar.sha256sum \
    && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$1/gh/.insteadOf" GIT_CONFIG_VALUE_0=https://github.com/ \
       git ls-remote --tags https://github.com/composer/composer.git | grep -c "refs/tags/1\.[0-9]\.0$" | grep -qx 6' _ "${_P66}"

_P66_OTHERS='ZEPHIR_LANG:zephir:bin/zephir PHALCON_DEVTOOLS:phalcon:bin/phalcon DEPLOYER:deployer:bin/dep SYMFONY_CLI:symfony-cli:symfony/bin/symfony PICKLE:pickle:bin/pickle PIE:pie:bin/pie MAGO:mago:bin/mago CASTOR:castor:bin/castor FABPOT_LOCAL_PHP_SECURITY_CHECKER:fabpot-local-php-security-checker:bin/fabpot-local-php-security-checker'
_p66_prep() { # $1 = installed composer tag|none, $2 = composer marker|none, $3 = installed laravel version|none, $4 = laravel marker|none
  local t="${_P66}/tools" o
  rm -rf "${t}" "${_P66}/curl.log"
  mkdir -p "${t}/versions" "${t}/errors" "${t}/bin" "${t}/symfony/bin" "${t}/composer/bin"
  for o in ${_P66_OTHERS}; do
    : >"${t}/${o##*:}"
    o="${o#*:}"
    printf 'n1\n' >"${t}/versions/phpbrew.${o%%:*}"
  done
  if [[ "$1" != none ]]; then
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -c advice.detachedHead=false clone -q --branch "$1" "${_P66}/src-repo" "${t}/composer/source" >/dev/null 2>&1
    mkdir -p "${t}/composer/source/vendor"
    : >"${t}/composer/source/stale-from-$1"
    cp "${_P66}/up/dl/$1/composer.phar" "${t}/composer/bin/composer"
  fi
  [[ "$2" == none ]] || printf '%s\n' "$2" >"${t}/versions/phpbrew.composer"
  if [[ "$3" != none ]]; then
    mkdir -p "${t}/composer/vendor/bin"
    printf '#!/bin/bash\necho "Laravel Installer %s"\n' "$3" >"${t}/composer/vendor/bin/laravel"
    chmod +x "${t}/composer/vendor/bin/laravel"
  fi
  [[ "$4" == none ]] || printf '%s\n' "$4" >"${t}/versions/phpbrew.laravel-installer"
}
_p66_run() { # $1 = composer pin, $2 = laravel pin → state string
  local rc=0 t="${_P66}/tools" src phar lar
  (cd "${_P66_CWD:-${_P66}/work}" && env -i HOME="${_P66}" P66="${_P66}" \
    PATH="${_P66_PATH_PRE:-}${_P66}/stub:${t}/composer/source/bin:${DIST_BIN}/base-bin:/usr/bin:/bin" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_COUNT=1 \
    "GIT_CONFIG_KEY_0=url.${_P66}/gh/.insteadOf" GIT_CONFIG_VALUE_0=https://github.com/ \
    GLOBAL_STACK_ERROR_TOKEN=p66-token GLOBAL_STACK_DOCKER_TOOLS_PATH="${t}" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${t}/errors" GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${t}/versions" \
    GLOBAL_STACK_DOCKER_ROOT_DIST_PATH="${_P66}/dist" \
    PHPBREW_BIN="${t}/bin" SYMFONY_HOME="${t}/symfony" COMPOSER_HOME="${t}/composer" COMPOSER_SOURCE="${t}/composer/source" \
    GLOBAL_STACK_COMPOSER_VERSION="$1" GLOBAL_STACK_LARAVEL_INSTALLER_VERSION="$2" \
    GLOBAL_STACK_ZEPHIR_LANG_VERSION="${_P66_ZEPHIR:-n1}" GLOBAL_STACK_PHALCON_DEVTOOLS_VERSION="${_P66_PHALCON:-n1}" \
    GLOBAL_STACK_DEPLOYER_VERSION="${_P66_DEPLOYER:-n1}" GLOBAL_STACK_SYMFONY_CLI_VERSION="${_P66_SYMFONY:-n1}" \
    GLOBAL_STACK_PICKLE_VERSION="${_P66_PICKLE:-n1}" GLOBAL_STACK_PIE_VERSION="${_P66_PIE:-n1}" \
    GLOBAL_STACK_MAGO_VERSION="${_P66_MAGO:-n1}" GLOBAL_STACK_CASTOR_VERSION="${_P66_CASTOR:-n1}" \
    GLOBAL_STACK_FABPOT_LOCAL_PHP_SECURITY_CHECKER_VERSION="${_P66_FABPOT:-n1}" \
    bash "${DIST_BIN}/phpbrew-bin/global-stack-phpbrew-install-tools.sh") >"${_P66}/last.log" 2>&1 || rc=fail
  src="$({ bash "${t}/composer/source/bin/composer" --version 2>/dev/null || true; } | awk '{ print $3 }')"
  phar="$({ bash "${t}/composer/bin/composer" --version 2>/dev/null || true; } | awk '{ print $3 }')"
  lar="$({ bash "${t}/composer/vendor/bin/laravel" 2>/dev/null || true; } | awk '{ print $3 }')"
  printf 'rc=%s src=%s phar=%s marker=%s stale=%s overlay=%s vendor=%s laravel=%s lmarker=%s' "${rc}" \
    "${src:-none}" "${phar:-none}" "$(cat "${t}/versions/phpbrew.composer" 2>/dev/null || echo none)" \
    "$(if compgen -G "${t}/composer/source/stale-from-*" >/dev/null; then echo yes; else echo no; fi)" \
    "$(if [[ -e "${t}/composer/source/src/overlay-applied" ]]; then echo yes; else echo no; fi)" \
    "$(if [[ -e "${t}/composer/source/vendor" ]]; then echo yes; else echo no; fi)" \
    "${lar:-none}" "$(cat "${t}/versions/phpbrew.laravel-installer" 2>/dev/null || echo none)"
}
mkdir -p "${_P66}/dist/conf/phpbrew-composer"
cp -r "${_P66}/overlay" "${_P66}/dist/conf/phpbrew-composer/source"

_p66_prep none none none none
assert_pass "66b: first install -> pinned phar + source built at the tag, overlay applied, laravel at its pin" \
  test "$(_p66_run 1.1.0 v1.1.0)" = "rc=0 src=1.1.0 phar=1.1.0 marker=1.1.0 stale=no overlay=yes vendor=yes laravel=1.1.0 lmarker=v1.1.0"
_p66_prep 1.0.0 1.0.0 1.0.0 v1.0.0
assert_pass "66c: composer 1.0.0 -> pin 1.1.0: new source and phar, old source gone, laravel kept" \
  test "$(_p66_run 1.1.0 v1.0.0)" = "rc=0 src=1.1.0 phar=1.1.0 marker=1.1.0 stale=no overlay=yes vendor=yes laravel=1.0.0 lmarker=v1.0.0"
_p66_prep 1.1.0 1.1.0 1.0.0 v1.0.0
assert_pass "66d: composer 1.1.0 -> pin moved back to 1.0.0" \
  test "$(_p66_run 1.0.0 v1.0.0)" = "rc=0 src=1.0.0 phar=1.0.0 marker=1.0.0 stale=no overlay=yes vendor=yes laravel=1.0.0 lmarker=v1.0.0"
for _c in '1.2.0:phar fails its published sha256' '1.3.0:no such tag to clone' '1.4.0:phar reports 1.4.00' '1.5.0:composer install fails' '1.6.0:phar not published' '1.7.0:source builds 1.7.1'; do
  _p66_prep 1.0.0 1.0.0 1.0.0 v1.0.0
  _o="$(_p66_run "${_c%%:*}" v1.0.0)"
  assert_pass "66e: composer pin ${_c%%:*} (${_c#*:}) -> FATAL, old source, phar and marker untouched" \
    bash -c '[[ "$1" == "rc=fail src=1.0.0 phar=1.0.0 marker=1.0.0 stale=yes overlay=no vendor=yes laravel=1.0.0 lmarker=v1.0.0" ]] && grep -q "^FATAL: .*composer left as it was" "$2/last.log"' _ "${_o}" "${_P66}"
done
_p66_prep 1.1.0 1.1.0 1.0.0 v1.0.0
assert_pass "66f: laravel v1.0.0 -> pin v1.1.0: installed and checked, marker written" \
  test "$(_p66_run 1.1.0 v1.1.0)" = "rc=0 src=1.1.0 phar=1.1.0 marker=1.1.0 stale=yes overlay=no vendor=yes laravel=1.1.0 lmarker=v1.1.0"
_p66_prep 1.1.0 1.1.0 1.0.0 v1.0.0
assert_pass "66g: laravel pin v1.4.0 installs something reporting 1.4.00 -> FATAL, marker not written" \
  bash -c '[[ "$1" == rc=fail\ *\ laravel=1.4.00\ lmarker=v1.0.0 ]]' _ "$(_p66_run 1.1.0 v1.4.0)"
_p66_prep 1.1.0 1.1.0 1.1.0 v1.1.0
_o="$(_p66_run 1.1.0 v1.1.0)"
assert_pass "66h: everything current -> nothing downloaded, nothing touched" \
  bash -c '[[ "$1" == "rc=0 src=1.1.0 phar=1.1.0 marker=1.1.0 stale=yes overlay=no vendor=yes laravel=1.1.0 lmarker=v1.1.0" && ! -s "$2/curl.log" ]]' _ "${_o}" "${_P66}"
# The script's cwd is compose's working_dir, /stack/projects: the developer's projects.
# The later blocks download with `curl -O` into the cwd and run `rm -rf zephir.pha*` (and
# phalcon/pickle/pie) there on every boot, so a developer file matching the glob was
# deleted. The model: a projects-like cwd holding such a file, composer reinstalling AND
# zephir bumped; the file must survive and nothing may be written beside it.
_p66_gh zephir n2 zephir.phar ok
mkdir -p "${_P66}/proj"
printf 'mine\n' >"${_P66}/proj/zephir.phar-notes"
_p66_prep 1.0.0 1.0.0 1.1.0 v1.1.0
_o="$(_P66_CWD="${_P66}/proj" _P66_ZEPHIR=n2 _p66_run 1.1.0 v1.1.0)"
assert_pass "66j: cwd = the projects dir, composer reinstall + zephir bump -> both installed, the developer's zephir.phar-notes survives, nothing added" \
  bash -c '[[ "$1" == rc=0\ src=1.1.0\ phar=1.1.0\ marker=1.1.0\ * && "$(cat "$2/tools/versions/phpbrew.zephir")" == n2 && "$(sed -n "s/^# id=//p" "$2/tools/bin/zephir")" == zephir@n2 && "$(ls -A "$2/proj")" == zephir.phar-notes ]]' _ "${_o}" "${_P66}"
# Comment lines stripped (the §19 shape): the rewrite's own comment names what it replaced.
assert_fail "66i: composer-setup.php (the unpinned bootstrap) is gone from executable lines" \
  bash -c 'grep -vE "^[[:space:]]*#" "$1" | grep -q "composer-setup\.php"' _ "${PHPBREW_TOOLS}"

# ─── Section 67: the six phars are checked before they replace the old one (castor since 15c) ──
# Pin-audit tranche 2 step 15b. zephir, phalcon, pickle, pie and deployer used to go
# straight from the download into tools/bin: `curl -fsSLO` + `mv` (deployer `curl -LO`
# with no -f, so a 404 page was installed and its marker written). None publishes a
# checksum. Now each is downloaded into the temp dir as <tool>.phar and opened as a Phar
# (signature-verified) before it replaces anything; deployer and pie, the two that run
# under the image's php, must also name their pin. zephir/phalcon/pickle cannot run
# there (mbstring missing), so their VERSION is pinned by URL only. castor (step 15c) joins
# them: it used to be `castor install | bash`, whose default is this same phar, and it
# runs under the image's php, so it is version-checked like deployer and pie.
printf '\n── Section 67: the six phars checked before they replace the old one (tranche 2 steps 15b/15c)\n'
_P67_TOOLS='zephir:ZEPHIR:zephir:zephir.phar:bin/zephir:zephir::
phalcon:PHALCON:phalcon-devtools:phalcon.phar:bin/phalcon:phalcon:v:
deployer:DEPLOYER:deployer:deployer.phar:bin/dep:deployer:v:Deployer %s
pickle:PICKLE:pickle:pickle.phar:bin/pickle:pickle:v:
pie:PIE:pie:pie.phar:bin/pie:pie::🥧 PHP Installer for Extensions (PIE) %s
castor:CASTOR:castor:castor.linux-amd64.phar:bin/castor:castor:v:castor v%s'
# Per tool: 1.1.0 and 1.2.0 good; 1.3.0 not published; 1.4.0 an HTML page served with
# 200; 1.5.0 truncated (no signature magic); 1.6.0 intact but, for the two that run,
# reporting 1.6.00.
while IFS=: read -r _k _sfx _repo _file _dest _mk _pfx _vl; do
  for _v in 1.1.0 1.2.0 1.6.0; do
    _line=""
    [[ -n "${_vl}" ]] && _line="$(printf "${_vl}" "${_v/1.6.0/1.6.00}")"
    _p66_gh "${_repo}" "${_pfx}${_v}" "${_file}" ok "${_line}"
  done
  _p66_gh "${_repo}" "${_pfx}1.4.0" "${_file}" html
  _p66_gh "${_repo}" "${_pfx}1.5.0" "${_file}" trunc
done <<<"${_P67_TOOLS}"

assert_pass "67a: stub php opens a good fixture phar, refuses the HTML page, the truncated file and a copy without .phar (non-vacuity)" \
  bash -c 'p="$1/stub/php"; g="$1/up/gh/pie"; c="try { new Phar(\$argv[1]); } catch (Throwable \$e) { exit(1); }"
    cp "$g/1.1.0/pie.phar" "$1/renamed"
    "$p" -r "$c" "$g/1.1.0/pie.phar" && ! "$p" -r "$c" "$g/1.4.0/pie.phar" && ! "$p" -r "$c" "$g/1.5.0/pie.phar" && ! "$p" -r "$c" "$1/renamed"' _ "${_P66}"
assert_pass "67a: stub curl without -f installs the 404 page (deployer's old defect), with -f fails 22 (non-vacuity)" \
  bash -c 'cd "$1/work" && P66="$1" "$1/stub/curl" -LO https://github.com/deployphp/deployer/releases/download/v1.3.0/deployer.phar && grep -q 404 deployer.phar && rm deployer.phar \
    && { P66="$1" "$1/stub/curl" -fsSLO https://github.com/deployphp/deployer/releases/download/v1.3.0/deployer.phar; test $? = 22; }' _ "${_P66}"

_p67_prep() { # $1 = tool spec line, $2 = installed tag|none
  local _k _sfx _repo _file _dest _mk _pfx _vl t="${_P66}/tools"
  IFS=: read -r _k _sfx _repo _file _dest _mk _pfx _vl <<<"$1"
  _p66_prep 1.1.0 1.1.0 1.1.0 v1.1.0
  rm -f "${t}/${_dest}" "${t}/versions/phpbrew.${_mk}"
  if [[ "$2" != none ]]; then
    cp "${_P66}/up/gh/${_repo}/$2/${_file}" "${t}/${_dest}"
    printf '%s\n' "$2" >"${t}/versions/phpbrew.${_mk}"
  fi
}
_p67_run() { # $1 = tool spec line, $2 = pin → rc, installed id, marker, named FATAL, strays in tools/bin
  local _k _sfx _repo _file _dest _mk _pfx _vl t="${_P66}/tools" o id
  IFS=: read -r _k _sfx _repo _file _dest _mk _pfx _vl <<<"$1"
  local -x "_P66_${_sfx}=$2"
  o="$(_p66_run 1.1.0 v1.1.0)"
  id="$(sed -n 's/^# id=//p' "${t}/${_dest}" 2>/dev/null || true)"
  printf '%s id=%s marker=%s fatal=%s stray=%s' "${o%% *}" "${id:-none}" \
    "$(cat "${t}/versions/phpbrew.${_mk}" 2>/dev/null || echo none)" \
    "$(if grep -q "^FATAL: .*${_k} left as it was" "${_P66}/last.log"; then echo yes; else echo no; fi)" \
    "$({ ls -A "${t}/bin" | grep -cE '\.phar|\.tmp|\.new' || true; })"
}
while IFS= read -r _spec; do
  IFS=: read -r _k _sfx _repo _file _dest _mk _pfx _vl <<<"${_spec}"
  _p67_prep "${_spec}" "${_pfx}1.1.0"
  assert_pass "67b: ${_k} ${_pfx}1.1.0 -> pin ${_pfx}1.2.0: checked, installed, marker last" \
    test "$(_p67_run "${_spec}" "${_pfx}1.2.0")" = "rc=0 id=${_repo}@${_pfx}1.2.0 marker=${_pfx}1.2.0 fatal=no stray=0"
  _p67_prep "${_spec}" "${_pfx}1.2.0"
  assert_pass "67c: ${_k} ${_pfx}1.2.0 -> pin moved back to ${_pfx}1.1.0" \
    test "$(_p67_run "${_spec}" "${_pfx}1.1.0")" = "rc=0 id=${_repo}@${_pfx}1.1.0 marker=${_pfx}1.1.0 fatal=no stray=0"
  _p67_prep "${_spec}" none
  assert_pass "67d: ${_k} first install at ${_pfx}1.1.0" \
    test "$(_p67_run "${_spec}" "${_pfx}1.1.0")" = "rc=0 id=${_repo}@${_pfx}1.1.0 marker=${_pfx}1.1.0 fatal=no stray=0"
  _p67_prep "${_spec}" "${_pfx}1.1.0"
  _o="$(_p67_run "${_spec}" "${_pfx}1.1.0")"
  assert_pass "67e: ${_k} current -> not downloaded, not touched" \
    bash -c '[[ "$1" == "rc=0 id=$3@$4 marker=$4 fatal=no stray=0" ]] && ! grep -q "/$3/releases/" "$2/curl.log"' _ "${_o}" "${_P66}" "${_repo}" "${_pfx}1.1.0"
  _fails='1.3.0:not published|1.4.0:an HTML page|1.5.0:truncated'
  [[ -n "${_vl}" ]] && _fails="${_fails}|1.6.0:reports 1.6.00"
  while IFS=: read -r _v _why; do
    _p67_prep "${_spec}" "${_pfx}1.1.0"
    assert_pass "67f: ${_k} pin ${_pfx}${_v} (${_why}) -> named FATAL, old ${_k} and marker untouched" \
      test "$(_p67_run "${_spec}" "${_pfx}${_v}")" = "rc=fail id=${_repo}@${_pfx}1.1.0 marker=${_pfx}1.1.0 fatal=yes stray=0"
  done <<<"${_fails//|/$'\n'}"
done <<<"${_P67_TOOLS}"
# An interrupted copy: an `install` that writes a short copy of anything headed for
# tools/bin. The compare after the copy must refuse it and leave the old marker.
mkdir -p "${_P66}/stub-short"
cat >"${_P66}/stub-short/install" <<'EOF'
#!/bin/bash
src="${@: -2:1}" dst="${@: -1}"
[[ "${dst}" == */tools/bin/* ]] || exec /usr/bin/install "$@"
head -c 20 "${src}" >"${dst}"
EOF
chmod +x "${_P66}/stub-short/install"
while IFS= read -r _spec; do
  IFS=: read -r _k _sfx _repo _file _dest _mk _pfx _vl <<<"${_spec}"
  [[ "${_k}" == zephir || "${_k}" == deployer ]] || continue
  _p67_prep "${_spec}" "${_pfx}1.1.0"
  _o="$(_P66_PATH_PRE="${_P66}/stub-short:" _p67_run "${_spec}" "${_pfx}1.2.0")"
  assert_pass "67g: ${_k} copy into tools/bin cut short -> FATAL, marker stays ${_pfx}1.1.0" \
    bash -c '[[ "$1" == rc=fail\ id=*\ marker="$3"\ fatal=no\ stray=0 ]] && grep -q "^FATAL: the installed $4 differs from the checked download" "$2/last.log"' _ "${_o}" "${_P66}" "${_pfx}1.1.0" "${_k}"
done <<<"${_P67_TOOLS}"

# ─── Section 68: symfony, mago and fabpot checked before they replace the old one ──
# Pin-audit tranche 2 step 15c. symfony was `curl -LO` (no -f) + tar; mago was
# `curl …/mago.sh | bash`; fabpot was `curl -LsS -o <the installed binary>` with no -f,
# so a 404 page overwrote the working checker and its marker was written. Now each is
# downloaded into the temp dir, checked against its release's checksums.txt where one is
# published (symfony, fabpot), its archive listed (symfony, mago), its version run, and
# only then placed. castor moved to §67.
printf '\n── Section 68: symfony, mago, fabpot checked before they replace the old one (tranche 2 step 15c)\n'
_P68_TOOLS='symfony:SYMFONY:symfony-cli:symfony/bin/symfony:symfony-cli:v:Symfony CLI version %s (c) 2021-2026 Fabien Potencier
mago:MAGO:mago:bin/mago:mago::mago %s
fabpot:FABPOT:local-php-security-checker:bin/fabpot-local-php-security-checker:fabpot-local-php-security-checker:v:Local PHP Security Checker %s, built at 2024-05-09T11:54:42Z'
# _p68_mk <spec> <ver> ok|badsum|nobin|html|badver|nosums → release <pfx><ver> of that tool.
# checksums.txt also lists a darwin asset that is never published, as the real ones do, so
# only the asset's OWN line can be checked. symfony answers `version` (rc 0) and exits 1
# on `--version`, as measured.
_p68_mk() {
  local _k _sfx _repo _dest _mk _pfx _vl tag d b line asset inner
  IFS=: read -r _k _sfx _repo _dest _mk _pfx _vl <<<"$1"
  tag="${_pfx}$2" d="${_P66}/up/gh/${_repo}/${_pfx}$2" b="${_P66}/up/bin/${_repo}/${_pfx}$2"
  mkdir -p "${d}" "${b}"
  line="$(printf "${_vl}" "$2")"
  [[ "$3" == badver ]] && line="$(printf "${_vl}" "$2"0)"
  {
    printf '#!/bin/bash\n# id=%s@%s\n' "${_repo}" "${tag}"
    if [[ "${_k}" == symfony ]]; then
      printf 'case "${1:-}" in version) echo "%s"; exit 0 ;; --version) echo "%s"; exit 1 ;; esac\nexit 0\n' "${line}" "${line}"
    else
      printf 'case "${1:-}" in --version) echo "%s" ;; esac\nexit 0\n' "${line}"
    fi
  } >"${b}/bin"
  chmod +x "${b}/bin"
  [[ "$3" == html ]] && printf '<html>Not Found</html>\n' >"${b}/bin"
  case "${_k}" in
    symfony)
      asset=symfony-cli_linux_amd64.tar.gz
      mkdir -p "${b}/t" && printf 'MIT\n' >"${b}/t/LICENSE"
      # bare member names (LICENSE, symfony), as the real tarball lists them [measured]
      if [[ "$3" == nobin ]]; then
        tar -czf "${d}/${asset}" -C "${b}/t" LICENSE
      else
        cp "${b}/bin" "${b}/t/symfony"
        tar -czf "${d}/${asset}" -C "${b}/t" LICENSE symfony
      fi ;;
    mago)
      inner="mago-$2-x86_64-unknown-linux-gnu" asset="mago-$2-x86_64-unknown-linux-gnu.tar.gz"
      [[ "$3" == nobin ]] && inner="mago-$2"
      mkdir -p "${b}/t/${inner}" && cp "${b}/bin" "${b}/t/${inner}/mago"
      tar -czf "${d}/${asset}" -C "${b}/t" "${inner}" ;;
    fabpot)
      asset=local-php-security-checker_linux_amd64
      cp "${b}/bin" "${d}/${asset}" ;;
  esac
  if [[ "${_k}" != mago && "$3" != nosums ]]; then
    {
      printf '%s  %s\n' "$(printf 'x' | sha256sum | cut -d' ' -f1)" "${asset/linux_amd64/darwin_arm64}"
      if [[ "$3" == badsum ]]; then
        printf '%064d  %s\n' 0 "${asset}"
      elif [[ "$3" != unlisted ]]; then
        (cd "${d}" && sha256sum "${asset}")
      fi
    } >"${d}/checksums.txt"
  fi
}
while IFS= read -r _spec; do
  IFS=: read -r _k _sfx _repo _dest _mk _pfx _vl <<<"${_spec}"
  for _m in 1.1.0:ok 1.2.0:ok 1.4.0:badsum 1.5.0:nobin 1.6.0:badver 1.7.0:nosums; do
    _p68_mk "${_spec}" "${_m%%:*}" "${_m#*:}"
  done
  [[ "${_k}" == fabpot ]] && _p68_mk "${_spec}" 1.5.0 html
  [[ "${_k}" == symfony ]] && _p68_mk "${_spec}" 1.8.0 unlisted
done <<<"${_P68_TOOLS}"
assert_pass "68a: fixtures — a good tarball's own checksums.txt line verifies, the whole file does not (non-vacuity)" \
  bash -c 'cd "$1/up/gh/symfony-cli/v1.1.0" && grep " symfony-cli_linux_amd64.tar.gz$" checksums.txt | sha256sum -c --quiet - && ! sha256sum -c --quiet checksums.txt >/dev/null 2>&1 \
    && tar -tzf "$1/up/gh/mago/1.1.0/mago-1.1.0-x86_64-unknown-linux-gnu.tar.gz" | grep -qx "mago-1.1.0-x86_64-unknown-linux-gnu/mago" \
    && tar -tzf "$1/up/gh/symfony-cli/v1.1.0/symfony-cli_linux_amd64.tar.gz" | grep -qx symfony \
    && ! "$1/up/bin/symfony-cli/v1.1.0/bin" --version >/dev/null && "$1/up/bin/symfony-cli/v1.1.0/bin" version | grep -q "version 1.1.0 " \
    && "$1/up/bin/mago/1.6.0/bin" --version | grep -qx "mago 1.6.00"' _ "${_P66}"

_p68_prep() { # $1 = tool spec, $2 = installed tag|none
  local _k _sfx _repo _dest _mk _pfx _vl t="${_P66}/tools"
  IFS=: read -r _k _sfx _repo _dest _mk _pfx _vl <<<"$1"
  _p66_prep 1.1.0 1.1.0 1.1.0 v1.1.0
  rm -f "${t}/${_dest}" "${t}/versions/phpbrew.${_mk}"
  if [[ "$2" != none ]]; then
    cp "${_P66}/up/bin/${_repo}/$2/bin" "${t}/${_dest}"
    printf '%s\n' "$2" >"${t}/versions/phpbrew.${_mk}"
  fi
}
_p68_run() { # $1 = tool spec, $2 = pin → rc, installed id, marker, named FATAL, strays
  local _k _sfx _repo _dest _mk _pfx _vl t="${_P66}/tools" o id
  IFS=: read -r _k _sfx _repo _dest _mk _pfx _vl <<<"$1"
  local -x "_P66_${_sfx}=$2"
  o="$(_p66_run 1.1.0 v1.1.0)"
  id="$(sed -n 's/^# id=//p' "${t}/${_dest}" 2>/dev/null || true)"
  printf '%s id=%s marker=%s fatal=%s stray=%s' "${o%% *}" "${id:-none}" \
    "$(cat "${t}/versions/phpbrew.${_mk}" 2>/dev/null || echo none)" \
    "$(if grep -q "^FATAL: .*${_k} left as it was" "${_P66}/last.log"; then echo yes; else echo no; fi)" \
    "$({ ls -A "${t}/bin" "${t}/symfony/bin" | grep -cE '\.tar\.gz|\.phar|\.tmp|\.new|checksums|\.sha256|linux' || true; })"
}
while IFS= read -r _spec; do
  IFS=: read -r _k _sfx _repo _dest _mk _pfx _vl <<<"${_spec}"
  _p68_prep "${_spec}" "${_pfx}1.1.0"
  assert_pass "68b: ${_k} ${_pfx}1.1.0 -> pin ${_pfx}1.2.0: checked, installed, marker last" \
    test "$(_p68_run "${_spec}" "${_pfx}1.2.0")" = "rc=0 id=${_repo}@${_pfx}1.2.0 marker=${_pfx}1.2.0 fatal=no stray=0"
  _p68_prep "${_spec}" "${_pfx}1.2.0"
  assert_pass "68c: ${_k} ${_pfx}1.2.0 -> pin moved back to ${_pfx}1.1.0" \
    test "$(_p68_run "${_spec}" "${_pfx}1.1.0")" = "rc=0 id=${_repo}@${_pfx}1.1.0 marker=${_pfx}1.1.0 fatal=no stray=0"
  _p68_prep "${_spec}" none
  assert_pass "68d: ${_k} first install at ${_pfx}1.1.0" \
    test "$(_p68_run "${_spec}" "${_pfx}1.1.0")" = "rc=0 id=${_repo}@${_pfx}1.1.0 marker=${_pfx}1.1.0 fatal=no stray=0"
  _p68_prep "${_spec}" "${_pfx}1.1.0"
  _o="$(_p68_run "${_spec}" "${_pfx}1.1.0")"
  assert_pass "68e: ${_k} current -> not downloaded, not touched" \
    bash -c '[[ "$1" == "rc=0 id=$3@$4 marker=$4 fatal=no stray=0" ]] && ! grep -q "/$3/releases/" "$2/curl.log"' _ "${_o}" "${_P66}" "${_repo}" "${_pfx}1.1.0"
  case "${_k}" in
    symfony) _fails='1.3.0:not published|1.4.0:checksum mismatch|1.5.0:tarball without the binary|1.6.0:reports a .00 version|1.7.0:no checksums.txt' ;;
    mago) _fails='1.3.0:not published|1.5.0:tarball without the binary|1.6.0:reports a .00 version' ;;
    fabpot) _fails='1.3.0:not published|1.4.0:checksum mismatch|1.5.0:an HTML page with a matching checksum|1.6.0:reports a .00 version|1.7.0:no checksums.txt' ;;
  esac
  while IFS=: read -r _v _why; do
    _p68_prep "${_spec}" "${_pfx}1.1.0"
    assert_pass "68f: ${_k} pin ${_pfx}${_v} (${_why}) -> named FATAL, old ${_k} and marker untouched" \
      test "$(_p68_run "${_spec}" "${_pfx}${_v}")" = "rc=fail id=${_repo}@${_pfx}1.1.0 marker=${_pfx}1.1.0 fatal=yes stray=0"
  done <<<"${_fails//|/$'\n'}"
done <<<"${_P68_TOOLS}"
# A checksums.txt that does not list the asset at all: fail closed either way, but the
# FATAL must say so rather than report a mismatch against nothing.
_spec="$(grep '^symfony:' <<<"${_P68_TOOLS}")"
_p68_prep "${_spec}" v1.1.0
_o="$(_p68_run "${_spec}" v1.8.0)"
assert_pass "68f: symfony pin v1.8.0 (checksums.txt without the asset's line) -> FATAL names it as not listed, old symfony kept" \
  bash -c '[[ "$1" == "rc=fail id=symfony-cli@v1.1.0 marker=v1.1.0 fatal=yes stray=0" ]] && grep -q "^FATAL: symfony-cli_linux_amd64.tar.gz is not listed in symfony" "$2/last.log"' _ "${_o}" "${_P66}"

# Static, comment lines stripped (the §19 shape — the comments name what they replaced):
# no remote script is piped into a shell (ruling: never pipe remote scripts), and every
# curl fails on an HTTP error. The floor keeps the curl check from passing on nothing.
_pt_exec="$(grep -vE '^[[:space:]]*#' "${PHPBREW_TOOLS}")"
assert_pass "68g: no executable line pipes into bash or sh" \
  bash -c '! grep -qE "\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh([[:space:]]|$)" <<<"$1"' _ "${_pt_exec}"
assert_pass "68h: at least 4 executable curl calls (counted per call, not per line), and every one carries -f (floor + guard)" \
  bash -c 'c="$(grep -oE "curl [^;|]*" <<<"$1")"; n="$(grep -c . <<<"${c}")"; bad="$(grep -cvE "[[:space:]]-[a-zA-Z]*f[a-zA-Z]*[[:space:]]" <<<"${c}" || true)"; [[ "${n}" -ge 4 && "${bad}" == 0 ]]' _ "${_pt_exec}"

# ─── Section 69: an android SDK reinstall keeps the Gradle cache ────────────
# Pin-audit tranche 2 step 16 (ruling 2026-09-24 23:55, option a): every reinstall
# trigger (a changed SDK input, a missing android.cli marker, RELOAD_ANDROID=true) wiped
# GRADLE_USER_HOME together with the SDK. Gradle's cache belongs to no SDK pin; the SDK
# wipe itself stays whole. The SHIPPED gate→wipe→mkdir block runs here, extracted by its
# anchors. SAFETY: that block is a real `sudo rm -rf` of variables an ordinary /stack
# shell exports, so it runs under env -i with every one of them pinned under ${_P69},
# and the stub sudo refuses any path outside ${_P69}. 69a proves the refusal first on a
# SIBLING tmp dir, never on a live path: if the guard ever broke, the probe would cost
# one empty tmp dir, not the developer's SDK.
printf '\n── Section 69: an android SDK reinstall keeps the Gradle cache (tranche 2 step 16)\n'
_P69="${TMP_DIR}/p69"
mkdir -p "${_P69}/stub"
cat >"${_P69}/stub/sudo" <<EOF
#!/bin/bash
for a in "\$@"; do
  [[ "\${a}" == -* || "\${a}" == "${_P69}"/* || "\${a}" == rm || "\${a}" == mkdir ]] || { echo "REFUSED \${a}" >&2; exit 99; }
done
exec "\$@"
EOF
chmod +x "${_P69}/stub/sudo"
_P69_ANDR="${DIST_BIN}/android-bin/global-stack-android-start.sh"
awk '/^_android_gate=/,/^mkdir -p "\$\{ANDROID_HOME\}"/' "${_P69_ANDR}" >"${_P69}/block.sh"
mkdir -p "${TMP_DIR}/outside69/x"
assert_pass "69a: the stub sudo refuses a sibling path outside the test root (exit 99, dir still there) and runs one inside it (fail-safe proven first)" \
  bash -c '"$1/stub/sudo" rm -rf "$2/x"; [[ $? == 99 && -d "$2/x" ]] && mkdir -p "$1/x" && "$1/stub/sudo" rm -rf "$1/x" && [[ ! -e "$1/x" ]]' _ "${_P69}" "${TMP_DIR}/outside69"
assert_pass "69a: the extracted block holds the wipe and the mkdir (anchor non-vacuity)" \
  bash -c 'grep -q "sudo rm -rf \"\${ANDROID_HOME}\"" "$1" && grep -q "^mkdir -p \"\${ANDROID_HOME}\"" "$1" && [[ "$(grep -c . "$1")" -ge 4 ]]' _ "${_P69}/block.sh"
_p69_run() { # $1 = gate answer (skip|install), $2 = RELOAD_ANDROID, $3 = android.cli marker present (1|0) → state
  local r="${_P69}/r" rc=0
  rm -rf "${r}"
  mkdir -p "${r}/tools/android/home/.android" "${r}/tools/android/platforms/x" "${r}/tools/gradle/caches/modules-2" "${r}/tools/versions"
  : >"${r}/tools/android/platforms/x/f"
  : >"${r}/tools/gradle/caches/modules-2/dep.jar"
  printf 'want\n' >"${r}/tools/versions/android.sdk"
  [[ "$3" == 1 ]] && printf 'cli\n' >"${r}/tools/versions/android.cli"
  env -i PATH="${_P69}/stub:/usr/bin:/bin" P69_GATE="$1" \
    ANDROID_HOME="${r}/tools/android" ANDROID_SDK_ROOT="${r}/tools/android" ANDROID_SDK_HOME="${r}/tools/android/home" \
    GRADLE_USER_HOME="${r}/tools/gradle" GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${r}/tools/versions" \
    GLOBAL_STACK_RELOAD_ANDROID="$2" GS_ANDROID_SDK_WANT=want \
    bash -c 'set -euo pipefail; gs_version_gate() { printf "%s" "${P69_GATE}"; }; source "$1"' _ "${_P69}/block.sh" \
    >"${_P69}/last.log" 2>&1 || rc=$?
  printf 'rc=%s sdk=%s gradle=%s sdkmarker=%s climarker=%s refused=%s' "${rc}" \
    "$(if [[ -e "${r}/tools/android/platforms/x/f" ]]; then echo kept; else echo wiped; fi)" \
    "$(if [[ -e "${r}/tools/gradle/caches/modules-2/dep.jar" ]]; then echo kept; else echo wiped; fi)" \
    "$(if [[ -e "${r}/tools/versions/android.sdk" ]]; then echo kept; else echo gone; fi)" \
    "$(if [[ -e "${r}/tools/versions/android.cli" ]]; then echo kept; else echo gone; fi)" \
    "$(grep -c REFUSED "${_P69}/last.log" || true)"
}
assert_pass "69b: an SDK input changed -> the SDK and both markers wiped, the Gradle cache kept" \
  test "$(_p69_run install false 1)" = "rc=0 sdk=wiped gradle=kept sdkmarker=gone climarker=gone refused=0"
assert_pass "69c: RELOAD_ANDROID=true -> the SDK wiped, the Gradle cache kept" \
  test "$(_p69_run skip true 1)" = "rc=0 sdk=wiped gradle=kept sdkmarker=gone climarker=gone refused=0"
assert_pass "69d: android.cli marker missing -> the SDK wiped, the Gradle cache kept" \
  test "$(_p69_run skip false 0)" = "rc=0 sdk=wiped gradle=kept sdkmarker=gone climarker=gone refused=0"
assert_pass "69e: everything current -> nothing wiped" \
  test "$(_p69_run skip false 1)" = "rc=0 sdk=kept gradle=kept sdkmarker=kept climarker=kept refused=0"

# ─── Section 70: fvm is checked in a temp dir before it replaces the old binary ──
# Pin-audit tranche 3 step 18 (ruling 2026-09-26 11:17). The fvm tarball used to be
# downloaded and unpacked in the cwd, which is compose's working_dir, the developer's
# /stack/projects, and the script then ran `sudo rm -rf fvm/` there. So a project named
# fvm was deleted on every fvm bump. Nothing was checked, either. The SHIPPED install block
# runs here, extracted by its anchors, against a stub curl that models -f and a stub sudo
# that refuses any absolute path outside ${_P70}. The fixture's fvm prints its version
# the way the real 4.3.1 binary does: `fvm --version` -> `4.3.1`, nothing else
# [measured 2026-09-26].
printf '\n── Section 70: fvm checked in a temp dir before it replaces the old binary (tranche 3 step 18)\n'
_P70="${TMP_DIR}/p70"
mkdir -p "${_P70}/stub" "${_P70}/fix"
cat >"${_P70}/stub/sudo" <<EOF
#!/bin/bash
for a in "\$@"; do
  [[ "\${a}" != /* || "\${a}" == "${_P70}"/* ]] || { echo "REFUSED \${a}" >&2; exit 99; }
done
exec "\$@"
EOF
cat >"${_P70}/stub/curl" <<'EOF'
#!/bin/bash
out="" url="" fail=0
while (($#)); do
  case "$1" in
    -o) out="$2"; shift ;;
    --connect-timeout|--max-time) shift ;;
    -*) [[ "$1" == --* ]] || [[ "$1" != *f* ]] || fail=1 ;;
    *) url="$1" ;;
  esac
  shift
done
printf '%s\n' "${url}" >>"${P70_LOG}"
src="${P70_FIX}/${url#https://github.com/leoafarias/fvm/releases/download/}"
if [[ -f "${src}" ]]; then cat "${src}" >"${out}"; exit 0; fi
((fail)) && exit 22
printf '<html>404 Not Found</html>\n' >"${out}"
EOF
chmod +x "${_P70}/stub/sudo" "${_P70}/stub/curl"
_p70_fvm() { # $1 = path, $2 = what `--version` prints
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\necho %s\n' "$2" >"$1"
  chmod 0755 "$1"
}
_p70_tgz() { # $1 = version, $2 = what its fvm prints ('' = the tarball holds no fvm/fvm)
  local d="${_P70}/build/$1"
  rm -rf "${d}"
  mkdir -p "${d}/fvm/src" "${_P70}/fix/$1"
  printf 'license\n' >"${d}/fvm/src/LICENSE"
  [[ -z "$2" ]] || _p70_fvm "${d}/fvm/fvm" "$2"
  tar -C "${d}" -czf "${_P70}/fix/$1/fvm-$1-linux-x64.tar.gz" fvm
}
_p70_tgz 4.3.0 4.3.0
_p70_tgz 4.3.1 4.3.1
_p70_tgz 4.3.2 4.3.2
_p70_tgz 4.4.0 ''     # no fvm/fvm in the tarball
_p70_tgz 4.5.0 4.5.00 # reports a different version
mkdir -p "${_P70}/fix/4.7.0"
printf '<html>not a tarball</html>\n' >"${_P70}/fix/4.7.0/fvm-4.7.0-linux-x64.tar.gz"
# 4.6.0 is not served at all (curl -f exits 22).
_P70_FVM="${DIST_BIN}/fvm-bin/global-stack-fvm-start.sh"
awk '/^if \[\[ "\$\{FVM_MODE\}" = "install" \]\]; then$/{n++} n==2{print} n==2 && /^fi$/{exit}' "${_P70_FVM}" >"${_P70}/block.sh"
assert_pass "70a: the extracted install block holds the download and the marker write (anchor non-vacuity)" \
  bash -c 'grep -q "releases/download" "$1" && grep -q "VERSIONS}/fvm\"\$" "$1" && [[ "$(grep -c . "$1")" -ge 8 ]]' _ "${_P70}/block.sh"
_p70_run() { # $1 = pin, $2 = installed fvm version ('' = none), $3 = marker ('' = none), $4 = RELOAD_FVM
  local r="${_P70}/r" rc=0
  rm -rf "${r}"
  mkdir -p "${r}/tools/bin" "${r}/tools/versions" "${r}/projects/fvm" "${r}/tmp"
  printf 'keep\n' >"${r}/projects/fvm/keep"
  printf 'mine\n' >"${r}/projects/fvm-$1-linux-x64.tar.gz"
  [[ -z "$2" ]] || _p70_fvm "${r}/tools/bin/fvm" "$2"
  [[ -z "$3" ]] || printf '%s\n' "$3" >"${r}/tools/versions/fvm"
  : >"${_P70}/curl.log"
  (cd "${r}/projects" && env -i PATH="${_P70}/stub:/usr/bin:/bin" HOME="${r}" TMPDIR="${r}/tmp" \
    P70_FIX="${_P70}/fix" P70_LOG="${_P70}/curl.log" FVM_MODE=install FVM_VERSION="$1" \
    GLOBAL_STACK_FVM_VERSION="$1" GLOBAL_STACK_RELOAD_FVM="$4" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${r}/tools/versions" GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN="${r}/tools/bin" \
    bash -c 'set -eE -o pipefail; source "$1"; source "$2"' _ \
    "${DIST_BIN}/base-bin/global-stack-base-version-gate.sh" "${_P70}/block.sh") >"${_P70}/last.log" 2>&1 || rc=$?
  printf 'rc=%s bin=%s marker=%s projects=%s tmp=%s curls=%s fatal=%s refused=%s' "${rc}" \
    "$("${r}/tools/bin/fvm" --version 2>/dev/null || echo none)" \
    "$(cat "${r}/tools/versions/fvm" 2>/dev/null || echo none)" \
    "$(if [[ "$(cat "${r}/projects/fvm/keep" "${r}/projects/fvm-$1-linux-x64.tar.gz" 2>/dev/null)" == $'keep\nmine' && "$(ls -A "${r}/projects" | wc -l)" == 2 ]]; then echo intact; else echo touched; fi)" \
    "$(ls -A "${r}/tmp" | wc -l)" "$(grep -c . "${_P70}/curl.log" || true)" \
    "$(grep -c '^FATAL: fvm' "${_P70}/last.log" || true)" "$(grep -c REFUSED "${_P70}/last.log" || true)"
}
assert_pass "70b: fvm 4.3.1 -> pin 4.3.2: checked in a temp dir, installed, marker last, the projects dir untouched" \
  test "$(_p70_run 4.3.2 4.3.1 4.3.1 false)" = "rc=0 bin=4.3.2 marker=4.3.2 projects=intact tmp=0 curls=1 fatal=0 refused=0"
assert_pass "70c: fvm 4.3.2 -> pin moved back to 4.3.0" \
  test "$(_p70_run 4.3.0 4.3.2 4.3.2 false)" = "rc=0 bin=4.3.0 marker=4.3.0 projects=intact tmp=0 curls=1 fatal=0 refused=0"
assert_pass "70d: first install at 4.3.1 (no binary, no marker)" \
  test "$(_p70_run 4.3.1 '' '' false)" = "rc=0 bin=4.3.1 marker=4.3.1 projects=intact tmp=0 curls=1 fatal=0 refused=0"
assert_pass "70e: marker = pin -> nothing downloaded, nothing changed" \
  test "$(_p70_run 4.3.1 4.3.1 4.3.1 false)" = "rc=0 bin=4.3.1 marker=4.3.1 projects=intact tmp=0 curls=0 fatal=0 refused=0"
assert_pass "70f: marker = pin but RELOAD_FVM=true -> reinstalled" \
  test "$(_p70_run 4.3.1 4.3.0 4.3.1 true)" = "rc=0 bin=4.3.1 marker=4.3.1 projects=intact tmp=0 curls=1 fatal=0 refused=0"
for _p70_bad in '4.4.0|holds no fvm/fvm' '4.5.0|reports 4.5.00' '4.6.0|is not published (curl -f)' '4.7.0|is an HTML page'; do
  assert_pass "70g: pin ${_p70_bad%%|*} (${_p70_bad#*|}) -> named FATAL, old fvm and marker untouched, projects untouched" \
    bash -c '[[ "$1" == "rc=1 bin=4.3.1 marker=4.3.1 projects=intact "*" fatal=1 refused=0" ]]' _ "$(_p70_run "${_p70_bad%%|*}" 4.3.1 4.3.1 false)"
done
# Without -f an unpublished pin downloads a 404 page. The listing check still refuses it,
# but the FATAL then blames the wrong thing, so -f is pinned directly (the §68h shape).
assert_pass "70h: fvm-start.sh has at least 1 executable curl call, and every one carries -f (floor + guard)" \
  bash -c 'calls="$(grep -vE "^[[:space:]]*#" "$1" | grep -oE "curl [^;|]*")"; [[ "$(grep -c . <<<"${calls}")" -ge 1 ]] && ! grep -vE "(^| )-[a-zA-Z]*f[a-zA-Z]*( |$)" <<<"${calls}" | grep -q .' _ "${_P70_FVM}"

# ─── Section 71: deno and bun are checked in a temp dir before they replace the old one ──
# Pin-audit tranche 3 step 19 (ruling 2026-09-26 11:17). deno ran a downloaded
# install.sh in the cwd, the developer's /stack/projects; bun was `curl bun.sh/install |
# bash`. Both removed the old binary and marker BEFORE fetching, so a failed download
# lost a working tool, and neither was checked. The WHOLE script runs here with the real
# prologue, so a FATAL is asserted by its error token. The fixtures mirror the real
# release layouts [measured 2026-09-26: deno v2.9.7 zip holds `deno`, whose --version
# prints three lines, the first `deno 2.9.7 (stable, release, x86_64-unknown-linux-gnu)`;
# bun-v1.4.2's zip holds `bun-linux-x64/bun`, which prints `1.4.2`; the checksums are
# `<hex>  <name>` in the asset's .sha256sum and in SHASUMS256.txt].
printf '\n── Section 71: deno and bun checked in a temp dir before they replace the old one (tranche 3 step 19)\n'
_P71="${TMP_DIR}/p71"
mkdir -p "${_P71}/stub" "${_P71}/fix"
cat >"${_P71}/stub/curl" <<'EOF'
#!/bin/bash
out="" url="" fail=0
while (($#)); do
  case "$1" in
    -o) out="$2"; shift ;;
    --connect-timeout|--max-time) shift ;;
    -*) [[ "$1" == --* ]] || [[ "$1" != *f* ]] || fail=1 ;;
    *) url="$1" ;;
  esac
  shift
done
printf '%s\n' "${url}" >>"${P71_LOG}"
src="${P71_FIX}/${url#https://github.com/}"
if [[ -f "${src}" && -n "${out}" ]]; then cat "${src}" >"${out}"; exit 0; fi
if [[ -f "${src}" ]]; then cat "${src}"; exit 0; fi
((fail)) && exit 22
if [[ -n "${out}" ]]; then printf '<html>404 Not Found</html>\n' >"${out}"; else printf '<html>404 Not Found</html>\n'; fi
EOF
chmod +x "${_P71}/stub/curl"
_p71_deno_bin() { # $1 = path, $2 = the version its first line reports
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\nprintf "deno %s (stable, release, x86_64-unknown-linux-gnu)\\nv8 15.0.245.2-rusty\\ntypescript 6.0.3\\n"\n' "$2" >"$1"
  chmod 0755 "$1"
}
_p71_bun_bin() { # $1 = path, $2 = what it prints
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\necho %s\n' "$2" >"$1"
  chmod 0755 "$1"
}
_p71_sum() { sha256sum "$1" | awk '{ print $1 }'; }
# _p71_deno <tag> <reports|''=no member> <sum: ok|bad>
_p71_deno() {
  local d="${_P71}/fix/denoland/deno/releases/download/$1" b="${_P71}/build/deno/$1" z=deno-x86_64-unknown-linux-gnu.zip
  rm -rf "${b}"; mkdir -p "${d}" "${b}"
  if [[ -n "$2" ]]; then _p71_deno_bin "${b}/deno" "$2"; else printf 'x\n' >"${b}/README"; fi
  (cd "${b}" && zip -q "${d}/${z}" ./*)
  if [[ "$3" == ok ]]; then printf '%s  %s\n' "$(_p71_sum "${d}/${z}")" "${z}" >"${d}/${z}.sha256sum"
  else printf '%064d  %s\n' 0 "${z}" >"${d}/${z}.sha256sum"; fi
}
# _p71_bun <tag> <reports|''=no member> <sum: ok|bad|unlisted>
_p71_bun() {
  local d="${_P71}/fix/oven-sh/bun/releases/download/$1" b="${_P71}/build/bun/$1" z=bun-linux-x64.zip
  rm -rf "${b}"; mkdir -p "${d}" "${b}/bun-linux-x64"
  if [[ -n "$2" ]]; then _p71_bun_bin "${b}/bun-linux-x64/bun" "$2"; else printf 'x\n' >"${b}/bun-linux-x64/README"; fi
  (cd "${b}" && zip -qr "${d}/${z}" bun-linux-x64)
  {
    printf '%064d  bun-darwin-aarch64.zip\n' 1
    case "$3" in
      ok) printf '%s  %s\n' "$(_p71_sum "${d}/${z}")" "${z}" ;;
      bad) printf '%064d  %s\n' 0 "${z}" ;;
    esac
    printf '%064d  bun-linux-x64-baseline.zip\n' 2
  } >"${d}/SHASUMS256.txt"
}
_p71_deno v2.9.7 2.9.7 ok
_p71_deno v2.9.8 2.9.8 ok
_p71_deno v2.9.9 2.9.90 ok   # reports 2.9.90: the version must be followed by a space
_p71_deno v2.10.0 2.10.0 bad # published checksum does not match
_p71_deno v2.12.0 '' ok      # zip without `deno`
_p71_bun bun-v1.4.2 1.4.2 ok
_p71_bun bun-v1.4.3 1.4.3 ok
_p71_bun bun-v1.5.0 1.5.0 unlisted # SHASUMS256.txt does not list bun-linux-x64.zip
_p71_bun bun-v1.6.0 1.6.0 bad
_p71_bun bun-v1.7.0 1.7.00 ok
_p71_bun bun-v1.9.0 '' ok
# An HTML page served as the zip, WITH a matching checksum: only the listing can refuse it.
_P71_H="${_P71}/fix/denoland/deno/releases/download/v2.13.0"
mkdir -p "${_P71_H}"
printf '<html>not a zip</html>\n' >"${_P71_H}/deno-x86_64-unknown-linux-gnu.zip"
printf '%s  deno-x86_64-unknown-linux-gnu.zip\n' "$(_p71_sum "${_P71_H}/deno-x86_64-unknown-linux-gnu.zip")" >"${_P71_H}/deno-x86_64-unknown-linux-gnu.zip.sha256sum"
# v2.11.0 and bun-v1.8.0 are not published at all (curl -f exits 22).
_P71_NT="${DIST_BIN}/nvm-bin/global-stack-nvm-install-tools.sh"
# _p71_run <deno pin> <bun pin> <deno installed|''> <deno marker|''> <bun installed|''> <bun marker|''>
_p71_run() {
  local r="${_P71}/r" rc=0 dv bv bx
  rm -rf "${r}"
  mkdir -p "${r}/tools/versions" "${r}/tools/errors" "${r}/tools/deno/gen" "${r}/tools/bun" "${r}/projects" "${r}/tmp"
  printf 'cache\n' >"${r}/tools/deno/gen/keep"
  printf 'mine\n' >"${r}/projects/deno-insall.sh"
  printf 'mine\n' >"${r}/projects/deno-x86_64-unknown-linux-gnu.zip"
  [[ -z "$3" ]] || _p71_deno_bin "${r}/tools/deno/bin/deno" "$3"
  [[ -z "$4" ]] || printf '%s\n' "$4" >"${r}/tools/versions/nvm.deno"
  [[ -z "$5" ]] || { _p71_bun_bin "${r}/tools/bun/bin/bun" "$5"; ln -s "${r}/tools/bun/bin/bun" "${r}/tools/bun/bin/bunx"; }
  [[ -z "$6" ]] || printf '%s\n' "$6" >"${r}/tools/versions/nvm.bun"
  : >"${_P71}/curl.log"
  (cd "${r}/projects" && env -i HOME="${r}" TMPDIR="${r}/tmp" PATH="${_P71}/stub:${DIST_BIN}/base-bin:/usr/bin:/bin" \
    P71_FIX="${_P71}/fix" P71_LOG="${_P71}/curl.log" \
    GLOBAL_STACK_ERROR_TOKEN=p71-token GLOBAL_STACK_DOCKER_TOOLS_PATH="${r}/tools" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${r}/tools/errors" GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${r}/tools/versions" \
    DENO_INSTALL="${r}/tools/deno" BUN_INSTALL="${r}/tools/bun" \
    GLOBAL_STACK_DENO_VERSION="$1" GLOBAL_STACK_BUN_VERSION="$2" \
    bash "${_P71_NT}") >"${_P71}/last.log" 2>&1 || rc=fail
  dv="$({ "${r}/tools/deno/bin/deno" --version 2>/dev/null || true; } | awk 'NR == 1 { print $2 }')"
  bv="$("${r}/tools/bun/bin/bun" --version 2>/dev/null || true)"
  bx="$("${r}/tools/bun/bin/bunx" --version 2>/dev/null || true)"
  printf 'rc=%s deno=%s dmarker=%s bun=%s bunx=%s bmarker=%s token=%s fatal=%s cache=%s projects=%s tmp=%s curls=%s' "${rc}" \
    "${dv:-none}" "$(cat "${r}/tools/versions/nvm.deno" 2>/dev/null || echo none)" "${bv:-none}" "${bx:-none}" \
    "$(cat "${r}/tools/versions/nvm.bun" 2>/dev/null || echo none)" \
    "$(if [[ -e "${r}/tools/errors/p71-token" ]]; then echo 1; else echo 0; fi)" \
    "$(grep -c '^FATAL: ' "${_P71}/last.log" || true)" \
    "$(cat "${r}/tools/deno/gen/keep" 2>/dev/null || echo gone)" \
    "$(if [[ "$(cat "${r}/projects/deno-insall.sh" "${r}/projects/deno-x86_64-unknown-linux-gnu.zip" 2>/dev/null)" == $'mine\nmine' && "$(ls -A "${r}/projects" | wc -l)" == 2 ]]; then echo intact; else echo touched; fi)" \
    "$(ls -A "${r}/tmp" | wc -l)" "$(grep -c . "${_P71}/curl.log" || true)"
}
_P71_OK="token=0 fatal=0 cache=cache projects=intact tmp=0"
assert_pass "71a: first install of both -> checked, installed, bunx made, markers last, deno's cache and the projects dir untouched" \
  test "$(_p71_run v2.9.7 bun-v1.4.2 '' '' '' '')" = "rc=0 deno=2.9.7 dmarker=v2.9.7 bun=1.4.2 bunx=1.4.2 bmarker=bun-v1.4.2 ${_P71_OK} curls=4"
assert_pass "71b: deno v2.9.7 -> pin v2.9.8 (bun current: not fetched)" \
  test "$(_p71_run v2.9.8 bun-v1.4.2 2.9.7 v2.9.7 1.4.2 bun-v1.4.2)" = "rc=0 deno=2.9.8 dmarker=v2.9.8 bun=1.4.2 bunx=1.4.2 bmarker=bun-v1.4.2 ${_P71_OK} curls=2"
assert_pass "71c: deno v2.9.8 -> pin moved back to v2.9.7" \
  test "$(_p71_run v2.9.7 bun-v1.4.2 2.9.8 v2.9.8 1.4.2 bun-v1.4.2)" = "rc=0 deno=2.9.7 dmarker=v2.9.7 bun=1.4.2 bunx=1.4.2 bmarker=bun-v1.4.2 ${_P71_OK} curls=2"
assert_pass "71d: bun 1.4.2 -> pin bun-v1.4.3, bunx follows" \
  test "$(_p71_run v2.9.7 bun-v1.4.3 2.9.7 v2.9.7 1.4.2 bun-v1.4.2)" = "rc=0 deno=2.9.7 dmarker=v2.9.7 bun=1.4.3 bunx=1.4.3 bmarker=bun-v1.4.3 ${_P71_OK} curls=2"
assert_pass "71e: bun 1.4.3 -> pin moved back to bun-v1.4.2" \
  test "$(_p71_run v2.9.7 bun-v1.4.2 2.9.7 v2.9.7 1.4.3 bun-v1.4.3)" = "rc=0 deno=2.9.7 dmarker=v2.9.7 bun=1.4.2 bunx=1.4.2 bmarker=bun-v1.4.2 ${_P71_OK} curls=2"
assert_pass "71f: both markers = pins -> nothing downloaded, nothing changed" \
  test "$(_p71_run v2.9.7 bun-v1.4.2 2.9.7 v2.9.7 1.4.2 bun-v1.4.2)" = "rc=0 deno=2.9.7 dmarker=v2.9.7 bun=1.4.2 bunx=1.4.2 bmarker=bun-v1.4.2 ${_P71_OK} curls=0"
assert_pass "71g: deno marker = pin but the binary is gone -> installed (the floor)" \
  test "$(_p71_run v2.9.7 bun-v1.4.2 '' v2.9.7 1.4.2 bun-v1.4.2)" = "rc=0 deno=2.9.7 dmarker=v2.9.7 bun=1.4.2 bunx=1.4.2 bmarker=bun-v1.4.2 ${_P71_OK} curls=2"
assert_pass "71g: bun marker = pin but the binary is gone -> installed, bunx made (the floor)" \
  test "$(_p71_run v2.9.7 bun-v1.4.2 2.9.7 v2.9.7 '' bun-v1.4.2)" = "rc=0 deno=2.9.7 dmarker=v2.9.7 bun=1.4.2 bunx=1.4.2 bmarker=bun-v1.4.2 ${_P71_OK} curls=2"
# Each bad pin also names the FATAL it must print: an unlisted asset would otherwise still be
# refused (by the checksum compare), and the message would blame the wrong thing. Only the
# FATAL line is searched: the prologue's failure dump quotes its ancestors' command lines.
for _p71_bad in 'v2.9.9|reports 2.9.90|reports "deno 2.9.90 ' 'v2.10.0|checksum mismatch|does not match its published SHA-256' \
  'v2.11.0|not published|could not be downloaded' 'v2.12.0|zip holds no deno|is not a zip holding deno ' \
  'v2.13.0|an HTML page with a matching checksum|is not a zip holding deno '; do
  IFS='|' read -r _p71_pin _p71_why _p71_msg <<<"${_p71_bad}"
  assert_pass "71h: deno pin ${_p71_pin} (${_p71_why}) -> its named FATAL + error token, old deno and marker untouched, projects untouched" \
    bash -c '[[ "$1" == "rc=fail deno=2.9.7 dmarker=v2.9.7 bun="*" token=1 fatal=1 cache=cache projects=intact "* ]] && grep "^FATAL: " "$3" | grep -qF "$2"' _ \
    "$(_p71_run "${_p71_pin}" bun-v1.4.2 2.9.7 v2.9.7 1.4.2 bun-v1.4.2)" "${_p71_msg}" "${_P71}/last.log"
done
for _p71_bad in 'bun-v1.5.0|SHASUMS256.txt does not list the asset|lists no single checksum for bun-linux-x64.zip' \
  'bun-v1.6.0|checksum mismatch|does not match its published SHA-256' 'bun-v1.7.0|reports 1.7.00|reports "1.7.00"' \
  'bun-v1.8.0|not published|could not be downloaded' 'bun-v1.9.0|zip holds no bun|is not a zip holding bun-linux-x64/bun '; do
  IFS='|' read -r _p71_pin _p71_why _p71_msg <<<"${_p71_bad}"
  assert_pass "71i: bun pin ${_p71_pin} (${_p71_why}) -> its named FATAL + error token, old bun, bunx and marker untouched" \
    bash -c '[[ "$1" == "rc=fail deno=2.9.7 dmarker=v2.9.7 bun=1.4.2 bunx=1.4.2 bmarker=bun-v1.4.2 token=1 fatal=1 cache=cache projects=intact "* ]] && grep "^FATAL: " "$3" | grep -qF "$2"' _ \
    "$(_p71_run v2.9.7 "${_p71_pin}" 2.9.7 v2.9.7 1.4.2 bun-v1.4.2)" "${_p71_msg}" "${_P71}/last.log"
done
_p71_exec="$(grep -vE '^[[:space:]]*#' "${_P71_NT}")"
assert_pass "71j: at least 2 executable curl calls, and every one carries -f (floor + guard)" \
  bash -c 'calls="$(grep -oE "curl [^;|]*" <<<"$1")"; [[ "$(grep -c . <<<"${calls}")" -ge 2 ]] && ! grep -vE "(^| )-[a-zA-Z]*f[a-zA-Z]*( |$)" <<<"${calls}" | grep -q .' _ "${_p71_exec}"
assert_pass "71k: no executable line pipes into bash or sh, and no installer script is fetched" \
  bash -c '! grep -qE "\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh\b|install\.sh|bun\.sh/install|deno\.land/x/install" <<<"$1"' _ "${_p71_exec}"

# ─── Section 72: a RUST bump checks rustup-init BEFORE it wipes the rust homes ──
# Pin-audit tranche 3 step 20 (rulings 2026-09-26 11:17 and 11:43, policy B). rust-start.sh
# wiped RUSTUP_HOME + CARGO_HOME on a RUST change and only then did rust-iou.sh fetch
# rustup-init, so an unpublished or broken pin left no rust at all. The wipe now lives in
# rust-iou.sh, AFTER rustup-init is downloaded and checked; a failed check leaves both
# homes, the cargo-installed tools and every marker untouched. The toolchain itself is
# downloaded by rustup after the wipe (rustup checks each component against the channel
# manifest's sha256 [read: src/dist/download.rs at 1.29.1]); a rustc that does not report
# the pin is FATAL and records no rust marker. Reuses §58's stubs and _p58_run.
printf '\n── Section 72: a RUST bump checks rustup-init before it wipes the rust homes (tranche 3 step 20)\n'
_o="$(_p58_run 1.29.1 1.29.1 1.29.1 1.98.0 1.98.1)"
assert_pass "72a: RUST 1.98.0 -> pin 1.98.1: homes wiped (jj and the old toolchain gone), rustup reinstalled, rustc checked, markers last (got: ${_o})" \
  test "$(_p58_field rc "${_o}")/$(_p58_field rustup "${_o}")/$(_p58_field init "${_o}")/$(_p58_field rust "${_o}")/$(_p58_field rustc "${_o}")/$(_p58_field jj "${_o}")/$(_p58_field token "${_o}")/$(_p58_field tmp "${_o}")" = "0/1.29.1/1.29.1/1.98.1/1.98.1/gone/0/0"
_o="$(_p58_run 1.29.1 1.29.1 1.29.1 1.98.1 1.97.0)"
assert_pass "72b: RUST pin moved back 1.98.1 -> 1.97.0: wiped and reinstalled at 1.97.0 (got: ${_o})" \
  test "$(_p58_field rc "${_o}")/$(_p58_field rust "${_o}")/$(_p58_field rustc "${_o}")/$(_p58_field jj "${_o}")" = "0/1.97.0/1.97.0/gone"
_o="$(_p58_run 1.29.1 1.29.1 1.29.1 1.98.1 1.98.1 true)"
assert_pass "72c: RELOAD_RUST=true with everything current -> wiped and reinstalled (got: ${_o})" \
  test "$(_p58_field rc "${_o}")/$(_p58_field rust "${_o}")/$(_p58_field jj "${_o}")/$(_p58_field rustup "${_o}")" = "0/1.98.1/gone/1.29.1"
for _p72_bad in '1.29.2|reports 1.29.20|reports "rustup-init 1.29.20 ' '1.29.3|checksum mismatch|does not match its published SHA-256' \
  '1.29.4|the .sha256 names another file|lists no single checksum' '1.29.5|not published|could not be downloaded'; do
  IFS='|' read -r _p72_pin _p72_why _ <<<"${_p72_bad}"
  _o="$(_p58_run "${_p72_pin}" 1.29.1 1.29.1 1.98.0 1.98.1)"
  assert_pass "72d: RUST bump with rustup-init ${_p72_pin} (${_p72_why}) -> its named FATAL + token BEFORE any wipe: homes, jj, both markers untouched (got: ${_o})" \
    test "$(_p58_field rc "${_o}")/$(_p58_field rustup "${_o}")/$(_p58_field init "${_o}")/$(_p58_field rust "${_o}")/$(_p58_field jj "${_o}")/$(_p58_field token "${_o}")/$(_p58_field fatal "${_o}")" = "1/1.29.1/1.29.1/1.98.0/kept/1/1"
done
# The FATAL text itself (the run's log is gone with its tmp dir, so assert it through a
# second run that keeps only the FATAL lines).
_p72_msg_of() { # $1 = rustup pin → the run's FATAL line(s)
  local d rc=0
  d="$(mktemp -d)"
  mkdir -p "${d}/bin" "${d}/versions" "${d}/errors" "${d}/cargo/bin" "${d}/rustup" "${d}/tmp"
  cp "${_P58}/tpl/curl" "${d}/bin/curl"
  env -i PATH="${d}/bin:${DIST_BIN}/base-bin:/usr/bin:/bin" HOME="${d}" TMPDIR="${d}/tmp" P58_LOG="${d}/log" \
    P58_TPL="${_P58}/tpl" P58_FIX="${_P58}/fix" CARGO_HOME="${d}/cargo" RUSTUP_HOME="${d}/rustup" \
    GLOBAL_STACK_ERROR_TOKEN=p72 GLOBAL_STACK_DOCKER_TOOLS_PATH="${d}" GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${d}/errors" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${d}/versions" GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES="${d}/successes" \
    GLOBAL_STACK_RUSTUP_INIT_VERSION="$1" GLOBAL_STACK_RUST_VERSION=1.98.1 GLOBAL_STACK_RELOAD_RUST=false \
    bash "${DIST_BIN}/rust-bin/global-stack-rust-iou.sh" >"${d}/out" 2>&1 || rc=$?
  grep '^FATAL: ' "${d}/out" || true
  rm -rf "${d}"
}
for _p72_bad in '1.29.2|reports "rustup-init 1.29.20 ' '1.29.3|does not match its published SHA-256' \
  '1.29.4|lists no single checksum' '1.29.5|could not be downloaded'; do
  assert_pass "72e: rustup-init ${_p72_bad%%|*} -> the FATAL says: ${_p72_bad#*|}" \
    grep -qF "${_p72_bad#*|}" <<<"$(_p72_msg_of "${_p72_bad%%|*}")"
done
_o="$(P58_RUSTC=1.98.10 _p58_run 1.29.1 1.29.1 1.29.1 1.98.0 1.98.1)"
assert_pass "72f: the toolchain install yields rustc 1.98.10 for pin 1.98.1 -> FATAL + token, NO rust marker (got: ${_o})" \
  test "$(_p58_field rc "${_o}")/$(_p58_field rust "${_o}")/$(_p58_field token "${_o}")/$(_p58_field fatal "${_o}")" = "1/none/1/1"
_p72_exec="$(grep -vE '^[[:space:]]*#' "${DIST_BIN}/rust-bin/global-stack-rust-iou.sh")"
assert_pass "72g: rust-iou.sh fetches no installer script (no rustup-init.sh, no rustup.installer.sh), pipes nothing into a shell" \
  bash -c '! grep -qE "rustup-init\.sh([^a-z0-9]|$)|rustup\.installer\.sh|\|[[:space:]]*(ba)?sh\b" <<<"$1"' _ "${_p72_exec}"
assert_pass "72h: at least 2 executable curl calls in rust-iou.sh, and every one carries -f (floor + guard)" \
  bash -c 'calls="$(grep -oE "curl [^;|]*" <<<"$1")"; [[ "$(grep -c . <<<"${calls}")" -ge 2 ]] && ! grep -vE "(^| )-[a-zA-Z]*f[a-zA-Z]*( |$)" <<<"${calls}" | grep -q .' _ "${_p72_exec}"
assert_fail "72i: rust-start.sh no longer wipes RUSTUP_HOME or CARGO_HOME (the wipe moved behind the check)" \
  bash -c 'grep -vE "^[[:space:]]*#" "$1" | grep -qE "rm -rf[^#]*(RUSTUP_HOME|CARGO_HOME)"' _ "${DIST_BIN}/rust-bin/global-stack-rust-start.sh"

# ─── Section 73: phpMyAdmin is built and checked in a temp dir before it replaces the old tree ──
# Pin-audit tranche 3 step 21 (rulings 2026-09-26 11:17 and 11:43). start.sh wiped
# tools/phpmyadmin and its marker BEFORE the iou fetched anything; the iou fetched GitHub
# archives with `curl -LsS` (no -f, so a 404 page was "downloaded"), and composer + yarn
# then built inside the live dir. A failed fetch or build left no phpMyAdmin. Now the iou
# downloads, lists, builds and checks the whole tree in a temp dir; only then is the old
# tree replaced. The marker is written by start.sh after the iou succeeded. The SHIPPED
# start.sh block (gate -> iou -> marker) runs here with the REAL iou on PATH, against stub
# curl/composer/yarn/php. A GitHub archive's top dir is `phpmyadmin-<ref>` with the FULL
# sha for a commit [measured 2026-09-26: phpmyadmin-d711de93c358f03fbf46ee67cfaeb8bab0108331/],
# so the listing is an identity check. A release zip's .sha256 reads `<hex>  <name>`.
printf '\n── Section 73: phpMyAdmin built and checked in a temp dir before it replaces the old tree (tranche 3 step 21)\n'
_P73="${TMP_DIR}/p73"
mkdir -p "${_P73}/stub" "${_P73}/fix" "${_P73}/build"
cat >"${_P73}/stub/curl" <<'EOF'
#!/bin/bash
out="" url="" fail=0
while (($#)); do
  case "$1" in
    -o) out="$2"; shift ;;
    --connect-timeout|--max-time) shift ;;
    -*) [[ "$1" == --* ]] || [[ "$1" != *f* ]] || fail=1 ;;
    *) url="$1" ;;
  esac
  shift
done
printf '%s\n' "${url}" >>"${P73_LOG}"
src="${P73_FIX}/${url#https://}"
if [[ -f "${src}" ]]; then cat "${src}" >"${out}"; exit 0; fi
((fail)) && exit 22
printf '<html>404</html>\n' >"${out}"
EOF
cat >"${_P73}/stub/composer" <<'EOF'
#!/bin/bash
[[ "$1" == install ]] || exit 0
case "${PWD}" in "${GLOBAL_STACK_DOCKER_TOOLS_PATH}"/*) w=tools ;; *) w=tmp ;; esac
printf '%s:%s\n' "${w}" "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/REV" 2>/dev/null || echo none)" >>"${P73_BLOG}"
[[ "${P73_FAIL:-}" == composer ]] && { echo "composer: failed" >&2; exit 1; }
grep -q '"name": "phpmyadmin/phpmyadminx",' composer.json || { echo "composer: name not rewritten" >&2; exit 3; }
mkdir -p vendor && printf '<?php\n' >vendor/autoload.php
EOF
cat >"${_P73}/stub/yarn" <<'EOF'
#!/bin/bash
[[ "$1" == build ]] || exit 0
[[ "${P73_FAIL:-}" == yarn ]] && { echo "yarn: build failed" >&2; exit 2; }
mkdir -p public/js && printf 'runtime\n' >public/js/runtime.js
EOF
cat >"${_P73}/stub/php" <<'EOF'
#!/bin/bash
[[ "$1" == -r && -f "$3" ]]
EOF
cat >"${_P73}/stub/sudo" <<EOF
#!/bin/bash
for a in "\$@"; do
  [[ "\${a}" != /* || "\${a}" == "${_P73}"/* ]] || { echo "REFUSED \${a}" >&2; exit 99; }
done
exec "\$@"
EOF
cat >"${_P73}/stub/global-stack-phpmyadmin-sync-dist.sh" <<'EOF'
#!/bin/bash
printf 'config\n' >"${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/config.inc.php"
EOF
chmod +x "${_P73}/stub/"*
_P73_A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
_P73_B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
_P73_D=dddddddddddddddddddddddddddddddddddddddd
_p73_src() { # $1 = archive path, $2 = top dir, $3 = rev
  local b="${_P73}/build/$2"
  rm -rf "${b}"; mkdir -p "${b}" "$(dirname "$1")"
  printf '<?php\n' >"${b}/index.php"
  printf '{\n    "name": "phpmyadmin/phpmyadmin",\n}\n' >"${b}/composer.json"
  printf '%s\n' "$3" >"${b}/REV"
  tar -C "${_P73}/build" -czf "$1" "$2"
}
_P73_GH="${_P73}/fix/github.com/phpmyadmin/phpmyadmin/archive"
_p73_src "${_P73_GH}/${_P73_A}.tar.gz" "phpmyadmin-${_P73_A}" A
_p73_src "${_P73_GH}/${_P73_B}.tar.gz" "phpmyadmin-${_P73_B}" B
_p73_src "${_P73_GH}/${_P73_D}.tar.gz" "phpmyadmin-${_P73_A}" A   # served for D, but it is commit A
_p73_src "${_P73_GH}/refs/heads/master.tar.gz" phpmyadmin-master M
# Release zips are prebuilt (vendor included); 5.2.4's published checksum does not match.
for _v in 5.2.3 5.2.4; do
  _b="${_P73}/build/rel/phpMyAdmin-${_v}-all-languages"
  mkdir -p "${_b}/vendor" "${_P73}/fix/files.phpmyadmin.net/phpMyAdmin/${_v}"
  printf '<?php\n' >"${_b}/index.php"; printf '<?php\n' >"${_b}/vendor/autoload.php"; printf 'R%s\n' "${_v}" >"${_b}/REV"
  _z="${_P73}/fix/files.phpmyadmin.net/phpMyAdmin/${_v}/phpMyAdmin-${_v}-all-languages.zip"
  (cd "${_P73}/build/rel" && zip -qr "${_z}" "phpMyAdmin-${_v}-all-languages")
  if [[ "${_v}" == 5.2.3 ]]; then printf '%s  %s\n' "$(sha256sum "${_z}" | awk '{ print $1 }')" "$(basename "${_z}")" >"${_z}.sha256"
  else printf '%064d  %s\n' 0 "$(basename "${_z}")" >"${_z}.sha256"; fi
done
_P73_START="${DIST_BIN}/phpmyadmin-bin/global-stack-phpmyadmin-start.sh"
awk '/^_pma_want=/{f=1} f{print} f && /^ *printf .*VERSIONS}\/phpmyadmin"$/{m=1} m && /^fi$/{exit}' "${_P73_START}" >"${_P73}/block.sh"
assert_pass "73a: the extracted start.sh block holds the gate, the iou call and the marker write (anchor non-vacuity)" \
  bash -c 'grep -q "^_pma_gate=" "$1" && grep -q "global-stack-phpmyadmin-iou.sh" "$1" && grep -q "VERSIONS}/phpmyadmin\"$" "$1"' _ "${_P73}/block.sh"
# _p73_run <version> <type> <old rev|''> <marker|''> [RELOAD] → state
_p73_run() {
  local r="${_P73}/r" rc=0
  rm -rf "${r}"
  mkdir -p "${r}/tools/versions" "${r}/tools/errors" "${r}/tmp" "${r}/home"
  if [[ -n "$3" ]]; then
    mkdir -p "${r}/tools/phpmyadmin/vendor"
    printf '%s\n' "$3" >"${r}/tools/phpmyadmin/REV"
    printf 'old\n' >"${r}/tools/phpmyadmin/old-only.txt"
    printf '<?php\n' >"${r}/tools/phpmyadmin/vendor/autoload.php"
  fi
  [[ -z "$4" ]] || printf '%s\n' "$4" >"${r}/tools/versions/phpmyadmin"
  : >"${_P73}/curl.log"; : >"${_P73}/build.log"
  env -i HOME="${r}/home" TMPDIR="${r}/tmp" PATH="${_P73}/stub:${DIST_BIN}/phpmyadmin-bin:${DIST_BIN}/base-bin:/usr/bin:/bin" \
    P73_FIX="${_P73}/fix" P73_LOG="${_P73}/curl.log" P73_BLOG="${_P73}/build.log" P73_FAIL="${P73_FAIL:-}" \
    GLOBAL_STACK_ERROR_TOKEN=p73-token GLOBAL_STACK_DOCKER_TOOLS_PATH="${r}/tools" \
    GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${r}/tools/errors" GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS="${r}/tools/versions" \
    GLOBAL_STACK_DOCKER_USER_ID="$(id -un)" GLOBAL_STACK_DOCKER_GROUP_ID="$(id -gn)" \
    GLOBAL_STACK_PHPMYADMIN_VERSION="$1" GLOBAL_STACK_PHPMYADMIN_TYPE_VERSION="$2" GLOBAL_STACK_RELOAD_PHPMYADMIN="${5:-false}" \
    bash -c 'set -eE -o pipefail; source "$1"; source "$2"' _ \
    "${DIST_BIN}/base-bin/global-stack-base-version-gate.sh" "${_P73}/block.sh" >"${_P73}/last.log" 2>&1 || rc=fail
  printf 'rc=%s build=%s rev=%s marker=%s oldonly=%s vendor=%s token=%s fatal=%s tmp=%s refused=%s curls=%s' "${rc}" \
    "$(if [[ -s "${_P73}/build.log" ]]; then paste -sd, "${_P73}/build.log"; else echo none; fi)" \
    "$(cat "${r}/tools/phpmyadmin/REV" 2>/dev/null || echo none)" \
    "$(cat "${r}/tools/versions/phpmyadmin" 2>/dev/null || echo none)" \
    "$(if [[ -e "${r}/tools/phpmyadmin/old-only.txt" ]]; then echo kept; else echo gone; fi)" \
    "$(if [[ -f "${r}/tools/phpmyadmin/vendor/autoload.php" ]]; then echo yes; else echo no; fi)" \
    "$(if [[ -e "${r}/tools/errors/p73-token" ]]; then echo 1; else echo 0; fi)" \
    "$(grep -c '^FATAL: ' "${_P73}/last.log" || true)" "$(ls -A "${r}/tmp" | wc -l)" \
    "$(grep -c REFUSED "${_P73}/last.log" || true)" "$(grep -c . "${_P73}/curl.log" || true)"
}
_P73_OK="oldonly=gone vendor=yes token=0 fatal=0 tmp=0 refused=0"
assert_pass "73b: commit A -> pin commit B: built in a temp dir WHILE the old tree stayed live, then replaced whole, marker last" \
  test "$(_p73_run "${_P73_B}" commit A "${_P73_A};type=commit")" = "rc=0 build=tmp:A rev=B marker=${_P73_B};type=commit ${_P73_OK} curls=1"
assert_pass "73c: commit B -> pin moved back to commit A" \
  test "$(_p73_run "${_P73_A}" commit B "${_P73_B};type=commit")" = "rc=0 build=tmp:B rev=A marker=${_P73_A};type=commit ${_P73_OK} curls=1"
assert_pass "73d: first install (no tree, no marker)" \
  test "$(_p73_run "${_P73_A}" commit '' '')" = "rc=0 build=tmp:none rev=A marker=${_P73_A};type=commit ${_P73_OK} curls=1"
assert_pass "73e: marker = pin -> nothing downloaded or built, the tree untouched" \
  test "$(_p73_run "${_P73_A}" commit A "${_P73_A};type=commit")" = "rc=0 build=none rev=A marker=${_P73_A};type=commit oldonly=kept vendor=yes token=0 fatal=0 tmp=0 refused=0 curls=0"
assert_pass "73f: marker = pin but RELOAD_PHPMYADMIN=true -> rebuilt" \
  test "$(_p73_run "${_P73_A}" commit A "${_P73_A};type=commit" true)" = "rc=0 build=tmp:A rev=A marker=${_P73_A};type=commit ${_P73_OK} curls=1"
assert_pass "73g: type=branch master still builds (the old pin shape)" \
  test "$(_p73_run master branch A "${_P73_A};type=commit")" = "rc=0 build=tmp:A rev=M marker=master;type=branch ${_P73_OK} curls=1"
assert_pass "73h: type=release 5.2.3: zip checked against its published sha256, no build step" \
  test "$(_p73_run 5.2.3 release A "${_P73_A};type=commit")" = "rc=0 build=none rev=R5.2.3 marker=5.2.3;type=release ${_P73_OK} curls=2"
for _p73_bad in "cccccccccccccccccccccccccccccccccccccccc|commit|-|not published|could not be downloaded" \
  "${_P73_D}|commit|-|the archive is another commit|does not hold phpmyadmin-${_P73_D}/index.php" \
  "${_P73_B}|commit|composer|composer install fails|the build failed" \
  "${_P73_B}|commit|yarn|yarn build fails|the build failed" \
  "5.2.4|release|-|checksum mismatch|does not match its published SHA-256"; do
  IFS='|' read -r _p73_v _p73_t _p73_f _p73_why _p73_msg <<<"${_p73_bad}"
  [[ "${_p73_f}" == - ]] && _p73_f=""
  assert_pass "73i: ${_p73_t} ${_p73_v:0:12} (${_p73_why}) -> its named FATAL + token, old tree and marker untouched, nothing left in tmp" \
    bash -c '[[ "$1" == "rc=fail build="*" rev=A marker=$4;type=commit oldonly=kept vendor=yes token=1 fatal=1 "*" refused=0 "* ]] && grep "^FATAL: " "$3" | grep -qF "$2"' _ \
    "$(P73_FAIL="${_p73_f}" _p73_run "${_p73_v}" "${_p73_t}" A "${_P73_A};type=commit")" "${_p73_msg}" "${_P73}/last.log" "${_P73_A}"
done
_p73_exec="$(grep -hvE '^[[:space:]]*#' "${DIST_BIN}/phpmyadmin-bin/global-stack-phpmyadmin-iou.sh")"
assert_pass "73j: at least 2 executable curl calls in the iou, and every one carries -f (floor + guard)" \
  bash -c 'calls="$(grep -oE "curl [^;|]*" <<<"$1")"; [[ "$(grep -c . <<<"${calls}")" -ge 2 ]] && ! grep -vE "(^| )-[a-zA-Z]*f[a-zA-Z]*( |$)" <<<"${calls}" | grep -q .' _ "${_p73_exec}"
assert_fail "73k: start.sh no longer removes tools/phpmyadmin itself (the swap moved behind the check)" \
  bash -c 'grep -vE "^[[:space:]]*#" "$1" | grep -qE "rm -rf[^#]*TOOLS_PATH}/phpmyadmin\""' _ "${_P73_START}"

# ─── Section 74: caddy is built locally by a checked xcaddy, then checked, then replaces the old binary ──
# Pin-audit tranche 3 step 22 (rulings 2026-09-26 11:17 and 11:43). start.sh wiped
# tools/caddy on a CADDY bump, then the iou ran `go build` and four `caddy add-package`,
# which DOWNLOAD a binary built by caddyserver.com [`caddy help add-package`]; nothing was
# checked, and the four plugin pins were not gate inputs, so a plugin bump did nothing (A4).
# The SHIPPED start.sh block (composite gate -> iou -> marker) runs here with the REAL iou
# on PATH. The stubs model what was MEASURED: xcaddy 0.4.7's checksums.txt holds SHA-512
# sums; `xcaddy version` -> `v0.4.7 h1:...`; `caddy version` -> `v2.11.4 h1:...`;
# `caddy list-modules --packages --versions` -> `<module> <version> <package>`, a commit pin
# listed as a pseudo-version ending in its first 12 hex digits.
printf '\n── Section 74: caddy built by a checked xcaddy, checked, then replaces the old binary (tranche 3 step 22)\n'
_P74="${TMP_DIR}/p74"
mkdir -p "${_P74}/stub" "${_P74}/fix" "${_P74}/build"
cat >"${_P74}/stub/curl" <<'EOF'
#!/bin/bash
out="" url="" fail=0
while (($#)); do
  case "$1" in
    -o) out="$2"; shift ;;
    --connect-timeout|--max-time) shift ;;
    -*) [[ "$1" == --* ]] || [[ "$1" != *f* ]] || fail=1 ;;
    *) url="$1" ;;
  esac
  shift
done
printf '%s\n' "${url}" >>"${P74_LOG}"
src="${P74_FIX}/${url#https://}"
if [[ -f "${src}" ]]; then cat "${src}" >"${out}"; exit 0; fi
((fail)) && exit 22
printf '<html>404</html>\n' >"${out}"
EOF
chmod +x "${_P74}/stub/curl"
# The fixture xcaddy: `version`, and `build <v> --output <f> --with pkg@pin...` writing a
# stub caddy that reports <v> and lists each plugin the way the real caddy does.
# P74_BUILD_FAIL / P74_REPORT (another caddy version) / P74_DROP (a package left out) /
# P74_SKEW (a package listed at another version) inject the failures.
_p74_xcaddy() { # $1 = version it reports
  cat <<EOF
#!/bin/bash
if [[ "\$1" == version ]]; then echo "$1 h1:stub="; exit 0; fi
[[ "\$1" == build ]] || exit 2
echo "build:GOTOOLCHAIN=\${GOTOOLCHAIN:-unset} \$*" >>"\${P74_LOG}"
[[ -n "\${P74_BUILD_FAIL:-}" ]] && { echo "go: build failed" >&2; exit 1; }
v="\$2"; shift 2; out=""; lines=""
while ((\$#)); do
  case "\$1" in
    --output) out="\$2"; shift ;;
    --with) pkg="\${2%@*}"; pin="\${2#*@}"; shift
      [[ "\${pkg}" == "\${P74_DROP:-}" ]] && { shift; continue; }
      [[ "\${pkg}" == "\${P74_SKEW:-}" ]] && pin="v9.9.9"
      [[ "\${pin}" =~ ^[0-9a-f]{40}\$ ]] && pin="v0.0.0-20260101000000-\${pin:0:12}"
      lines+="mod.\${pkg##*/} \${pin} \${pkg}"\$'\n' ;;
  esac
  shift
done
{ printf '#!/bin/bash\n'
  printf 'if [[ "\$1" == version ]]; then echo "%s h1:x="; exit 0; fi\n' "\${P74_REPORT:-\${v}}"
  printf 'if [[ "\$1" == list-modules ]]; then cat <<"MODS"\nhttp.handlers.file_server\n%sMODS\nfi\n' "\${lines}"
} >"\${out}"
chmod +x "\${out}"
EOF
}
# _p74_rel <xcaddy version, no v> <what it reports> <sums: ok|bad|unlisted>
_p74_rel() {
  local d="${_P74}/fix/github.com/caddyserver/xcaddy/releases/download/v$1" b="${_P74}/build/$1" a="xcaddy_$1_linux_amd64.tar.gz"
  rm -rf "${b}"
  mkdir -p "${d}" "${b}"
  _p74_xcaddy "$2" >"${b}/xcaddy"
  chmod +x "${b}/xcaddy"
  printf 'l\n' >"${b}/LICENSE"
  tar -C "${b}" -czf "${d}/${a}" LICENSE xcaddy
  case "$3" in
    ok) printf '%s  %s\n' "$(sha512sum "${d}/${a}" | awk '{ print $1 }')" "${a}" >"${d}/xcaddy_$1_checksums.txt" ;;
    bad) printf '%0128d  %s\n' 0 "${a}" >"${d}/xcaddy_$1_checksums.txt" ;;
    unlisted) printf '%s  xcaddy_$1_linux_arm64.tar.gz\n' "$(sha512sum "${d}/${a}" | awk '{ print $1 }')" >"${d}/xcaddy_$1_checksums.txt" ;;
  esac
}
_p74_rel 0.4.7 v0.4.7 ok
_p74_rel 0.4.8 v0.4.8 bad
_p74_rel 0.4.9 v0.4.9 unlisted
_p74_rel 0.4.6 v0.4.60 ok # reports another version
# v0.5.0 is not published (curl -f exits 22).
_P74_TE=ba4124974830222da7f12a091cf11ddf4d49363f
_P74_START="${DIST_BIN}/caddy-bin/global-stack-caddy-start.sh"
awk '/^_caddy_want=/{f=1} f{print} f && /^ *printf .*CADDY_VERSIONS_PATH}"$/{m=1} m && /^fi$/{exit}' "${_P74_START}" >"${_P74}/block.sh"
assert_pass "74a: the extracted start.sh block holds the composite gate, the iou call and the marker write (anchor non-vacuity)" \
  bash -c 'grep -q "^_caddy_gate=" "$1" && grep -q "global-stack-caddy-iou.sh" "$1" && grep -q "CADDY_VERSIONS_PATH}\"$" "$1"' _ "${_P74}/block.sh"
# _p74_run <caddy pin> <brotli pin> <old caddy|''> <marker|''> [RELOAD] [xcaddy pin] → state
_p74_run() {
  local r="${_P74}/r" rc=0 bin _p74_xc="${6:-v0.4.7}"
  [[ "${_p74_xc}" != EMPTY ]] || _p74_xc="" # compose hands an un-scanned pin over EMPTY
  rm -rf "${r}"
  mkdir -p "${r}/tools/versions" "${r}/tools/errors" "${r}/tools/caddy/logs" "${r}/tools/caddy/vhosts" "${r}/tools/caddy/bin" "${r}/tmp"
  printf 'log\n' >"${r}/tools/caddy/logs/access.log"
  if [[ -n "${P74_STALE_BUILD:-}" ]]; then mkdir -p "${r}/tools/caddy/caddy-build" && printf 'module x\n' >"${r}/tools/caddy/caddy-build/go.mod"; fi
  if [[ -n "$3" ]]; then
    printf '#!/bin/bash\necho "%s h1:old="\n' "$3" >"${r}/tools/caddy/bin/caddy"
    chmod +x "${r}/tools/caddy/bin/caddy"
  fi
  [[ -z "$4" ]] || printf '%s\n' "$4" >"${r}/tools/versions/caddy"
  : >"${_P74}/log"
  env -i HOME="${r}" TMPDIR="${r}/tmp" PATH="${_P74}/stub:${DIST_BIN}/caddy-bin:${DIST_BIN}/base-bin:/usr/bin:/bin" \
    P74_FIX="${_P74}/fix" P74_LOG="${_P74}/log" P74_BUILD_FAIL="${P74_BUILD_FAIL:-}" P74_REPORT="${P74_REPORT:-}" \
    P74_DROP="${P74_DROP:-}" P74_SKEW="${P74_SKEW:-}" \
    GLOBAL_STACK_ERROR_TOKEN=caddy GLOBAL_STACK_DOCKER_TOOLS_PATH="${r}/tools" GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS="${r}/tools/errors" \
    CADDY_PATH="${r}/tools/caddy" CADDY_VERSIONS_PATH="${r}/tools/versions/caddy" GLOBAL_STACK_RELOAD_CADDY="${5:-false}" \
    GLOBAL_STACK_CADDY_VERSION="$1" GLOBAL_STACK_CADDY_BROTLI_VERSION="$2" GLOBAL_STACK_XCADDY_VERSION="${_p74_xc}" \
    GLOBAL_STACK_CADDY_TRANSFORM_ENCODER_VERSION="${_P74_TE}" GLOBAL_STACK_CADDY_SECURITY_VERSION=v1.1.64 \
    GLOBAL_STACK_CADDY_CACHE_HANDLER_VERSION=v0.17.0 \
    bash -c 'set -eE -o pipefail; source "$1"; source "$2"' _ \
    "${DIST_BIN}/base-bin/global-stack-base-version-gate.sh" "${_P74}/block.sh" >"${_P74}/last.log" 2>&1 || rc=fail
  bin="$({ "${r}/tools/caddy/bin/caddy" version 2>/dev/null || true; } | awk '{ print $1 }')"
  printf 'rc=%s caddy=%s marker=%s logs=%s token=%s fatal=%s tmp=%s builds=%s' "${rc}" "${bin:-none}" \
    "$(cat "${r}/tools/versions/caddy" 2>/dev/null || echo none)" \
    "$(if [[ -e "${r}/tools/caddy/logs/access.log" ]]; then echo kept; else echo gone; fi)" \
    "$(if [[ -e "${r}/tools/errors/caddy" ]]; then echo 1; else echo 0; fi)" \
    "$(grep -c '^FATAL: ' "${_P74}/last.log" || true)" "$(ls -A "${r}/tmp" | wc -l)" "$(grep -c '^build:' "${_P74}/log" || true)"
}
_p74_want() { printf '%s;transform-encoder=%s;brotli=%s;security=v1.1.64;cache-handler=v0.17.0' "$1" "${_P74_TE}" "$2"; }
_P74_OLD="$(_p74_want v2.11.3 v1.6.0)"
assert_pass "74b: caddy v2.11.3 -> pin v2.11.4: built by the checked xcaddy, checked, installed, composite marker, logs kept" \
  test "$(_p74_run v2.11.4 v1.6.0 v2.11.3 "${_P74_OLD}")" = "rc=0 caddy=v2.11.4 marker=$(_p74_want v2.11.4 v1.6.0) logs=kept token=0 fatal=0 tmp=0 builds=1"
assert_pass "74c: caddy pin moved back v2.11.4 -> v2.11.3" \
  test "$(_p74_run v2.11.3 v1.6.0 v2.11.4 "$(_p74_want v2.11.4 v1.6.0)")" = "rc=0 caddy=v2.11.3 marker=${_P74_OLD} logs=kept token=0 fatal=0 tmp=0 builds=1"
assert_pass "74d: a PLUGIN bump alone (brotli v1.6.0 -> v1.6.1) rebuilds caddy (it did nothing before)" \
  test "$(_p74_run v2.11.3 v1.6.1 v2.11.3 "${_P74_OLD}")" = "rc=0 caddy=v2.11.3 marker=$(_p74_want v2.11.3 v1.6.1) logs=kept token=0 fatal=0 tmp=0 builds=1"
assert_pass "74e: marker = every pin -> nothing downloaded or built" \
  test "$(_p74_run v2.11.3 v1.6.0 v2.11.3 "${_P74_OLD}")" = "rc=0 caddy=v2.11.3 marker=${_P74_OLD} logs=kept token=0 fatal=0 tmp=0 builds=0"
assert_pass "74f: marker = every pin but RELOAD_CADDY=true -> rebuilt" \
  test "$(_p74_run v2.11.3 v1.6.0 v2.11.3 "${_P74_OLD}" true)" = "rc=0 caddy=v2.11.3 marker=${_P74_OLD} logs=kept token=0 fatal=0 tmp=0 builds=1"
assert_pass "74g: first install (no binary, no marker)" \
  test "$(_p74_run v2.11.4 v1.6.0 '' '')" = "rc=0 caddy=v2.11.4 marker=$(_p74_want v2.11.4 v1.6.0) logs=kept token=0 fatal=0 tmp=0 builds=1"
for _p74_bad in 'v0.4.8|-|xcaddy checksum mismatch|does not match its published SHA-512' \
  'EMPTY|-|the xcaddy pin is empty (.env.local not yet env-scanned)|GLOBAL_STACK_XCADDY_VERSION is empty' \
  'v0.4.9|-|checksums.txt does not list the asset|lists no single checksum' \
  'v0.5.0|-|xcaddy not published|could not be downloaded' \
  'v0.4.6|-|xcaddy reports v0.4.60|reports "v0.4.60 h1' \
  'v0.4.7|P74_BUILD_FAIL=1|xcaddy build fails|xcaddy build failed' \
  'v0.4.7|P74_REPORT=v2.11.40|the built caddy reports v2.11.40|the built binary reports "v2.11.40' \
  'v0.4.7|P74_DROP=github.com/ueffel/caddy-brotli|a plugin missing from the binary|lists github.com/ueffel/caddy-brotli at ""' \
  'v0.4.7|P74_SKEW=github.com/greenpau/caddy-security|a plugin at another version|lists github.com/greenpau/caddy-security at "v9.9.9"' \
  'v0.4.7|P74_SKEW=github.com/caddyserver/transform-encoder|the commit-pinned plugin at another version|lists github.com/caddyserver/transform-encoder at "v9.9.9"'; do
  IFS='|' read -r _p74_x _p74_env _p74_why _p74_msg <<<"${_p74_bad}"
  [[ "${_p74_env}" == - ]] && _p74_env="P74_NONE="
  assert_pass "74h: ${_p74_why} -> its named FATAL + token, the old binary and marker untouched, logs kept, no temp dir left" \
    bash -c '[[ "$1" == "rc=fail caddy=v2.11.3 marker=$4 logs=kept token=1 fatal=1 tmp=0 "* ]] && grep "^FATAL: " "$3" | grep -qF "$2"' _ \
    "$(
      export "${_p74_env?}"
      _p74_run v2.11.4 v1.6.0 v2.11.3 "${_P74_OLD}" false "${_p74_x}"
    )" \
    "${_p74_msg}" "${_P74}/last.log" "${_P74_OLD}"
done
# Both ways, discovered (the §47 shape): every GLOBAL_STACK_CADDY_*_VERSION the iou builds
# with is in the start.sh composite, and every one in the composite is built with.
# `|| true`: an anchor matching nothing must red the floor below, not abort the run under
# set -e with no tally.
_p74_iou_vars="$(grep -vE '^[[:space:]]*#' "${DIST_BIN}/caddy-bin/global-stack-caddy-iou.sh" | grep -oE 'GLOBAL_STACK_CADDY_[A-Z_]+_VERSION' | sort -u || true)"
_p74_want_vars="$(grep '^_caddy_want=' "${_P74_START}" | grep -oE 'GLOBAL_STACK_CADDY_[A-Z_]*VERSION' | sort -u || true)"
assert_pass "74i: the composite holds the caddy pin plus at least 4 plugin pins (floor), and the iou builds with the same plugin set" \
  bash -c '[[ "$(grep -c . <<<"$2")" -ge 5 ]] && [[ "$(grep -vx GLOBAL_STACK_CADDY_VERSION <<<"$2")" == "$(grep -vx GLOBAL_STACK_CADDY_VERSION <<<"$1")" ]]' _ "${_p74_iou_vars}" "${_p74_want_vars}"
_p74_exec="$(grep -vE '^[[:space:]]*#' "${DIST_BIN}/caddy-bin/global-stack-caddy-iou.sh")"
assert_pass "74j: at least 2 executable curl calls in the iou, every one with -f, and no add-package left" \
  bash -c 'calls="$(grep -oE "curl [^;|]*" <<<"$1")"; [[ "$(grep -c . <<<"${calls}")" -ge 2 ]] && ! grep -vE "(^| )-[a-zA-Z]*f[a-zA-Z]*( |$)" <<<"${calls}" | grep -q . && ! grep -q "add-package" <<<"$1"' _ "${_p74_exec}"
# 74k reads the WHOLE start.sh (comment lines out, backslash continuations joined): the
# old wipe was a multi-line `rm -rf \` naming "${CADDY_PATH}" on its own line.
assert_fail "74k: start.sh wipes \${CADDY_PATH} nowhere (the iou replaces the binary only after its checks)" \
  bash -c 'grep -vE "^[[:space:]]*#" "$1" | sed -e ":a" -e "/\\\\$/{N;s/\\\\\n//;ba}" | grep -qE "rm -rf.*\"\\\$\{CADDY_PATH\}\"( |$)"' _ "${_P74_START}"
# GOTOOLCHAIN defaults to `auto` [measured: tools/go 1.27.1], under which a module whose
# go.mod needs a newer go makes go DOWNLOAD an unpinned toolchain. The build must run with
# `local`, so that case fails the build (a named FATAL) instead of fetching.
_p74_run v2.11.4 v1.6.0 v2.11.3 "${_P74_OLD}" >/dev/null
assert_pass "74l: xcaddy builds with GOTOOLCHAIN=local (a newer-go module FATALs, never downloads a toolchain)" \
  bash -c 'grep "^build:" "$1" | grep -q "^build:GOTOOLCHAIN=local "' _ "${_P74}/log"
# The old build left a git clone of caddy at tools/caddy/caddy-build; a build removes it.
P74_STALE_BUILD=1 _p74_run v2.11.4 v1.6.0 v2.11.3 "${_P74_OLD}" >/dev/null
assert_fail "74m: a build removes the old build's caddy-build clone" \
  test -e "${_P74}/r/tools/caddy/caddy-build/go.mod"
# ...and only a build does: with the marker current nothing runs, so the fixture stays
# (this is also 74m's non-vacuity — a fixture that was never created would pass 74m).
P74_STALE_BUILD=1 _p74_run v2.11.3 v1.6.0 v2.11.3 "${_P74_OLD}" >/dev/null
assert_pass "74m2: ...and nothing touches it when no build runs (74m's fixture is real)" \
  test -e "${_P74}/r/tools/caddy/caddy-build/go.mod"
# The builder is pinned like everything else (the §39 shape): defined, annotated, plumbed.
assert_pass "74n: .env pins GLOBAL_STACK_XCADDY_VERSION under an @todo env-update annotation" \
  bash -c 'grep -B1 "^GLOBAL_STACK_XCADDY_VERSION=v[0-9]" "$1" | grep -q "^# @todo env-update github:caddyserver/xcaddy "' _ "${REPO_ROOT}/.env"
assert_pass "74n: ...and 01caddy plumbs it into the container" \
  grep -q 'GLOBAL_STACK_XCADDY_VERSION=${GLOBAL_STACK_XCADDY_VERSION}' "${REPO_ROOT}/docker/images/01caddy/docker-compose.yaml"

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
