#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  local exit_code=${1}
  local line_num=${2}
  local command=${3}
  # Re-entry guard, same name as the shared prologue's. The `sleep infinity` below
  # normally makes a second entry impossible, but the trap on line 6 also catches
  # SIGHUP — which interrupts that sleep and would re-enter with the trap's own line
  # number, overwriting a precise error token with a useless one.
  if [[ -n "${_STACK_CAUGHT:-}" ]]; then
    return 0
  fi
  # Row 30: 141 (SIGPIPE) now joins the exemption that every other prologue-exempt
  # handler already had — this was the only one without it, so a routine broken pipe
  # parked the container in the sleep below forever. The code-1 arm that used to sit
  # here is gone for the reason row 25 removed it from the 11 web-server handlers:
  # it is the most common real failure, and exempting it produced total silence.
  if [[ "${exit_code}" -ne 0 && "${exit_code}" -ne 141 ]]; then
    _STACK_CAUGHT=1
    echo "Error detected !!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${line_num} ** ** command: ${command} ** global-stack-android-start.sh" >>"${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    # The token MUST be written BEFORE the sleep. 04android's healthcheck is
    # `! test -f errors/android && test -f successes/android`, so without it a failed
    # container sat alive, unhealthy and unattributable for the full 24h start_period.
    # Spelled as an `if` rather than the web servers' `[[ … ]] && printf …`: here the
    # next statement is a sleep, not `exit 1`, so an unset token would abort under
    # `set -e` and skip the stay-alive entirely.
    if [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]]; then
      printf 'line: %s\ncommand: %s\n' "${line_num}" "${command}" \
        >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    fi
    # DELIBERATE, see the note at the version gate below: this container stays up on
    # failure so `make login-04android` can inspect it. Do NOT replace with `exit 1`.
    sleep infinity
  fi
}

SECONDS=0

sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/android"
rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"

PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/yarn/bin:${DENO_DIR}/bin:${BUN_INSTALL}/bin:${PNPM_HOME}:${RBENV_ROOT}/bin:${PUB_CACHE}/bin:${FVM_CACHE_PATH}/versions/${FLUTTER_VERSION:-}/bin:${ANDROID_HOME}/cmdline-tools/bin:${ANDROID_HOME}/cmdline-tools/tools/bin:${ANDROID_HOME}/tools:${ANDROID_HOME}/tools/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/build-tools/${GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION}:${ANDROID_HOME}/cmdline-tools/${GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION}/bin:${ANDROID_NDK_HOME}:${ANDROID_SDK_ROOT}/emulator:${PATH}"
export PATH

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${GLOBAL_STACK_DOCKER_TOOLS_PATH}/yarn/bin:${DENO_DIR}/bin:${BUN_INSTALL}/bin:${PNPM_HOME}:${RBENV_ROOT}/bin:${PUB_CACHE}/bin:${FVM_CACHE_PATH}/versions/${FLUTTER_VERSION:-}/bin:${ANDROID_HOME}/cmdline-tools/bin:${ANDROID_HOME}/cmdline-tools/tools/bin:${ANDROID_HOME}/tools:${ANDROID_HOME}/tools/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/build-tools/${GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION}:${ANDROID_HOME}/cmdline-tools/${GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION}/bin:${ANDROID_NDK_HOME}:${ANDROID_SDK_ROOT}/emulator:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

global-stack-base-wait-for.sh \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/java.${JAVA_VERSION_AS}" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/node.${NODE_VERSION_AS}" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/ruby.${RUBY_VERSION_AS}" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/flutter.${FLUTTER_VERSION_AS}"

"${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/sdkman.installer.sh
echo '"${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/sdkman.installer.sh' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
source "${SDKMAN_DIR}"/bin/sdkman-init.sh
echo 'source "${SDKMAN_DIR}"/bin/sdkman-init.sh' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc" && echo "export PATH=${NVM_DIR}/versions/node/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.${NODE_VERSION_AS}")/bin:${PNPM_HOME}:${PNPM_HOME}/4/node_modules/.bin:${PNPM_HOME}/5/node_modules/.bin:${YARN_GLOBAL_FOLDER}/bin:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc" && export PATH="${NVM_DIR}/versions/node/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.${NODE_VERSION_AS}")/bin:${PNPM_HOME}:${PNPM_HOME}/4/node_modules/.bin:${PNPM_HOME}/5/node_modules/.bin:${YARN_GLOBAL_FOLDER}/bin:${PATH}"

cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" && echo "export PATH=${RBENV_ROOT}/bin:${RBENV_ROOT}/versions/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.${RUBY_VERSION_AS}")/bin:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" && export PATH=${RBENV_ROOT}/bin:${RBENV_ROOT}/versions/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.${RUBY_VERSION_AS}")/bin:${PATH}

echo -e "\n \033[0;31m Setting up java ${JAVA_VERSION}"

mkdir -p "${HOME}/.sdkman/etc/"
touch "${HOME}/.sdkman/etc/config"
echo "sdkman_healthcheck_enable=false" > "${HOME}/.sdkman/etc/config"

source "${HOME}/.sdkman/etc/config"

set +E
sdk use java "${JAVA_VERSION}"
set -E
echo "sdk use java '${JAVA_VERSION}'" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

source /usr/local/bin/global-stack-base-setup-packages.sh
set +E
global_stack_base_setup_packages \
  --prefix='SDKMAN' \
  --command='echo -e "**** Using ${PACKAGE_NAME} ${PACKAGE_VERSION}"' \
  --command='sdk use ${PACKAGE_NAME} "${PACKAGE_VERSION}"' \
  --command='echo "sdk use ${PACKAGE_NAME} \"${PACKAGE_VERSION}\"" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"'
