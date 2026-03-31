#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
trap 'stackCatch ${?} ${LINENO} "${BASH_COMMAND}"' EXIT ERR PIPE SIGPIPE SIGHUP
stackCatch() {
  if [ "${1}" != "0" ]; then
    # error handling goes here
    echo "Error detected !!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${2} ** ** message: ${3} ** phpbrew (${PHP_VERSION_AS}) ${PHPBREW_MODE:-} global-stack-phpbrew-install-tools.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

COMPOSER_PHAR_FILE="${COMPOSER_SOURCE}/bin/composer"
# COMPOSER_LATEST="$(curl --silent https://api.github.com/repos/composer/composer/releases | grep '"name": "[0-9vV]' | sed 's/"name"\: "//g' | sed 's/",//g' | awk '!/RC/ && !/[a-zA-Z]/' | sort --version-sort --field-separator=. | tail -n1 | sed 's/    //g')"
COMPOSER_LATEST=${GLOBAL_STACK_COMPOSER_VERSION}
if [[ -f "${COMPOSER_PHAR_FILE}" && "${COMPOSER_LATEST}" = "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.composer")" ]]; then
    echo -e "\n${COMPOSER_PHAR_FILE} already installed ($(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.composer") - ${COMPOSER_LATEST})."
else
    echo -e "\nInstalling ${COMPOSER_PHAR_FILE}."
    echo -e "${COMPOSER_LATEST}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.composer"
    rm -rf "${COMPOSER_SOURCE}" "${COMPOSER_HOME}/bin/composer"
    mkdir -p "${COMPOSER_SOURCE}"
	git clone --progress --verbose --branch "${COMPOSER_LATEST}" https://github.com/composer/composer.git --depth 1 "${COMPOSER_SOURCE}"
    chmod a+x "${COMPOSER_SOURCE}/bin/composer"
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    php composer-setup.php --install-dir="${COMPOSER_HOME}/bin" --filename=composer
    rm composer-setup.php 2> /dev/null
    chmod a+x "${COMPOSER_HOME}/bin/composer"

    rsync -rav ${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-composer/source/ "${COMPOSER_SOURCE}"
    cd "${COMPOSER_SOURCE}" && php "${COMPOSER_HOME}/bin/composer" install

    git -C "${COMPOSER_SOURCE}" config core.fileMode false
fi

echo -e "\n*** Composer -- installing laravel/installer."
composer global require --ignore-platform-reqs laravel/installer
echo -e "\n*** Composer -- updating globals."
composer global update --ignore-platform-reqs --with-all-dependencies

ZEPHIR_LANG_PHAR_FILE="${PHPBREW_BIN}/zephir"
# ZEPHIR_LANG_LATEST=$(curl --silent https://api.github.com/repos/zephir-lang/zephir/releases/latest | jq .name -r)
ZEPHIR_LANG_LATEST=${GLOBAL_STACK_ZEPHIR_LANG_VERSION}
if [[ -f "${ZEPHIR_LANG_PHAR_FILE}" && "${ZEPHIR_LANG_LATEST}" = "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.zephir")" ]]; then
    echo -e "\n${ZEPHIR_LANG_PHAR_FILE} already installed ($(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.zephir") - ${ZEPHIR_LANG_LATEST})."
else
    echo -e "\nInstalling ${ZEPHIR_LANG_PHAR_FILE}."
    echo -e "${ZEPHIR_LANG_LATEST}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.zephir"
    wget https://github.com/zephir-lang/zephir/releases/download/${ZEPHIR_LANG_LATEST}/zephir.phar
    mv zephir.phar "${ZEPHIR_LANG_PHAR_FILE}"
    chmod a+x "${ZEPHIR_LANG_PHAR_FILE}"
fi
rm -rf zephir.pha*

PHALCON_DEVTOOLS_PHAR_FILE="${PHPBREW_BIN}/phalcon"
# PHALCON_DEVTOOLS_LATEST=$(curl --silent https://api.github.com/repos/phalcon/phalcon-devtools/releases/latest | jq .name -r)
PHALCON_DEVTOOLS_LATEST=${GLOBAL_STACK_PHALCON_DEVTOOLS_VERSION}
if [[ -f "${PHALCON_DEVTOOLS_PHAR_FILE}" && "${PHALCON_DEVTOOLS_LATEST}" = "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.phalcon")" ]]; then
    echo -e "\n${PHALCON_DEVTOOLS_PHAR_FILE} already installed ($(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.phalcon") - ${PHALCON_DEVTOOLS_LATEST})."
