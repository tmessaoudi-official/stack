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
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && printf 'line: %s\ncommand: %s\n' "${2}" "${3}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

git clone --progress https://gitlab.com/newbit/rootAVD.git --depth 1 ${ANDROID_HOME}/newbit-rootAVD

sudo touch "${ANDROID_SDK_HOME}/.android/repositories.cfg"
sudo chmod -R a+rwx "${ANDROID_HOME}" "${ANDROID_SDK_HOME}" "${ANDROID_SDK_ROOT}" "${GRADLE_USER_HOME}"
sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}" "${ANDROID_HOME}" "${ANDROID_SDK_HOME}" "${ANDROID_SDK_ROOT}" "${GRADLE_USER_HOME}"
## Installs Android SDK
cd "${ANDROID_HOME}"
curl --connect-timeout 30 --max-time 300 -fsSL -o "${ANDROID_HOME}/tools.zip" "https://dl.google.com/android/repository/commandlinetools-linux-${GLOBAL_STACK_ANDROID_SDK_URL}_latest.zip"
unzip "${ANDROID_HOME}/tools.zip" && rm "${ANDROID_HOME}/tools.zip"
# Download tools
# @todo fix version not found !!! "platform-tools;${GLOBAL_STACK_ANDROID_PLATFORM_TOOLS_VERSION}" "ndk-bundle;${GLOBAL_STACK_ANDROID_NDK_BUNDLE_VERSION}" "ndk;${GLOBAL_STACK_ANDROID_NDK_VERSION}"
# @todo check-updates
while true; do echo 'y'; sleep 2; done | sdkmanager --sdk_root="${ANDROID_HOME}" "cmdline-tools;${GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION}" "platform-tools" "build-tools;36.0.0" "build-tools;36.1.0" "build-tools;${GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION}" "ndk-bundle" "ndk;${GLOBAL_STACK_ANDROID_NDK_VERSION}" "platforms;android-37.0" "platforms;android-37.1" "platforms;android-37.2-beta1" "extras;android;m2repository" "extras;google;google_play_services" "extras;google;instantapps" "extras;google;m2repository" "add-ons;addon-google_apis-google-22" "add-ons;addon-google_apis-google-23" "add-ons;addon-google_apis-google-24"
if [ "${GLOBAL_STACK_ANDROID_INSTALL_SYSTEM_IMAGES}" = "true" ]; then
  while true; do echo 'y'; sleep 2; done | sdkmanager --sdk_root="${ANDROID_HOME}" "emulator" "system-images;android-37.0;google_apis_ps16k;x86_64" "system-images;android-37.0;google_apis_playstore_ps16k;x86_64" "system-images;android-37.1;google_apis_ps16k;x86_64" "system-images;android-37.1;google_apis_playstore_ps16k;x86_64" "system-images;android-37.2-beta1;google_apis_ps16k;x86_64" "system-images;android-37.2-beta1;google_apis_playstore_ps16k;x86_64"
fi
yes | sdkmanager --sdk_root="${ANDROID_HOME}" --licenses
set -xeEu -o pipefail
# rm -rf ${ANDROID_HOME}/licenses
echo "$(sdkmanager --sdk_root="${ANDROID_HOME}" --version)" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/android.sdkmanager"
# Row 19: the component-pin marker the gate in global-stack-android-start.sh reads.
# Composed THERE and exported, deliberately not recomputed here — two copies of the
# same string would drift and every boot would then look like a version change.
# Written last, so a failed sdkmanager run above cannot record success. Empty when
# this script is run standalone: that leaves the marker absent, and the next start
# reinstalls rather than trusting an unverified state.
[[ -n "${GS_ANDROID_SDK_WANT:-}" ]] && printf '%s\n' "${GS_ANDROID_SDK_WANT}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/android.sdk"