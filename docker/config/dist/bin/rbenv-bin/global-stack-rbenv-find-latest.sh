#!/bin/bash
set -xeE -o pipefail

RBENV_CURRENT_RUBY_VERSION=""
if [ -n "${1}" ]; then
  if [ -e "${RBENV_ROOT}/versions/${1}" ]; then
    RBENV_CURRENT_RUBY_VERSION="${1}"
  else
    RBENV_CURRENT_RUBY_VERSION="$(rbenv install --list-all | grep "^${1}" | cut -c1- | tail -n1 || true)"
  fi
fi

# No match is a hard error, not a fallback. This used to echo the raw pin, so a pin
# newer than this ruby-build's definitions reached the gate as a "new version" and the
# start script deleted the working ruby before `rbenv install` failed on it (pin-audit
# A1, startup-prologue.test.sh §57). Exiting non-zero with nothing on stdout fails the
# caller's assignment under set -eE: the prologue writes the error token and the
# installed ruby is left alone. Remedy: bump GLOBAL_STACK_RBENV_RUBY_BUILD_VERSION.
if [[ "" = "${RBENV_CURRENT_RUBY_VERSION}" ]]; then
  printf 'FATAL: no installed ruby and no ruby-build definition matches "%s" - bump GLOBAL_STACK_RBENV_RUBY_BUILD_VERSION or fix the pin\n' \
    "${1:-}" >&2
  exit 1
fi

echo "${RBENV_CURRENT_RUBY_VERSION}"
