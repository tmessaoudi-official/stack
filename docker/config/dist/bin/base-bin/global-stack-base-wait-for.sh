#!/bin/bash
set -euo pipefail

_timeout="${GLOBAL_STACK_WAIT_FOR_TIMEOUT:-3600}"

for dependency in "$@"; do
  echo -e "Checking ${dependency}"
  _elapsed=0

  while [ ! -f "${dependency}" ]; do
    if ((_elapsed >= _timeout)); then
      echo "ERROR: timed out waiting for ${dependency} after ${_timeout}s" >&2
      exit 1
    fi
    sleep 1
    ((_elapsed++)) || true
  done

  echo " yes"
done
