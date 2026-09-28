#!/bin/bash

set -xeE -o pipefail
source global-stack-base-prologue.sh

SECONDS=0

# This service declares GLOBAL_STACK_ERROR_TOKEN=02sonarqube and its healthcheck
# fails while that file exists, so a token left by an earlier failed run would keep
# the container unhealthy forever even once the cause is fixed.
rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"

sleep 1

global-stack-base-wait-for.sh \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

global-stack-base-init-mkcert.sh

# SonarQube runs as a CHILD, not via exec, so an exit nobody asked for can be
# reported. On 2026-09-28 it could not reach Postgres, logged "SonarQube is stopped"
# and exited 0: `restart: on-failure:5` never restarts an exit 0 and nothing wrote a
# token, so the container sat Exited (0) with a healthcheck stuck on "starting".
#
# A stop is forwarded as SIGTERM whatever arrived: docker stop sends SIGINT (the
# image's StopSignal), but a background child starts with SIGINT IGNORED (measured:
# SigIgn 0x6), and a signal ignored on entry cannot be handled — the JVM would never
# see it. SIGTERM runs the JVM's shutdown hooks, SonarQube's graceful stop.
_gs_sq_stop_requested=0
_gs_sq_child=""
# shellcheck disable=SC2329  # invoked by the INT/TERM trap below
_gs_sq_forward_stop() {
  _gs_sq_stop_requested=1
  # A signal can land after the child exited but before `wait` returned; kill then
  # fails with ESRCH, which must not abort the shutdown under set -e.
  [[ -n "${_gs_sq_child}" ]] && kill -s TERM "${_gs_sq_child}" 2>/dev/null || :
}
trap '_gs_sq_forward_stop' INT TERM

"${GS_SONARQUBE_ENTRYPOINT:-/opt/sonarqube/docker/entrypoint.sh}" &
_gs_sq_child=$!

# `wait` returns early (status > 128) each time a trapped signal arrives; keep
# waiting until the child is really gone, so its own exit status is the one kept.
_gs_sq_rc=0
wait "${_gs_sq_child}" || _gs_sq_rc=$?
while kill -0 "${_gs_sq_child}" 2>/dev/null; do
  _gs_sq_rc=0
  wait "${_gs_sq_child}" || _gs_sq_rc=$?
done

if ((_gs_sq_stop_requested)); then
  stackExit "${_gs_sq_rc}"
fi

# Unrequested exit, whatever its status (0 included): the EXIT trap's stackCatch
# writes the error token, and a non-zero status is what on-failure:5 restarts.
printf 'SonarQube exited on its own (status %s) — reporting it as a failure\n' "${_gs_sq_rc}" >&2
exit 1
