#!/bin/bash

set -xeEu
shopt -s extdebug
IFS=$'\n\t'
trap '' PIPE SIGPIPE SIGHUP
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR
stackCatch() {
  if [ "${1}" != "0" ] && [ "${1}" != "141" ] && [ "${1}" != "1" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** global-stack-android-setup-dit.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}
  
for CONFIG_FILE in "${ANDROID_SDK_HOME}"/.android/avd/*.avd/config.ini; do
    cp -f ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/android-avd-conf/config-apis.ini ${CONFIG_FILE}
    android_version=$(echo -e ${CONFIG_FILE} | grep -oP '.*android_\K[^_]+(?=_google_apis)')
    sed -i "s|{AvdId}|pixel_9_pro_android_${android_version}_google_apis|g; s|{AvdDisplayname}|pixel 9 pro android ${android_version} google apis|g; s|{deviceName}|pixel_9_pro|g; s|{androidSystemName}|android-${android_version}|g; s|{androidHome}|${ANDROID_HOME}|g; s|{skinName}|pixel_9_pro|g" "${CONFIG_FILE}"
done