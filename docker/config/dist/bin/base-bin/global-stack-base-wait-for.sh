#!/bin/bash
set -euo pipefail

_timeout="${GLOBAL_STACK_WAIT_FOR_TIMEOUT:-3600}"

for dependency in "$@"; do
  echo -e "Checking ${dependency}"
  _elapsed=0

  # The error token is normally derived from the success path. successes/web-server
  # is the one marker with no matching producer: caddy, nginx and httpd are
  # interchangeable ALTERNATIVES that all signal it, so each writes its OWN error
  # token instead (the documented exception to the token invariant). Poll all
  # three IN ADDITION to the derived path — a web server that is not enabled
  # writes nothing, each producer clears its own stale token at startup, and
  # `make down` clears errors/*. Keeping the derived path means a future
  # errors/web-server producer is still honoured.
  _error_paths=("${dependency/\/successes\//\/errors\/}")
  if [[ "${dependency}" == */successes/web-server ]]; then
    # Written out in full so each token appears as a greppable `errors/<name>`
    # literal: bin/tests/startup-prologue.test.sh §21c reads the tokens from the
    # three compose files and asserts this file names every one of them, so a
    # rename on either side reds instead of silently uncoupling.
    _tools_root="${dependency%/successes/web-server}"
    _error_paths+=(
      "${_tools_root}/errors/caddy"
      "${_tools_root}/errors/nginx"
      "${_tools_root}/errors/httpd"
    )
  fi

  while [ ! -f "${dependency}" ]; do
    for _error_path in "${_error_paths[@]}"; do
      if [[ "${_error_path}" != "${dependency}" && -f "${_error_path}" ]]; then
        echo "ERROR: dependency failed — error token found: ${_error_path}" >&2
        exit 1
      fi
    done
    if ((_elapsed >= _timeout)); then
      echo "ERROR: timed out waiting for ${dependency} after ${_timeout}s" >&2
      exit 1
    fi
    sleep 1
    ((_elapsed++)) || true
  done

  echo " yes"
done
