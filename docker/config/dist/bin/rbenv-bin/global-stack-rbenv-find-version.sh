#!/bin/bash
set -xeE -o pipefail

if [ -n "${1}" ]; then
  if [ -e "${RBENV_ROOT}/versions/${1}" ]; then
    echo "${1}"
  else
    # SC2005 (useless echo) and SC2010 (ls|grep) are pre-existing and intentional:
    # the echo wrapper is load-bearing — it masks the grep exit code (1 on no match)
    # under set -e / pipefail. Do NOT remove the echo to "fix" SC2005.
    # shellcheck disable=SC2005,SC2010
    echo "$(ls "${RBENV_ROOT}/versions" | grep "^${1}" | cut -c1- | tail -n1 || true)"
  fi
fi