set -E

# Row 18/19. This script is prologue-EXEMPT (its own stackCatch above, which ends
# in `sleep infinity` rather than exiting), so it takes the version gate ALONE.
# Sourcing it here also covers global-stack-base-setup-packages.sh, sourced above:
# that library calls gs_version_gate when a caller passes --marker-prefix, and this
# caller does not — so the gate was an unbound command waiting to happen.
source global-stack-base-version-gate.sh

# The android.sdkmanager marker holds the sdkmanager BINARY's own version, which is
# not any of the .env pins — so it could never detect an SDK component bump. This
# composite marker carries the inputs the install actually consumes, and it is the
# ONLY thing that makes a bump of one of them reach the SDK: gs_version_gate
# compares it, and the mismatch is what drives the wipe-and-reinstall below.
#
# ALL TWELVE, since row 33. It carried three (cmdline-tools, build-tools, ndk), so a
# bump of any of the other nine was silently never applied — the gate said `skip`,
# the SDK kept the old component, and nothing warned. The two that mattered most:
# INSTALL_SYSTEM_IMAGES=true would have installed an emulator and six system images
# and instead did nothing, and API_LEVEL_3's pending move off a beta would have read
# as applied while the old platform stayed on disk.
#
# GLOBAL_STACK_ANDROID_PLATFORM_TOOLS_VERSION is IN — as an EXPECTED version, which
# is not the reason row 33 gave. Row 33 said the `_pkgs` array installs
# "platform-tools;${…}" as a live element; row 36 measured that id and found it
# installs NOTHING ("Package platform-tools/37.0.1 not found.", exit 0 — platform-
# tools is single-instance upstream and takes no version). The id is bare now, and
# the pin is asserted against the build upstream actually served, after the verify
# loop in global-stack-android-setup.sh. So it stays IN for a sound reason: bumping
# it must change the marker, because the reinstall that follows is the ONLY way a
# single-instance package picks up a new build.
# _NDK_BUNDLE_VERSION is a different case and stays OUT — it has no consumer at all,
# live or asserted (the array passes a bare "ndk-bundle", and nothing compares its
# version). Track 5 says values nothing reads stay out of the composite, so a bump
# cannot force a reinstall for nothing.
#
# The SYSTEM_IMAGE_* three are included even while INSTALL_SYSTEM_IMAGES=false, when
# they install nothing. That is deliberate: the cost of the spurious reinstall is
# minutes, once, on a value that almost never moves, and the alternative is a second
# code path whose only job is to be conditionally correct. Simplicity wins here.
#
# Order is fixed and the assignment is ONE LINE — startup-prologue.test.sh §27
# extracts it with `grep -m1 '^GS_ANDROID_SDK_WANT='`, so an array-join or a
# backslash continuation would silently truncate every behavioural probe. §47
# DISCOVERS the consumed set from setup.sh and checks it against this line both
# ways, so a thirteenth input cannot be added there and forgotten here.
GS_ANDROID_SDK_WANT="sdk-build=${GLOBAL_STACK_ANDROID_SDK_BUILD};cmdline-tools=${GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION};platform-tools=${GLOBAL_STACK_ANDROID_PLATFORM_TOOLS_VERSION};build-tools=${GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION};ndk=${GLOBAL_STACK_ANDROID_NDK_VERSION};api1=${GLOBAL_STACK_ANDROID_API_LEVEL_1};api2=${GLOBAL_STACK_ANDROID_API_LEVEL_2};api3=${GLOBAL_STACK_ANDROID_API_LEVEL_3};sysimg=${GLOBAL_STACK_ANDROID_INSTALL_SYSTEM_IMAGES};sysimg-tag=${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_TAG};sysimg-ps-tag=${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_PLAYSTORE_TAG};sysimg-abi=${GLOBAL_STACK_ANDROID_SYSTEM_IMAGE_ABI}"
export GS_ANDROID_SDK_WANT
_android_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/android.sdk" "${GS_ANDROID_SDK_WANT}" "android.sdk")"

if [ "${_android_gate}" != "skip" ] || [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/android.sdkmanager" ] || [ "${GLOBAL_STACK_RELOAD_ANDROID}" = "true" ]; then
  sudo rm -rf "${ANDROID_HOME}" "${ANDROID_SDK_HOME}" "${ANDROID_SDK_ROOT}" "${GRADLE_USER_HOME}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/android.sdkmanager" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/android.sdk"
fi

mkdir -p "${ANDROID_HOME}" "${ANDROID_SDK_HOME}/.android" "${ANDROID_SDK_ROOT}" "${GRADLE_USER_HOME}"

if [ "${_android_gate}" != "skip" ] || [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/android.sdkmanager" ] || [ "${GLOBAL_STACK_RELOAD_ANDROID}" = "true" ]; then
  global-stack-android-setup.sh
fi

global-stack-android-setup-dist.sh

flutter config --android-sdk "${ANDROID_HOME}"
flutter doctor --android-licenses
flutter doctor -v

global-stack-base-init-mkcert.sh

global-stack-base-prepare-shell.sh

echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION="${SECONDS}"
global-stack-base-print-success.sh "${DURATION}" "android"

: > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/android"

if [ "${GLOBAL_STACK_RELOAD_ANDROID:-false}" = "true" ]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_ANDROID is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi

sleep infinity
