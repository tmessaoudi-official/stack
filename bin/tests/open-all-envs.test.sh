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
#   sdk-behaviour "interrupt" kills the script mid-run, after the config was
#   captured and before the explicit restore, so only the EXIT trap can save it.
#   The vector is `kill -TERM $$`, chosen for determinism after measuring three:
#   `kill -INT $$` is SWALLOWED because the script calls `sdk list … | grep ""`
#   and a SIGINT raised inside a pipeline does not stop the shell [Verified: loop
#   runs to completion, exit 0]; `kill -INT 0` reaches the group the way a
#   terminal's Ctrl-C does but RACES the pipeline's own completion [Verified:
#   11/12 runs exit 130, 1/12 exits 0 — a flaky test is worse than no test];
#   `kill -TERM $$` is 12/12 deterministic and needs no `setsid` isolation. The
#   guarantee under test is the same for all three — the shell dies mid-block and
#   the EXIT trap runs — and that trap is confirmed to fire for INT and TERM
#   alike [Verified: exit 130 / 143, the line after the kill never executes].
make_sandbox() {
  local _env_content="${1}" _sdk_behaviour="${2:-noop}" _c
  RUN_EXTRA_ENV=()
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
      printf 'sdk() { kill -TERM $$; }\n'
    else
      printf 'sdk() { :; }\n'
    fi
  } >"${SBX}/profile.sh"
}

# Extra KEY=VAL pairs spliced into the `env -i` of the next run_sut. Reset per
# case by make_sandbox so one case cannot leak into the next.
RUN_EXTRA_ENV=()

# run_sut <cwd> — sets RUN_OUT and RUN_RC.
run_sut() {
  RUN_OUT="$(cd "${1}" && env -i \
    ${RUN_EXTRA_ENV[@]+"${RUN_EXTRA_ENV[@]}"} \
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
run_sut "${SBX}/foreign"

# 143 = killed by SIGTERM. Asserting it proves the kill really landed, so a
# green restore below cannot be a run that simply never reached the sdk loop.
[[ "${RUN_RC}" -eq 143 ]] \
  && ok "the kill landed mid-run (exit 143)" \
  || ko "expected exit 143 from the signal, got ${RUN_RC}; output: ${RUN_OUT}"

cmp -s "${SBX}/config.original" "${SDK_CFG}" \
  && ok "config restored byte-identical after the interrupt" \
  || ko "interrupted run left: $(tr '\n' '|' <"${SDK_CFG}" 2>/dev/null || echo '<deleted>')"

# ── The safety net's OWN failure paths must not be the destructive ones ─────
# A backup that silently did not happen is worse than no backup at all: the
# restore then runs against nothing and "restores" by deleting. Both shapes
# below end with the developer's file intact or explicitly preserved.
printf '\n  %b6. a backup that fails does not cost the config%b\n' "${C_BOLD}" "${C_RESET}"

# mktemp cannot create the backup → the block must not run at all.
make_sandbox "${ENV_WITH_LINKS}"
SDK_CFG="${SBX}/home/.sdkman/etc/config"
printf 'sdkman_auto_answer=true\nsdkman_debug_mode=false\n' >"${SDK_CFG}"
cp "${SDK_CFG}" "${SBX}/config.original"
RUN_EXTRA_ENV=(TMPDIR=/nonexistent/no-such-dir)
run_sut "${SBX}/foreign"

cmp -s "${SBX}/config.original" "${SDK_CFG}" \
  && ok "mktemp failure: config untouched" \
  || ko "mktemp failure destroyed the config — now: $(tr '\n' '|' <"${SDK_CFG}" 2>/dev/null || echo '<deleted>')"

grep -qi 'could not back up' <<<"${RUN_OUT}" \
  && ok "mktemp failure: says the listing was skipped, not silently dropped" \
  || ko "no message about the failed backup: $(tr '\n' '|' <<<"${RUN_OUT}")"

# The restore itself fails → the backup must survive and the WARN must be true.
REAL_CP="$(command -v cp)"
make_sandbox "${ENV_WITH_LINKS}"
SDK_CFG="${SBX}/home/.sdkman/etc/config"
printf 'sdkman_auto_answer=true\nsdkman_debug_mode=false\n' >"${SDK_CFG}"
cp "${SDK_CFG}" "${SBX}/config.original"
# Fails only when the config is the DESTINATION, so the capture succeeds and the
# restore does not — `cp -p src dst` puts the destination last.
cat >"${SBX}/stub/cp" <<EOF
#!/usr/bin/env bash
if [[ "\${@: -1}" == "${SDK_CFG}" ]]; then
  echo "cp: simulated failure" >&2
  exit 1
fi
exec "${REAL_CP}" "\$@"
EOF
chmod +x "${SBX}/stub/cp"
run_sut "${SBX}/foreign"

_bak_path="$(sed -n 's/.*your original is kept at \(.*\)$/\1/p' <<<"${RUN_OUT}" | tail -1)"
[[ -n "${_bak_path}" ]] \
  && ok "restore failure: WARN names the kept backup" \
  || ko "restore failed with no WARN naming a backup: $(tr '\n' '|' <<<"${RUN_OUT}")"

if [[ -n "${_bak_path}" && -f "${_bak_path}" ]]; then
  cmp -s "${_bak_path}" "${SBX}/config.original" \
    && ok "restore failure: the kept backup really is the original" \
    || ko "the kept backup is not the original content"
  rm -f "${_bak_path}"
else
  ko "the WARN promised a backup at '${_bak_path}' and it is not there"
fi

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
