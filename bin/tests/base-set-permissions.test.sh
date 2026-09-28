#!/usr/bin/env bash
# Tests for global-stack-base-set-permissions.sh (review-remediation rows 17/18, audit P1-7).
#
# The failure this guards (2026-09-28): the script ran `sudo chmod -R a+rwx` over ROOT_PATH, TOOLS_PATH
# and WORKDIR. ROOT_PATH is /stack and WORKDIR is /stack/projects, a host bind mount, so every start
# with a fresh tools volume (the `permissions` marker is gone after a hard restart) made every project
# file on the host 777: `.env` files world-writable, every file executable. The 2026-09-27 fix that
# only dropped WORKDIR would have changed nothing, because ROOT_PATH contains WORKDIR.
#
# Contract: only the shared TOOLS_PATH is made a+rwx; ROOT_PATH and WORKDIR get the chown alone; the
# marker gates the whole thing; a RELOAD flag re-runs it. And since nothing re-adds +x any more, every
# shebang script under docker/config/dist/bin must carry mode 100755 in git itself.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SET_PERMS="${ROOT}/docker/config/dist/bin/base-bin/global-stack-base-set-permissions.sh"

PASS=0
FAIL=0
FAILURES=()

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_GREEN=$'\033[32m' C_RED=$'\033[31m' C_BOLD=$'\033[1m' C_RESET=$'\033[0m'
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
section() { printf '\n%b── %s%b\n' "${C_BOLD}" "$1" "${C_RESET}"; }

T="$(mktemp -d)"
trap 'rm -rf "${T}"' EXIT

# A sudo that records one argv per line (args joined by a TAB) and runs nothing.
mkdir -p "${T}/stubs"
cat >"${T}/stubs/sudo" <<'STUB'
#!/usr/bin/env bash
(IFS=$'\t'; printf '%s\n' "$*") >>"${SUDO_LOG}"
STUB
chmod +x "${T}/stubs/sudo"

# run <marker: yes|no> [VAR=value ...] — runs the script with fake paths; the sudo log is in ${T}/sudo.log.
run() {
  local marker="$1"; shift
  local tools="${T}/tools"
  rm -rf "${tools}"; mkdir -p "${tools}"; : >"${T}/sudo.log"
  [[ "${marker}" == yes ]] && : >"${tools}/permissions"
  env PATH="${T}/stubs:${PATH}" SUDO_LOG="${T}/sudo.log" \
    GLOBAL_STACK_DOCKER_ROOT_PATH=/fake/stack \
    GLOBAL_STACK_DOCKER_TOOLS_PATH="${tools}" \
    GLOBAL_STACK_DOCKER_WORKDIR=/fake/stack/projects \
    GLOBAL_STACK_DOCKER_USER_ID=developer GLOBAL_STACK_DOCKER_GROUP_ID=developer \
    GLOBAL_STACK_RELOAD_ALL=false GLOBAL_STACK_RELOAD_PERMISSIONS=false \
    "$@" bash "${SET_PERMS}" >/dev/null 2>&1
}
# The sudo lines whose command is $1 (chmod / chown).
cmd_lines() { grep -E "^$1"$'\t' "${T}/sudo.log" || true; }
# True when a TAB-separated argv line has $2 as one of its arguments (an exact element, not a substring).
has_arg() { [[ $'\t'"$1"$'\t' == *$'\t'"$2"$'\t'* ]]; }

section "1. a fresh tools volume (no marker)"
run no
chmod_lines="$(cmd_lines chmod)"
chown_lines="$(cmd_lines chown)"
[[ -n "${chmod_lines}" && -n "${chown_lines}" ]] && ok "runs chmod and chown when the marker is absent" \
  || ko "runs chmod and chown when the marker is absent (log: $(tr '\t\n' ' |' <"${T}/sudo.log"))"
leak=""
while IFS= read -r l; do
  [[ -z "${l}" ]] && continue
  has_arg "${l}" /fake/stack && leak+="ROOT_PATH "
  has_arg "${l}" /fake/stack/projects && leak+="WORKDIR "
done <<<"${chmod_lines}"
[[ -z "${leak}" ]] && ok "no chmod touches ROOT_PATH or WORKDIR (the host projects bind mount)" \
  || ko "no chmod touches ROOT_PATH or WORKDIR — chmod targets: ${leak}"
tools_rwx=0
while IFS= read -r l; do
  has_arg "${l}" "-R" && has_arg "${l}" "a+rwx" && has_arg "${l}" "${T}/tools" && tools_rwx=1
done <<<"${chmod_lines}"
[[ "${tools_rwx}" == 1 ]] && ok "TOOLS_PATH still gets chmod -R a+rwx (the shared tools volume)" \
  || ko "TOOLS_PATH still gets chmod -R a+rwx"
own=1
for p in /fake/stack "${T}/tools" /fake/stack/projects; do
  hit=0
  while IFS= read -r l; do has_arg "${l}" "-R" && has_arg "${l}" "developer:developer" && has_arg "${l}" "${p}" && hit=1; done <<<"${chown_lines}"
  [[ "${hit}" == 1 ]] || own=0
done
[[ "${own}" == 1 ]] && ok "chown -R developer:developer still covers ROOT_PATH, TOOLS_PATH and WORKDIR" \
  || ko "chown -R developer:developer still covers ROOT_PATH, TOOLS_PATH and WORKDIR"

section "2. the marker gates it; a reload flag re-runs it"
run yes
[[ ! -s "${T}/sudo.log" ]] && ok "marker present, no reload flag → no sudo call at all" \
  || ko "marker present, no reload flag → no sudo call at all (log: $(tr '\t\n' ' |' <"${T}/sudo.log"))"
run yes GLOBAL_STACK_RELOAD_PERMISSIONS=true
[[ -n "$(cmd_lines chown)" ]] && ok "GLOBAL_STACK_RELOAD_PERMISSIONS=true re-runs it despite the marker" \
  || ko "GLOBAL_STACK_RELOAD_PERMISSIONS=true re-runs it despite the marker"
run yes GLOBAL_STACK_RELOAD_ALL=true
[[ -n "$(cmd_lines chown)" ]] && ok "GLOBAL_STACK_RELOAD_ALL=true re-runs it despite the marker" \
  || ko "GLOBAL_STACK_RELOAD_ALL=true re-runs it despite the marker"

section "3. dist/bin scripts are executable in git, not by the sweep"
bad=()
while IFS=$'\t' read -r meta path; do
  mode="${meta%% *}"
  [[ "$(head -c2 "${ROOT}/${path}" 2>/dev/null)" == '#!' && "${mode}" != 100755 ]] && bad+=("${path}")
done < <(git -C "${ROOT}" ls-files -s -- docker/config/dist/bin)
n="$(git -C "${ROOT}" ls-files -- docker/config/dist/bin | wc -l)"
if [[ "${n}" -eq 0 ]]; then
  ko "git lists docker/config/dist/bin (0 files — not run from a git checkout?)"
elif [[ ${#bad[@]} -eq 0 ]]; then
  ok "every shebang file under docker/config/dist/bin is 100755 in git (${n} files checked)"
else
  ko "every shebang file under docker/config/dist/bin is 100755 in git — ${#bad[@]} are not, e.g. ${bad[0]}"
fi

printf '\n%b%d passed, %d failed%b\n' "${C_BOLD}" "${PASS}" "${FAIL}" "${C_RESET}"
((FAIL == 0)) || { printf '  %s\n' "${FAILURES[@]}"; exit 1; }
