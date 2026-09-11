#!/bin/bash

set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

# NOT `SECONDS`: that is a bash SPECIAL variable. Assigning to it sets the
# counter's ORIGIN, and every later read returns the assigned value PLUS the
# seconds that have passed since — so the two writes below, which sit behind
# `$(date …)` command substitutions, print a number that grows with how long
# this script takes. shellcheck has no rule for special-variable clobber, so
# only bin/tests/startup-prologue.test.sh §44b catches it: with a `date` that
# sleeps 2s, a DURATION of 5 was written as 9. HOURS and MINUTES are ordinary
# names and were never affected.
HOURS="$((${1} / 3600))"
MINUTES="$(((${1} % 3600) / 60))"
_SECS="$(((${1} % 3600) % 60))"
echo -e "\n$(date '+%d-%m-%Y %H:%M:%S') - ${HOURS} hours and ${MINUTES} minutes and ${_SECS} seconds elapsed."
echo -e "\nInstallation complete -- seems like it went well !"

if [ "${3:-update}" = "create" ]; then
  echo -e "$(date '+%d-%m-%Y %H:%M:%S'): $(echo "${2}") - ${HOURS} hours and ${MINUTES} minutes and ${_SECS} seconds elapsed." > "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
  chmod o+w "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
else
  echo -e "$(date '+%d-%m-%Y %H:%M:%S'): $(echo "${2}") - ${HOURS} hours and ${MINUTES} minutes and ${_SECS} seconds elapsed." >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
fi
