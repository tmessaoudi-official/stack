#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch $? $LINENO' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** global-stack-alltogether-start.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    sleep infinity
  fi
}

SECONDS=0

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

sleep 1

global-stack-base-wait-for.sh \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/web-server" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/node.${NODE_VERSION_AS}" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/java.${JAVA_VERSION_AS}" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/ruby.${RUBY_VERSION_AS}" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rust" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/python.${PYTHON_VERSION_AS}" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/php.${PHP_VERSION_AS}" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/flutter.${FLUTTER_VERSION_AS}" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/android"

PATH="${RUSTUP_HOME}/bin:${RUSTUP_HOME}/toolchains/stable-x86_64-unknown-linux-gnu/bin/:${CARGO_HOME}/bin:${COMPOSER_HOME}/vendor/bin:${COMPOSER_SOURCE}/bin:${SYMFONY_HOME}/bin:${PHPBREW_SRC}/bin:${PYENV_ROOT}/bin:${GLOBAL_STACK_DOCKER_TOOLS_PATH}/yarn/bin:${DENO_DIR}/bin:${BUN_INSTALL}/bin:${PNPM_HOME}:${RBENV_ROOT}/bin:${PUB_CACHE}/bin:${FVM_CACHE_PATH}/versions/${FLUTTER_VERSION:-}/bin::${ANDROID_HOME}/cmdline-tools/bin:${ANDROID_HOME}/cmdline-tools/tools/bin:${ANDROID_HOME}/tools:${ANDROID_HOME}/tools/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/build-tools/${GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION}:${ANDROID_HOME}/cmdline-tools/${GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION}/bin:${ANDROID_NDK_HOME}:${ANDROID_SDK_ROOT}/emulator:${PATH}"
export PATH

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${RUSTUP_HOME}/bin:${RUSTUP_HOME}/toolchains/stable-x86_64-unknown-linux-gnu/bin/:${CARGO_HOME}/bin:${COMPOSER_HOME}/vendor/bin:${COMPOSER_SOURCE}/bin:${SYMFONY_HOME}/bin:${PHPBREW_SRC}/bin:${PYENV_ROOT}/bin:${GLOBAL_STACK_DOCKER_TOOLS_PATH}/yarn/bin:${DENO_DIR}/bin:${BUN_INSTALL}/bin:${PNPM_HOME}:${RBENV_ROOT}/bin:${PUB_CACHE}/bin:${FVM_CACHE_PATH}/versions/${FLUTTER_VERSION:-}/bin::${ANDROID_HOME}/cmdline-tools/bin:${ANDROID_HOME}/cmdline-tools/tools/bin:${ANDROID_HOME}/tools:${ANDROID_HOME}/tools/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/build-tools/${GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION}:${ANDROID_HOME}/cmdline-tools/${GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION}/bin:${ANDROID_NDK_HOME}:${ANDROID_SDK_ROOT}/emulator:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc"
source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc
source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/pyenv.shellrc
source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/phpbrew.shellrc
source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/sdkman.shellrc
source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/fvm.shellrc
"${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/sdkman.installer.sh
source "${SDKMAN_DIR}"/bin/sdkman-init.sh

PYENV_VERSION=$(cat ${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python.${PYTHON_VERSION_AS})
export PYENV_VERSION
PHPBREW_PHP=$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}")
export PHPBREW_PHP
PATH=${PHPBREW_ROOT}/php/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}")/bin:${PHPBREW_ROOT}/php/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}")/sbin:${PYENV_ROOT}/bin:${RBENV_ROOT}/bin:${RBENV_ROOT}/versions/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.${RUBY_VERSION_AS}")/bin:${NVM_DIR}/versions/node/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.${NODE_VERSION_AS}")/bin:${PNPM_HOME}/4/node_modules/.bin:${PNPM_HOME}/5/node_modules/.bin:${YARN_GLOBAL_FOLDER}/bin:${GLOBAL_STACK_DOCKER_TOOLS_PATH}/deno/bin:${PATH}
export PATH

echo '"${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/sdkman.installer.sh' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo 'source "${SDKMAN_DIR}"/bin/sdkman-init.sh' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/pyenv.shellrc" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/phpbrew.shellrc" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/fvm.shellrc" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "PYENV_VERSION=$(cat ${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python.${PYTHON_VERSION_AS})" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PYENV_VERSION" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "PHPBREW_PHP=$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}")" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PHPBREW_PHP" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "PATH=${PHPBREW_ROOT}/php/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}")/bin:${PHPBREW_ROOT}/php/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/php.${PHP_VERSION_AS}")/sbin:${PYENV_ROOT}/bin:${RBENV_ROOT}/bin:${RBENV_ROOT}/versions/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.${RUBY_VERSION_AS}")/bin:${NVM_DIR}/versions/node/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.${NODE_VERSION_AS}")/bin:${PNPM_HOME}/4/node_modules/.bin:${PNPM_HOME}/5/node_modules/.bin:${YARN_GLOBAL_FOLDER}/bin:${GLOBAL_STACK_DOCKER_TOOLS_PATH}/deno/bin:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

eval "$(pyenv init -)"
eval "$(pyenv init --path)"
echo -e 'eval "$(pyenv init -)"' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo -e 'eval "$(pyenv init --path)"' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo -e 'eval "$(pyenv init --path)"' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.profile"

echo -e "\n \033[0;31m Setting up java ${JAVA_VERSION}"

mkdir -p "${HOME}/.sdkman/etc/"
touch "${HOME}/.sdkman/etc/config"
echo "sdkman_healthcheck_enable=false" > "${HOME}/.sdkman/etc/config"

source "${HOME}/.sdkman/etc/config"

set +e
sdk use java "${JAVA_VERSION}"
set -e
echo "sdk use java '${JAVA_VERSION}'" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

source /usr/local/bin/global-stack-base-setup-packages.sh
set +e
global_stack_base_setup_packages \
  --prefix='SDKMAN' \
  --command='echo -e "**** Using ${PACKAGE_NAME} ${PACKAGE_VERSION}"' \
  --command='sdk use ${PACKAGE_NAME} "${PACKAGE_VERSION}"' \
  --command='echo "sdk use ${PACKAGE_NAME} \"${PACKAGE_VERSION}\"" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"'
set -e

global-stack-base-init-mkcert.sh
global-stack-nvm-eval-yarnrc.sh

source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

[ "${GLOBAL_STACK_DOCKER_IN_DOCKER}" = "true" ] && global-stack-base-start-docker.sh || echo -e "\n Docker In Docker will not be started"

global-stack-base-prepare-shell.sh

echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION=$SECONDS
global-stack-base-print-success.sh "${DURATION}" "${ALLTOGETHER_NAME}"

: > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/${ALLTOGETHER_NAME}"

sleep infinity
