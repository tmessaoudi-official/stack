#!/usr/bin/env bash
# Tests for the 01mongo9 kernel-7 workaround (SERVER-121912).
#
# mongo:9.0.x sets `ENV GLIBC_TUNABLES glibc.pthread.rseq=0` upstream. On a
# kernel >= 6.19 that very tunable is what makes mongod 9.0.2 refuse to start
# ("Linux kernel versions 6.19 and newer has a known incompatibility"); with it
# cleared mongod starts, serves, and survives a restart [measured 2026-10-01,
# kernel 7.0.0-34]. So docker/images/01mongo9 must reset it, and nothing that
# runs the service may put it back.
#
#   1  the Dockerfile resets the tunable, after the FROM, to the empty string
#   2  no compose file for the service sets it
#   3  the BUILT image carries it empty (skipped, loudly, when no image exists)
#   4  opt-in (GS_MONGO9_PROBE=1): the built image really starts mongod
#
# Static checks read the file with comment lines stripped, so a comment that
# quotes the old value cannot satisfy or fail a check.
# shellcheck disable=SC2329  # the check functions are invoked indirectly, by name
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${GS_MONGO9_TEST_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
DOCKERFILE="${ROOT}/docker/images/01mongo9/Dockerfile"
COMPOSE="${ROOT}/docker/images/01mongo9/docker-compose.yaml"
IMAGE="${GS_MONGO9_TEST_IMAGE:-global_stack-01mongo9:latest}"

PASS=0
FAIL=0
ok() {
  PASS=$((PASS + 1))
  printf '  ✓  %s\n' "$1"
}
ko() {
  FAIL=$((FAIL + 1))
  printf '  ✗  %s\n' "$1"
}
check() { # check <name> <command...>
  local name="$1"
  shift
  if "$@"; then ok "${name}"; else ko "${name}"; fi
}

# Executable lines only: drop comments, so prose never decides a verdict.
_live() { grep -v -E '^[[:space:]]*#' "$1" 2>/dev/null; }

# --- 1. Dockerfile ------------------------------------------------------------
_df_resets_after_from() {
  local from_line env_line
  from_line="$(_live "${DOCKERFILE}" | grep -n -E '^FROM[[:space:]]' | head -1 | cut -d: -f1)"
  # Last GLIBC_TUNABLES assignment decides the image's value.
  env_line="$(_live "${DOCKERFILE}" | grep -n -E '^ENV[[:space:]]+GLIBC_TUNABLES' | tail -1)"
  [[ -n "${from_line}" && -n "${env_line}" ]] || return 1
  [[ "${env_line%%:*}" -gt "${from_line}" ]] || return 1
  # Value must be empty: `GLIBC_TUNABLES=`, `GLIBC_TUNABLES=""` or `GLIBC_TUNABLES=''`.
  [[ "${env_line}" =~ GLIBC_TUNABLES=(\"\"|\'\')?[[:space:]]*$ ]]
}
_df_never_sets_rseq() { ! _live "${DOCKERFILE}" | grep -q 'rseq'; }

echo "-- 1. Dockerfile"
[[ -f "${DOCKERFILE}" ]] || {
  ko "Dockerfile present: ${DOCKERFILE}"
  echo "ABORT: nothing to test"
  exit 1
}
check "1a ENV GLIBC_TUNABLES is reset to empty after the FROM" _df_resets_after_from
check "1b no live line re-enables rseq" _df_never_sets_rseq

# --- 2. compose ---------------------------------------------------------------
echo "-- 2. compose"
_compose_clean() { ! _live "${COMPOSE}" | grep -q 'GLIBC_TUNABLES'; }
if [[ -f "${COMPOSE}" ]]; then
  check "2a compose does not set GLIBC_TUNABLES (it would override the image)" _compose_clean
else
  ko "compose file present: ${COMPOSE}"
fi

# --- 3. built image -----------------------------------------------------------
echo "-- 3. built image"
if command -v docker >/dev/null 2>&1 && docker image inspect "${IMAGE}" >/dev/null 2>&1; then
  _image_value_empty() {
    local v
    v="$(docker image inspect "${IMAGE}" --format '{{range .Config.Env}}{{println .}}{{end}}' | grep '^GLIBC_TUNABLES=' | tail -1)"
    [[ "${v}" == "GLIBC_TUNABLES=" ]]
  }
  check "3a ${IMAGE} carries GLIBC_TUNABLES empty (rebuild it after a Dockerfile change)" _image_value_empty
else
  echo "  -  SKIPPED: no docker or no image ${IMAGE} — the BUILT-image guarantee is UNCERTIFIED-BY-EXECUTION"
fi

# --- 4. opt-in: mongod really starts -----------------------------------------
echo "-- 4. start probe"
if [[ "${GS_MONGO9_PROBE:-0}" == "1" ]]; then
  _probe_starts() {
    local out
    out="$(timeout 60 docker run --rm --entrypoint sh "${IMAGE}" -c \
      'mkdir -p /tmp/db && mongod --dbpath /tmp/db --bind_ip 127.0.0.1 --fork --logpath /tmp/m.log >/dev/null 2>&1; sleep 3; mongosh --quiet --eval "db.runCommand({ping:1}).ok"' 2>&1)"
    [[ "${out##*$'\n'}" == "1" ]]
  }
  check "4a mongod starts and answers ping in the built image" _probe_starts
else
  echo "  -  SKIPPED: set GS_MONGO9_PROBE=1 to start a throwaway mongod (needs the built image)"
fi

echo
if [[ ${FAIL} -eq 0 ]]; then
  echo "ALL PASSED ✓ ${PASS} / $((PASS + FAIL))"
  exit 0
fi
echo "FAILED ✗ ${FAIL} of $((PASS + FAIL))"
exit 1
