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
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** global-stack-android-setup-dit.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

if [ "${GLOBAL_STACK_ANDROID_INSTALL_SYSTEM_IMAGES}" = "true" ]; then
  avdmanager create avd --force --name global_stack_auto_pixel_7_pro_android_36_google_apis --package "system-images;android-36;google_apis;x86_64" --device "pixel_7_pro"
  avdmanager create avd --force --name global_stack_auto_pixel_9_pro_android_36.1_google_apis --package "system-images;android-36.1;google_apis;x86_64" --device "pixel_9_pro"
  avdmanager create avd --force --name global_stack_auto_pixel_9_pro_android_CinnamonBun_google_apis --package "system-images;android-CinnamonBun;google_apis_ps16k;x86_64" --device "pixel_9_pro"
  
  for CONFIG_FILE in "${ANDROID_SDK_HOME}"/.android/avd/global_stack_auto_*.avd/config.ini; do
      cp -f ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/android-avd-conf/config-apis.ini ${CONFIG_FILE}
      android_version=$(echo -e ${CONFIG_FILE} | grep -oP '.*android_\K[^_]+(?=_google_apis)')
      pixel_version=$(echo -e ${CONFIG_FILE} | grep -oP '.*pixel_\K[^_]+(?=_pro)')
      sed -i "s|{AvdId}|global_stack_auto_pixel_${pixel_version}_pro_android_${android_version}_google_apis|g; s|{AvdDisplayname}|global stack auto pixel ${pixel_version} pro android ${android_version} google apis|g; s|{deviceName}|pixel_${pixel_version}_pro|g; s|{androidSystemName}|android-${android_version}|g; s|{androidHome}|${ANDROID_HOME}|g; s|{skinName}|pixel_${pixel_version}_pro|g" "${CONFIG_FILE}"
  done
fi