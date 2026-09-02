#!/usr/bin/env bash
# Tests for bin/open-all-envs.sh — the "open every env-update link" helper.
#
# Two defects are pinned here. Both are invisible from a successful run:
#
#  F11 — `.env` was read as a bare RELATIVE path, so from any directory but
#        /stack the script enumerated nothing, opened ZERO links and exited 0.
#        A run that did nothing looked exactly like a run that worked.
#
#  F12 — the sdkman block rewrote the HOST's ~/.sdkman/etc/config in place:
#        clobbered by the first `>`, deleted by `rm -rf`, and left as the single
#        line `sdkman_healthcheck_enable=false` even when the run SUCCEEDED. A
#        helper that only means to list versions destroyed the developer's file.
#
# Every case runs the script under `env -i` inside a copy-to-tempdir sandbox.
# Without `env -i` the host's exported GLOBAL_STACK_*_VERSION vars reach
# `compgen -v`, and the run heads off into the real nvm/npm/pyenv — and the
# network. The sandbox also supplies HOME, so no case can touch the real
# ~/.sdkman.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Overridable so a red-baseline run can point at a pre-fix copy of the script
# (precedent: _GS_CIV_ENV_FILE in bin/check-image-versions.sh).
SUT="${_GS_OAE_SUT:-${SCRIPT_DIR}/../open-all-envs.sh}"
DOC="${SCRIPT_DIR}/../../templates/tips/open-many-links.md"

PASS=0
FAIL=0
FAILURES=()
SANDBOXES=()

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

cleanup() {
  local _s
  for _s in ${SANDBOXES+"${SANDBOXES[@]}"}; do
    [[ -n "${_s}" && -d "${_s}" ]] && rm -rf "${_s}"
  done
}
trap cleanup EXIT

# A fixture .env carrying one openable annotation (github) and one sdkman
# annotation, which the tool loop at the end of the script enumerates.
ENV_WITH_LINKS='GLOBAL_STACK_FOO_VERSION=1.0
# @todo env-update github:foo/bar 1.0
GLOBAL_STACK_JAVA_VERSION=21
# @todo env-update sdkman:java 21
'
# No annotation anywhere: the script has nothing to open. This is the shape a
# wrong-cwd run produced silently before the fix.
ENV_NO_LINKS='GLOBAL_STACK_FOO_VERSION=1.0
GLOBAL_STACK_BAR_VERSION=2.0
'

