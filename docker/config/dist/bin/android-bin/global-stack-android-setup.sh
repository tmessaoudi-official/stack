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
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** global-stack-android-setup.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

git clone --progress https://gitlab.com/newbit/rootAVD.git --depth 1 ${ANDROID_HOME}/newbit-rootAVD

sudo touch "${ANDROID_SDK_HOME}/.android/repositories.cfg"
sudo chmod -R a+rwx "${ANDROID_HOME}" "${ANDROID_SDK_HOME}" "${ANDROID_SDK_ROOT}" "${GRADLE_USER_HOME}"
sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}" "${ANDROID_HOME}" "${ANDROID_SDK_HOME}" "${ANDROID_SDK_ROOT}" "${GRADLE_USER_HOME}"
## Installs Android SDK
cd "${ANDROID_HOME}"
wget -O "${ANDROID_HOME}/tools.zip" "${GLOBAL_STACK_ANDROID_SDK_URL}"
unzip "${ANDROID_HOME}/tools.zip" && rm "${ANDROID_HOME}/tools.zip"
# Download tools
# @todo fix version not found !!! "platform-tools;${GLOBAL_STACK_ANDROID_PLATFORM_TOOLS_VERSION}" "ndk-bundle;${GLOBAL_STACK_ANDROID_NDK_BUNDLE_VERSION}" "ndk;${GLOBAL_STACK_ANDROID_NDK_VERSION}"
# @todo check-updates
while true; do echo 'y'; sleep 2; done | sdkmanager --sdk_root="${ANDROID_HOME}" "cmdline-tools;${GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION}" "platform-tools" "build-tools;36.0.0" "build-tools;36.1.0" "build-tools;37.0.0-rc2" "ndk-bundle" "ndk;${GLOBAL_STACK_ANDROID_NDK_VERSION}" "platforms;android-36" "platforms;android-36.1" "platforms;android-CinnamonBun" "extras;android;m2repository" "extras;google;google_play_services" "extras;google;instantapps" "extras;google;m2repository" "add-ons;addon-google_apis-google-22" "add-ons;addon-google_apis-google-23" "add-ons;addon-google_apis-google-24"
if [ "${GLOBAL_STACK_ANDROID_INSTALL_SYSTEM_IMAGES}" = "true" ]; then
  while true; do echo 'y'; sleep 2; done | sdkmanager --sdk_root="${ANDROID_HOME}" "emulator" "system-images;android-36;google_apis;x86_64" "system-images;android-36;google_apis_playstore;x86_64" "system-images;android-36.1;google_apis;x86_64" "system-images;android-36.1;google_apis_playstore;x86_64" "system-images;android-CinnamonBun;google_apis_ps16k;x86_64" "system-images;android-CinnamonBun;google_apis_playstore_ps16k;x86_64"
fi
yes | sdkmanager --sdk_root="${ANDROID_HOME}" --licenses
set -xeEu -o pipefail
# rm -rf ${ANDROID_HOME}/licenses
echo "$(sdkmanager --sdk_root="${ANDROID_HOME}" --version)" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/android.sdkmanager"