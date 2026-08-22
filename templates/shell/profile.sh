#!/bin/bash
# Put this file in /etc/profile.d/xxx.sh

xset led 3
GPG_TTY=$(tty)
export GPG_TTY

# @todo change this if you have you stack in another folder
if [[ -z "${GLOBAL_STACK_DOCKER_ROOT_PATH}" ]]; then
	GLOBAL_STACK_DOCKER_ROOT_PATH=/stack
	export GLOBAL_STACK_DOCKER_ROOT_PATH
fi

if [ ! -f "${GLOBAL_STACK_DOCKER_ROOT_PATH}"/.env.local ]; then
	exit 0
fi

_gs_prof_exclude="^(COMPOSE_FILE|BUILDX_EXPERIMENTAL|BUILDKIT_PROGRESS|BUILDX_BUILDER|COMPOSE_PROJECT_NAME|COMPOSE_REMOVE_ORPHANS|COMPOSE_HTTP_TIMEOUT|GLOBAL_STACK_EXPOSED_VIRTUAL_HOSTS|COMPOSE_PATH_SEPARATOR|DOCKER_BUILDKIT|COMPOSE_DOCKER_CLI_BUILD|GLOBAL_STACK_COMPOSE_CLI|GLOBAL_STACK_HTTPS_LOCALHOST_IPS|GLOBAL_STACK_HTTPS_CONTAINER_IPS|GLOBAL_STACK_(.*)_COMMAND_SUFFIX|GLOBAL_STACK_(.*)_CLI_OPTIONS|GLOBAL_STACK_(.*)_CLI_VARIANTS|GLOBAL_STACK_ANDROID_SYSTEM_IMAGES|GLOBAL_STACK_ANDROID_PACKAGES|GLOBAL_STACK_LOCAL_POSTGRES(.*))="
_gs_prof_envfile="${GLOBAL_STACK_DOCKER_ROOT_PATH}/.env.local"
eval "$(grep -vE "${_gs_prof_exclude}" "${_gs_prof_envfile}" | sed 's/^/export /')"
eval "$(grep -vE "${_gs_prof_exclude}" "${_gs_prof_envfile}" | sed 's/^/export /')"
eval "$(grep -vE "${_gs_prof_exclude}" "${_gs_prof_envfile}" | sed 's/^/export /')"
unset _gs_prof_exclude _gs_prof_envfile

sudo chown root:root /opt/${GLOBAL_STACK_DOCKER_USER_ID}/code/chrome-sandbox
sudo chmod 4755 /opt/${GLOBAL_STACK_DOCKER_USER_ID}/code/chrome-sandbox
sudo chown root:root /opt/${GLOBAL_STACK_DOCKER_USER_ID}/devin/chrome-sandbox
sudo chmod 4755 /opt/${GLOBAL_STACK_DOCKER_USER_ID}/devin/chrome-sandbox
sudo chown root:root /opt/${GLOBAL_STACK_DOCKER_USER_ID}/balena-etcher/chrome-sandbox
sudo chmod 4755 /opt/${GLOBAL_STACK_DOCKER_USER_ID}/balena-etcher/chrome-sandbox

alias gksudo='pkexec env DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY'
alias balena-etcher='/opt/${GLOBAL_STACK_DOCKER_USER_ID}/balena-etcher/balena-etcher'
alias code='/opt/${GLOBAL_STACK_DOCKER_USER_ID}/code/bin/code'
alias devin-desktop='/opt/${GLOBAL_STACK_DOCKER_USER_ID}/devin/bin/devin-desktop'
alias android-studio='/opt/${GLOBAL_STACK_DOCKER_USER_ID}/intellij/android-studio/bin/studio'
alias idea='/opt/${GLOBAL_STACK_DOCKER_USER_ID}/intellij/idea/bin/idea'
alias phpstorm='/opt/${GLOBAL_STACK_DOCKER_USER_ID}/intellij/phpstorm/bin/phpstorm'
alias webstorm='/opt/${GLOBAL_STACK_DOCKER_USER_ID}/intellij/webstorm/bin/webstorm'
alias megit='/opt/${GLOBAL_STACK_DOCKER_USER_ID}/megit/megit'
alias sublime_text='/opt/${GLOBAL_STACK_DOCKER_USER_ID}/sublime_text/sublime_text'

