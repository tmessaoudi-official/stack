#!/bin/bash
set -euo pipefail

_timeout="${GLOBAL_STACK_WAIT_FOR_TIMEOUT:-3600}"

for dependency in "$@"; do
  echo -e "Checking ${dependency}"
  _elapsed=0

  while [ ! -f "${dependency}" ]; do
    _error_path="${dependency/\/successes\//\/errors\/}"
    if [[ "${_error_path}" != "${dependency}" && -f "${_error_path}" ]]; then
      echo "ERROR: dependency failed — error token found: ${_error_path}" >&2
      exit 1
    fi
    if ((_elapsed >= _timeout)); then
      echo "ERROR: timed out waiting for ${dependency} after ${_timeout}s" >&2
      exit 1
    fi
    sleep 1
    ((_elapsed++)) || true
  done

  echo " yes"
done