# make_sandbox <env-content> [sdk-behaviour]
#   sdk-behaviour "interrupt" makes the `sdk` shell function raise SIGINT the way
#   a terminal does — at the whole process GROUP (`kill -INT 0`), landing mid-run
#   after the config was captured. `kill -INT $$` is not a substitute: the script
#   calls `sdk list … | grep ""`, and a SIGINT raised from inside a pipeline is
#   swallowed [Verified: the loop runs to completion, exit 0; the same kill
#   outside a pipeline exits 130]. Because it hits the group, the case runs under
#   `setsid -w` or it takes this suite down with it.
make_sandbox() {
  local _env_content="${1}" _sdk_behaviour="${2:-noop}" _c
  SBX="$(mktemp -d)"
  SANDBOXES+=("${SBX}")
  mkdir -p "${SBX}/bin" "${SBX}/stub" "${SBX}/home/.sdkman/etc" "${SBX}/foreign"
  cp "${SUT}" "${SBX}/bin/open-all-envs.sh"
  printf '%s' "${_env_content}" >"${SBX}/.env"

  # Link opener: records the URL it is handed, one per line.
  cat >"${SBX}/stub/firefox" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\${@: -1}" >>"${SBX}/opened.log"
EOF
  # Probe/list commands the script really invokes — no-ops in the sandbox.
  for _c in curl npm sdkmanager pip; do
    printf '#!/usr/bin/env bash\nexit 0\n' >"${SBX}/stub/${_c}"
  done
  chmod +x "${SBX}"/stub/*
  : >"${SBX}/opened.log"

  # Stands in for /etc/profile.d/stack.sh. `nvm` and `sdk` are shell FUNCTIONS
  # in the real profile, so neither can be stubbed on PATH.
  {
    printf 'nvm() { :; }\n'
    if [[ "${_sdk_behaviour}" == "interrupt" ]]; then
      printf 'sdk() { kill -INT 0; }\n'
    else
      printf 'sdk() { :; }\n'
    fi
  } >"${SBX}/profile.sh"
}

# run_sut <cwd> [isolated] — sets RUN_OUT and RUN_RC.
run_sut() {
  local _pre=()
  [[ "${2:-}" == "isolated" ]] && _pre=(setsid -w)
  RUN_OUT="$(cd "${1}" && ${_pre[@]+"${_pre[@]}"} env -i \
    HOME="${SBX}/home" \
    PATH="${SBX}/stub:/usr/local/bin:/usr/bin:/bin" \
    _GS_EU_MD_PROFILE_SH="${SBX}/profile.sh" \
    bash "${SBX}/bin/open-all-envs.sh" 2>&1)"
  RUN_RC=$?
}

printf '\n%b── open-all-envs.sh ──%b\n' "${C_BOLD}" "${C_RESET}"

# ── F11: the .env must be found from any cwd ────────────────────────────────
printf '\n  %b1. .env is resolved from the checkout, not from $PWD%b\n' "${C_BOLD}" "${C_RESET}"

make_sandbox "${ENV_WITH_LINKS}"
run_sut "${SBX}/foreign"
OPENED_N="$(wc -l <"${SBX}/opened.log" | tr -d ' ')"

[[ "${OPENED_N}" -gt 0 ]] \
  && ok "run from a foreign cwd opens links (${OPENED_N})" \
  || ko "run from a foreign cwd opened ZERO links — the silent-vacuity defect (rc=${RUN_RC})"

grep -qxF 'https://github.com/foo/bar/releases' "${SBX}/opened.log" \
  && ok "the annotation's URL is the one that was opened" \
  || ko "expected github URL absent from opened.log: $(tr '\n' ' ' <"${SBX}/opened.log")"

[[ "${RUN_RC}" -eq 0 ]] \
  && ok "a run that opened links exits 0" \
  || ko "a healthy run exited ${RUN_RC}; output: ${RUN_OUT}"

# ── F11b: opening nothing is a failure, not a clean pass ────────────────────
printf '\n  %b2. a run that opens nothing fails loudly%b\n' "${C_BOLD}" "${C_RESET}"

make_sandbox "${ENV_NO_LINKS}"
run_sut "${SBX}/foreign"

[[ "${RUN_RC}" -ne 0 ]] \
  && ok "no annotations → non-zero exit (${RUN_RC})" \
  || ko "no annotations → exit 0: a scan that found nothing reported success"

grep -q 'no links opened' <<<"${RUN_OUT}" \
  && ok "the message says no links were opened" \
  || ko "unhelpful output for a zero-link run: ${RUN_OUT}"

# ── F12: the host's sdkman config is not collateral damage ──────────────────
printf '\n  %b3. ~/.sdkman/etc/config survives byte-identical%b\n' "${C_BOLD}" "${C_RESET}"

make_sandbox "${ENV_WITH_LINKS}"
SDK_CFG="${SBX}/home/.sdkman/etc/config"
cat >"${SDK_CFG}" <<'EOF'
sdkman_auto_answer=true
sdkman_checksum_enable=true
sdkman_healthcheck_enable=true
sdkman_debug_mode=false
EOF
cp "${SDK_CFG}" "${SBX}/config.original"
run_sut "${SBX}/foreign"

cmp -s "${SBX}/config.original" "${SDK_CFG}" \
  && ok "pre-existing config restored byte-identical after a full run" \
  || ko "config was rewritten — now: $(tr '\n' '|' <"${SDK_CFG}" 2>/dev/null || echo '<deleted>')"

grep -q '^sdkman_debug_mode=false$' "${SDK_CFG}" 2>/dev/null \
  && ok "a key the script never writes is still there (non-vacuity)" \
  || ko "sdkman_debug_mode lost — the file was not the developer's any more"

# ── F12b: nothing left behind when there was no config to begin with ────────
printf '\n  %b4. no config before the run → none after%b\n' "${C_BOLD}" "${C_RESET}"

make_sandbox "${ENV_WITH_LINKS}"
rm -f "${SBX}/home/.sdkman/etc/config"
run_sut "${SBX}/foreign"

[[ ! -e "${SBX}/home/.sdkman/etc/config" ]] \
  && ok "the script removed only what it created" \
  || ko "left a config behind: $(tr '\n' '|' <"${SBX}/home/.sdkman/etc/config")"

# ── F12c: a Ctrl-C mid-run still restores ──────────────────────────────────
printf '\n  %b5. interrupted mid-run, the config still comes back%b\n' "${C_BOLD}" "${C_RESET}"

make_sandbox "${ENV_WITH_LINKS}" interrupt
SDK_CFG="${SBX}/home/.sdkman/etc/config"
printf 'sdkman_auto_answer=true\nsdkman_debug_mode=false\n' >"${SDK_CFG}"
cp "${SDK_CFG}" "${SBX}/config.original"
run_sut "${SBX}/foreign" isolated

# 130 = killed by SIGINT. Asserting it proves the interrupt really fired, so a
# green restore below cannot be a run that simply never reached the sdk loop.
[[ "${RUN_RC}" -eq 130 ]] \
  && ok "the interrupt fired (exit 130)" \
  || ko "expected exit 130 from the SIGINT, got ${RUN_RC}; output: ${RUN_OUT}"

cmp -s "${SBX}/config.original" "${SDK_CFG}" \
  && ok "config restored byte-identical after the interrupt" \
  || ko "interrupted run left: $(tr '\n' '|' <"${SDK_CFG}" 2>/dev/null || echo '<deleted>')"

# ── The doc block is the same bytes as the script ──────────────────────────
printf '\n  %b6. templates/tips/open-many-links.md stays in sync%b\n' "${C_BOLD}" "${C_RESET}"

# The tip file embeds this script verbatim (script line N → doc line N+7), and
# the pairing is what makes the doc safe to paste. Nothing but this assertion
# stops the two drifting after a one-sided edit.
SUT_LINES="$(wc -l <"${SUT}" | tr -d ' ')"
if [[ -r "${DOC}" ]]; then
  if diff -u <(tail -n +2 "${SUT}") \
    <(sed -n "9,$((SUT_LINES + 7))p" "${DOC}") >"${SCRIPT_DIR}/.oae-doc.diff" 2>&1; then
    ok "doc lines 9-$((SUT_LINES + 7)) are byte-identical to script lines 2-${SUT_LINES}"
  else
    ko "doc/script pairing drifted: $(head -12 "${SCRIPT_DIR}/.oae-doc.diff" | tr '\n' '|')"
  fi
  rm -f "${SCRIPT_DIR}/.oae-doc.diff"

  # The doc carries two trailing lines the script does not (a blank and the
  # env-update invocation) — if they vanish, the offset above is wrong.
  [[ "$(wc -l <"${DOC}" | tr -d ' ')" -gt "$((SUT_LINES + 7))" ]] \
    && ok "the doc's trailing lines beyond the paired block are still present" \
    || ko "doc is shorter than the paired block — the 9/+7 offset no longer holds"
else
  ko "cannot read ${DOC}"
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
