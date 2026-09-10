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
# Download tools.
#
# `sdkmanager` is DEPRECATED: it now prints "The SDK Manager CLI tool (sdkmanager)
# is deprecated. Android CLI will be used instead." and is a thin SHIM over
# `android sdk`, already emitting the new slash-form ids. Calling `android sdk`
# directly is the same code path without the shim. Mapping: --sdk_root= -> --sdk=,
# and BOTH the old "a;b;c" and new "a/b/c" package ids are accepted (verified by
# installing each form into a throwaway --sdk root), so the ids below are unchanged.
#
# The licence feeders are GONE. They were `while true; do echo 'y'; sleep 2; done |`
# and they were the source of the recurring
#     global-stack-android-setup.sh: line 30: echo: write error: Broken pipe
# -- when sdkmanager exited, the loop's next echo hit a closed pipe, and because
# line 6 of this script does `trap '' PIPE SIGPIPE`, SIGPIPE is IGNORED, so the
# write returns EPIPE and bash reports it instead of the loop dying quietly.
# `android sdk install` accepts the licences itself: verified on a FRESH --sdk root
# with stdin closed, it wrote licenses/android-sdk-license unprompted. Upstream
# agrees -- `--licenses` now answers "The --licenses option is no longer needed."
#
# platform-tools IS pinned now: "platform-tools;<ver>" installs correctly. ndk-bundle
# is NOT, and must not be: "ndk-bundle;22.1.7171670" answers "Package
# ndk-bundle/22.1.7171670 not found." and EXITS 0, installing nothing. That is what
# the old `@todo fix version not found !!!` was about. See the .env annotations.
#
# @todo check-updates
android sdk install --sdk="${ANDROID_HOME}" \
  "cmdline-tools;${GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION}" \
  "platform-tools;${GLOBAL_STACK_ANDROID_PLATFORM_TOOLS_VERSION}" \
  "build-tools;36.0.0" "build-tools;36.1.0" \
  "build-tools;${GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION}" \
  "ndk-bundle" "ndk;${GLOBAL_STACK_ANDROID_NDK_VERSION}" \
  "platforms;android-${GLOBAL_STACK_ANDROID_API_LEVEL_1}" \
  "platforms;android-${GLOBAL_STACK_ANDROID_API_LEVEL_2}" \
  "platforms;android-${GLOBAL_STACK_ANDROID_API_LEVEL_3}" \
  "extras;android;m2repository" "extras;google;google_play_services" \
  "extras;google;instantapps" "extras;google;m2repository" \
  "add-ons;addon-google_apis-google-22" "add-ons;addon-google_apis-google-23" \
  "add-ons;addon-google_apis-google-24"
if [ "${GLOBAL_STACK_ANDROID_INSTALL_SYSTEM_IMAGES}" = "true" ]; then
  android sdk install --sdk="${ANDROID_HOME}" "emulator" \
    "system-images;android-${GLOBAL_STACK_ANDROID_API_LEVEL_1};${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_TAG};${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_ABI}" \
    "system-images;android-${GLOBAL_STACK_ANDROID_API_LEVEL_1};${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_PLAYSTORE_TAG};${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_ABI}" \
    "system-images;android-${GLOBAL_STACK_ANDROID_API_LEVEL_2};${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_TAG};${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_ABI}" \
    "system-images;android-${GLOBAL_STACK_ANDROID_API_LEVEL_2};${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_PLAYSTORE_TAG};${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_ABI}" \
    "system-images;android-${GLOBAL_STACK_ANDROID_API_LEVEL_3};${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_TAG};${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_ABI}" \
    "system-images;android-${GLOBAL_STACK_ANDROID_API_LEVEL_3};${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_PLAYSTORE_TAG};${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_ABI}"
fi
set -xeEu -o pipefail

# `android sdk install` EXITS 0 ON A PACKAGE THAT DOES NOT EXIST -- it prints
# "Package <id> not found." and returns 0, installing nothing. `set -e` cannot see
# that, so a renamed or mistyped id would install nothing and this script would
# still write its success marker. That is the most plausible way the
# google_apis -> google_apis_ps16k rename reached production unnoticed. So VERIFY:
# every id we asked for must appear in `android sdk list`, or fail loudly here.
_installed="$(android sdk list --sdk="${ANDROID_HOME}" 2>/dev/null || true)"
_missing=""
for _want in \
  "cmdline-tools/${GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION}" \
  "platform-tools" "build-tools/${GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION}" \
  "ndk-bundle" "ndk/${GLOBAL_STACK_ANDROID_NDK_VERSION}" \
  "platforms/android-${GLOBAL_STACK_ANDROID_API_LEVEL_1}" \
  "platforms/android-${GLOBAL_STACK_ANDROID_API_LEVEL_2}" \
  "platforms/android-${GLOBAL_STACK_ANDROID_API_LEVEL_3}"; do
  printf '%s\n' "${_installed}" | grep -qF -- "${_want}" || _missing="${_missing} ${_want}"
done
if [ "${GLOBAL_STACK_ANDROID_INSTALL_SYSTEM_IMAGES}" = "true" ]; then
  for _lvl in "${GLOBAL_STACK_ANDROID_API_LEVEL_1}" "${GLOBAL_STACK_ANDROID_API_LEVEL_2}" "${GLOBAL_STACK_ANDROID_API_LEVEL_3}"; do
    _want="system-images/android-${_lvl}/${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_TAG}/${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_ABI}"
    printf '%s\n' "${_installed}" | grep -qF -- "${_want}" || _missing="${_missing} ${_want}"
  done
fi
if [ -n "${_missing}" ]; then
  printf 'FATAL: android sdk install reported success but these packages are absent:%s\n' "${_missing}" >&2
  printf '       android sdk install exits 0 on "Package not found" - check the ids against\n' >&2
  printf '       android sdk list --all --beta before assuming a network problem.\n' >&2
  exit 1
fi

# rm -rf ${ANDROID_HOME}/licenses
android --version > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/android.sdkmanager"
# Row 19: the component-pin marker the gate in global-stack-android-start.sh reads.
# Composed THERE and exported, deliberately not recomputed here — two copies of the
# same string would drift and every boot would then look like a version change.
# Written last, so a failed sdkmanager run above cannot record success. Empty when
# this script is run standalone: that leaves the marker absent, and the next start
# reinstalls rather than trusting an unverified state.
[[ -n "${GS_ANDROID_SDK_WANT:-}" ]] && printf '%s\n' "${GS_ANDROID_SDK_WANT}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/android.sdk"