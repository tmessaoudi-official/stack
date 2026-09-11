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
  # a failed install wrote no token, no elapsed line and no message (row 30).
  if [[ -n "${_STACK_CAUGHT:-}" ]]; then
    return 0
  fi
  if [[ "${exit_code}" -ne 0 && "${exit_code}" -ne 141 ]]; then
    _STACK_CAUGHT=1
    echo "Error detected !!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${line_num} ** ** command: ${command} ** global-stack-android-setup.sh" >>"${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    if [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]]; then
      printf 'line: %s\ncommand: %s\n' "${line_num}" "${command}" \
        >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    fi
    exit 1
  fi
}

git clone --progress https://gitlab.com/newbit/rootAVD.git --depth 1 "${ANDROID_HOME}/newbit-rootAVD"

sudo touch "${ANDROID_SDK_HOME}/.android/repositories.cfg"
sudo chmod -R a+rwx "${ANDROID_HOME}" "${ANDROID_SDK_HOME}" "${ANDROID_SDK_ROOT}" "${GRADLE_USER_HOME}"
sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}":"${GLOBAL_STACK_DOCKER_GROUP_ID}" "${ANDROID_HOME}" "${ANDROID_SDK_HOME}" "${ANDROID_SDK_ROOT}" "${GRADLE_USER_HOME}"
## Installs Android SDK
cd "${ANDROID_HOME}"
curl --connect-timeout 30 --max-time 300 -fsSL -o "${ANDROID_HOME}/tools.zip" "https://dl.google.com/android/repository/commandlinetools-linux-${GLOBAL_STACK_ANDROID_SDK_BUILD}_latest.zip"
unzip "${ANDROID_HOME}/tools.zip" && rm "${ANDROID_HOME}/tools.zip"
# Download tools.
#
# `sdkmanager` is DEPRECATED: it now prints "The SDK Manager CLI tool (sdkmanager)
# is deprecated. Android CLI will be used instead." and is a thin SHIM over
# `android sdk`, already emitting the new slash-form ids. Calling `android sdk`
# directly is the same code path without the shim. BOTH the old "a;b;c" and new
# "a/b/c" package ids are accepted, so the ids below are unchanged.
#
# `--sdk` REPLACES `--sdk_root=`, but it is a GLOBAL option and belongs BEFORE the
# subcommand: `android --sdk=<path> sdk install …`. Written after the subcommand it is
# rejected outright -- "Unknown option: '--sdk=…'", exit 2 -- for BOTH `sdk install`
# and `sdk list`, measured against android 1.0.15985488, the build that the pinned
# commandlinetools-linux-${GLOBAL_STACK_ANDROID_SDK_BUILD}_latest.zip yields. b2ae4d1
# shipped the wrong position; nothing caught it because gs_version_gate had been
# returning "skip" on a warm tools/ volume, so this whole block had never run.
#
# The licence feeders are GONE. They were `while true; do echo 'y'; sleep 2; done |`
# and they were the source of the recurring
#     global-stack-android-setup.sh: line 30: echo: write error: Broken pipe
# -- when sdkmanager exited, the loop's next echo hit a closed pipe, and because
# line 6 of this script does `trap '' PIPE SIGPIPE`, SIGPIPE is IGNORED, so the
# write returns EPIPE and bash reports it instead of the loop dying quietly.
# `android sdk install` accepts the licences itself: on a FRESH SDK root with stdin
# closed it wrote licenses/android-sdk-license unprompted. Upstream
# agrees -- `--licenses` now answers "The --licenses option is no longer needed."
#
# platform-tools IS pinned now: "platform-tools;<ver>" installs correctly. ndk-bundle
# is NOT, and must not be: "ndk-bundle;22.1.7171670" answers "Package
# ndk-bundle/22.1.7171670 not found." and EXITS 0, installing nothing. That is what
# the old `@todo fix version not found !!!` was about. See the .env annotations.
#
# The package set is declared ONCE, here, and the verification loop below iterates
# these same arrays. Row 25's lesson one level down: the loop used to carry its own
# hand-written list, which covered 11 of the 24 ids while its comment claimed "every
# id we asked for". A second list drifts; an array cannot.
#
# @todo check-updates
_pkgs=(
  "cmdline-tools;${GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION}"
  "platform-tools;${GLOBAL_STACK_ANDROID_PLATFORM_TOOLS_VERSION}"
  "build-tools;36.0.0" "build-tools;36.1.0"
  "build-tools;${GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION}"
  "ndk-bundle" "ndk;${GLOBAL_STACK_ANDROID_NDK_VERSION}"
  "platforms;android-${GLOBAL_STACK_ANDROID_API_LEVEL_1}"
  "platforms;android-${GLOBAL_STACK_ANDROID_API_LEVEL_2}"
  "platforms;android-${GLOBAL_STACK_ANDROID_API_LEVEL_3}"
  "extras;android;m2repository" "extras;google;google_play_services"
  "extras;google;instantapps" "extras;google;m2repository"
  "add-ons;addon-google_apis-google-22" "add-ons;addon-google_apis-google-23"
  "add-ons;addon-google_apis-google-24"
)
_img_pkgs=()
if [ "${GLOBAL_STACK_ANDROID_INSTALL_SYSTEM_IMAGES}" = "true" ]; then
  _img_pkgs+=("emulator")
  for _lvl in "${GLOBAL_STACK_ANDROID_API_LEVEL_1}" "${GLOBAL_STACK_ANDROID_API_LEVEL_2}" "${GLOBAL_STACK_ANDROID_API_LEVEL_3}"; do
    _img_pkgs+=("system-images;android-${_lvl};${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_TAG};${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_ABI}")
    _img_pkgs+=("system-images;android-${_lvl};${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_PLAYSTORE_TAG};${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_ABI}")
  done