else
    echo -e "\nInstalling ${PHALCON_DEVTOOLS_PHAR_FILE}."
    echo -e "${PHALCON_DEVTOOLS_LATEST}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.phalcon"
    wget https://github.com/phalcon/phalcon-devtools/releases/download/${PHALCON_DEVTOOLS_LATEST}/phalcon.phar
    mv phalcon.phar "${PHALCON_DEVTOOLS_PHAR_FILE}"
    chmod a+x "${PHALCON_DEVTOOLS_PHAR_FILE}"
fi
rm -rf phalcon.pha*

DEPLOYER_PHAR_FILE="${PHPBREW_BIN}/dep"
if [ -f "${DEPLOYER_PHAR_FILE}" ]; then
    echo -e "\n${DEPLOYER_PHAR_FILE} already installed."
    echo -e "\nUpdating deployer"
    # dep self-update --upgrade
else
    echo -e "\nInstalling ${DEPLOYER_PHAR_FILE}."
    echo -e "${GLOBAL_STACK_DEPLOYER_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.deployer"
    curl -LO https://github.com/deployphp/deployer/releases/download/${GLOBAL_STACK_DEPLOYER_VERSION}/deployer.phar
    mv deployer.phar "${DEPLOYER_PHAR_FILE}" 2> /dev/null
    chmod a+x "${DEPLOYER_PHAR_FILE}" 2> /dev/null
fi

# SYMFONY_INSTALLER_PHAR_FILE="${PHPBREW_BIN}/symfony-installer"
# if [ -f "${SYMFONY_INSTALLER_PHAR_FILE}" ]; then
#     echo -e "\n${SYMFONY_INSTALLER_PHAR_FILE} already installed."
#     echo -e "\nUpdating symfony installer"
#     symfony-installer self-update
# else
#     echo -e "\nInstalling ${SYMFONY_INSTALLER_PHAR_FILE}."
#     curl -LsS https://symfony.com/installer -o "${SYMFONY_INSTALLER_PHAR_FILE}"
#     chmod a+x "${SYMFONY_INSTALLER_PHAR_FILE}" 2> /dev/null
# fi

SYMFONY_CLI_PHAR_FILE="${SYMFONY_HOME}/bin/symfony"
if [ -f "${SYMFONY_CLI_PHAR_FILE}" ]; then
    echo -e "\n${SYMFONY_CLI_PHAR_FILE} already installed."
    # echo -e "\nUpdating symfony cli"
    # symfony self:update
else
    echo -e "\nInstalling ${SYMFONY_CLI_PHAR_FILE}."
    echo -e "${GLOBAL_STACK_SYMFONY_CLI_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.symfony-cli"
    curl -LO https://github.com/symfony-cli/symfony-cli/releases/download/${GLOBAL_STACK_SYMFONY_CLI_VERSION}/symfony-cli_linux_amd64.tar.gz
    tar --extract --file=symfony-cli_linux_amd64.tar.gz symfony
    chmod a+x ./symfony 2> /dev/null
    mv ./symfony "${SYMFONY_HOME}/bin/symfony"
    chmod a+x "${SYMFONY_CLI_PHAR_FILE}" 2> /dev/null
    rm -rf symfony-cli_linux_amd64.tar.gz 2> /dev/null
fi

PICKLE_PHAR_FILE="${PHPBREW_BIN}/pickle"
# PICKLE_LATEST=$(curl --silent https://api.github.com/repos/FriendsOfPHP/pickle/releases/latest | jq .name -r)
PICKLE_LATEST=${GLOBAL_STACK_PICKLE_VERSION}
if [[ -f "${PICKLE_PHAR_FILE}" && "${PICKLE_LATEST}" = "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.pickle")" ]]; then
    echo -e "\n${PICKLE_PHAR_FILE} already installed ($(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.pickle") - ${PICKLE_LATEST})."
else
    echo -e "\nInstalling ${PICKLE_PHAR_FILE}."
    echo -e "${PICKLE_LATEST}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.pickle"
    wget https://github.com/FriendsOfPHP/pickle/releases/download/${PICKLE_LATEST}/pickle.phar
    mv pickle.phar "${PICKLE_PHAR_FILE}"
    chmod a+x "${PICKLE_PHAR_FILE}"