GOROOT=${GLOBAL_STACK_GOROOT}
export GOROOT
GOPATH=${GLOBAL_STACK_GOPATH}
export GOPATH
CAROOT=${GLOBAL_STACK_CAROOT}
export CAROOT
AWS_ENDPOINT_URL_S3=${GLOBAL_STACK_BASE_AWS_ENDPOINT_URL_S3}
export AWS_ENDPOINT_URL_S3
AWS_ENDPOINT_URL_SQS=${GLOBAL_STACK_BASE_AWS_ENDPOINT_URL_SQS}
export AWS_ENDPOINT_URL_SQS
AWS_ENDPOINT_URL_LAMBDA=${GLOBAL_STACK_BASE_AWS_ENDPOINT_URL_LAMBDA}
export AWS_ENDPOINT_URL_LAMBDA
AWS_ENDPOINT_URL_SNS=${GLOBAL_STACK_BASE_AWS_ENDPOINT_URL_SNS}
export AWS_ENDPOINT_URL_SNS
AWS_ENDPOINT_URL_SNS_NOTIFICATION_ENDPOINT=${GLOBAL_STACK_BASE_AWS_ENDPOINT_URL_SNS_NOTIFICATION_ENDPOINT}
export AWS_ENDPOINT_URL_SNS_NOTIFICATION_ENDPOINT
AWS_ACCESS_KEY_ID="${GLOBAL_STACK_BASE_AWS_ACCESS_KEY_ID}"
export AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY="${GLOBAL_STACK_BASE_AWS_SECRET_ACCESS_KEY}"
export AWS_SECRET_ACCESS_KEY
AWS_REGION="${GLOBAL_STACK_BASE_AWS_REGION}"
export AWS_REGION
AWS_DEFAULT_REGION="${GLOBAL_STACK_BASE_AWS_DEFAULT_REGION}"
export AWS_DEFAULT_REGION
AWS_CA_BUNDLE="${GLOBAL_STACK_BASE_AWS_CA_BUNDLE}"
export AWS_CA_BUNDLE
NODE_EXTRA_CA_CERTS="${GLOBAL_STACK_BASE_NODE_EXTRA_CA_CERTS}"
export NODE_EXTRA_CA_CERTS
SSL_CERT_FILE="${GLOBAL_STACK_BASE_SSL_CERT_FILE}"
export SSL_CERT_FILE
REQUESTS_CA_BUNDLE="${GLOBAL_STACK_BASE_REQUESTS_CA_BUNDLE}"
export REQUESTS_CA_BUNDLE
CURL_CA_BUNDLE="${GLOBAL_STACK_BASE_CURL_CA_BUNDLE}"
export CURL_CA_BUNDLE
SERVERLESS_ACCESS_KEY="${GLOBAL_STACK_BASE_SERVERLESS_ACCESS_KEY}"
export SERVERLESS_ACCESS_KEY
GLOBAL_STACK_DOCKER_TOOLS_PATH_CACHE="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/cache"
export GLOBAL_STACK_DOCKER_TOOLS_PATH_CACHE
CYPRESS_CACHE_FOLDER="${GLOBAL_STACK_CYPRESS_CACHE_FOLDER}"
export CYPRESS_CACHE_FOLDER
SDKMAN_DIR="${GLOBAL_STACK_SDKMAN_DIR}"
export SDKMAN_DIR
PUB_CACHE="${GLOBAL_STACK_PUB_CACHE}"
export PUB_CACHE
ANDROID_HOME="${GLOBAL_STACK_ANDROID_HOME}"
export ANDROID_HOME
ANDROID_SDK_ROOT="${ANDROID_HOME}"
export ANDROID_SDK_ROOT
ANDROID_SDK_HOME="${GLOBAL_STACK_ANDROID_SDK_HOME}"
export ANDROID_SDK_HOME
ANDROID_NDK_HOME="${GLOBAL_STACK_ANDROID_NDK_HOME}"
export ANDROID_NDK_HOME
GRADLE_USER_HOME="${GLOBAL_STACK_GRADLE_USER_HOME}"
export GRADLE_USER_HOME
RUSTUP_HOME="${GLOBAL_STACK_RUSTUP_HOME}"
export RUSTUP_HOME
CARGO_HOME="${GLOBAL_STACK_CARGO_HOME}"
export CARGO_HOME
NVM_DIR="${GLOBAL_STACK_NVM_DIR}"
export NVM_DIR
DENO_INSTALL="${GLOBAL_STACK_DENO_INSTALL}"
export DENO_INSTALL
DENO_INSTALL_ROOT="${GLOBAL_STACK_DENO_INSTALL_ROOT}"
export DENO_INSTALL_ROOT
DENO_DIR="${GLOBAL_STACK_DENO_DIR}"
export DENO_DIR
BUN_INSTALL="${GLOBAL_STACK_BUN_INSTALL}"
export BUN_INSTALL
YARN_OFFLINE_MIRROR="${GLOBAL_STACK_YARN_OFFLINE_MIRROR}"
export YARN_OFFLINE_MIRROR
YARN_CACHE_FOLDER="${GLOBAL_STACK_YARN_CACHE_FOLDER}"
export YARN_CACHE_FOLDER
YARN_GLOBAL_FOLDER="${GLOBAL_STACK_YARN_GLOBAL_FOLDER}"
export YARN_GLOBAL_FOLDER
PNPM_HOME="${GLOBAL_STACK_PNPM_GLOBAL_DIR}"
export PNPM_HOME
NPM_CACHE_DIR="${GLOBAL_STACK_NPM_CACHE_DIR}"
export NPM_CACHE_DIR
PHPBREW_BIN="${GLOBAL_STACK_PHPBREW_BIN}"
export PHPBREW_BIN
PHPBREW_HOME="${GLOBAL_STACK_PHPBREW_HOME}"
export PHPBREW_HOME
PHPBREW_ROOT="${GLOBAL_STACK_PHPBREW_ROOT}"
export PHPBREW_ROOT
PHPBREW_SRC="${GLOBAL_STACK_PHPBREW_SRC}"
export PHPBREW_SRC
PHPBREW_SKIP_INIT="1"
export PHPBREW_SKIP_INIT
PHPBREW_RC_ENABLE="1"
export PHPBREW_RC_ENABLE
COMPOSER_HOME="${GLOBAL_STACK_COMPOSER_HOME}"
export COMPOSER_HOME
SYMFONY_HOME="${GLOBAL_STACK_SYMFONY_HOME}"
export SYMFONY_HOME
PYENV_ROOT="${GLOBAL_STACK_PYENV_ROOT}"
export PYENV_ROOT
PYTHON_VERSION="${GLOBAL_STACK_PYTHON3_VERSION_AS}"
export PYTHON_VERSION
PYENV_VERSION="${GLOBAL_STACK_PYTHON3_VERSION}"
export PYENV_VERSION
PHP_VERSION=${GLOBAL_STACK_PHPEDGE_VERSION}
export PHP_VERSION
PHPBREW_PHP="${GLOBAL_STACK_PHPEDGE_VERSION_NAME}"
export PHPBREW_PHP
PHPBREW_PHP_PATH="${PHPBREW_ROOT}/php/${PHPBREW_PHP}"
export PHPBREW_PHP_PATH
PHPBREW_PATH="${PHPBREW_PHP_PATH}/bin"
export PHPBREW_PATH
NODE_VERSION=${GLOBAL_STACK_NODEEDGE_VERSION_AS}
export NODE_VERSION
NVM_VERSION="${GLOBAL_STACK_NODEEDGE_VERSION}"
export NVM_VERSION
RBENV_ROOT="${GLOBAL_STACK_RBENV_ROOT}"
export RBENV_ROOT
RUBY_VERSION=${GLOBAL_STACK_RUBY4_VERSION_AS}
export RUBY_VERSION
RBENV_VERSION="${GLOBAL_STACK_RUBY4_VERSION}"
export RBENV_VERSION
FVM_CACHE_PATH=${GLOBAL_STACK_FVM_CACHE_PATH}
export FVM_CACHE_PATH
FVM_GIT_CACHE_PATH=${GLOBAL_STACK_FVM_GIT_CACHE_PATH}
export FVM_GIT_CACHE_PATH
FVM_USE_GIT_CACHE=${GLOBAL_STACK_FVM_USE_GIT_CACHE}
export FVM_USE_GIT_CACHE
FVM_FLUTTER_URL=${GLOBAL_STACK_FVM_FLUTTER_URL}
export FVM_FLUTTER_URL
FLUTTER_VERSION=${GLOBAL_STACK_FLUTTER3_VERSION}
export FLUTTER_VERSION
FLUTTER_ROOT=${GLOBAL_STACK_FLUTTER3_ROOT}
export FLUTTER_ROOT
FLUTTER_HOME=${GLOBAL_STACK_FLUTTER3_HOME}
export FLUTTER_HOME

