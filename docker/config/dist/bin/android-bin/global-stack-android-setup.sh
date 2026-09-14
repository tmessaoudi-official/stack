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
# THREE of these packages are SINGLE-INSTANCE upstream -- platform-tools, ndk-bundle
# and emulator -- and a single-instance id takes NO version. Append one and the CLI
# answers "Package <id>/<ver> not found." and EXITS 0, installing nothing. Measured,
# all three, against android 1.0.15985488 [2026-09-11]:
#
#   platform-tools;37.0.1     -> Package platform-tools/37.0.1 not found.      exit 0
#   ndk-bundle;22.1.7171670   -> Package ndk-bundle/22.1.7171670 not found.    exit 0
#   emulator;37.1.11          -> Package emulator/37.1.11 not found.           exit 0
#   build-tools;37.0.0        -> (accepted -- multi-instance, version required)
#
# The line that used to stand here claimed "platform-tools IS pinned now:
# platform-tools;<ver> installs correctly", in the same breath as correctly
# describing ndk-bundle failing this exact way. It was false, and the VERIFY LOOP
# BELOW IS WHAT CAUGHT IT -- on the first boot that ever executed this block it
# printed "these packages are absent: platform-tools" and exited 1, exactly as
# designed. The blind spot was not here; it was the TEST STUB, which accepted the
# versioned id and then listed it bare, so the suite was green on a package the real
# CLI never installed. That is also what the old `@todo fix version not found !!!`
# was about. See the .env annotations.
#
# So the version pins for these three are EXPECTED versions, not requestable ones:
# whatever upstream currently serves is what gets installed. _PLATFORM_TOOLS_VERSION
# is asserted against the installed build after the verify loop; _NDK_BUNDLE_VERSION
# has no consumer at all (it is a record of the bundled version -- see .env).
#
# The package set is declared ONCE, here, and the verification loop below iterates
# these same arrays. Row 25's lesson one level down: the loop used to carry its own
# hand-written list, which covered 11 of the 24 ids while its comment claimed "every
# id we asked for". A second list drifts; an array cannot.
#
# The build-tools compat pair used to be LITERALS here ("build-tools;36.0.0"
# "build-tools;36.1.0"), with a .env note asking whoever bumped the pin to move
# the outgoing version down by hand. Row 41: all three are .env vars, and so are
# the three platforms below, each tracked by env-update as latest / latest-1 /
# latest-2 via (offset:N) on its annotation -- the window rolls on --apply and
# this file needs no edit. Order is oldest first, matching the API-level slots.
_pkgs=(
  "cmdline-tools;${GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION}"
  "platform-tools"
  "build-tools;${GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION_PREV_2}"
  "build-tools;${GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION_PREV_1}"
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
  # The listing's id column is the install id with ';' -> '/', with NO exception: the
  # single-instance ids are bare on BOTH sides -- bare going in (see the class note
  # above) and listed bare with their version in column 2. An exception used to live
  # here, mapping "platform-tools;<ver>" back to bare. Its listing-side half was
  # CORRECT -- platform-tools really is listed bare -- but it existed only because the
  # install array one up carried a version, so it encoded a false premise about the
  # install side. It masked nothing: with the versioned id it mapped to bare, grepped,
  # found nothing, and FATALed -- which is exactly how this bug was caught, live, on
  # the first boot that ever ran this block. With the install id bare, "${_want//;//}"
  # already yields bare and the exception is simply unnecessary.
  _id="${_want//;//}"
  printf '%s\n' "${_installed}" | grep -qF -- "${_id}" || _missing="${_missing} ${_id}"
done
if [ -n "${_missing}" ]; then
  printf 'FATAL: android sdk install reported success but these packages are absent:%s\n' "${_missing}" >&2
  printf '       android sdk install exits 0 on "Package not found" - check the ids against\n' >&2
  printf '       android --sdk=<sdk root> sdk list --all --beta before assuming a network\n' >&2
  printf '       problem (--sdk is a GLOBAL option: it goes BEFORE the subcommand).\n' >&2
  exit 1
fi

# platform-tools is single-instance, so its version is NOT requestable -- the install
# above asked for a bare id and upstream served whatever it currently offers. The
# .env pin is therefore an EXPECTED version, and this is where it earns its keep:
# assert it against the build actually on disk (column 2 of the bare listing line).
#
# WARN, deliberately NOT fatal, and this is not a swallowed error -- there is no
# failure here to absorb. The install succeeded; the pin is simply describing a build
# upstream has moved past. The only remedy is a human `.env` bump (the pin is
# env-update-tracked: `@todo env-update androidsdk:platform-tools`), and exiting 1
# would strand 04android plus 05stable/05edge/local.05 behind documentation drift.
#
# Fires once per INSTALL, not once per boot: the gate keys on the pin, so after a
# mismatch the marker still carries platform-tools=<pin> and the next boot answers
# `skip` without reaching this line. Bumping .env changes the marker, which forces
# the reinstall that picks up upstream's current build -- which is what the pin means
# for a single-instance package.
_ptv_got="$(printf '%s\n' "${_installed}" | awk '$1 == "platform-tools" { print $2; exit }')"
if [ "${_ptv_got}" != "${GLOBAL_STACK_ANDROID_PLATFORM_TOOLS_VERSION}" ]; then
  printf 'WARN: platform-tools %s != pinned %s (single-instance: upstream serves one build, the pin cannot request another - bump .env to match)\n' \
    "${_ptv_got:-<absent>}" "${GLOBAL_STACK_ANDROID_PLATFORM_TOOLS_VERSION}" >&2
fi

# rm -rf ${ANDROID_HOME}/licenses
android --version > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/android.cli"
# Row 19: the component-pin marker the gate in global-stack-android-start.sh reads.
# Composed THERE and exported, deliberately not recomputed here — two copies of the
# same string would drift and every boot would then look like a version change.
# Written last, so a failed android sdk run above cannot record success. Empty when
# this script is run standalone: that leaves the marker absent, and the next start
# reinstalls rather than trusting an unverified state.
# An `if`, not `[[ ... ]] && ...`: this is the script's last statement, so a
# short-circuited test returns 1 as the SCRIPT's own exit status -- reporting
# failure for having had nothing to do. Measured: var unset -> 1, set -> 0.
# The absent-marker behaviour above is unchanged; only the status is.
if [[ -n "${GS_ANDROID_SDK_WANT:-}" ]]; then
  printf '%s\n' "${GS_ANDROID_SDK_WANT}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/android.sdk"
fi
