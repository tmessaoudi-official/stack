#!/bin/bash

# set -xeE
# shopt -s extdebug
# IFS=$'\n\t'
# trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
# stackCatch() {
#   if [ "${1}" != "0" ] && [ "${1}" != "1" ]; then
#     # error handling goes here
#     echo "Error detected !!"
#     echo -e "\n$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** global-stack-android-start.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
#     sleep infinity
#   fi
# }

SECONDS=0

sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/android"

PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/yarn/bin:${DENO_DIR}/bin:${BUN_INSTALL}/bin:${PNPM_HOME}:${RBENV_ROOT}/bin:${PUB_CACHE}/bin:${FLUTTER_HOME}/bin:${ANDROID_HOME}/cmdline-tools/bin:${ANDROID_HOME}/cmdline-tools/tools/bin:${ANDROID_HOME}/tools:${ANDROID_HOME}/tools/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/build-tools/${GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION}:${ANDROID_NDK_HOME}:${ANDROID_SDK_ROOT}/emulator:${PATH}"
export PATH

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${GLOBAL_STACK_DOCKER_TOOLS_PATH}/yarn/bin:${DENO_DIR}/bin:${BUN_INSTALL}/bin:${PNPM_HOME}:${RBENV_ROOT}/bin:${PUB_CACHE}/bin:${FLUTTER_HOME}/bin:${ANDROID_HOME}/cmdline-tools/bin:${ANDROID_HOME}/cmdline-tools/tools/bin:${ANDROID_HOME}/tools:${ANDROID_HOME}/tools/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/build-tools/${GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION}:${ANDROID_NDK_HOME}:${ANDROID_SDK_ROOT}/emulator:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

global-stack-base-wait-for.sh \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/java.25" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/node.26" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/ruby.3"

"${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/sdkman.installer.sh
echo '"${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/sdkman.installer.sh' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
source "${SDKMAN_DIR}"/bin/sdkman-init.sh
echo 'source "${SDKMAN_DIR}"/bin/sdkman-init.sh' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc" && echo "export PATH=${NVM_DIR}/versions/node/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.26")/bin:${PNPM_HOME}:${PNPM_HOME}/4/node_modules/.bin:${PNPM_HOME}/5/node_modules/.bin:${YARN_GLOBAL_FOLDER}/bin:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc" && export PATH="${NVM_DIR}/versions/node/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.26")/bin:${PNPM_HOME}:${PNPM_HOME}/4/node_modules/.bin:${PNPM_HOME}/5/node_modules/.bin:${YARN_GLOBAL_FOLDER}/bin:${PATH}"


cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" && echo "export PATH=${RBENV_ROOT}/bin:${RBENV_ROOT}/versions/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.3")/bin:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" && export PATH=${RBENV_ROOT}/bin:${RBENV_ROOT}/versions/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.3")/bin:${PATH}

echo -e "\n \033[0;31m Setting up java ${JAVA_VERSION}"
sdk offline enable
sdk use java "${JAVA_VERSION}"
echo "sdk offline enable" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "sdk use java '${JAVA_VERSION}'" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

source /usr/local/bin/global-stack-base-setup-packages.sh
global_stack_base_setup_packages \
  --prefix='SDKMAN' \
  --command='echo -e "**** Using ${PACKAGE_NAME} ${PACKAGE_VERSION}"' \
  --command='sdk use ${PACKAGE_NAME} "${PACKAGE_VERSION}"' \
  --command='echo "sdk use ${PACKAGE_NAME} \"${PACKAGE_VERSION}\"" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"'

if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/android.sdkmanager" ] || [ "${GLOBAL_STACK_RELOAD_ANDROID}" = "true" ]; then
  sudo rm -rf "${ANDROID_HOME}" "${ANDROID_SDK_HOME}" "${ANDROID_SDK_ROOT}" "${GRADLE_USER_HOME}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/android.sdkmanager"
fi

mkdir -p "${ANDROID_HOME}" "${ANDROID_SDK_HOME}/.android" "${ANDROID_SDK_ROOT}" "${GRADLE_USER_HOME}"

if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter" ] || [ "${GLOBAL_STACK_RELOAD_ANDROID}" = "true" ]; then
  sudo rm -rf "${FLUTTER_HOME}" "${PUB_CACHE}"
fi

mkdir -p "${FLUTTER_HOME}" "${PUB_CACHE}"

if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/android.sdkmanager" ] || [ "${GLOBAL_STACK_RELOAD_ANDROID}" = "true" ]; then
  global-stack-android-setup.sh
fi

global-stack-android-setup-dist.sh

if [ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter" ] || [ "${GLOBAL_STACK_RELOAD_ANDROID}" = "true" ]; then
  global-stack-android-flutter-iou.sh
fi

global-stack-base-init-mkcert.sh

global-stack-base-prepare-shell.sh

echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION="${SECONDS}"
global-stack-base-print-success.sh "${DURATION}" "android"

: > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/android"

sleep infinity
