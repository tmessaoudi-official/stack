#!/usr/bin/env bash
# bin/local-registry.sh — lifecycle of the local TLS registry the stack builds through.
#
#   ensure   make the registry reachable without ever touching its certificate:
#              running   -> wait for /v2/
#              exited    -> docker start, wait      (what `make soft-restart` left
#              created   -> docker start, wait       behind on 2026-11-07)
#              paused    -> docker unpause, wait
#              restarting-> wait
#              missing   -> create (cert must already exist)
#              dead/removing/anything else -> FAIL
#   create   `docker run` the registry container (fails if one already exists), wait
#
# Why ensure never makes a certificate: the buildx builder image
# (docker/buildkit/Dockerfile) COPIES the cert in at image build time, so a new
# cert is trusted only after `make create-buildx-builder` rebuilds it. Rotation is
# therefore `make start-local-registry create-buildx-builder`, explicitly — the only
# path that needs sudo or a daemon restart. A running registry that never answers,
# or one in a state ensure cannot start (dead), is not a trust problem: the probe
# is `curl -k`, so trust and expiry cannot silence it. The usual cure is
# root-free: remove the container and let ensure re-create it from the existing
# cert (the data is bind-mounted, so it survives). Only a cert/key mismatch, for
# example after an interrupted `openssl req`, needs the rotation. ensure never
# removes a container on its own, so it stops and names both, root-free first
# (panel round 4).
#
# Values come from the environment: run it through make (`make ensure-local-registry`),
# which exports .env.local — GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS is NESTED
# (`${…_NAME}.local`), and only make resolves it.
#
# Tests: bin/tests/local-registry.test.sh
set -eEuo pipefail

_gs_lr_fatal() {
  printf 'FATAL: %s\n' "$1" >&2
  if [[ -n "${2:-}" ]]; then printf '       %s\n' "$2" >&2; fi
  exit 1
}

_gs_lr_require() {
  local _v
  for _v in GLOBAL_STACK_DOCKER_ROOT_PATH \
    GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_NAME \
    GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS \
    GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000 \
    GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_VERSION; do
    [[ -n "${!_v:-}" ]] || _gs_lr_fatal "${_v} is not set" \
      "Run this through make (e.g. 'make ensure-local-registry'), which exports .env.local."
  done
}

_gs_lr_require
_GS_LR_NAME="${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_NAME}"
_GS_LR_ALIAS="${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_ALIAS}"
_GS_LR_PORT="${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_PORT_5000}"
_GS_LR_DIR="${GLOBAL_STACK_DOCKER_ROOT_PATH}/docker/registry"
_GS_LR_CRT="${_GS_LR_DIR}/certs/${_GS_LR_ALIAS}.crt"
_GS_LR_KEY="${_GS_LR_DIR}/certs/${_GS_LR_ALIAS}.key"
_GS_LR_URL="https://${_GS_LR_ALIAS}:${_GS_LR_PORT}/v2/"
_GS_LR_TRIES="${GS_LOCAL_REGISTRY_WAIT_TRIES:-30}"
_GS_LR_ROTATE="make start-local-registry create-buildx-builder"
_GS_LR_RECREATE_HINT="Re-create it from the existing cert (no root, no daemon restart, data kept): 'docker rm -f ${_GS_LR_NAME} && make ensure-local-registry'. Only if it still does not answer (e.g. a cert/key mismatch), rotate: '${_GS_LR_ROTATE}'."

# Prints the container state (running/exited/created/paused/restarting/dead/
# removing), or nothing when no such container exists. A docker failure (daemon
# down) is fatal — it must not read as "missing" and trigger a create.
_gs_lr_state() {
  local _out
  _out="$(docker container ls --all --filter "name=^/${_GS_LR_NAME}$" --format '{{.State}}')" \
    || _gs_lr_fatal "cannot query docker for '${_GS_LR_NAME}'" "Is the Docker daemon running? ('docker info')"
  printf '%s' "${_out%%$'\n'*}"
}

