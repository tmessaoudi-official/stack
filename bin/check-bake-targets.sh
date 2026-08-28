#!/usr/bin/env bash
# check-bake-targets.sh — fatal preflight: the bake file must name something to build.
#
# `generate-buildx` produces ${BUILDX_BAKE_FILE} by redirecting
# `docker buildx bake --print` through a sub-make that carries
# `--ignore-errors --keep-going`. That sub-make therefore exits 0 even when bake
# fails, while the `>` redirect has already truncated the file — so a failed
# generation leaves a 0-byte bake file and still "succeeds".
#
# `make build` then feeds that file to `jq -r '.group.default.targets[]'`, and
# jq exits 0 with no output on empty input. The while loop iterates zero times,
# the failure file stays empty, and the recipe prints "=== Build complete ==="
# and exits 0 — after which `up` starts the stack on stale or absent images with
# no error anywhere in the transcript.
#
# This turns that silent zero-iteration case into a loud, non-zero failure.
#
# Contract: READ-ONLY. Exits 1 (fatal) when nothing would be built — unlike
# check-image-versions.sh, which is a non-fatal warner. Callers must NOT
# suffix it with `|| true`; refusing to build is the entire point.
#
# Usage: check-bake-targets.sh [bake-file]

set -eEuo pipefail

# Defaults resolve from THIS script's location, never from $PWD — a relative
# default makes the check vacuous from any other cwd, which is the exact defect
# fixed in check-image-versions.sh (661cef3).
_GS_CBT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_GS_CBT_REPO_ROOT="$(cd "${_GS_CBT_SCRIPT_DIR}/.." && pwd)"
_GS_CBT_BAKE_FILE="${1:-${_GS_CBT_REPO_ROOT}/docker-bake.local.json}"

if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
  _GS_CBT_RED=$'\033[31m'
  _GS_CBT_BOLD=$'\033[1m'
  _GS_CBT_RESET=$'\033[0m'
else
  _GS_CBT_RED='' _GS_CBT_BOLD='' _GS_CBT_RESET=''
fi

_gs_cbt_fatal() {
  printf '%s%sFATAL:%s %s\n' "${_GS_CBT_BOLD}" "${_GS_CBT_RED}" "${_GS_CBT_RESET}" "$1" >&2
  printf '       %s\n' "$2" >&2
  exit 1
}

if [[ ! -f "${_GS_CBT_BAKE_FILE}" ]]; then
  _gs_cbt_fatal \
    "bake file not found: ${_GS_CBT_BAKE_FILE}" \
    "Run 'make generate-buildx' and check its output before building."
fi

if [[ ! -s "${_GS_CBT_BAKE_FILE}" ]]; then
  _gs_cbt_fatal \
    "bake file is empty: ${_GS_CBT_BAKE_FILE} — no build targets" \
    "'docker buildx bake --print' failed and left a truncated file. Its sub-make runs with --ignore-errors, so the failure was not propagated. Run 'make generate-buildx' and read the error."
fi

# `jq -e` sets exit status from the last output value, so a false result and a
# parse error are both non-zero — which is what we want here.
if ! jq -e '(.group.default.targets // []) | length > 0' \
  "${_GS_CBT_BAKE_FILE}" >/dev/null 2>&1; then
  _gs_cbt_fatal \
    "bake file lists no build targets: ${_GS_CBT_BAKE_FILE}" \
    "It is unparseable, or .group.default.targets is missing or empty — 'make build' would iterate zero times and still report success. Run 'make generate-buildx' and read the error."
fi

exit 0
