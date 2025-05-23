#!/bin/bash

global_stack_base_setup_packages() {
    local PREFIX
    local COMMAND_COUNTER=0
    local -A COMMANDS=()

    while [[ $# -gt 0 ]]; do
        local __CURRENT_ARG__="${1}"

        case "${__CURRENT_ARG__}" in
            --prefix=*)
                PREFIX="$(echo "${__CURRENT_ARG__}" | sed 's/^--[a-zA-Z0-9_-]\+=//')"
                ;;
            --command=*)
                COMMANDS[${COMMAND_COUNTER}]="$(echo "${__CURRENT_ARG__}" | sed 's/^--[a-zA-Z0-9_-]\+=//')"
                ((COMMAND_COUNTER++)) || true
                ;;
            *)
                echo -e "\n ---- (global-stack-setup-packages): Unknown arg passed to global-stack-setup-packages: '${__CURRENT_ARG__}' \n"
                exit 1
                ;;
        esac
        shift
    done

    if [[ -z "${PREFIX:-}" ]]; then
        echo -e "Prefix was not provided !!"
        exit 1
    fi
    if [[ ${#COMMANDS[@]} -eq 0 ]]; then
        echo -e "Command(s) was not provided !!"
        exit 1
    fi

    compgen -A variable | grep "^${PREFIX}_INSTALL_PACKAGE_" | sort | while read -r VARIABLE_NAME; do
        PACKAGE_CONFIG_TEMPLATE="$(echo "${VARIABLE_NAME}" | sed "s/${PREFIX}_INSTALL_PACKAGE_/${PREFIX}_CONFIG_PACKAGE_/")"
        PACKAGE_CONFIG_NAME="$(echo "${PACKAGE_CONFIG_TEMPLATE}" |  sed 's/_VERSION$/_NAME/')"
        PACKAGE_CONFIG_COMMAND_SUFFIX="$(echo "${PACKAGE_CONFIG_TEMPLATE}" | sed 's/_VERSION$/_COMMAND_SUFFIX/')"

        eval "PACKAGE_NAME=\"\${${PACKAGE_CONFIG_NAME}:-}\"; export PACKAGE_NAME"
        eval "PACKAGE_VERSION=\"\${${VARIABLE_NAME}:-}\"; export PACKAGE_VERSION"
        eval "PACKAGE_COMMAND_SUFFIX=\"\${${PACKAGE_CONFIG_COMMAND_SUFFIX}:-}\"; export PACKAGE_COMMAND_SUFFIX"

        if [[ "${PACKAGE_NAME}" = "dummy" ]]; then
            continue
        fi

        if [[ -n "${PACKAGE_NAME}" && -n "${PACKAGE_VERSION}" ]]; then
            for (( INDEX=0; INDEX<${#COMMANDS[@]}; INDEX++ )); do
                eval "${COMMANDS[${INDEX}]}"
            done
        fi
    done
}