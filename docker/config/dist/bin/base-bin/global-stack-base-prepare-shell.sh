#!/bin/bash
set -euo pipefail

# Uncomment to set GPG_TTY in the .shellrc file
# echo 'GPG_TTY=$(tty)' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

# Source mise.shellrc if it exists and add activation to .she
eval "$(ssh-agent -s)"

mise_shellrc="${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/mise.shellrc"
user_shellrc="/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

if [[ -f "${mise_shellrc}" ]]; then
    source "${mise_shellrc}"
    {
        echo "source \"${mise_shellrc}\""
        echo 'eval "$(mise activate ${GLOBAL_STACK_SHELL})"'
    } >> "${user_shellrc}"
    eval "$(mise activate ${GLOBAL_STACK_SHELL})"
fi

if [[ -n "${GLOBAL_STACK_DOCKER_USER_EMAIL}" ]]; then
    git config --global user.email "${GLOBAL_STACK_DOCKER_USER_EMAIL}"
fi


if [[ -n "${GLOBAL_STACK_DOCKER_USER_NAME}" ]]; then
    git config --global user.name "${GLOBAL_STACK_DOCKER_USER_NAME}"
fi