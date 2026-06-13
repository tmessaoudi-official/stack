#!/bin/bash
# iou = install-or-upgrade

set -xeE
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

PHPMYADMIN_CURRENT_RELEASE=$([[ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin" ]] && cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin" || echo "null")

set -xeE -o pipefail

if [ "${GLOBAL_STACK_PHPMYADMIN_VERSION}" != "${PHPMYADMIN_CURRENT_RELEASE}" ]; then
  rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpmyadmin" "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin"
  mkdir -p "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin"

  echo -e "\nUpdating phpmyadmin from ${PHPMYADMIN_CURRENT_RELEASE} to ${GLOBAL_STACK_PHPMYADMIN_VERSION} ..."

  mkdir -p "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin-${GLOBAL_STACK_PHPMYADMIN_VERSION}"

  sudo chmod -R a+rwx "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/"
  sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/"

  cd "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin"

  if [[ "${GLOBAL_STACK_PHPMYADMIN_TYPE_VERSION}" == "release" ]]; then
    curl --connect-timeout 30 --max-time 300 -fsSL -o "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin${GLOBAL_STACK_PHPMYADMIN_VERSION}.zip" "https://files.phpmyadmin.net/phpMyAdmin/${GLOBAL_STACK_PHPMYADMIN_VERSION}/phpMyAdmin-${GLOBAL_STACK_PHPMYADMIN_VERSION}-all-languages.zip"
    unzip "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin${GLOBAL_STACK_PHPMYADMIN_VERSION}.zip"
    rsync -rav "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpMyAdmin-${GLOBAL_STACK_PHPMYADMIN_VERSION}-all-languages/" "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/"
  elif [[ "${GLOBAL_STACK_PHPMYADMIN_TYPE_VERSION}" == "branch" ]]; then
    PHPMYADMIN_REF_VALUE="archive/refs/heads/${GLOBAL_STACK_PHPMYADMIN_VERSION}"
    curl --connect-timeout 30 --max-time 300 -LsS "https://github.com/phpmyadmin/phpmyadmin/${PHPMYADMIN_REF_VALUE}.tar.gz" -o "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin${GLOBAL_STACK_PHPMYADMIN_VERSION}.tar.gz"
    # --directory="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpMyAdmin-${GLOBAL_STACK_PHPMYADMIN_VERSION}-all-languages/" --strip-components=1
    tar -xzf "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin${GLOBAL_STACK_PHPMYADMIN_VERSION}.tar.gz"
    rsync -rav "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin-${GLOBAL_STACK_PHPMYADMIN_VERSION}/" "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/"
  elif [[ "${GLOBAL_STACK_PHPMYADMIN_TYPE_VERSION}" == "tag" ]]; then
    PHPMYADMIN_REF_VALUE="archive/refs/tags/${GLOBAL_STACK_PHPMYADMIN_VERSION}"
    curl --connect-timeout 30 --max-time 300 -LsS "https://github.com/phpmyadmin/phpmyadmin/${PHPMYADMIN_REF_VALUE}.tar.gz" -o "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin${GLOBAL_STACK_PHPMYADMIN_VERSION}.tar.gz"
    tar -xzf "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin${GLOBAL_STACK_PHPMYADMIN_VERSION}.tar.gz"
    rsync -rav "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin-${GLOBAL_STACK_PHPMYADMIN_VERSION}/" "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/"
  elif [[ "${GLOBAL_STACK_PHPMYADMIN_TYPE_VERSION}" == "commit" ]]; then
    PHPMYADMIN_REF_VALUE="archive/${GLOBAL_STACK_PHPMYADMIN_VERSION}"
    curl --connect-timeout 30 --max-time 300 -LsS "https://github.com/phpmyadmin/phpmyadmin/${PHPMYADMIN_REF_VALUE}.tar.gz" -o "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin${GLOBAL_STACK_PHPMYADMIN_VERSION}.tar.gz"
    tar -xzf "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin${GLOBAL_STACK_PHPMYADMIN_VERSION}.tar.gz"
    rsync -rav "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin-${GLOBAL_STACK_PHPMYADMIN_VERSION}/" "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/"
  fi
else
  echo -e "\nphpmyadmin is already latest"
fi

rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin${GLOBAL_STACK_PHPMYADMIN_VERSION}.zip"
rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin${GLOBAL_STACK_PHPMYADMIN_VERSION}.tar.gz"
rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin${GLOBAL_STACK_PHPMYADMIN_VERSION}/"
rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpmyadmin-${GLOBAL_STACK_PHPMYADMIN_VERSION}/"
rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/phpmyadmin/phpMyAdmin-${GLOBAL_STACK_PHPMYADMIN_VERSION}-all-languages"
