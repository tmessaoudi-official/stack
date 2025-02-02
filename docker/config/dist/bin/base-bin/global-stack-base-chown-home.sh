#!/bin/bash

GLOBAL_STACK_DOCKER_USER_CONFIG="${GLOBAL_STACK_DOCKER_USER_CONFIG:-"/home/${GLOBAL_STACK_DOCKER_USER_ID:-}:${GLOBAL_STACK_DOCKER_GROUP_ID:-}"}"

echo -e "\nGLOBAL_STACK_DOCKER_USER_CONFIG : '${GLOBAL_STACK_DOCKER_USER_CONFIG}' \n"

if [[ "${GLOBAL_STACK_DOCKER_USER_CONFIG:-}" != ":" && "${GLOBAL_STACK_DOCKER_USER_CONFIG:-}" != "" ]]; then
    IFS=',' read -ra GLOBAL_STACK_BASE_USER_HOME_GROUP_PAIRS <<< "${GLOBAL_STACK_DOCKER_USER_CONFIG}"

    for GLOBAL_STACK_BASE_USER_HOME_GROUP_PAIR in "${GLOBAL_STACK_BASE_USER_HOME_GROUP_PAIRS[@]}"; do

        echo -e "\nGLOBAL_STACK_BASE_USER_HOME_GROUP_PAIR : '${GLOBAL_STACK_BASE_USER_HOME_GROUP_PAIR}' \n"

        IFS=':' read -r GLOBAL_STACK_BASE_USER_HOME GLOBAL_STACK_BASE_GROUP <<< "${GLOBAL_STACK_BASE_USER_HOME_GROUP_PAIR}"

        echo -e "\nGLOBAL_STACK_BASE_USER_HOME : '${GLOBAL_STACK_BASE_USER_HOME}' \n"
        echo -e "\nGLOBAL_STACK_BASE_GROUP : '${GLOBAL_STACK_BASE_GROUP}' \n"
        
        GLOBAL_STACK_BASE_USERNAME=$(basename "${GLOBAL_STACK_BASE_USER_HOME}")

        echo -e "\nGLOBAL_STACK_BASE_USERNAME : '${GLOBAL_STACK_BASE_USERNAME}' \n"

        if [[ -d "${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/home/user" && -d "${GLOBAL_STACK_BASE_USER_HOME}" ]]; then
            echo -e "\nrsynching ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/home/user/ into ${GLOBAL_STACK_BASE_USER_HOME} \n"
            sudo rsync -raz --ignore-times \
                ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/home/user/ \
                ${GLOBAL_STACK_BASE_USER_HOME}
        fi

        if [[ -d "${GLOBAL_STACK_BASE_USER_HOME}" ]]; then
            echo -e "\nSetting permissions ${GLOBAL_STACK_BASE_USERNAME}:${GLOBAL_STACK_BASE_GROUP} to ${GLOBAL_STACK_BASE_USER_HOME}/ \n"
            # Set ownership for the user's home directory
            sudo chown -R "${GLOBAL_STACK_BASE_USERNAME}:${GLOBAL_STACK_BASE_GROUP}" "${GLOBAL_STACK_BASE_USER_HOME}/"

            # Set permissions for files and directories
            find "${GLOBAL_STACK_BASE_USER_HOME}/" -type f -exec sudo chmod 600 {} +
            find "${GLOBAL_STACK_BASE_USER_HOME}/" -type d -exec sudo chmod 700 {} +

            # Make CLI plugins executable if the directory exists
            cli_plugins_dir="${GLOBAL_STACK_BASE_USER_HOME}/.docker/cli-plugins/"
            if [[ -d "${cli_plugins_dir}" ]]; then
                find "${cli_plugins_dir}" -type f -exec sudo chmod a+x {} +
            fi

            eval "$(ssh-agent -s)" 1> /dev/null 2> /dev/null
        fi
    done
fi