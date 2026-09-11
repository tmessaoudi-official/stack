#!/bin/bash

set -xeEu
shopt -s extdebug
IFS=$'\n\t'
trap '' PIPE SIGPIPE SIGHUP
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR
stackCatch() {
  local exit_code=${1}
  local line_num=${2}
  local command=${3}
  # Re-entry guard: ERR fires first, then this handler's own `exit 1` comes back
  # through the EXIT trap and would overwrite the error token with the trap's own
  # line number. The code-1 arm removed below had been absorbing that re-entry by
  # accident, at the cost of silencing the most common real failure code entirely —
  # a failed AVD/dist setup wrote no token, no elapsed line and no message (row 30).
  if [[ -n "${_STACK_CAUGHT:-}" ]]; then
    return 0
  fi
  if [[ "${exit_code}" -ne 0 && "${exit_code}" -ne 141 ]]; then
    _STACK_CAUGHT=1
    echo "Error detected !!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${line_num} ** ** command: ${command} ** global-stack-android-setup-dist.sh" >>"${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    if [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]]; then
      printf 'line: %s\ncommand: %s\n' "${line_num}" "${command}" \
        >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    fi
    exit 1
  fi
}

if [ "${GLOBAL_STACK_ANDROID_INSTALL_SYSTEM_IMAGES}" = "true" ]; then
  # avdmanager is deliberately NOT migrated to `android emulator create`: it is not
  # deprecated (its own output carries no such warning), and the replacement takes a
  # single <profile> positional with no --name / --package / --device -- its
  # --list-profiles offers only six generic profiles (small_phone, medium_phone,
  # medium_tablet, three desktops), so it cannot express a pixel_7_pro on a pinned
  # system image, and the config.ini loop below depends on these exact AVD names.
  #
  # The image tag and abi come from .env now. They used to be literals here AND,
  # separately, in config-apis.ini -- and the two drifted: this file moved to
  # Google's 16 KB page-size images (google_apis_ps16k) while the template kept
  # saying google_apis, so every AVD referenced a system image that does not exist
  # and avdmanager reported all three as "could not be loaded". Single source now.
  _gs_avd_pkg() { # $1 = api level
    printf 'system-images;android-%s;%s;%s' \
      "${1}" "${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_TAG}" "${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_ABI}"
  }
  avdmanager create avd --force --name "global_stack_auto_pixel_7_pro_android_${GLOBAL_STACK_ANDROID_API_LEVEL_1}_google_apis" --package "$(_gs_avd_pkg "${GLOBAL_STACK_ANDROID_API_LEVEL_1}")" --device "pixel_7_pro"
  avdmanager create avd --force --name "global_stack_auto_pixel_9_pro_android_${GLOBAL_STACK_ANDROID_API_LEVEL_2}_google_apis" --package "$(_gs_avd_pkg "${GLOBAL_STACK_ANDROID_API_LEVEL_2}")" --device "pixel_9_pro"
  avdmanager create avd --force --name "global_stack_auto_pixel_9_pro_android_${GLOBAL_STACK_ANDROID_API_LEVEL_3}_google_apis" --package "$(_gs_avd_pkg "${GLOBAL_STACK_ANDROID_API_LEVEL_3}")" --device "pixel_9_pro"


  for CONFIG_FILE in "${ANDROID_SDK_HOME}"/.android/avd/global_stack_auto_*.avd/config.ini; do
      cp -f ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/android-avd-conf/config-apis.ini ${CONFIG_FILE}
      android_version=$(echo -e ${CONFIG_FILE} | grep -oP '.*android_\K[^_]+(?=_google_apis)')
      pixel_version=$(echo -e ${CONFIG_FILE} | grep -oP '.*pixel_\K[^_]+(?=_pro)')
      # {androidImageTag} and {androidImageAbi} are what stops this template from
      # drifting away from the installer again -- see the comment above.
      sed -i "s|{AvdId}|global_stack_auto_pixel_${pixel_version}_pro_android_${android_version}_google_apis|g; s|{AvdDisplayname}|global stack auto pixel ${pixel_version} pro android ${android_version} google apis|g; s|{deviceName}|pixel_${pixel_version}_pro|g; s|{androidSystemName}|android-${android_version}|g; s|{androidHome}|${ANDROID_HOME}|g; s|{skinName}|pixel_${pixel_version}_pro|g; s|{androidImageTag}|${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_TAG}|g; s|{androidImageAbi}|${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_ABI}|g" "${CONFIG_FILE}"
      # The template must not leave an unsubstituted placeholder behind: an AVD with
      # a literal {androidImageTag} in image.sysdir.1 fails exactly as silently as
      # the wrong tag did. Fail loudly instead.
      if grep -q '{[A-Za-z]*}' "${CONFIG_FILE}"; then
        printf 'FATAL: unsubstituted placeholder left in %s: %s\n' \
          "${CONFIG_FILE}" "$(grep -o '{[A-Za-z]*}' "${CONFIG_FILE}" | sort -u | tr '\n' ' ')" >&2
        exit 1
      fi
  done
fi