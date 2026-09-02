#!/usr/bin/env bash
# check-image-versions.sh — non-fatal host-side preflight (checkpoint 5).
#
# For each image service that builds FROM an UPSTREAM tag pinned by a
# GLOBAL_STACK_IMAGE_<X>_VERSION variable (e.g. `FROM mysql:${GLOBAL_STACK_IMAGE_MYSQL9_VERSION}`),
# compare the active env pin against the `ARG <VAR>=` default baked into that
# service's Dockerfile. "Active" means `.env.local` when it exists and `.env`
# otherwise, because `.env.local` is what `make up` builds from (Makefile:213-215)
# — comparing canonical `.env` reports drift the build never sees and hides
# drift it does. On drift the locally-built image is stale — a plain
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
# Semantics (honest about what is compared): this detects env <-> Dockerfile
# drift — i.e. "you bumped a version but have not run env-scan + rebuild". It
# intentionally reads only host files (no docker, no running container) so it is
# safe and deterministic as an `up` preflight. Every WARN names the env file it
# read, so a surprising result can be traced without guessing which one it was.
# Silence still means clean: a service that could NOT be compared is reported
# rather than skipped, so an examined-nothing run can no longer pass for a
# passed-everything run.
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

# `make up` builds from .env.local (Makefile:213-215), so .env.local is the file
# whose pins decide whether the built image is stale. Reading canonical .env
# instead reports drift the build will never see and hides drift it will hit —
# the two diverge on any machine where a pin was tuned locally. Fall back to
# .env when there is no .env.local, which is the fresh-clone shape.
if [[ -z "${_GS_CIV_ENV_FILE:-}" ]]; then
  if [[ -f "${_GS_CIV_REPO_ROOT}/.env.local" ]]; then
    _GS_CIV_ENV_FILE="${_GS_CIV_REPO_ROOT}/.env.local"
  else
    _GS_CIV_ENV_FILE="${_GS_CIV_REPO_ROOT}/.env"
  fi
fi
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
# Services that pin an upstream tag, i.e. the ones this check is FOR. Counted
# separately from _gs_civ_checked so "nothing to compare" (a tree of purely
# internal FROMs) stays distinguishable from "everything was dropped".
_gs_civ_candidates=0

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

  _gs_civ_candidates=$((_gs_civ_candidates + 1))
  _svc="$(basename "$(dirname "${_df}")")"

  _arg="$(grep -m1 -E "^ARG ${_var}=" "${_df}" 2>/dev/null | cut -d= -f2- || true)"
  _env="$(_gs_civ_env_value "${_var}")"

  # A candidate that cannot be compared was NOT checked, and dropping it in
  # silence produces the exact output of a clean pass while the scan quietly
  # narrows. Name the service and say which side is missing — a renamed or
  # deleted pin is the whole failure mode here.
  if [[ -z "${_arg}" || -z "${_env}" ]]; then
    if [[ -z "${_arg}" && -z "${_env}" ]]; then
      _missing="neither the Dockerfile ARG nor ${_GS_CIV_ENV_FILE} defines it"
    elif [[ -z "${_arg}" ]]; then
      _missing="the Dockerfile has no 'ARG ${_var}=' line"
    else
      _missing="${_GS_CIV_ENV_FILE} does not define it"
    fi
    printf '%sWARN%s: image service %s pins %s but could not be compared — %s; this service was NOT checked.\n' \
      "${_GS_CIV_YELLOW}" "${_GS_CIV_RESET}" "${_svc}" "${_var}" "${_missing}" >&2
    continue
  fi

  _gs_civ_checked=$((_gs_civ_checked + 1))
  if [[ "${_arg}" != "${_env}" ]]; then
    _gs_civ_drift=$((_gs_civ_drift + 1))
    printf '%sWARN%s: image service %s — %s pins %s=%s but Dockerfile ARG=%s; the built image is stale (`make up` will not rebuild it). Run bin/env-scan.sh then `make down-n-rebuild-force-recreate`.\n' \
      "${_GS_CIV_YELLOW}" "${_GS_CIV_RESET}" "${_svc}" "${_GS_CIV_ENV_FILE}" "${_var}" "${_env}" "${_arg}" >&2
  fi
done

# Zero comparisons while candidates existed is NOT clean: every service this
# check exists for was dropped above. Same reasoning as the zero-Dockerfiles
# guard — loud, still non-fatal. Gated on candidates so a tree whose services
# all chain FROM ${GLOBAL_STACK_VERSION} stays correctly silent.
if [[ "${_gs_civ_checked}" -eq 0 && "${_gs_civ_candidates}" -gt 0 ]]; then
  printf '%sWARN%s: %d image service(s) pin an upstream tag but NONE could be compared against %s — the version check did NOT run.\n' \
    "${_GS_CIV_YELLOW}" "${_GS_CIV_RESET}" "${_gs_civ_candidates}" "${_GS_CIV_ENV_FILE}" >&2
fi

if [[ "${_gs_civ_drift}" -gt 0 ]]; then
  printf '%sWARN%s: %d of %d image service(s) have .env<->Dockerfile version drift (see above) — env-scan + rebuild recommended.\n' \
    "${_GS_CIV_YELLOW}" "${_GS_CIV_RESET}" "${_gs_civ_drift}" "${_gs_civ_checked}" >&2
fi

exit 0
