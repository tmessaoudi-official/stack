#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

COMPOSER_PHAR_FILE="${COMPOSER_SOURCE}/bin/composer"
# COMPOSER_LATEST="$(curl --silent https://api.github.com/repos/composer/composer/releases | grep '"name": "[0-9vV]' | sed 's/"name"\: "//g' | sed 's/",//g' | awk '!/RC/ && !/[a-zA-Z]/' | sort --version-sort --field-separator=. | tail -n1 | sed 's/    //g')"
COMPOSER_LATEST=${GLOBAL_STACK_COMPOSER_VERSION}
# Row 17: converged on gs_version_gate. The hand-rolled compare this replaces was
# correct about WHEN to reinstall but wrote its marker BEFORE installing, so a
# failed install recorded success and every later boot skipped it. Marker is now
# written last in every block below.
_composer_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.composer" "${COMPOSER_LATEST}" "phpbrew.composer")"
if [ "${_composer_gate}" = "skip" ] && [ -f "${COMPOSER_PHAR_FILE}" ]; then
    echo -e "\n${COMPOSER_PHAR_FILE} already installed (${COMPOSER_LATEST})."
else
    echo -e "\nInstalling ${COMPOSER_PHAR_FILE}."
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
    printf '%s\n' "${COMPOSER_LATEST}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.composer"
fi

# laravel/installer — row 17, and the one case the Track 5 scope guard was widened
# for (developer ruling 2026-09-04). It used to be `composer global require` with
# NO version, followed by a blanket update of all globals, so a gate alone could
# not hold a pin: the update moved it straight back off.
# The update line is DELETED rather than constrained because it operated on exactly
# one package — laravel/installer is the only `composer global require` in the repo
# and the rsynced composer source seeds no composer.json, so it declared no others.
# Not a phar: the gate's floor is `composer global show`, not a file test.
_laravel_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.laravel-installer" "${GLOBAL_STACK_LARAVEL_INSTALLER_VERSION}" "phpbrew.laravel-installer")"
if [ "${_laravel_gate}" = "skip" ] && composer global show laravel/installer >/dev/null 2>&1; then
    echo -e "\n*** Composer -- laravel/installer already installed (${GLOBAL_STACK_LARAVEL_INSTALLER_VERSION})."
else
    echo -e "\n*** Composer -- installing laravel/installer ${GLOBAL_STACK_LARAVEL_INSTALLER_VERSION}."
    composer global require --ignore-platform-reqs "laravel/installer:${GLOBAL_STACK_LARAVEL_INSTALLER_VERSION}"
    printf '%s\n' "${GLOBAL_STACK_LARAVEL_INSTALLER_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.laravel-installer"
fi

ZEPHIR_LANG_PHAR_FILE="${PHPBREW_BIN}/zephir"
# ZEPHIR_LANG_LATEST=$(curl --silent https://api.github.com/repos/zephir-lang/zephir/releases/latest | jq .name -r)
ZEPHIR_LANG_LATEST=${GLOBAL_STACK_ZEPHIR_LANG_VERSION}
_zephir_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.zephir" "${ZEPHIR_LANG_LATEST}" "phpbrew.zephir")"
if [ "${_zephir_gate}" = "skip" ] && [ -f "${ZEPHIR_LANG_PHAR_FILE}" ]; then
    echo -e "\n${ZEPHIR_LANG_PHAR_FILE} already installed (${ZEPHIR_LANG_LATEST})."
else
    echo -e "\nInstalling ${ZEPHIR_LANG_PHAR_FILE}."
    curl --connect-timeout 30 --max-time 300 -fsSLO "https://github.com/zephir-lang/zephir/releases/download/${ZEPHIR_LANG_LATEST}/zephir.phar"
    mv zephir.phar "${ZEPHIR_LANG_PHAR_FILE}"
    chmod a+x "${ZEPHIR_LANG_PHAR_FILE}"
    printf '%s\n' "${ZEPHIR_LANG_LATEST}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.zephir"
fi
rm -rf zephir.pha*

PHALCON_DEVTOOLS_PHAR_FILE="${PHPBREW_BIN}/phalcon"
# PHALCON_DEVTOOLS_LATEST=$(curl --silent https://api.github.com/repos/phalcon/phalcon-devtools/releases/latest | jq .name -r)
PHALCON_DEVTOOLS_LATEST=${GLOBAL_STACK_PHALCON_DEVTOOLS_VERSION}
_phalcon_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.phalcon" "${PHALCON_DEVTOOLS_LATEST}" "phpbrew.phalcon")"
if [ "${_phalcon_gate}" = "skip" ] && [ -f "${PHALCON_DEVTOOLS_PHAR_FILE}" ]; then
    echo -e "\n${PHALCON_DEVTOOLS_PHAR_FILE} already installed (${PHALCON_DEVTOOLS_LATEST})."
