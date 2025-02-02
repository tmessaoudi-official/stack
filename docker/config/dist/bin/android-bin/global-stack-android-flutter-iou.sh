#!/bin/bash

set -xeEu -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap '' PIPE SIGPIPE SIGHUP
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR
stackCatch() {
  if [ "${1}" != "0" ] && [ "${1}" != "141" ] && [ "${1}" != "1" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** global-stack-android-flutter-iou.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

if [ ! -d "${FLUTTER_HOME}/.git" ]; then
	sudo chmod -R a+rwx "${FLUTTER_HOME}" "${PUB_CACHE}"
	sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}" "${FLUTTER_HOME}" "${PUB_CACHE}"
	git clone --progress --verbose --branch ${GLOBAL_STACK_ANDROID_FLUTTER_VERSION} https://github.com/flutter/flutter.git --depth 1 "${FLUTTER_HOME}"
fi

# git -C "${FLUTTER_HOME}" branch --set-upstream-to=origin/stable stable
# git -C "${FLUTTER_HOME}" config core.fileMode false
# git -C "${FLUTTER_HOME}" fetch --progress --verbose
# git -C "${FLUTTER_HOME}" pull --progress --verbose --rebase

flutter config --android-sdk "${ANDROID_HOME}"
flutter precache
flutter doctor -v

echo "$(flutter --version | grep Flutter | sed 's/Flutter //' | sed 's/ .*//')" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter"