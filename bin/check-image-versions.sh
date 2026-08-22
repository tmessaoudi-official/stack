#!/usr/bin/env bash
# check-image-versions.sh — non-fatal host-side preflight (checkpoint 5).
#
# For each image service that builds FROM an UPSTREAM tag pinned by a
# GLOBAL_STACK_IMAGE_<X>_VERSION variable (e.g. `FROM mysql:${GLOBAL_STACK_IMAGE_MYSQL9_VERSION}`),
# compare the canonical `.env` pin against the `ARG <VAR>=` default baked into
# that service's Dockerfile. On drift the locally-built image is stale — a plain
# `make up` will NOT rebuild it because the local image tag is the invariant
# ${GLOBAL_STACK_VERSION} (e.g. 2_0_0_local), not the upstream tag — so WARN and
# point at the fix.
#
# Scope: services whose FROM references GLOBAL_STACK_IMAGE_*_VERSION are the only
# ones that carry an external upstream tag; every other service chains
# `FROM ${GLOBAL_STACK_VERSION}` off the local registry and is refreshed whenever
# the chain is rebuilt, so it needs no image-tag warning. The selection is
# self-discovering: a new image service is covered the moment its Dockerfile
# lands, with no list to maintain here.
#
# Semantics (honest about what is compared): this detects `.env` <-> Dockerfile
# drift — i.e. "you bumped a version in .env but have not run env-scan + rebuild".
# It intentionally reads only host files (no docker, no running container) so it
# is safe and deterministic as an `up` preflight.
#
# Contract: READ-ONLY and ALWAYS exits 0. It must never block `make up`
# (the Makefile also calls it with `|| true` as a second guard).

set -eEuo pipefail

# Defaults resolve from THIS script's location, never from $PWD. A relative
# default made the scan vacuous from any other cwd — nothing compared, nothing
# printed, exit 0, which is the exact signature of a clean run. Same defect as
# the hardcoded --env-file fixed in 661cef3.
_GS_CIV_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_GS_CIV_REPO_ROOT="$(cd "${_GS_CIV_SCRIPT_DIR}/.." && pwd)"

_GS_CIV_ENV_FILE="${_GS_CIV_ENV_FILE:-${_GS_CIV_REPO_ROOT}/.env}"
_GS_CIV_IMAGES_DIR="${_GS_CIV_IMAGES_DIR:-${_GS_CIV_REPO_ROOT}/docker/images}"

# NO_COLOR (no-color.org); color only when stderr is a terminal.
if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
  _GS_CIV_YELLOW=$'\033[33m'
  _GS_CIV_RESET=$'\033[0m'
else
  _GS_CIV_YELLOW=''
  _GS_CIV_RESET=''
fi

# Last-definition-wins value of VAR in the env file, or empty when absent.
_gs_civ_env_value() {
  local _var="${1:-}"
  [[ -z "${_var}" ]] && return 0
  grep -E "^${_var}=" "${_GS_CIV_ENV_FILE}" 2>/dev/null | tail -n1 | cut -d= -f2- || true
}

_gs_civ_drift=0
_gs_civ_checked=0

shopt -s nullglob
_GS_CIV_DOCKERFILES=("${_GS_CIV_IMAGES_DIR}"/*/Dockerfile)

# Zero Dockerfiles is NOT "clean" — the scan never ran (dir missing, renamed, or
# an override pointing at the wrong tree). Zero *drift* stays silent (that is the
# preflight contract); zero *comparisons possible* must be loud, or a check that
# examined nothing is indistinguishable from a check that passed.
if [[ "${#_GS_CIV_DOCKERFILES[@]}" -eq 0 ]]; then
  printf '%sWARN%s: no image Dockerfile found under %s — the .env<->Dockerfile version check did NOT run.\n' \
    "${_GS_CIV_YELLOW}" "${_GS_CIV_RESET}" "${_GS_CIV_IMAGES_DIR}" >&2
  exit 0
fi

for _df in "${_GS_CIV_DOCKERFILES[@]}"; do
  # Only image services that build FROM an upstream GLOBAL_STACK_IMAGE_*_VERSION tag.
  _from="$(grep -m1 -E '^FROM .*\$\{GLOBAL_STACK_IMAGE_[A-Za-z0-9_]+_VERSION' "${_df}" 2>/dev/null || true)"
  [[ -z "${_from}" ]] && continue

  _var="$(printf '%s' "${_from}" | sed -nE 's/.*\$\{(GLOBAL_STACK_IMAGE_[A-Za-z0-9_]+_VERSION)(:-[^}]*)?\}.*/\1/p' | head -n1)"
  [[ -z "${_var}" ]] && continue

  _arg="$(grep -m1 -E "^ARG ${_var}=" "${_df}" 2>/dev/null | cut -d= -f2- || true)"
  _env="$(_gs_civ_env_value "${_var}")"

  # Cannot compare unless both sides are readable — skip silently.
  [[ -z "${_arg}" || -z "${_env}" ]] && continue

  _gs_civ_checked=$((_gs_civ_checked + 1))
  if [[ "${_arg}" != "${_env}" ]]; then
    _gs_civ_drift=$((_gs_civ_drift + 1))
    _svc="$(basename "$(dirname "${_df}")")"
    printf '%sWARN%s: image service %s — .env pins %s=%s but Dockerfile ARG=%s; the built image is stale (`make up` will not rebuild it). Run bin/env-scan.sh then `make down-n-rebuild-force-recreate`.\n' \
      "${_GS_CIV_YELLOW}" "${_GS_CIV_RESET}" "${_svc}" "${_var}" "${_env}" "${_arg}" >&2
  fi
done

if [[ "${_gs_civ_drift}" -gt 0 ]]; then
  printf '%sWARN%s: %d of %d image service(s) have .env<->Dockerfile version drift (see above) — env-scan + rebuild recommended.\n' \
    "${_GS_CIV_YELLOW}" "${_GS_CIV_RESET}" "${_gs_civ_drift}" "${_gs_civ_checked}" >&2
fi

exit 0