else
    echo -e "\nInstalling ${PHALCON_DEVTOOLS_PHAR_FILE}."
    curl --connect-timeout 30 --max-time 300 -fsSLO "https://github.com/phalcon/phalcon-devtools/releases/download/${PHALCON_DEVTOOLS_LATEST}/phalcon.phar"
    mv phalcon.phar "${PHALCON_DEVTOOLS_PHAR_FILE}"
    chmod a+x "${PHALCON_DEVTOOLS_PHAR_FILE}"
    printf '%s\n' "${PHALCON_DEVTOOLS_LATEST}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.phalcon"
fi
rm -rf phalcon.pha*

DEPLOYER_PHAR_FILE="${PHPBREW_BIN}/dep"
# Was the write-only-marker shape: it WROTE phpbrew.deployer but the guard only
# asked whether the phar existed, so the marker was never read and a version bump
# did nothing.
_deployer_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.deployer" "${GLOBAL_STACK_DEPLOYER_VERSION}" "phpbrew.deployer")"
if [ "${_deployer_gate}" = "skip" ] && [ -f "${DEPLOYER_PHAR_FILE}" ]; then
    echo -e "\n${DEPLOYER_PHAR_FILE} already installed (${GLOBAL_STACK_DEPLOYER_VERSION})."
else
    echo -e "\nInstalling ${DEPLOYER_PHAR_FILE}."
    curl --connect-timeout 30 --max-time 300 -LO https://github.com/deployphp/deployer/releases/download/${GLOBAL_STACK_DEPLOYER_VERSION}/deployer.phar
    mv deployer.phar "${DEPLOYER_PHAR_FILE}" 2> /dev/null
    chmod a+x "${DEPLOYER_PHAR_FILE}" 2> /dev/null
    printf '%s\n' "${GLOBAL_STACK_DEPLOYER_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.deployer"
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
# Same write-only-marker shape as deployer above.
_symfony_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.symfony-cli" "${GLOBAL_STACK_SYMFONY_CLI_VERSION}" "phpbrew.symfony-cli")"
if [ "${_symfony_gate}" = "skip" ] && [ -f "${SYMFONY_CLI_PHAR_FILE}" ]; then
    echo -e "\n${SYMFONY_CLI_PHAR_FILE} already installed (${GLOBAL_STACK_SYMFONY_CLI_VERSION})."
    # symfony self:update deliberately not run — the .env pin is the source of truth
else
    echo -e "\nInstalling ${SYMFONY_CLI_PHAR_FILE}."
    curl --connect-timeout 30 --max-time 300 -LO https://github.com/symfony-cli/symfony-cli/releases/download/${GLOBAL_STACK_SYMFONY_CLI_VERSION}/symfony-cli_linux_amd64.tar.gz
    tar --extract --file=symfony-cli_linux_amd64.tar.gz symfony
    chmod a+x ./symfony 2> /dev/null
    mv ./symfony "${SYMFONY_HOME}/bin/symfony"
    chmod a+x "${SYMFONY_CLI_PHAR_FILE}" 2> /dev/null
    rm -rf symfony-cli_linux_amd64.tar.gz 2> /dev/null
    printf '%s\n' "${GLOBAL_STACK_SYMFONY_CLI_VERSION}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.symfony-cli"
fi

PICKLE_PHAR_FILE="${PHPBREW_BIN}/pickle"
# PICKLE_LATEST=$(curl --silent https://api.github.com/repos/FriendsOfPHP/pickle/releases/latest | jq .name -r)
PICKLE_LATEST=${GLOBAL_STACK_PICKLE_VERSION}
_pickle_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.pickle" "${PICKLE_LATEST}" "phpbrew.pickle")"
if [ "${_pickle_gate}" = "skip" ] && [ -f "${PICKLE_PHAR_FILE}" ]; then
    echo -e "\n${PICKLE_PHAR_FILE} already installed (${PICKLE_LATEST})."
else
    echo -e "\nInstalling ${PICKLE_PHAR_FILE}."
    curl --connect-timeout 30 --max-time 300 -fsSLO "https://github.com/FriendsOfPHP/pickle/releases/download/${PICKLE_LATEST}/pickle.phar"
    mv pickle.phar "${PICKLE_PHAR_FILE}"
    chmod a+x "${PICKLE_PHAR_FILE}"
    printf '%s\n' "${PICKLE_LATEST}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.pickle"
fi
rm -rf pickle.pha*

