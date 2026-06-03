#!/usr/bin/env bash
set -euo pipefail

SDKMAN_DIR="${SDKMAN_DIR:-/stack/tools/sdkman}"
PASS=0
FAIL=0

run_test() {
  local name="$1"
  local script="$2"
  local expect_exit="$3"
  local actual_exit=0
  bash -c "$script" 2>/dev/null || actual_exit=$?
  if [[ "$actual_exit" -eq "$expect_exit" ]]; then
    echo "PASS: $name (exit=$actual_exit)"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name (expected exit=$expect_exit, got exit=$actual_exit)"
    FAIL=$((FAIL + 1))
  fi
}

# Simulate the exact container environment:
#   - set -eE -o pipefail (as the startup scripts use)
#   - stackCatch-style ERR trap (exit 99 as sentinel)
#   - ALL sdkman paths stripped from PATH (first-run state in container before sdk use)
# Stripping ALL sdkman paths (not just java/candidates) is required because
# sdkman-init.sh adds sdkman/bin to PATH; __sdkman_path_contains runs grep in a $()
# subshell which exits 1 when java is not yet in PATH — triggering the inherited ERR trap.
BASE="
  set -eE -o pipefail
  SDKMAN_DIR=${SDKMAN_DIR}
  source \"\${SDKMAN_DIR}/bin/sdkman-init.sh\" 2>/dev/null
  trap \"exit 99\" ERR
  export PATH=\$(echo \"\$PATH\" | tr \":\" \"\n\" | grep -v \"sdkman\" | tr \"\n\" \":\" | sed \"s/:\$//\")
"

# Test A: set +e (wrong letter — the prior broken fix) — MUST trigger inherited ERR trap
# With -E still active: grep exits 1 inside __sdkman_path_contains $() subshell →
# inherited ERR trap fires "exit 99" → script exits 99.
run_test "set +e is broken (regression proof — prior fix wrong letter)" \
  "${BASE} set +e; sdk use java 26.0.1-zulu >/dev/null 2>&1; set -e; echo REACHED_END" \
  99

# Test B: set +E (correct fix) — MUST reach REACHED_END (exit 0)
# With -E suppressed: grep exits 1 in subshell → ERR trap NOT inherited → sdk use succeeds.
run_test "set +E suppresses spurious subshell ERR trap inheritance" \
  "${BASE} set +E; sdk use java 26.0.1-zulu >/dev/null 2>&1; set -E; echo REACHED_END" \
  0

# Test C: set +E with genuine sdk failure — ERR trap MUST still fire (exit 99)
# A bogus version cannot be used; sdk use exits non-zero in the parent shell scope →
# ERR trap fires in parent (parent's -E is off, but trap is still live for parent scope).
run_test "set +E preserves ERR trap for genuine sdk failures in parent scope" \
  "${BASE} set +E; sdk use java BOGUS_VERSION_THAT_DOES_NOT_EXIST >/dev/null 2>&1 || exit 99; set -E; echo REACHED_END" \
  99

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