fi

android --sdk="${ANDROID_HOME}" sdk install "${_pkgs[@]}"
if [ "${#_img_pkgs[@]}" -gt 0 ]; then
  android --sdk="${ANDROID_HOME}" sdk install "${_img_pkgs[@]}"
fi
set -xeEu -o pipefail

# `android sdk install` EXITS 0 ON A PACKAGE THAT DOES NOT EXIST -- it prints
# "Package <id> not found." and returns 0, installing nothing. `set -e` cannot see
# that, so a renamed or mistyped id would install nothing and this script would
# still write its success marker. That is the most plausible way the
# google_apis -> google_apis_ps16k rename reached production unnoticed. So VERIFY:
# every id we asked for must appear in `android sdk list`, or fail loudly here. The
# loop iterates the SAME arrays the install used, so that claim is true by
# construction rather than by a second list someone has to remember to extend.
#
# NOT swallowed with `2>/dev/null || true`: the correct invocation exits 0, so there
# is no failure to absorb, and the swallow is precisely what turned the misplaced
# `--sdk` into a FATAL that blamed the package ids for a broken command line.
_installed="$(android --sdk="${ANDROID_HOME}" sdk list)"
_missing=""
for _want in "${_pkgs[@]}" ${_img_pkgs[@]+"${_img_pkgs[@]}"}; do
  # The listing's id column is the install id with ';' -> '/'. ONE exception:
  # platform-tools is single-instance upstream, so it is installed as
  # "platform-tools;<ver>" but LISTED bare, with its version in the second column.
  # Transforming it like the rest yields "platform-tools/<ver>", which never appears
  # in any listing -- a correct install would report itself missing.
  case "${_want}" in
    "platform-tools;"*) _id="platform-tools" ;;
    *) _id="${_want//;//}" ;;
  esac
  printf '%s\n' "${_installed}" | grep -qF -- "${_id}" || _missing="${_missing} ${_id}"
done
if [ -n "${_missing}" ]; then
  printf 'FATAL: android sdk install reported success but these packages are absent:%s\n' "${_missing}" >&2
  printf '       android sdk install exits 0 on "Package not found" - check the ids against\n' >&2
  printf '       android --sdk=<sdk root> sdk list --all --beta before assuming a network\n' >&2
  printf '       problem (--sdk is a GLOBAL option: it goes BEFORE the subcommand).\n' >&2
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
# An `if`, not `[[ ... ]] && ...`: this is the script's last statement, so a
# short-circuited test returns 1 as the SCRIPT's own exit status -- reporting
# failure for having had nothing to do. Measured: var unset -> 1, set -> 0.
# The absent-marker behaviour above is unchanged; only the status is.
if [[ -n "${GS_ANDROID_SDK_WANT:-}" ]]; then
  printf '%s\n' "${GS_ANDROID_SDK_WANT}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/android.sdk"
fi
