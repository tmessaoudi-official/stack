#!/usr/bin/env bash
# Tests for the local registry lifecycle (docs/plans/local-registry-lifecycle.plan.md).
#
# 2026-11-07: `make soft-restart` stopped EVERY container on the host — the
# local registry included — and never started it again; `--restart=always`
# does not revive an explicitly stopped container while the daemon stays up.
# The stack still came up (images were in the local store), so the dead
# registry surfaced only at the next `global-stack-start.sh`, as buildkit's
# `dial tcp 127.0.0.1:42728: connect: connection refused`. The build's own
# FATAL registry gate fired, but the wrapper ran make with --ignore-errors
# --keep-going, so make carried on and the wrapper exited 0.
#
# Sections:
#   1  bin/local-registry.sh ensure — one case per container state
#   2  bin/local-registry.sh create — the `docker run` contract
#   3  Makefile wiring — prerequisites, soft-restart scope, hints
#   4  templates/shell/global-stack-make-exec.sh — stops on the first failure
#   5  end to end — the wrapper drives a sandbox copy of the real Makefile
#
# Nothing here can reach the real registry, daemon or tree: docker, curl and
# sleep are stubs in a per-case sandbox, sudo/systemctl/openssl are stubs that
# FAIL the case if anything calls them, and every run is under `env -i` (an
# interactive /stack shell exports .env.local, which would leak real values).
#
# SC2016: every `check … eval '<expr>'` single-quotes on purpose, so <expr> is
# expanded when the check RUNS, not when the line is parsed. SC2329: the
# predicate helpers are only ever called from inside those eval strings.
# shellcheck disable=SC2016,SC2329
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MAKEFILE="${REPO_ROOT}/Makefile"
LR_SCRIPT="${REPO_ROOT}/bin/local-registry.sh"
WRAPPER="${REPO_ROOT}/templates/shell/global-stack-make-exec.sh"
SYS_PATH="/usr/local/bin:/usr/bin:/bin"

PASS=0
FAIL=0
FAILURES=()
SANDBOXES=()

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
check() { # check <description> <command...> — passes when the command succeeds
  local _d="$1"
  shift
  if "$@"; then ok "${_d}"; else ko "${_d}"; fi
}
section() { printf '\n%b%s%b\n' "${C_BOLD}" "$1" "${C_RESET}"; }

cleanup() {
  local _s
  for _s in ${SANDBOXES+"${SANDBOXES[@]}"}; do
    [[ -n "${_s}" && -d "${_s}" ]] && rm -rf "${_s}"
  done
}
trap cleanup EXIT

# ── sandbox ──────────────────────────────────────────────────────────────────
# make_sandbox <registry-state> [nocert|nokey]
#   <registry-state>: running | exited | created | paused | restarting | dead |
#   missing. The stub docker reads and updates $SBX/reg.state; the stub curl
#   answers only while it says `running` and $SBX/silent is absent.
make_sandbox() {
  SBX="$(mktemp -d)"
  SANDBOXES+=("${SBX}")
  mkdir -p "${SBX}/stub" "${SBX}/bin" "${SBX}/tools" \
    "${SBX}/docker/registry/certs" "${SBX}/docker/registry/data" "${SBX}/docker/registry/registry"
  printf '%s\n' "$1" >"${SBX}/reg.state"
  [[ "${2:-}" == nocert ]] || printf 'CERT\n' >"${SBX}/docker/registry/certs/test-reg.local.crt"
  [[ "${2:-}" == nokey ]] || printf 'KEY\n' >"${SBX}/docker/registry/certs/test-reg.local.key"
  : >"${SBX}/docker.log"
  : >"${SBX}/curl.log"
  : >"${SBX}/forbidden.log"

  {
    printf '#!/usr/bin/env bash\nSBX=%q\n' "${SBX}"
    cat <<'EOF'
printf '%s\n' "$*" >>"${SBX}/docker.log"
state="$(cat "${SBX}/reg.state")"
case "${1:-}" in
  container)
    [[ -e "${SBX}/daemon-down" ]] && { echo "Cannot connect to the Docker daemon" >&2; exit 1; }
    if [[ "${2:-}" == ls ]]; then
      [[ "${state}" != missing ]] && printf '%s\n' "${state}"
      exit 0
    fi
    ;;
  start | unpause)
    [[ -e "${SBX}/start-fails" ]] && exit 1
    echo running >"${SBX}/reg.state"
    exit 0
    ;;
  run)
    [[ "${state}" != missing ]] && { echo "Conflict. The container name is already in use" >&2; exit 125; }
    echo running >"${SBX}/reg.state"
    exit 0
    ;;
  compose)
    prev=""
    for a in "$@"; do
      [[ "${prev}" == --output ]] && printf 'services: {}\n' >"${a}"
      prev="${a}"
    done
    exit 0
    ;;
  buildx)
    for a in "$@"; do
      if [[ "${a}" == --print ]]; then
        printf '%s\n' '{"group":{"default":{"targets":["svc-a","svc-b"]}},"target":{"svc-a":{"tags":["x/a"]},"svc-b":{"tags":["x/b"]}}}'
        exit 0
      fi
    done
    for a in "$@"; do [[ -e "${SBX}/fail-target.${a}" ]] && exit 1; done
    exit 0
    ;;