# The same probe as `make build`'s gate: -k because trust is the builder's job,
# not this check's; it only answers "is something serving /v2/ there". curl's
# exit code picks the hint: 6 (cannot resolve) is the missing /etc/hosts alias of
# a fresh machine, which a rotation — a daemon restart — would not fix. Bounded:
# a registry that accepts TCP and never answers costs --max-time per try (curl
# exit 28, the "did not answer" branch), never a hang.
_gs_lr_wait() { # _gs_lr_wait [created] — "created": the container was made just now
  local _i _rc=0 _state _hint="${_GS_LR_RECREATE_HINT}"
  for ((_i = 1; _i <= _GS_LR_TRIES; _i++)); do
    curl -fks --connect-timeout 2 --max-time 5 "${_GS_LR_URL}" >/dev/null 2>&1 && return 0 || _rc=$?
    if ((_i < _GS_LR_TRIES)); then sleep 1; fi
  done
  if ((_rc == 6)); then
    _gs_lr_fatal "cannot resolve '${_GS_LR_ALIAS}' (curl exit 6) — the registry alias is not in /etc/hosts" \
      "Add '127.0.0.1 ${_GS_LR_ALIAS}' to /etc/hosts (templates/tips/docker-local-registry.md), then run 'make ensure-local-registry'."
  fi
  _state="$(_gs_lr_state)"
  # Re-creating a container made a moment ago from the same cert cannot help
  # (panel round 5, R5-5): what is left is a cert/key mismatch, i.e. a rotation.
  if [[ "${1:-}" == created ]]; then
    _hint="It was just created from the cert on disk, so re-creating it will not help. If the logs show a TLS or cert/key error, rotate: '${_GS_LR_ROTATE}'."
  fi
  _gs_lr_fatal "local registry '${_GS_LR_NAME}' is ${_state} but ${_GS_LR_URL} did not answer after ${_GS_LR_TRIES} tries (curl exit ${_rc})" \
    "Check 'docker logs ${_GS_LR_NAME}'. ${_hint}"
}

_gs_lr_create() {
  [[ -f "${_GS_LR_CRT}" && -f "${_GS_LR_KEY}" ]] || _gs_lr_fatal \
    "local registry certificate missing (${_GS_LR_CRT} / .key)" \
    "Run '${_GS_LR_ROTATE}' — the buildx builder bakes the cert in, so both targets are needed."
  docker run --detach \
    --publish "${_GS_LR_PORT}:5000" \
    --restart=always \
    --mount "type=bind,source=${_GS_LR_DIR}/certs,target=/docker/registry/certs" \
    --env REGISTRY_HTTP_ADDR=0.0.0.0:5000 \
    --env "REGISTRY_HTTP_TLS_CERTIFICATE=/docker/registry/certs/${_GS_LR_ALIAS}.crt" \
    --env "REGISTRY_HTTP_TLS_KEY=/docker/registry/certs/${_GS_LR_ALIAS}.key" \
    --env REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/data \
    --mount "type=bind,source=${_GS_LR_DIR}/data,target=/data" \
    --mount "type=bind,source=${_GS_LR_DIR}/registry,target=/var/lib/registry" \
    --name "${_GS_LR_NAME}" \
    "registry:${GLOBAL_STACK_DOCKER_LOCAL_REGISTRY_VERSION}" >/dev/null
  _gs_lr_wait created
}

_gs_lr_ensure() {
  local _state
  _state="$(_gs_lr_state)"
  case "${_state}" in
    running | restarting) ;;
    exited | created)
      echo "local registry '${_GS_LR_NAME}' is ${_state} — starting it"
      docker start "${_GS_LR_NAME}" >/dev/null
      ;;
    paused)
      echo "local registry '${_GS_LR_NAME}' is paused — unpausing it"
      docker unpause "${_GS_LR_NAME}" >/dev/null
      ;;
    "")
      echo "local registry '${_GS_LR_NAME}' does not exist — creating it"
      _gs_lr_create
      return 0
      ;;
    *)
      _gs_lr_fatal "local registry '${_GS_LR_NAME}' is in state '${_state}'" \
        "${_GS_LR_RECREATE_HINT}"
      ;;
  esac
  _gs_lr_wait
}

case "${1:-}" in
  ensure) _gs_lr_ensure ;;
  create)
    # Assigned, not tested inline: inside `[[ -z "$(…)" ]]` a failed query only
    # exits the substitution's subshell, reads as "missing" and creates anyway.
    _st="$(_gs_lr_state)"
    [[ -z "${_st}" ]] || _gs_lr_fatal "local registry '${_GS_LR_NAME}' already exists (${_st})" \
      "'make ensure-local-registry' starts a stopped one; '${_GS_LR_ROTATE}' re-creates it with a new cert."
    _gs_lr_create
    ;;
  *) _gs_lr_fatal "usage: ${0##*/} ensure|create" ;;
esac
