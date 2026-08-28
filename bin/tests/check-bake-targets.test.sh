#!/usr/bin/env bash
# Tests for bin/check-bake-targets.sh — the gate that stops `make build`
# declaring success having built nothing.
#
# The failure this guards is swallowed twice over. `generate-buildx` runs
# `docker buildx bake --print` through a sub-make carrying --ignore-errors
# --keep-going, so the sub-make exits 0 even when bake fails; the `>` redirect
# has already truncated the bake file, so it is left 0 bytes and
# `generate-buildx` "succeeds". Then `build` runs
# `jq -r '.group.default.targets[]'` on that empty file — jq exits 0 with no
# output — the while loop body never runs, the failure file stays empty, and
# the recipe prints "=== Build complete ===" and exits 0. The stack then comes
# up on stale or absent images with no error anywhere in the transcript.
#
# So the contract under test is: anything that would make the loop iterate zero
# times must be a LOUD, non-zero failure.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="${SCRIPT_DIR}/../check-bake-targets.sh"

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

# Run the gate against a bake file holding $2; assert exit code $1.
# Sets OUT so the caller can assert on the message.
expect() {
  local want="$1" content="$2" label="$3" f
  f="$(mktemp)"
  printf '%s' "${content}" >"${f}"
  OUT="$(bash "${SUT}" "${f}" 2>&1)"
  local rc=$?
  rm -f "${f}"
  if [[ "${rc}" -eq "${want}" ]]; then
    ok "${label} → exit ${rc}"
  else
    ko "${label} → exit ${rc} (want ${want}); output: ${OUT}"
  fi
}

printf '\n%b── check-bake-targets.sh ──%b\n' "${C_BOLD}" "${C_RESET}"

# ── The exact shape that produced the silent success ────────────────────────
expect 1 '' "empty file (what a failed 'bake --print' leaves behind)"
grep -qi 'no build targets\|empty\|failed' <<<"${OUT}" \
  && ok "empty file: message says what went wrong" \
  || ko "empty file: unhelpful message: ${OUT}"

# ── Neighbouring shapes that are equally zero-iteration ─────────────────────
expect 1 '{}' "valid JSON with no .group"
expect 1 '{"group":{"default":{"targets":[]}}}' "explicit empty target list"
expect 1 '{"group":{"other":{"targets":["a"]}}}' "no default group"
expect 1 'not json at all' "unparseable content"

# ── The good case must stay silent and pass ────────────────────────────────
expect 0 '{"group":{"default":{"targets":["00base","01caddy"]}}}' "two real targets"
[[ -z "${OUT}" ]] && ok "healthy bake file: silent" || ko "healthy bake file printed: ${OUT}"

# ── A missing file is not the same as a healthy one ────────────────────────
OUT="$(bash "${SUT}" /nonexistent/docker-bake.local.json 2>&1)"
rc=$?
[[ "${rc}" -eq 1 ]] && ok "missing file → exit 1" || ko "missing file → exit ${rc} (want 1)"

# ── cwd-independence: the default must resolve from the script, not $PWD ───
# A relative default is the defect fixed in check-image-versions.sh (661cef3):
# from another cwd the check looks at the wrong path, finds nothing, and the
# result is indistinguishable from a clean run.
#
# Asserted on the PATH the script resolves, not on the verdict: the repo's real
# bake file is a gitignored build artifact whose health varies, so asserting
# "exit 0" here would make this test's result depend on whether someone has run
# `make generate-buildx` lately.
REPO_ROOT_EXPECTED="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUT_ROOT="$(cd / && bash "${SUT}" 2>&1 || true)"
OUT_HOME="$(cd "${HOME}" && bash "${SUT}" 2>&1 || true)"
[[ "${OUT_ROOT}" == "${OUT_HOME}" ]] \
  && ok "no argument: identical result from / and \$HOME (cwd-independent)" \
  || ko "no argument: result differs by cwd — the default is \$PWD-relative"

# An explicitly good fixture must pass from any cwd too.
GOOD="$(mktemp)"
printf '{"group":{"default":{"targets":["00base"]}}}' >"${GOOD}"
(cd / && bash "${SUT}" "${GOOD}" >/dev/null 2>&1) \
  && ok "healthy fixture passes from / as well" \
  || ko "healthy fixture failed when run from /"
rm -f "${GOOD}"

# When it does fail with no argument, it must name the repo's path — never a
# path relative to wherever it happened to be invoked.
if [[ -n "${OUT_ROOT}" ]]; then
  grep -qF "${REPO_ROOT_EXPECTED}/docker-bake.local.json" <<<"${OUT_ROOT}" \
    && ok "no argument: names the repo-root bake path, not a \$PWD-relative one" \
    || ko "no argument: resolved an unexpected path: ${OUT_ROOT}"
else
  ok "no argument: repo bake file is currently healthy (silent)"
fi

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