fi
rm -rf pickle.pha*

PIE_PHAR_FILE="${PHPBREW_BIN}/pie"
PIE_LATEST=${GLOBAL_STACK_PIE_VERSION}
if [[ -f "${PIE_PHAR_FILE}" && "${PIE_LATEST}" = "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.pie")" ]]; then
    echo -e "\n${PIE_PHAR_FILE} already installed ($(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.pie") - ${PIE_LATEST})."
else
    echo -e "\nInstalling ${PIE_PHAR_FILE}."
    echo -e "${PIE_LATEST}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.pie"
    wget https://github.com/php/pie/releases/download/${PIE_LATEST}/pie.phar
    mv pie.phar "${PIE_PHAR_FILE}"
    chmod a+x "${PIE_PHAR_FILE}"
fi
rm -rf pie.pha*

MAGO_PHAR_FILE="${PHPBREW_BIN}/mago"
MAGO_LATEST=${GLOBAL_STACK_MAGO_VERSION}
if [[ -f "${MAGO_PHAR_FILE}" && "${MAGO_LATEST}" = "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.mago")" ]]; then
    echo -e "\n${MAGO_PHAR_FILE} already installed ($(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.mago") - ${MAGO_LATEST})."
else
    echo -e "\nInstalling ${MAGO_PHAR_FILE}."
    echo -e "${MAGO_LATEST}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.mago"
    curl --proto '=https' --tlsv1.2 -sSf https://carthage.software/mago.sh | bash -s -- --install-dir=${PHPBREW_BIN} --version=${MAGO_LATEST}
    chmod a+x "${MAGO_PHAR_FILE}"
fi

CASTOR_PHAR_FILE="${PHPBREW_BIN}/castor"
CASTOR_LATEST=${GLOBAL_STACK_CASTOR_VERSION}
if [[ -f "${CASTOR_PHAR_FILE}" && "${CASTOR_LATEST}" = "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.castor")" ]]; then
    echo -e "\n${CASTOR_PHAR_FILE} already installed ($(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.castor") - ${CASTOR_LATEST})."
else
    echo -e "\nInstalling ${CASTOR_PHAR_FILE}."
    echo -e "${CASTOR_LATEST}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.castor"
    curl "https://castor.jolicode.com/install" | bash -s -- --install-dir=${PHPBREW_BIN} --version=${CASTOR_LATEST}
    chmod a+x "${CASTOR_PHAR_FILE}"
fi

FABPOT_LOCAL_PHP_SECURITY_CHECKER="${PHPBREW_BIN}/fabpot-local-php-security-checker"
# FABPOT_LOCAL_PHP_SECURITY_CHECKER_LATEST=$(curl --silent https://api.github.com/repos/fabpot/local-php-security-checker/releases/latest | jq .name -r)
FABPOT_LOCAL_PHP_SECURITY_CHECKER_LATEST=${GLOBAL_STACK_FABPOT_LOCAL_PHP_SECURITY_CHECKER_VERSION}
if [[ -f "${FABPOT_LOCAL_PHP_SECURITY_CHECKER}" && "${FABPOT_LOCAL_PHP_SECURITY_CHECKER_LATEST}" = "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.fabpot-local-php-security-checker")" ]]; then
    echo -e "\n${FABPOT_LOCAL_PHP_SECURITY_CHECKER} already installed ($(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.fabpot-local-php-security-checker") - ${FABPOT_LOCAL_PHP_SECURITY_CHECKER_LATEST})."
else
    echo -e "\nInstalling ${FABPOT_LOCAL_PHP_SECURITY_CHECKER}."
    echo -e "${FABPOT_LOCAL_PHP_SECURITY_CHECKER_LATEST}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.fabpot-local-php-security-checker"
    curl -LsS "https://github.com/fabpot/local-php-security-checker/releases/download/${FABPOT_LOCAL_PHP_SECURITY_CHECKER_LATEST}/local-php-security-checker_linux_amd64" -o "${FABPOT_LOCAL_PHP_SECURITY_CHECKER}"
    chmod a+x "${FABPOT_LOCAL_PHP_SECURITY_CHECKER}"
fi

mkdir -p ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp
sudo chmod -R a+rwx ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp
