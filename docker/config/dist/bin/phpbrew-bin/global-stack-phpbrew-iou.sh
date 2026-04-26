#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** phpbrew (${PHP_VERSION_AS}) ${PHPBREW_MODE:-} global-stack-phpbrew-iou.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

# PHPBREW_LATEST_VERSION=$(curl --silent https://api.github.com/repos/phpbrew/phpbrew/releases/latest | jq .name -r | sed "s/Release //g" )

if [ ! -d "${PHPBREW_SRC}/.git" ]; then
	sudo chmod -R a+rwx "${PHPBREW_SRC}"
	sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}" "${PHPBREW_SRC}"
	git clone --progress --verbose --branch ${GLOBAL_STACK_PHPBREW_VERSION} https://github.com/phpbrew/phpbrew.git --depth 1 "${PHPBREW_SRC}"
	sudo chmod a+x "${PHPBREW_SRC}"/bin/phpbrew
  if [[ "${GLOBAL_STACK_PHPBREW_VERSION}" != "2.2.0" && -d ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew/source/ ]]; then
    echo "There is an override for phpbrew source, but it is not used for version ${GLOBAL_STACK_PHPBREW_VERSION}."
    exit 1
  fi

  if [[ -d ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew/source/ ]]; then
    rsync -rav ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew/source/ "${PHPBREW_SRC}"
  fi
  cd "${PHPBREW_SRC}" && php "${COMPOSER_HOME}/bin/composer" --ignore-platform-reqs update
  git -C "${PHPBREW_SRC}" config core.fileMode false
fi

echo -e "\n**** phpbrew init"
phpbrew init

# echo -e "\n**** phpbrbew self-update"
# phpbrew self-update
echo -e "\n**** phpbrbew update"
phpbrew update || true
echo -e "\n**** phpbrbew update --old"
phpbrew update --old || true

#echo -e "\n**** phpbrew lookup-prefix debian"
#phpbrew lookup-prefix debian