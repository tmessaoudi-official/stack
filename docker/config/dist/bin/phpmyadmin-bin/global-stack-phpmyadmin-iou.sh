#!/bin/bash

set -xeE
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** phpmyadmin global-stack-phpmyadmin-iou.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}
PHPMYADMIN_LATEST_RELEASE=${GLOBAL_STACK_PHPMYADMIN_VERSION}
PHPMYADMIN_CURRENT_RELEASE=$([[ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin" ]] && cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin" || echo "null")

set -xeE -o pipefail

if [ "${PHPMYADMIN_LATEST_RELEASE}" != "${PHPMYADMIN_CURRENT_RELEASE}" ]; then
  rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin" "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin"
  mkdir -p "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin"

  echo -e "\nUpdating phpmyadmin from ${PHPMYADMIN_CURRENT_RELEASE} to ${PHPMYADMIN_LATEST_RELEASE} ..."

  if [ "${PHPMYADMIN_CURRENT_RELEASE}" != "" ]; then
    rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin${PHPMYADMIN_CURRENT_RELEASE}.zip"
  fi

  mkdir -p "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin-${PHPMYADMIN_LATEST_RELEASE}"

  sudo chmod -R a+rwx "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/"
  sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/"

  wget "https://files.phpmyadmin.net/phpMyAdmin/${PHPMYADMIN_LATEST_RELEASE}/phpMyAdmin-${PHPMYADMIN_LATEST_RELEASE}-all-languages.zip" -O "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin${PHPMYADMIN_LATEST_RELEASE}.zip"

  cd "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin"
  unzip "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin${PHPMYADMIN_LATEST_RELEASE}.zip"
  rsync -rav "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpMyAdmin-${PHPMYADMIN_LATEST_RELEASE}-all-languages/" "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/"
else
  echo -e "\nphpmyadmin is already latest"
fi

global-stack-phpmyadmin-sync-dist.sh
rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin${PHPMYADMIN_LATEST_RELEASE}.zip"
rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin${PHPMYADMIN_LATEST_RELEASE}/"
rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin-${PHPMYADMIN_LATEST_RELEASE}/"
rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpMyAdmin-${PHPMYADMIN_LATEST_RELEASE}-all-languages"
