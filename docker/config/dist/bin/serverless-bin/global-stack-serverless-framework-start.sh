#!/bin/bash

# # Enable strict error handling and debugging
# set -xeEuo pipefail
# shopt -s extdebug
# IFS=$'\n\t'

# # Function to handle errors and trap cleanup
# stackCatch() {
#   local exit_code=${1}
#   local line_num=${2}
#   local command=${3}
#   if [[ ${exit_code} -ne 0 ]]; then
#     echo "Error detected!"
#     echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - exit_code: ${exit_code}, line: ${line_num}, command: ${command}, serverless-framework global-stack-serverless-framework-start.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
#     sleep infinity
#   fi
# }

# # Trap errors for cleanup or error reporting
# trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' ERR EXIT

SECONDS=0

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

sleep 1

global-stack-base-wait-for.sh \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/web-server" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/node.${NODE_VERSION_AS}" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/java.${JAVA_VERSION_AS}" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/ruby.${RUBY_VERSION_AS}" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/python.${PYTHON_VERSION_AS}" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/php.${PHP_VERSION_AS}" \
  "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rust"

PATH="${RUSTUP_HOME}/bin:${RUSTUP_HOME}/toolchains/stable-x86_64-unknown-linux-gnu/bin:${CARGO_HOME}/bin:${COMPOSER_HOME}/vendor/bin:${COMPOSER_SOURCE}/bin:${SYMFONY_HOME}/bin:${PHPBREW_SRC}/bin:${PYENV_ROOT}/bin:${GLOBAL_STACK_DOCKER_TOOLS_PATH}/yarn/bin:${DENO_DIR}/bin:${BUN_INSTALL}/bin:${PNPM_HOME}:${RBENV_ROOT}/bin:${PATH}"
export PATH

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${RUSTUP_HOME}/bin:${RUSTUP_HOME}/toolchains/stable-x86_64-unknown-linux-gnu/bin:${CARGO_HOME}/bin:${COMPOSER_HOME}/vendor/bin:${COMPOSER_SOURCE}/bin:${SYMFONY_HOME}/bin:${PHPBREW_SRC}/bin:${PYENV_ROOT}/bin:${GLOBAL_STACK_DOCKER_TOOLS_PATH}/yarn/bin:${DENO_DIR}/bin:${BUN_INSTALL}/bin:${PNPM_HOME}:${RBENV_ROOT}/bin:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

[ -f ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/run/elasticmq.pid ] && sudo kill -9 $(cat ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/run/elasticmq.pid)
[ -f ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/run/serverless-framework.pid ] && sudo kill -9 $(cat ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/run/serverless-framework.pid)

source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc"
source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc
source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/pyenv.shellrc
source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/phpbrew.shellrc
source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/sdkman.shellrc
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

sdk use java "${JAVA_VERSION}"
echo "sdk use java '${JAVA_VERSION}'" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

source /usr/local/bin/global-stack-base-setup-packages.sh
global_stack_base_setup_packages \
  --prefix='SDKMAN' \
  --command='echo -e "**** Using ${PACKAGE_NAME} ${PACKAGE_VERSION}"' \
  --command='sdk use ${PACKAGE_NAME} "${PACKAGE_VERSION}"' \
  --command='echo "sdk use ${PACKAGE_NAME} \"${PACKAGE_VERSION}\"" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"'

global-stack-base-init-mkcert.sh
global-stack-nvm-eval-yarnrc.sh

# @todo put versions in .env
# @todo refactor all serverless files

sudo chmod -R a+rwx ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework
sudo chown -R "${GLOBAL_STACK_DOCKER_USER_ID}:${GLOBAL_STACK_DOCKER_GROUP_ID}" ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework

rm -rf \
  ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/build \
  ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/dist \
  ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/serverless.js* \
  ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/.serverless \
  ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/conf \
  ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/src \
  ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/tmp \
  ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/run \
  ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/overrides/ready

[ -d ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/overrides ] && find ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/overrides -mindepth 1 -maxdepth 1 ! -name "overriden" -exec rm -rf {} +

mkdir -p \
  ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework \
  ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/storage/s3-buckets \
  ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/storage/sqs-queues \
  ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/storage/sqs-messages \
  ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/log \
  ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/run \
  ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/overrides/ready

rsync -raz --ignore-times \
  ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/serverless/ \
  ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework


if [[ ! -d ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/bin ]]; then
  mkdir -p ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/bin
fi

if [[ ! -f ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/bin/elasticmq-server-all.jar ]]; then
  curl -fsSL -o "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/bin/elasticmq-server-all.jar" "https://github.com/softwaremill/elasticmq/releases/download/${GLOBAL_STACK_SERVERLESS_FRAMEWORK_ELASTICMQ_VERSION}/elasticmq-server-all-$(echo "${GLOBAL_STACK_SERVERLESS_FRAMEWORK_ELASTICMQ_VERSION}" | sed 's/v//').jar"