PATH="${GLOBAL_STACK_DOCKER_WORKDIR}/phorj/target/release:${FVM_CACHE_PATH}/versions/${FLUTTER_VERSION:-}/bin:${RBENV_ROOT}/bin:${PYENV_ROOT}/bin:${GLOBAL_STACK_DOCKER_TOOLS_PATH}/bin:${COMPOSER_HOME}/vendor/bin:${COMPOSER_HOME}/source/bin:${SYMFONY_HOME}/bin:${PHPBREW_BIN}:${PHPBREW_SRC}/bin:${PHPBREW_PHP_PATH}/bin:${PHPBREW_PHP_PATH}/sbin:${PNPM_HOME}:${PNPM_HOME}/4/node_modules/.bin:${PNPM_HOME}/5/node_modules/.bin:${YARN_GLOBAL_FOLDER}/bin:${DENO_INSTALL}/bin:${BUN_INSTALL}/bin:${CARGO_HOME}/bin:${RUSTUP_HOME}/toolchains/stable-x86_64-unknown-linux-gnu/bin:${PUB_CACHE}/bin:${JAVA_HOME}/bin:${ANDROID_HOME}/cmdline-tools/bin:${ANDROID_HOME}/cmdline-tools/tools/bin:${ANDROID_HOME}/tools:${ANDROID_HOME}/tools/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/build-tools/${GLOBAL_STACK_ANDROID_BUILD_TOOLS_VERSION}:${ANDROID_HOME}/cmdline-tools/${GLOBAL_STACK_ANDROID_CMDLINE_TOOLS_VERSION}/bin:${ANDROID_NDK_HOME}:${PATH}"
if [ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.${RUBY_VERSION}" ]; then
	PATH="${RBENV_ROOT}/versions/$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.${RUBY_VERSION}")/bin:${PATH}"
