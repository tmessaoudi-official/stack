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
      # slow-ls: a REAL delay (the sandbox's `sleep` is a no-op stub), so a
      # parallel make would reach `down` while ensure is still querying (5.16).
      [[ -e "${SBX}/slow-ls" ]] && /usr/bin/sleep 3
      # Answer like real docker, so a drift in the script's query is visible
      # (panel 2026-11-07: dropping --all or switching to {{.Status}} stayed
      # 74/74 against a stub that ignored its arguments).
      shift 2
      all=0 filt="" fmt=""
      while (($#)); do
        case "$1" in
          --all | -a) all=1 ;;
          --filter) filt="${2:-}"; shift ;;
          --format) fmt="${2:-}"; shift ;;
        esac
        shift
      done
      [[ "${state}" == missing ]] && exit 0
      [[ "${filt}" == 'name=^/test-reg$' ]] || exit 0 # another container's name
      # without --all, docker lists only running/paused/restarting containers
      ((all)) || [[ "${state}" == running || "${state}" == paused || "${state}" == restarting ]] || exit 0
      if [[ "${fmt}" == '{{.State}}' ]]; then printf '%s\n' "${state}"; else printf 'Exited (2) 5 hours ago\n'; fi
      exit 0
    fi
    ;;
  ps)
    [[ " $* " == *" --filter volume=${SBX}/tools "* ]] && printf 'c1\n'
    exit 0
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
    # compose-fails: an unparseable project (bad YAML, a trailing ';' in
    # COMPOSE_FILE) — every compose call fails, as the real one does (5.18/5.19).
    [[ -e "${SBX}/compose-fails" ]] && { echo "yaml: line 3: mapping values are not allowed here" >&2; exit 1; }
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
        [[ -e "${SBX}/bake-print-fails" ]] && { echo "ERROR: failed to parse bake definition" >&2; exit 1; }
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
[[ -e "${SBX}/curl-rc" ]] && exit "$(cat "${SBX}/curl-rc")"
[[ "$(cat "${SBX}/reg.state")" == running && ! -e "${SBX}/silent" ]] && exit 0
exit 7
EOF
  } >"${SBX}/stub/curl"

  printf '#!/usr/bin/env bash\nexit 0\n' >"${SBX}/stub/sleep"
  {
    printf '#!/usr/bin/env bash\nSBX=%q\n' "${SBX}"
    cat <<'EOF'
printf '%s\n' "$*" >>"${SBX}/getent.log"
[[ "${1:-}" == hosts ]] || exit 2
# Like glibc getent: NO key enumerates the database and exits 0; an EMPTY key
# ('getent hosts ""') is not found, exit 2 (panel round 3: the old stub
# answered 0 for both, so an unquoted empty alias passed the guard unseen).
(($# == 1)) && { printf '127.0.0.1 localhost\n'; exit 0; }
[[ -n "${2}" && ! -e "${SBX}/alias-unresolved" ]] && { printf '127.0.0.1 %s\n' "${2}"; exit 0; }
exit 2
EOF
  } >"${SBX}/stub/getent"

  {
    printf '#!/usr/bin/env bash\nSBX=%q\n' "${SBX}"
    cat <<'EOF'
if [[ -e "${SBX}/allow-sudo-rm-tools" && "$*" == "rm -rf tools" && "$(pwd -P)" == "$(cd "${SBX}" && pwd -P)" ]]; then
  printf '%s\n' "$*" >>"${SBX}/sudo.log"
  exec "$@"
fi
printf 'sudo %s\n' "$*" >>"${SBX}/forbidden.log"
exit 1
EOF
  } >"${SBX}/stub/sudo"
  : >"${SBX}/sudo.log"
  {
    printf '#!/usr/bin/env bash\nSBX=%q\n' "${SBX}"
    printf '%s\n' 'printf "systemctl %s\n" "$*" >>"${SBX}/forbidden.log"' 'exit 1'
  } >"${SBX}/stub/systemctl"
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
check "1.9  running but silent: never re-creates on its own (removal is the developer's call)" \
  eval '! docker_called "^(rm|run|start) "'
# The probe is curl -k, so trust/expiry cannot make it silent: the first remedy is
# root-free (re-create from the existing cert), the rotation only the fallback
# (panel round 4, R4-3 — the rotation restarts the daemon twice).
check "1.9b running but silent: offers the root-free re-create FIRST, the rotation as fallback" \
  eval 'out_has "docker rm -f test-reg && make ensure-local-registry" && out_has "make start-local-registry create-buildx-builder" && [[ "${RUN_OUT%%docker rm -f test-reg*}" != *"make start-local-registry"* ]]'

make_sandbox exited
touch "${SBX}/start-fails"
run_lr ensure
check "1.10 exited and 'docker start' fails: exits non-zero" rc_nonzero

make_sandbox dead
run_lr ensure
check "1.11 dead: exits non-zero, names the recreate command, touches nothing" \
  eval 'rc_nonzero && out_has "make start-local-registry create-buildx-builder" && ! docker_called "^(start|run|rm) "'
check "1.11b dead: offers the root-free re-create FIRST, the rotation as fallback" \
  eval 'out_has "docker rm -f test-reg && make ensure-local-registry" && [[ "${RUN_OUT%%docker rm -f test-reg*}" != *"make start-local-registry"* ]]'

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
run_lr ensure
check "1.12b the state query is exactly 'container ls --all --filter name=^/test-reg\$ --format {{.State}}'" \
  eval '[[ "$(grep -m1 "^container " "${SBX}/docker.log")" == "container ls --all --filter name=^/test-reg\$ --format {{.State}}" ]]'

# A cold machine without the /etc/hosts alias: curl exits 6 (cannot resolve).
# Rotating would restart the daemon and fix nothing, so it must not be suggested.
make_sandbox running
echo 6 >"${SBX}/curl-rc"
run_lr ensure
check "1.15 alias does not resolve (curl 6): exits non-zero and points at /etc/hosts" \
  eval 'rc_nonzero && out_has "/etc/hosts" && out_has "test-reg.local"'
check "1.15 ... and does NOT suggest a rotation (it restarts the daemon, fixes nothing)" \
  eval '! out_has "create-buildx-builder"'
check "1.15 ... and continues with 'make ensure-local-registry'" out_has "make ensure-local-registry"

# A registry that accepts TCP but never answers must not hang the probe forever.
make_sandbox running
run_lr ensure
check "1.16 the /v2/ probe is bounded (--connect-timeout and --max-time)" \
  eval 'grep -q -e "--connect-timeout" "${SBX}/curl.log" && grep -q -e "--max-time" "${SBX}/curl.log"'

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

# _gs_lr_state's fatal used to exit only the `$(…)` of create's guard, so a
# failed query read as "missing" and create went on to `docker run`.
make_sandbox missing
touch "${SBX}/daemon-down"
run_lr create
check "2.6  create when the docker query fails: exits non-zero, no 'docker run'" \
  eval 'rc_nonzero && ! docker_called "^run "'

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

for _t in build up up-build up-build-force-recreate; do
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
_ens_ln="$(grep -n -F -e "ensure-local-registry" <<<"${_soft}" | head -n1 | cut -d: -f1)"
_up_ln="$(grep -n -E -e '\$\(MAKE\) up( |$)' <<<"${_soft}" | head -n1 | cut -d: -f1)"
check "3.9  soft-restart runs ensure-local-registry BEFORE \$(MAKE) up" \
  eval '[[ -n "${_ens_ln}" && -n "${_up_ln}" && "${_ens_ln}" -lt "${_up_ln}" ]]'
_down_ln="$(grep -n -E -e '\$\(MAKE\) down( |$)' <<<"${_soft}" | head -n1 | cut -d: -f1)"
check "3.9  ... and BEFORE its \$(MAKE) down (a broken registry must leave the stack untouched)" \
  eval '[[ -n "${_ens_ln}" && -n "${_down_ln}" && "${_ens_ln}" -lt "${_down_ln}" ]]'
check "3.9  ... and without --ignore-errors (a failure must stop it)" \
  eval '! grep -F -e "ensure-local-registry" <<<"${_soft}" | grep -qF -e "--ignore-errors"'
_guard_ln="$(grep -n -F -e 'test -n "${GLOBAL_STACK_DOCKER_TOOLS_PATH}"' <<<"${_soft}" | head -n1 | cut -d: -f1)"
check "3.9b soft-restart refuses an empty GLOBAL_STACK_DOCKER_TOOLS_PATH before the scoped stop" \
  eval '[[ -n "${_guard_ln}" && -n "${_stop_ln}" && "${_guard_ln}" -lt "${_stop_ln}" ]]'
check "3.10 hard-restart keeps its host-wide stop (its prune needs it — 664b215)" \
  eval 'recipe_of hard-restart | grep -qF -e "docker ps -q | xargs -r docker stop"'
check "3.11 build's cert-expiry hint names 'make start-local-registry create-buildx-builder'" \
  eval 'recipe_of build | grep -F -e "expires within" | grep -qF -e "make start-local-registry create-buildx-builder"'

first_prereq() { rule_line "$1" | sed -E 's/^[^:]+:+[[:space:]]*//' | awk '{print $1}'; }
for _t in down-n-up down-n-rebuild down-n-rebuild-force-recreate; do
  check "3.14 '${_t}' checks the registry BEFORE its down (first prerequisite: ensure-local-registry)" \
    eval '[[ "$(first_prereq "${_t}")" == ensure-local-registry ]]'
done
check "3.15 start-local-registry checks the alias resolves BEFORE anything else" \
  eval 'recipe_of start-local-registry | head -n1 | grep -qF -e "getent hosts"'
check "3.16 build's registry gate probe is bounded (--max-time)" \
  eval 'recipe_of build | grep -F -e "curl -fks" | grep -qF -e "--max-time"'
check "3.12 build's registry gate points at 'make ensure-local-registry'" \
  eval 'recipe_of build | grep -F -e "FATAL: local registry" | grep -qF -e "make ensure-local-registry"'
check "3.13 no hint names a bare 'make start-local-registry' (a new cert needs create-buildx-builder)" \
  eval '! grep -qF -e "make start-local-registry'"'"'" "${MAKEFILE}" "${LR_SCRIPT}"'

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
run_e2e() { # run_e2e <make-target> [VAR=value ...] — the wrapper, exactly as global-stack-*.sh call it
  local _t="$1"
  shift
  RUN_OUT="$(env -i HOME="${SBX}" PATH="${SBX}/stub:${SYS_PATH}" GLOBAL_STACK_DOCKER_ROOT_PATH="${SBX}" \
    GLOBAL_STACK_MAKE_EXEC="${_t}" "$@" timeout 120 bash "${WRAPPER}" 2>&1)"
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
check "5.6  ... and says the stack is DOWN and 'make up' starts it again" \
  eval 'out_has "stack is DOWN" && out_has "make up"'

e2e_sandbox exited
run_e2e down-n-up
check "5.8  'down-n-up' with the registry stopped: succeeds and starts it BEFORE up" \
  eval 'rc_zero && [[ -n "$(first_line_of "^start test-reg$")" && "$(first_line_of "^start test-reg$")" -lt "$(first_line_of " up --remove-orphans --detach$")" ]]'

# soft-restart, executed: sudo is allowed for exactly `rm -rf tools` in the sandbox.
soft_sandbox() {
  e2e_sandbox "$@"
  touch "${SBX}/allow-sudo-rm-tools"
  mkdir -p "${SBX}/var/tools"
  printf 'snapshot\n' >"${SBX}/var/tools/from-snapshot"
  printf 'live\n' >"${SBX}/tools/live-only"
}
soft_sandbox exited
run_e2e soft-restart
check "5.9  soft-restart, registry stopped: exits 0" rc_zero
check "5.9  ... asks docker for the tools-path holders only" \
  eval 'docker_called "^ps -q --filter volume=${SBX}/tools$"'
check "5.9  ... stops exactly those ('docker stop c1')" docker_called '^stop c1$'
check "5.9  ... restores tools/ from var/tools" \
  eval '[[ -f "${SBX}/tools/from-snapshot" && ! -e "${SBX}/tools/live-only" ]]'
check "5.9  ... starts the registry BEFORE up" \
  eval '[[ -n "$(first_line_of "^start test-reg$")" && "$(first_line_of "^start test-reg$")" -lt "$(first_line_of " up --remove-orphans --detach$")" ]]'

# An ensure failure must stop soft-restart BEFORE it tears anything down. A grep for
# --ignore-errors alone let a '-' recipe prefix or '-i' through (panel round 2).
soft_sandbox dead
run_e2e soft-restart
check "5.11 soft-restart, registry dead: exits non-zero" rc_nonzero
check "5.11 ... before 'down', the stop or 'rm -rf tools'" \
  eval '! docker_called "compose .* down" && ! docker_called "^ps -q --filter volume=" && [[ ! -s "${SBX}/sudo.log" && -f "${SBX}/tools/live-only" ]]'

for _t in down-n-up down-n-rebuild-force-recreate; do
  e2e_sandbox dead
  run_e2e "${_t}"
  check "5.12 '${_t}', registry dead: exits non-zero with the stack untouched (no 'down')" \
    eval 'rc_nonzero && ! docker_called "compose .* down"'
done

# A broken bake definition must not strand the stack: up does not use the bake
# file (its first recipe line deletes it), so down-n-up must still bring the
# stack up (panel round 3, R3-I1 — the wrapper no longer ignores errors).
e2e_sandbox running
touch "${SBX}/bake-print-fails"
run_e2e down-n-up
check "5.15 'down-n-up' with a failing 'buildx bake --print': still brings the stack up" \
  eval 'rc_zero && docker_called "^compose --env-file .env.local up --remove-orphans --detach$"'

# Under parallel make (MAKEFLAGS=-j4 passes through the wrapper) the order of
# prerequisites is not an order: ensure must still fail BEFORE any down
# (panel round 3, R3-I2). slow-ls keeps ensure busy long enough for -j to show.
for _t in down-n-up down-n-rebuild-force-recreate; do
  e2e_sandbox dead
  touch "${SBX}/slow-ls"
  run_e2e "${_t}" MAKEFLAGS=-j4
  check "5.16 '${_t}' under MAKEFLAGS=-j4, registry dead: no 'down' ran" \
    eval 'rc_nonzero && ! docker_called "compose .* down"'
done

# An unparseable compose project must fail loudly, and BEFORE any down: the
# round-3 fix took generate-buildx (whose bake check caught it) off up's path,
# and up's own compose sub-make ignores errors (panel round 4, R4-I1).
e2e_sandbox running
touch "${SBX}/compose-fails"
run_e2e up
check "5.18 'make up' with an unparseable compose project: exits non-zero and says so" \
  eval 'rc_nonzero && out_has "does not parse" && ! docker_called " up --remove-orphans"'
for _t in down-n-up down-n-rebuild-force-recreate; do
  e2e_sandbox running
  touch "${SBX}/compose-fails"
  run_e2e "${_t}"
  check "5.19 '${_t}' with an unparseable compose project: exits non-zero BEFORE any 'down'" \
    eval 'rc_nonzero && out_has "does not parse" && ! docker_called "compose .* down"'
done
soft_sandbox running
touch "${SBX}/compose-fails"
run_e2e soft-restart
check "5.19 soft-restart with an unparseable compose project: exits non-zero before 'down', the stop or 'rm -rf tools'" \
  eval 'rc_nonzero && out_has "does not parse" && ! docker_called "compose .* down" && ! docker_called "^ps -q --filter volume=" && [[ ! -s "${SBX}/sudo.log" && -f "${SBX}/tools/live-only" ]]'

soft_sandbox running
sed -i 's|^GLOBAL_STACK_DOCKER_TOOLS_PATH=.*|GLOBAL_STACK_DOCKER_TOOLS_PATH=|' "${SBX}/.env.local"
run_e2e soft-restart
check "5.10 soft-restart with GLOBAL_STACK_DOCKER_TOOLS_PATH empty: exits non-zero and names it" \
  eval 'rc_nonzero && out_has "GLOBAL_STACK_DOCKER_TOOLS_PATH"'
check "5.10 ... and never removes tools/" \
  eval '[[ ! -s "${SBX}/sudo.log" && -f "${SBX}/tools/live-only" ]]'

_forbidden=0
for _s in "${SANDBOXES[@]}"; do [[ -s "${_s}/forbidden.log" ]] && _forbidden=$((_forbidden + 1)); done
check "5.7  no wrapper target called sudo/systemctl/openssl" eval '[[ ${_forbidden} -eq 0 ]]'

# After 5.7 on purpose: 5.14 reaches `openssl req` (a forbidden stub) by design.
# start-local-registry on a machine without the /etc/hosts alias: fail before any
# cert, root or daemon step (it used to mint a cert and restart the daemon first).
e2e_sandbox running
touch "${SBX}/alias-unresolved"
run_e2e start-local-registry
check "5.13 start-local-registry, alias unresolved: exits non-zero and points at /etc/hosts" \
  eval 'rc_nonzero && out_has "/etc/hosts"'
check "5.13 ... before openssl, sudo, systemctl or 'docker rm'" \
  eval '[[ ! -s "${SBX}/forbidden.log" ]] && ! docker_called "^rm "'
e2e_sandbox running
run_e2e start-local-registry
check "5.14 start-local-registry, alias resolves: the check lets it through (next step: openssl req)" \
  eval 'grep -q "^openssl req" "${SBX}/forbidden.log"'
# An EMPTY alias (no .env.local yet, or set blank) must fail the same check: an
# unquoted operand turns it into 'getent hosts', which enumerates and exits 0.
e2e_sandbox running
sed -i 's|^GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS=.*|GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS=|' "${SBX}/.env.local"
run_e2e start-local-registry
check "5.17 start-local-registry, alias EMPTY: exits non-zero and names the missing .env.local" \
  eval 'rc_nonzero && out_has "GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS is empty" && out_has ".env.local"'
check "5.17 ... and does NOT tell you to add an empty name to /etc/hosts" \
  eval '! out_has "add '"'"'127.0.0.1 '"'"' to"'
check "5.17 ... before openssl, sudo, systemctl or 'docker rm'" \
  eval '[[ ! -s "${SBX}/forbidden.log" ]] && ! docker_called "^rm "'

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