PIE_PHAR_FILE="${PHPBREW_BIN}/pie"
PIE_LATEST=${GLOBAL_STACK_PIE_VERSION}
_pie_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.pie" "${PIE_LATEST}" "phpbrew.pie")"
if [ "${_pie_gate}" = "skip" ] && [ -f "${PIE_PHAR_FILE}" ]; then
    echo -e "\n${PIE_PHAR_FILE} already installed (${PIE_LATEST})."
else
    echo -e "\nInstalling ${PIE_PHAR_FILE}."
    curl --connect-timeout 30 --max-time 300 -fsSLO "https://github.com/php/pie/releases/download/${PIE_LATEST}/pie.phar"
    mv pie.phar "${PIE_PHAR_FILE}"
    chmod a+x "${PIE_PHAR_FILE}"
    printf '%s\n' "${PIE_LATEST}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.pie"
fi
rm -rf pie.pha*

MAGO_PHAR_FILE="${PHPBREW_BIN}/mago"
MAGO_LATEST=${GLOBAL_STACK_MAGO_VERSION}
_mago_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.mago" "${MAGO_LATEST}" "phpbrew.mago")"
if [ "${_mago_gate}" = "skip" ] && [ -f "${MAGO_PHAR_FILE}" ]; then
    echo -e "\n${MAGO_PHAR_FILE} already installed (${MAGO_LATEST})."
else
    echo -e "\nInstalling ${MAGO_PHAR_FILE}."
    curl --connect-timeout 30 --max-time 300 --proto '=https' --tlsv1.2 -sSf https://carthage.software/mago.sh | bash -s -- --install-dir=${PHPBREW_BIN} --version=${MAGO_LATEST}
    chmod a+x "${MAGO_PHAR_FILE}"
    printf '%s\n' "${MAGO_LATEST}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.mago"
fi

CASTOR_PHAR_FILE="${PHPBREW_BIN}/castor"
CASTOR_LATEST=${GLOBAL_STACK_CASTOR_VERSION}
_castor_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.castor" "${CASTOR_LATEST}" "phpbrew.castor")"
if [ "${_castor_gate}" = "skip" ] && [ -f "${CASTOR_PHAR_FILE}" ]; then
    echo -e "\n${CASTOR_PHAR_FILE} already installed (${CASTOR_LATEST})."
else
    echo -e "\nInstalling ${CASTOR_PHAR_FILE}."
    curl --connect-timeout 30 --max-time 300 "https://castor.jolicode.com/install" | bash -s -- --install-dir=${PHPBREW_BIN} --version=${CASTOR_LATEST}
    chmod a+x "${CASTOR_PHAR_FILE}"
    printf '%s\n' "${CASTOR_LATEST}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.castor"
fi

FABPOT_LOCAL_PHP_SECURITY_CHECKER="${PHPBREW_BIN}/fabpot-local-php-security-checker"
# FABPOT_LOCAL_PHP_SECURITY_CHECKER_LATEST=$(curl --silent https://api.github.com/repos/fabpot/local-php-security-checker/releases/latest | jq .name -r)
FABPOT_LOCAL_PHP_SECURITY_CHECKER_LATEST=${GLOBAL_STACK_FABPOT_LOCAL_PHP_SECURITY_CHECKER_VERSION}
_fabpot_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.fabpot-local-php-security-checker" "${FABPOT_LOCAL_PHP_SECURITY_CHECKER_LATEST}" "phpbrew.fabpot-local-php-security-checker")"
if [ "${_fabpot_gate}" = "skip" ] && [ -f "${FABPOT_LOCAL_PHP_SECURITY_CHECKER}" ]; then
    echo -e "\n${FABPOT_LOCAL_PHP_SECURITY_CHECKER} already installed (${FABPOT_LOCAL_PHP_SECURITY_CHECKER_LATEST})."
else
    echo -e "\nInstalling ${FABPOT_LOCAL_PHP_SECURITY_CHECKER}."
    curl --connect-timeout 30 --max-time 300 -LsS "https://github.com/fabpot/local-php-security-checker/releases/download/${FABPOT_LOCAL_PHP_SECURITY_CHECKER_LATEST}/local-php-security-checker_linux_amd64" -o "${FABPOT_LOCAL_PHP_SECURITY_CHECKER}"
    chmod a+x "${FABPOT_LOCAL_PHP_SECURITY_CHECKER}"
    printf '%s\n' "${FABPOT_LOCAL_PHP_SECURITY_CHECKER_LATEST}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.fabpot-local-php-security-checker"
fi

mkdir -p ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp
sudo chmod -R a+rwx ${GLOBAL_STACK_DOCKER_TOOLS_PATH}/frankenphp