fi
if [ -d /opt/${GLOBAL_STACK_DOCKER_USER_ID}/sonar-scanner-cli/bin ]; then 
	PATH="/opt/${GLOBAL_STACK_DOCKER_USER_ID}/sonar-scanner-cli/bin:${PATH}"
fi
if [ -d /opt/${GLOBAL_STACK_DOCKER_USER_ID}/task ]; then 
	PATH="/opt/${GLOBAL_STACK_DOCKER_USER_ID}/task:${PATH}"
fi
if [ -d /opt/${GLOBAL_STACK_DOCKER_USER_ID}/bat ]; then 
	PATH="/opt/${GLOBAL_STACK_DOCKER_USER_ID}/bat:${PATH}"
fi
if [ -d "${GOROOT}"/bin ]; then 
	PATH="${GOROOT}/bin:${PATH}"
fi
if [[ -d "${GLOBAL_STACK_ZIGPATH}" ]]; then 
    PATH="${GLOBAL_STACK_ZIGPATH}:${PATH}"
fi
if [[ -d "${GLOBAL_STACK_HURLPATH}/bin" ]]; then 
	PATH="${GLOBAL_STACK_HURLPATH}/bin:${PATH}"
fi

export PATH

# >>> gs-quiet
# This file is read by EVERY shell that sources /etc/profile, non-interactive
# ones included (scripts, `bash -c`, agent/tool harnesses, and
# bin/open-all-envs.sh which sources it directly). The SDKMAN installer, `sdk
# use`, the per-package `**** Using ...` echoes, `nvm use` and `phpbrew switch`
# each print a banner — together ~90 lines on every single shell start, which is
# noise when nobody is watching and a real cost inside a tool harness.
#
# _gs_quiet keeps the side effects and drops only the chatter: it runs its
# argument as a plain command in THIS shell, so PATH edits and exports made by
# those shell functions still apply. Interactive shells are untouched — a human
# logging in still gets the full version report.
if [[ $- == *i* ]]; then
	_gs_quiet() { "$@"; }
