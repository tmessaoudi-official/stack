#!/usr/bin/env bash
# Tests for the `gs-claude-fullauto` block carried by the three host shell templates:
#   templates/shell/profile.sh      → /etc/profile.d/stack.sh   (every shell sourcing /etc/profile)
#   templates/shell/.shellrc        → end of ~/.shellrc          (user interactive rc)
#   templates/shell/shell.shellrc   → end of /etc/shell.shellrc  (system-wide interactive rc)
#
# What is guarded: in INTERACTIVE shells only, plain `claude` must carry
# --allow-dangerously-skip-permissions (bypassPermissions enters the Shift+Tab cycle, unarmed),
# passing every argument through; `command claude` must reach the bare binary; and NON-interactive
# shells (scripts, hooks, `claude -p` subprocesses, agent harnesses) must never get the function.
# The three copies must stay byte-identical — the triplication is the first thing a future edit
# breaks. Runs the REAL extracted bytes, never a re-typed copy; guards its own vacuity with a fake
# `claude` that prints its argv (so "flag present" can only come from the block under test).
# Certified under bash; the zsh case runs only when zsh is installed (skipped otherwise, not failed).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TPL="${REPO_ROOT}/templates/shell"
FILES=(profile.sh .shellrc shell.shellrc)
MARK_BEGIN='# >>> gs-claude-fullauto'
MARK_END='# <<< gs-claude-fullauto'

PASS=0; FAIL=0; FAILURES=()
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'; else C_GREEN='' C_RED='' C_BOLD='' C_RESET=''; fi
ok() { PASS=$((PASS + 1)); printf '  %b✓%b  %s\n' "${C_GREEN}" "${C_RESET}" "$1"; }
ko() { FAIL=$((FAIL + 1)); FAILURES+=("$1"); printf '  %b✗%b  %s\n' "${C_RED}" "${C_RESET}" "$1"; }

# Fake `claude` on PATH: prints its argv so the flag can only originate from the block under test.
FAKEBIN="$(mktemp -d)"; printf '#!/usr/bin/env bash\nprintf "ARGV:%%s\\n" "$*"\n' > "${FAKEBIN}/claude"; chmod +x "${FAKEBIN}/claude"
trap 'rm -rf "${FAKEBIN}"' EXIT
extract() { sed -n "/${MARK_BEGIN}/,/${MARK_END}/p" "${TPL}/$1"; }

printf '\n%b── templates/shell: gs-claude-fullauto ──%b\n' "${C_BOLD}" "${C_RESET}"

# ── Case 0: vacuity guard — the fake alone never shows the flag ─────────────
out="$(PATH="${FAKEBIN}:${PATH}" bash -c 'claude a b' 2>/dev/null)"
grep -q -- '--allow-dangerously-skip-permissions' <<<"${out}" \
  && ko "vacuity: fake claude prints the flag by itself — harness is inert" \
  || ok "vacuity: fake claude alone shows no flag (${out})"

for f in "${FILES[@]}"; do
  SUT="${TPL}/${f}"
  printf '%b[%s]%b\n' "${C_BOLD}" "${f}" "${C_RESET}"

  # ── Case 1: parses (dotfile templates are fragments; bash -n still applies) ──
  bash -n "${SUT}" 2>/dev/null && ok "${f}: bash -n clean" || ko "${f}: bash -n FAILED"

  # ── Case 2: the fenced block is present and extractable ──────────────────
  BLOCK="$(extract "${f}")"
  if [[ -z "${BLOCK}" ]]; then ko "${f}: markers missing — cannot extract the block"; continue; fi
  ok "${f}: delimited block present"
  grep -q 'command claude' <<<"${BLOCK}" && ok "${f}: block calls the bare binary via 'command'" \
    || ko "${f}: block does not use 'command claude' — recursion/escape hatch broken"

  # ── Case 3: interactive → flag + args pass through (real bytes, forced -i) ──
  P="$(mktemp)"; { printf '%s\n' "${BLOCK}"; printf '%s\n' 'claude one "two words"'; } > "${P}"
  out="$(PATH="${FAKEBIN}:${PATH}" bash -i "${P}" 2>/dev/null </dev/null || true)"
  [[ "${out}" == *'ARGV:--allow-dangerously-skip-permissions one two words'* ]] \
    && ok "${f}: interactive: flag first, args preserved" \
    || ko "${f}: interactive: expected flag+args, got '${out}'"

  # ── Case 4: interactive → `command claude` reaches the bare binary ───────
  { printf '%s\n' "${BLOCK}"; printf '%s\n' 'command claude plain'; } > "${P}"
  out="$(PATH="${FAKEBIN}:${PATH}" bash -i "${P}" 2>/dev/null </dev/null || true)"
  [[ "${out}" == 'ARGV:plain' ]] && ok "${f}: 'command claude' escape reaches the bare binary" \
    || ko "${f}: 'command claude' still wrapped: '${out}'"

  # ── Case 5: NON-interactive → no function at all (hooks / claude -p keep the binary) ──
  { printf '%s\n' "${BLOCK}"; printf '%s\n' 'type -t claude; claude x'; } > "${P}"
  out="$(PATH="${FAKEBIN}:${PATH}" bash "${P}" 2>/dev/null </dev/null || true)"
  [[ "${out}" == $'file\nARGV:x' ]] && ok "${f}: non-interactive: no function, bare binary, no flag" \
    || ko "${f}: non-interactive shell got the wrapper (would flag hooks/claude -p): '${out}'"
  rm -f "${P}"
done

# ── Case 6: the three copies are byte-identical ──────────────────────────────
if [[ -n "$(extract profile.sh)" && -n "$(extract .shellrc)" && -n "$(extract shell.shellrc)" ]]; then
  if diff -q <(extract profile.sh) <(extract .shellrc) >/dev/null && diff -q <(extract profile.sh) <(extract shell.shellrc) >/dev/null; then
    ok "triplication: block byte-identical across the 3 templates"
  else
    ko "triplication: the 3 copies of the block have drifted"
  fi
else
  ko "triplication: cannot compare — a block is missing"
fi

# ── Case 7: zsh (only if installed) ─────────────────────────────────────────
if command -v zsh >/dev/null 2>&1 && [[ -n "$(extract .shellrc)" ]]; then
  P="$(mktemp)"; { extract .shellrc; printf '%s\n' 'claude z'; } > "${P}"
  out="$(PATH="${FAKEBIN}:${PATH}" zsh -i "${P}" 2>/dev/null </dev/null || true)"
  [[ "${out}" == *'ARGV:--allow-dangerously-skip-permissions z'* ]] && ok "zsh: interactive wrapper works" || ko "zsh: wrapper broken: '${out}'"
  rm -f "${P}"
else
  printf '  %b-%b  zsh: not installed — case skipped (bash-certified only)\n' "${C_BOLD}" "${C_RESET}"
fi

printf '\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
if [[ "${FAIL}" -eq 0 ]]; then
  printf '  %bALL PASSED%b   ✓ %d / %d\n' "${C_GREEN}" "${C_RESET}" "${PASS}" "$((PASS + FAIL))"
else
  printf '  %bFAILED%b        ✗ %d / %d\n' "${C_RED}" "${C_RESET}" "${FAIL}" "$((PASS + FAIL))"
  for x in "${FAILURES[@]}"; do printf '    - %s\n' "$x"; done
  exit 1
fi
