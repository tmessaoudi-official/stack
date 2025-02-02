#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** rbenv ($([[ -n "${RUBY_VERSION_AS:-}" && "" != "${RUBY_VERSION_AS:-}" ]] && echo "${RUBY_VERSION_AS:-}" || echo "${RUBY_VERSION:-}")) ${RBENV_MODE:-} global-stack-rbenv-iou.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}