fi

chmod a+x ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/bin/elasticmq-server-all.jar

cd ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework

if [[ -f ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/serverless.local.ts ]]; then
  mv \
    ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/serverless.local.ts \
    ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/serverless.ts
fi

rm -rf ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/tmp/finder-result.txt ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/tmp/finder.sh

npm install

for overriden_package in "s3rver"; do
  if [[ ! -d ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/overrides/original/${overriden_package}/ ]]; then
    mkdir -p ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/overrides/original/${overriden_package}/
    cp -R ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/node_modules/${overriden_package}/* ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/overrides/original/${overriden_package}/
  fi

  original_dist_package="$(cat ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/overrides/original/${overriden_package}/package.json | grep '"version": ' | sed 's/.*"version": "//; s/",//')"
  node_modules_package="$(cat ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/node_modules/${overriden_package}/package.json | grep '"version": ' | sed 's/.*"version": "//; s/",//')"

  overriden_dist_package=$(cat ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/overrides/overriden/${overriden_package}/.version)

  if [[ "${original_dist_package}" != "${node_modules_package}" || "${overriden_dist_package}" != "${original_dist_package}" ]]; then
    echo -e "You need to upgrade ${overriden_package} from ${overriden_dist_package} to ${node_modules_package}"
    exit 1
  fi

  rm -rf ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/node_modules/${overriden_package}/ ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/overrides/ready/${overriden_package}/
  mkdir -p ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/node_modules/${overriden_package}/ ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/overrides/ready/${overriden_package}/

  cp -R ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/overrides/original/${overriden_package}/* ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/overrides/ready/${overriden_package}/
  cp -R ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/overrides/overriden/${overriden_package}/* ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/overrides/ready/${overriden_package}/
done

base_dir="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework"

mkdir -p ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/tmp
echo -e "#!/bin/bash\n\nfind \"${base_dir}\" \\( -path \"${base_dir}/node_modules\" -o -path \"${base_dir}/build\" -o -path \"${base_dir}/dist\" -o -path \"${base_dir}/bin\" -o -path \"${base_dir}/overrides/original\" -o -path \"${base_dir}/overrides/overriden\" -o -path \"${base_dir}/overrides/packages\" -o -path \"${base_dir}/.serverless\" -o -path \"${base_dir}/.serverless-offline\" -o -path \"${base_dir}/var\" \\) -prune -o -type f -print" > ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/tmp/finder.sh
chmod a+x ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/tmp/finder.sh

${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/tmp/finder.sh > ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/tmp/finder-result.txt
while IFS= read -r file || [[ -n "$file" ]]; do
  temp_file="${file}.tmp"
  > "${temp_file}"

  first_line=true
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
      while [[ ${line} =~ \$\{global_stack_process\.customEnv\.([^ \}]+)\} ]]; do
          var_name="${BASH_REMATCH[1]}"
          var_value="${!var_name:-}"
          line="${line/\$\{global_stack_process.customEnv.$var_name\}/$var_value}"
      done
      if [[ "${first_line}" = "true" ]]; then
        echo -n "${line}" >> "${temp_file}"
        first_line=false
      else
        echo -n "
${line}" >> "${temp_file}"
      fi
  done < "${file}"

  echo "" >> "${temp_file}"

  mv "${temp_file}" "${file}"
done < ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/tmp/finder-result.txt

for overriden_package in "s3rver"; do
  cp -R ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/overrides/ready/${overriden_package}/* ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/node_modules/${overriden_package}/
done

npm run build

touch ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/log/elasticmq-$(date '+%d-%m-%Y').log ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/log/serverless-framework-$(date '+%d-%m-%Y').log

[ "${GLOBAL_STACK_DOCKER_IN_DOCKER}" = "true" ] && global-stack-base-start-docker.sh || echo -e "\n Docker In Docker will not be started"

java -Dconfig.file=${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/conf/elasticmq/custom.conf -Dlogback.configurationFile=${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/conf/elasticmq/logback.xml -jar ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/bin/elasticmq-server-all.jar >> ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/log/elasticmq-$(date '+%d-%m-%Y').log 2>&1 &
elasticmq_pid=$!
serverless offline start >> ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/log/serverless-framework-$(date '+%d-%m-%Y').log 2>&1 &
serverless_framework_pid=$!

echo ${elasticmq_pid} > ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/run/elasticmq.pid
echo ${serverless_framework_pid} > ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/serverless-framework/var/run/serverless-framework.pid

global-stack-base-prepare-shell.sh
echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION=${SECONDS}
global-stack-base-print-success.sh "${DURATION}" "serverless (framework)"

echo "framework" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}"/serverless

sleep infinity