esac
exit 0
EOF
  } >"${SBX}/stub/docker"

  {
    printf '#!/usr/bin/env bash\nSBX=%q\n' "${SBX}"
    cat <<'EOF'
printf '%s\n' "$*" >>"${SBX}/curl.log"
[[ "$(cat "${SBX}/reg.state")" == running && ! -e "${SBX}/silent" ]] && exit 0
exit 7
EOF
  } >"${SBX}/stub/curl"

  printf '#!/usr/bin/env bash\nexit 0\n' >"${SBX}/stub/sleep"

  local _f
  for _f in sudo systemctl; do
    {
      printf '#!/usr/bin/env bash\nSBX=%q\n' "${SBX}"
      printf '%s\n' 'printf "%s %s\n" "$(basename "$0")" "$*" >>"${SBX}/forbidden.log"' 'exit 1'
    } >"${SBX}/stub/${_f}"
  done
  # openssl: `build`'s read-only expiry warning (`x509 … -checkend`) is
  # legitimate and answers "not expiring"; anything else — `req`, i.e. making a
  # certificate — is a rotation and is forbidden on every path under test.
  {
    printf '#!/usr/bin/env bash\nSBX=%q\n' "${SBX}"
    cat <<'EOF'
if [[ "${1:-}" == x509 && " $* " == *" -checkend "* ]]; then exit 0; fi
printf 'openssl %s\n' "$*" >>"${SBX}/forbidden.log"
exit 1
EOF
  } >"${SBX}/stub/openssl"
  chmod +x "${SBX}"/stub/*
}

# run_lr <subcommand> [VAR=value ...] — runs bin/local-registry.sh in the
# sandbox; sets RUN_OUT and RUN_RC. Extra VAR=value pairs override the defaults;
# `-VAR` removes one.
run_lr() {
  local _sub="$1"
  shift
  local -a _env=(
    HOME="${SBX}" PATH="${SBX}/stub:${SYS_PATH}"
    GLOBAL_STACK_DOCKER_ROOT_PATH="${SBX}"
    GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_NAME=test-reg
    GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS=test-reg.local
    GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000=42999
    GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_VERSION=9.9.9
    GS_LOCAL_REGISTRY_WAIT_TRIES=3
  )
  local _a _i
  for _a in "$@"; do
    if [[ "${_a}" == -* ]]; then
      for _i in "${!_env[@]}"; do [[ "${_env[_i]}" == "${_a#-}="* ]] && unset '_env[_i]'; done
    else
      _env+=("${_a}")
    fi
  done
  RUN_OUT="$(env -i "${_env[@]}" timeout 60 bash "${LR_SCRIPT}" "${_sub}" 2>&1)"
  RUN_RC=$?
}

docker_called() { grep -qE -e "$1" "${SBX}/docker.log"; }
no_forbidden() { [[ ! -s "${SBX}/forbidden.log" ]]; }
out_has() { [[ "${RUN_OUT}" == *"$1"* ]]; }
rc_zero() { [[ "${RUN_RC}" -eq 0 ]]; }
rc_nonzero() { [[ "${RUN_RC}" -ne 0 ]]; }

# ── 1 ── ensure, per state ──────────────────────────────────────────────────
section "1  bin/local-registry.sh ensure"

make_sandbox running
run_lr ensure
check "1.1  running + answering: exits 0" rc_zero
check "1.1  running + answering: no start, no run" eval '! docker_called "^(start|run|unpause) "'

make_sandbox exited
run_lr ensure
check "1.2  exited (the 2026-11-07 state): exits 0" rc_zero
check "1.2  exited: 'docker start test-reg'" docker_called '^start test-reg$'
check "1.2  exited: never 'docker run' (would conflict with the stopped container)" eval '! docker_called "^run "'

make_sandbox created
run_lr ensure
check "1.3  created: 'docker start test-reg' and exits 0" eval 'docker_called "^start test-reg$" && rc_zero'

make_sandbox paused
run_lr ensure
check "1.4  paused: 'docker unpause test-reg' and exits 0" eval 'docker_called "^unpause test-reg$" && rc_zero'

make_sandbox restarting
run_lr ensure
check "1.5  restarting: waits, starts nothing, exits non-zero when it never answers" \
  eval 'rc_nonzero && ! docker_called "^(start|run|unpause) "'

make_sandbox missing
run_lr ensure
check "1.6  missing + cert present: 'docker run' and exits 0" eval 'docker_called "^run " && rc_zero'

make_sandbox missing nocert
run_lr ensure
check "1.7  missing + cert absent: exits non-zero" rc_nonzero
check "1.7  missing + cert absent: names 'make start-local-registry create-buildx-builder'" \
  out_has "make start-local-registry create-buildx-builder"
check "1.7  missing + cert absent: never creates a container" eval '! docker_called "^run "'

make_sandbox missing nokey
run_lr ensure
check "1.8  missing + key absent: exits non-zero without 'docker run'" eval 'rc_nonzero && ! docker_called "^run "'

make_sandbox running
touch "${SBX}/silent"
run_lr ensure
check "1.9  running but /v2/ never answers: exits non-zero" rc_nonzero
check "1.9  running but silent: points at 'docker logs test-reg'" out_has "docker logs test-reg"
check "1.9  running but silent: polls exactly GS_LOCAL_REGISTRY_WAIT_TRIES times" \
  eval '[[ "$(grep -c "https://test-reg.local:42999/v2/" "${SBX}/curl.log")" -eq 3 ]]'
check "1.9  running but silent: never re-creates (a silent registry is a cert/trust problem)" \
  eval '! docker_called "^(rm|run|start) "'

make_sandbox exited
touch "${SBX}/start-fails"
run_lr ensure
check "1.10 exited and 'docker start' fails: exits non-zero" rc_nonzero

make_sandbox dead
run_lr ensure
check "1.11 dead: exits non-zero, names the recreate command, touches nothing" \
  eval 'rc_nonzero && out_has "make start-local-registry create-buildx-builder" && ! docker_called "^(start|run|rm) "'

make_sandbox exited
touch "${SBX}/daemon-down"
run_lr ensure
check "1.12 docker query fails (daemon down): exits non-zero, no 'docker run'" \
  eval 'rc_nonzero && ! docker_called "^run "'

make_sandbox exited
run_lr ensure -GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS
check "1.13 a required var unset: exits non-zero and names it" \
  eval 'rc_nonzero && out_has "GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS"'
check "1.13 a required var unset: touches nothing" eval '! docker_called "^(start|run) "'

# set -u alone would satisfy 1.13 (sabotage M4, 2026-11-07); the guard's own job
# is a var that is SET BUT EMPTY — .env.local writes opt-outs as `VAR=` — which
# would otherwise `docker start` and probe https://:42999/v2/.
make_sandbox exited
run_lr ensure GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS=
check "1.13b a required var set but EMPTY: exits non-zero, names it, touches nothing" \
  eval 'rc_nonzero && out_has "GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS is not set" && ! docker_called "^(start|run) "'

make_sandbox exited
run_lr bogus
check "1.14 unknown subcommand: exits non-zero" rc_nonzero

# ── 2 ── create: the docker run contract ─────────────────────────────────────
section "2  bin/local-registry.sh create"

make_sandbox missing
run_lr create
check "2.1  create: exits 0 once /v2/ answers" rc_zero
_run_line="$(grep -m1 '^run ' "${SBX}/docker.log" || true)"
for _want in \
  "--detach" \
  "--restart=always" \
  "--publish 42999:5000" \
  "--name test-reg" \
  "--env REGISTRY_HTTP_ADDR=0.0.0.0:5000" \
  "--env REGISTRY_HTTP_TLS_CERTIFICATE=/docker/registry/certs/test-reg.local.crt" \
  "--env REGISTRY_HTTP_TLS_KEY=/docker/registry/certs/test-reg.local.key" \
  "--env REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/data" \
  "--mount type=bind,source=${SBX}/docker/registry/certs,target=/docker/registry/certs" \
  "--mount type=bind,source=${SBX}/docker/registry/data,target=/data" \
  "--mount type=bind,source=${SBX}/docker/registry/registry,target=/var/lib/registry" \
  "registry:9.9.9"; do
  check "2.2  docker run carries '${_want}'" eval '[[ "${_run_line}" == *"${_want}"* ]]'
done

make_sandbox exited
run_lr create
check "2.3  create over an existing container: exits non-zero (no silent replace)" rc_nonzero

make_sandbox missing nocert
run_lr create
check "2.4  create without a cert: exits non-zero, no 'docker run'" eval 'rc_nonzero && ! docker_called "^run "'

# Every case above ran with failing sudo/systemctl/openssl stubs; one log per
# sandbox, so read them all.
_forbidden=0
for _s in "${SANDBOXES[@]}"; do [[ -s "${_s}/forbidden.log" ]] && _forbidden=$((_forbidden + 1)); done
check "2.5  sections 1-2: sudo/systemctl/openssl never called (ensure/create need no root)" \
  eval '[[ ${_forbidden} -eq 0 ]]'

# ── 3 ── Makefile wiring ─────────────────────────────────────────────────────
section "3  Makefile wiring"

rule_line() { grep -m1 -E "^$1:" "${MAKEFILE}"; }
recipe_of() { awk -v t="$1" '$0 ~ "^"t":" {on=1; next} on && /^\t/ {print; next} on {exit}' "${MAKEFILE}"; }
has_prereq() { rule_line "$1" | sed -E 's/^[^:]+:+//' | tr ' ' '\n' | grep -qxF -e "$2"; }

for _t in build up-build up-build-force-recreate; do
  check "3.1  '${_t}' has the prerequisite ensure-local-registry" has_prereq "${_t}" ensure-local-registry
done
check "3.2  ensure-local-registry runs 'bin/local-registry.sh ensure'" \
  eval 'recipe_of ensure-local-registry | grep -qF -e "bin/local-registry.sh ensure"'
check "3.3  ensure-local-registry is declared .PHONY" \
  eval 'sed -n "/^\.PHONY:/,/^\$/p" "${MAKEFILE}" | grep -qw -e "ensure-local-registry"'
check "3.4  start-local-registry creates via 'bin/local-registry.sh create' (one docker run contract)" \
  eval 'recipe_of start-local-registry | grep -qF -e "bin/local-registry.sh create"'
check "3.5  start-local-registry no longer inlines 'docker run'" \
  eval '! recipe_of start-local-registry | grep -qF -e "docker run"'

_soft="$(recipe_of soft-restart)"
check "3.6  soft-restart stops only containers mounting the tools path" \
  eval '[[ "${_soft}" == *"docker ps -q --filter volume=\${GLOBAL_STACK_DOCKER_TOOLS_PATH} | xargs -r docker stop"* ]]'
check "3.7  soft-restart has no unfiltered 'docker ps -q |' (it stopped the registry)" \
  eval '! grep -qF -e "docker ps -q |" <<<"${_soft}"'
_stop_ln="$(grep -n -F -e "--filter volume=" <<<"${_soft}" | head -n1 | cut -d: -f1)"
_rm_ln="$(grep -n -F -e "sudo rm -rf tools" <<<"${_soft}" | head -n1 | cut -d: -f1)"
# Both line numbers must EXIST: an empty one reads as 0 in [[ -lt ]] and the
# order check would pass with no filtered stop at all.
check "3.8  soft-restart stops tools/ holders BEFORE 'sudo rm -rf tools'" \
  eval '[[ -n "${_stop_ln}" && -n "${_rm_ln}" && "${_stop_ln}" -lt "${_rm_ln}" ]]'
check "3.9  soft-restart ends with ensure-local-registry" \
  eval 'tail -n1 <<<"${_soft}" | grep -qF -e "ensure-local-registry"'
check "3.10 hard-restart keeps its host-wide stop (its prune needs it — 664b215)" \
  eval 'recipe_of hard-restart | grep -qF -e "docker ps -q | xargs -r docker stop"'
check "3.11 build's cert-expiry hint names 'make start-local-registry create-buildx-builder'" \
  eval 'recipe_of build | grep -F -e "expires within" | grep -qF -e "make start-local-registry create-buildx-builder"'

# ── 4 ── the wrapper ─────────────────────────────────────────────────────────
section "4  templates/shell/global-stack-make-exec.sh"

WSBX="$(mktemp -d)"
SANDBOXES+=("${WSBX}")
printf '%s\n' 'all: gate after' 'gate:' '	@echo gate-ran; exit 1' 'after:' '	@echo after-ran' 'fine:' '	@echo fine-ran' >"${WSBX}/Makefile"
run_wrapper() { # run_wrapper <make-target> — sets RUN_OUT / RUN_RC
  RUN_OUT="$(env -i HOME="${WSBX}" PATH="${SYS_PATH}" GLOBAL_STACK_DOCKER_ROOT_PATH="${WSBX}" \
    GLOBAL_STACK_MAKE_EXEC="$1" timeout 60 bash "${WRAPPER}" 2>&1)"
  RUN_RC=$?
}
run_wrapper all
check "4.1  a failing prerequisite makes the wrapper exit non-zero" rc_nonzero
check "4.2  ... and the targets after it do not run" eval '! out_has after-ran'
run_wrapper fine
check "4.3  a passing target: exit 0 and its output shown" eval 'rc_zero && out_has fine-ran'

# ── 5 ── end to end ──────────────────────────────────────────────────────────
section "5  end to end: wrapper -> sandbox Makefile -> stub docker"

# e2e_sandbox <registry-state> [nocert] — a sandbox holding the real Makefile and
# the bin/ scripts its recipes call, with a minimal .env.local whose registry
# ALIAS is NESTED like the real one (only make resolves it).
e2e_sandbox() {
  make_sandbox "$@"
  cp "${MAKEFILE}" "${SBX}/Makefile"
  cp "${REPO_ROOT}/bin/check-bake-targets.sh" "${REPO_ROOT}/bin/check-image-versions.sh" "${SBX}/bin/"
  [[ -f "${LR_SCRIPT}" ]] && cp "${LR_SCRIPT}" "${SBX}/bin/"
  cat >"${SBX}/.env.local" <<EOF
GLOBAL_STACK_VERSION=test
GLOBAL_STACK_DOCKER_ROOT_PATH=${SBX}
GLOBAL_STACK_DOCKER_TOOLS_PATH=\${GLOBAL_STACK_DOCKER_ROOT_PATH}/tools
BUILDX_BAKE_FILE=docker-bake.local.json
COMPOSE_FULL_FILE=docker-compose.full.local.yaml
GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_VERSION=9.9.9
GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000=42999
GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_NAME=test-reg
GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS=\${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_NAME}.local
GS_LOCAL_REGISTRY_WAIT_TRIES=3
EOF
}
run_e2e() { # run_e2e <make-target> — the wrapper, exactly as global-stack-*.sh call it
  RUN_OUT="$(env -i HOME="${SBX}" PATH="${SBX}/stub:${SYS_PATH}" GLOBAL_STACK_DOCKER_ROOT_PATH="${SBX}" \
    GLOBAL_STACK_MAKE_EXEC="$1" timeout 120 bash "${WRAPPER}" 2>&1)"
  RUN_RC=$?
}
first_line_of() { grep -n -E -e "$1" "${SBX}/docker.log" | head -n1 | cut -d: -f1; }

e2e_sandbox running
run_e2e down
check "5.1  'down' (global-stack-stop.sh) succeeds without --ignore-errors" rc_zero

e2e_sandbox running
run_e2e down-n-up
check "5.2  'down-n-up' (global-stack-up.sh) succeeds and brings the stack up" \
  eval 'rc_zero && docker_called "^compose --env-file .env.local up --remove-orphans --detach$"'

e2e_sandbox running
run_e2e down-n-rebuild-force-recreate
check "5.3  'down-n-rebuild-force-recreate' (global-stack-start.sh), registry up: succeeds" rc_zero
check "5.3  ... builds and pushes every bake target" \
  eval 'docker_called "bake --push --load svc-a" && docker_called "bake --push --load svc-b"'
check "5.3  ... runs up --build --force-recreate" docker_called 'up --remove-orphans --detach --build --force-recreate'
check "5.3  ... the build ran inside the sandbox (tools/elapsed created there)" eval '[[ -f "${SBX}/tools/elapsed" ]]'

e2e_sandbox exited
run_e2e down-n-rebuild-force-recreate
check "5.4  THE INCIDENT — registry stopped, global-stack-start.sh: succeeds" rc_zero
check "5.4  ... the registry was started again ('docker start test-reg')" docker_called '^start test-reg$'
check "5.4  ... and started BEFORE the first push" \
  eval '[[ -n "$(first_line_of "^start test-reg$")" && "$(first_line_of "^start test-reg$")" -lt "$(first_line_of "bake --push")" ]]'
check "5.4  ... make resolved the NESTED alias for the probe (test-reg.local)" \
  eval 'grep -qF -e "https://test-reg.local:42999/v2/" "${SBX}/curl.log"'

e2e_sandbox missing nocert
run_e2e down-n-rebuild-force-recreate
check "5.5  no registry + no cert: the wrapper exits non-zero" rc_nonzero
check "5.5  ... names 'make start-local-registry create-buildx-builder'" \
  out_has "make start-local-registry create-buildx-builder"
check "5.5  ... and nothing was built or brought up" \
  eval '! docker_called "bake --push" && ! docker_called " up --remove-orphans"'

e2e_sandbox running
touch "${SBX}/fail-target.svc-a"
run_e2e down-n-rebuild-force-recreate
check "5.6  one service build fails: the wrapper exits non-zero" rc_nonzero
check "5.6  ... reports BUILD FAILURES naming it" eval 'out_has "BUILD FAILURES" && out_has "svc-a"'
check "5.6  ... and the stack is NOT brought up on stale images" \
  eval '! docker_called "up --remove-orphans --detach --build --force-recreate"'

_forbidden=0
for _s in "${SANDBOXES[@]}"; do [[ -s "${_s}/forbidden.log" ]] && _forbidden=$((_forbidden + 1)); done
check "5.7  no wrapper target called sudo/systemctl/openssl" eval '[[ ${_forbidden} -eq 0 ]]'

# ── leak check + tally ───────────────────────────────────────────────────────
cleanup
_left=0
for _s in "${SANDBOXES[@]}"; do [[ -e "${_s}" ]] && _left=$((_left + 1)); done
check "6.1  every sandbox was removed" eval '[[ ${_left} -eq 0 ]]'

TOTAL=$((PASS + FAIL))
printf '\n'
if [[ ${FAIL} -eq 0 && ${TOTAL} -gt 0 ]]; then
  printf '%bALL PASSED ✓ %d / %d%b\n' "${C_GREEN}" "${PASS}" "${TOTAL}" "${C_RESET}"
  exit 0
fi
printf '%bFAILED ✗ %d / %d%b\n' "${C_RED}" "${FAIL}" "${TOTAL}" "${C_RESET}"
for _f in ${FAILURES+"${FAILURES[@]}"}; do printf '  - %s\n' "${_f}"; done
exit 1