else
	_gs_quiet() { "$@" > /dev/null 2>&1; }
fi
# <<< gs-quiet

if [[ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/sdkman.installer.sh ]]; then
	chmod a+x "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/sdkman.installer.sh
	_gs_quiet "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/sdkman.installer.sh
fi
if [[ -f "${SDKMAN_DIR}/bin/sdkman-init.sh" ]]; then
	chmod a+x "${SDKMAN_DIR}/bin/sdkman-init.sh"
	source "${SDKMAN_DIR}/bin/sdkman-init.sh"
fi
if [[ "" != "$(command -v sdk)" ]]; then
	mkdir -p "${HOME}/.sdkman/etc/"
	touch "${HOME}/.sdkman/etc/config"
	echo "sdkman_healthcheck_enable=false" > "${HOME}/.sdkman/etc/config"

	source "${HOME}/.sdkman/etc/config"

	_gs_quiet sdk use java ${GLOBAL_STACK_JAVA26_VERSION}

	source "${GLOBAL_STACK_DOCKER_ROOT_PATH}"/docker/config/dist/bin/base-bin/global-stack-base-setup-packages.sh
	_gs_quiet global_stack_base_setup_packages \
		--prefix='GLOBAL_STACK_JAVA' \
		--command='echo -e "**** Using ${PACKAGE_NAME} ${PACKAGE_VERSION}"' \
		--command='sdk use ${PACKAGE_NAME} "${PACKAGE_VERSION}"'
fi

if [[ -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}"/mise.shellrc ]]; then
	source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}"/mise.shellrc
	eval "$(mise activate ${GLOBAL_STACK_SHELL})"
fi

[ -s "${PHPBREW_ROOT}"/bashrc ] && source "${PHPBREW_ROOT}"/bashrc
[ -s "${NVM_DIR}/nvm.sh" ] && source "${NVM_DIR}/nvm.sh"  # This loads nvm
[ -s "${NVM_DIR}/bash_completion" ] && source "${NVM_DIR}/bash_completion"  # This loads nvm bash_completion
if [[ "" != "$(command -v pyenv)" ]]; then
	eval "$(pyenv init -)"
	eval "$(pyenv init --path)"
fi
if [[ "" != "$(command -v rbenv)" ]]; then
	eval "$(rbenv init - ${GLOBAL_STACK_SHELL})"
fi
if [[ "" != "$(command -v nvm)" ]]; then
	_gs_quiet nvm use "${NVM_VERSION}"
fi
if [[ "" != "$(command -v phpbrew)" ]]; then
	_gs_quiet phpbrew switch ${PHPBREW_PHP}

	LD_LIBRARY_PATH="$(php-config --lib-dir):${LD_LIBRARY_PATH}"
	export LD_LIBRARY_PATH
fi
if [[ "" != "$(command -v task)" ]]; then
	eval "$(task --completion ${GLOBAL_STACK_SHELL})"
fi
if [[ "" != "$(command -v adb)" ]]; then
	if ! nc -z localhost 5037 >/dev/null 2>&1; then
		adb -a nodaemon server start &> /dev/null &
	fi
fi
