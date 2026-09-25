#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

# Pin-audit tranche 2 step 15 (ruling 2026-09-25; startup-prologue.test.sh §66-§68).
# Every tool below is downloaded into this temp dir and checked — published checksum
# where there is one, the tool's own version output where it can run — BEFORE the
# installed copy is replaced; the marker stays last. The prologue owns the EXIT trap,
# so the dir is removed at the end of the script and a FATAL leaves it in the
# container's /tmp. Every fallible check sits inside its `if`: a bare failing
# capture would fire the prologue's ERR trap before the FATAL could say why.
_pt_dl="$(mktemp -d)"
# symfony still downloads with `curl -O` into the CURRENT directory (the phar blocks did
# too, and ran `rm -rf zephir.pha*`-style globs there on EVERY boot until step 15b). The
# cwd is compose's `working_dir`, /stack/projects: the developer's own projects, where
# such a glob deleted a file of theirs (or, after the old composer block's bare `cd`,
# composer's source tree). Working in the temp dir keeps every download out of both.
cd "${_pt_dl}"

# _pt_names <output> <text right before the version> <version>: true when the output
# names exactly that version — the version must not continue with a digit or a dot,
# so 1.4.0 never accepts 1.4.00.
_pt_names() {
    local _pt_rest
    [[ "$1" == *"$2$3"* ]] || return 1
    _pt_rest="${1#*"$2$3"}"
    [[ ! "${_pt_rest}" =~ ^[0-9.] ]]
}

# _pt_fatal <message>: the reason on stderr, then exit 1 (the prologue writes the token).
_pt_fatal() {
    printf 'FATAL: %s\n' "$1" >&2
    exit 1
}

# _pt_phar <tool> <url>: download to ${_pt_dl}/<tool>.phar and open it as a Phar. With
# phar.require_hash on (the image's default) the open verifies the archive's signature,
# so a truncated file, an HTML error page and a single corrupted byte are all refused
# [measured in the 02phpbrew image, 2026-09-25]. PHP opens only a *.phar name, hence -o.
# None of these tools publishes a checksum, so this is their integrity check.
_pt_phar() {
    if ! curl --connect-timeout 30 --max-time 300 -fsSL -o "${_pt_dl}/$1.phar" "$2"; then
        _pt_fatal "$1 could not be downloaded from $2 - $1 left as it was"
    fi
    if ! php -r 'try { new Phar($argv[1]); } catch (Throwable $e) { exit(1); }' "${_pt_dl}/$1.phar" >/dev/null 2>&1; then
        _pt_fatal "$1 from $2 is not an intact phar - $1 left as it was"
    fi
}

# _pt_runs <file> <text right before the version> <version>: the file runs under php and
# names exactly that version. Only deployer and pie can run under the image's php;
# zephir, phalcon and pickle need mbstring, so their version is pinned by URL alone.
_pt_runs() {
    local _pt_v
    _pt_v="$(php "$1" --version --no-ansi 2>/dev/null)" && _pt_names "${_pt_v}" "$2" "$3"
}

# _pt_place <tool> <installed path>: replace the installed copy with the checked download
# and compare the two, so an interrupted copy cannot leave a marker behind.
_pt_place() {
    install -m 0755 "${_pt_dl}/$1.phar" "$2"
    if ! cmp -s "${_pt_dl}/$1.phar" "$2"; then
        _pt_fatal "the installed $1 differs from the checked download - marker not written"
    fi
}

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
    # Step 15a: this used to remove the source and the bootstrap phar FIRST, and the
    # bootstrap came from composer-setup.php with no --version (i.e. latest). Now the
    # pinned composer.phar is checked against its published sha256 and its version,
    # the source is cloned at the tag, overlaid and `composer install`ed in the temp
    # dir and version-checked, and only then do the old source and phar go. Only
    # source/ and bin/composer are replaced: COMPOSER_HOME/vendor (laravel) and the
    # cache stay. The temp dir is container /tmp, so the final move is a copy.
    _pt_c="${_pt_dl}/composer"
    mkdir -p "${_pt_c}"
    if ! curl --connect-timeout 30 --max-time 300 -fsSL -o "${_pt_c}/composer.phar" "https://getcomposer.org/download/${COMPOSER_LATEST}/composer.phar" || ! curl --connect-timeout 30 --max-time 60 -fsSL -o "${_pt_c}/composer.phar.sha256sum" "https://getcomposer.org/download/${COMPOSER_LATEST}/composer.phar.sha256sum"; then
        _pt_fatal "composer ${COMPOSER_LATEST} could not be downloaded from getcomposer.org - composer left as it was"
    fi
    if ! (cd "${_pt_c}" && sha256sum -c --quiet composer.phar.sha256sum >/dev/null 2>&1); then
        _pt_fatal "composer.phar ${COMPOSER_LATEST} does not match its published sha256 - composer left as it was"
    fi
    if ! _pt_got="$(php "${_pt_c}/composer.phar" --version --no-ansi 2>/dev/null)" || ! _pt_names "${_pt_got}" "Composer version " "${COMPOSER_LATEST}"; then
        _pt_fatal "the downloaded composer.phar is not ${COMPOSER_LATEST} - composer left as it was"
    fi
    if ! git clone --progress --verbose --branch "${COMPOSER_LATEST}" https://github.com/composer/composer.git --depth 1 "${_pt_c}/source"; then
        _pt_fatal "composer tag ${COMPOSER_LATEST} could not be cloned - composer left as it was"
    fi
    rsync -rav "${GLOBAL_STACK_DOCKER_ROOT_DIST_PATH}/conf/phpbrew-composer/source/" "${_pt_c}/source"
    if ! (cd "${_pt_c}/source" && php "${_pt_c}/composer.phar" install); then
        _pt_fatal "composer install failed in the ${COMPOSER_LATEST} source - composer left as it was"
    fi
    chmod a+x "${_pt_c}/source/bin/composer"
    if ! _pt_got="$(php "${_pt_c}/source/bin/composer" --version --no-ansi 2>/dev/null)" || ! _pt_names "${_pt_got}" "Composer version " "${COMPOSER_LATEST}"; then
        _pt_fatal "the composer built from source is not ${COMPOSER_LATEST} - composer left as it was"
    fi

    # Checked: from here on the old source and phar go.
    rm -rf "${COMPOSER_SOURCE}" "${COMPOSER_HOME}/bin/composer"
    mkdir -p "$(dirname "${COMPOSER_SOURCE}")" "${COMPOSER_HOME}/bin"
    mv -T "${_pt_c}/source" "${COMPOSER_SOURCE}"
    install -m 0755 "${_pt_c}/composer.phar" "${COMPOSER_HOME}/bin/composer"
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
    if ! _pt_got="$(php "${COMPOSER_HOME}/vendor/bin/laravel" --version --no-ansi 2>/dev/null)" \
        || ! _pt_names "${_pt_got}" "Laravel Installer " "${GLOBAL_STACK_LARAVEL_INSTALLER_VERSION#v}"; then
        _pt_fatal "laravel/installer does not report ${GLOBAL_STACK_LARAVEL_INSTALLER_VERSION} - marker not written"
    fi
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
    _pt_phar zephir "https://github.com/zephir-lang/zephir/releases/download/${ZEPHIR_LANG_LATEST}/zephir.phar"
    _pt_place zephir "${ZEPHIR_LANG_PHAR_FILE}"
    printf '%s\n' "${ZEPHIR_LANG_LATEST}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.zephir"
fi

PHALCON_DEVTOOLS_PHAR_FILE="${PHPBREW_BIN}/phalcon"
# PHALCON_DEVTOOLS_LATEST=$(curl --silent https://api.github.com/repos/phalcon/phalcon-devtools/releases/latest | jq .name -r)
PHALCON_DEVTOOLS_LATEST=${GLOBAL_STACK_PHALCON_DEVTOOLS_VERSION}
_phalcon_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.phalcon" "${PHALCON_DEVTOOLS_LATEST}" "phpbrew.phalcon")"
if [ "${_phalcon_gate}" = "skip" ] && [ -f "${PHALCON_DEVTOOLS_PHAR_FILE}" ]; then
    echo -e "\n${PHALCON_DEVTOOLS_PHAR_FILE} already installed (${PHALCON_DEVTOOLS_LATEST})."
else
    echo -e "\nInstalling ${PHALCON_DEVTOOLS_PHAR_FILE}."
    _pt_phar phalcon "https://github.com/phalcon/phalcon-devtools/releases/download/${PHALCON_DEVTOOLS_LATEST}/phalcon.phar"
    _pt_place phalcon "${PHALCON_DEVTOOLS_PHAR_FILE}"
    printf '%s\n' "${PHALCON_DEVTOOLS_LATEST}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.phalcon"
fi

DEPLOYER_PHAR_FILE="${PHPBREW_BIN}/dep"
# Was the write-only-marker shape: it WROTE phpbrew.deployer but the guard only
# asked whether the phar existed, so the marker was never read and a version bump
# did nothing.
_deployer_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.deployer" "${GLOBAL_STACK_DEPLOYER_VERSION}" "phpbrew.deployer")"
if [ "${_deployer_gate}" = "skip" ] && [ -f "${DEPLOYER_PHAR_FILE}" ]; then
    echo -e "\n${DEPLOYER_PHAR_FILE} already installed (${GLOBAL_STACK_DEPLOYER_VERSION})."
else
    echo -e "\nInstalling ${DEPLOYER_PHAR_FILE}."
    _pt_phar deployer "https://github.com/deployphp/deployer/releases/download/${GLOBAL_STACK_DEPLOYER_VERSION}/deployer.phar"
    if ! _pt_runs "${_pt_dl}/deployer.phar" "Deployer " "${GLOBAL_STACK_DEPLOYER_VERSION#v}"; then
        _pt_fatal "the downloaded deployer is not ${GLOBAL_STACK_DEPLOYER_VERSION} - deployer left as it was"
    fi
    _pt_place deployer "${DEPLOYER_PHAR_FILE}"
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
    _pt_phar pickle "https://github.com/FriendsOfPHP/pickle/releases/download/${PICKLE_LATEST}/pickle.phar"
    _pt_place pickle "${PICKLE_PHAR_FILE}"
    printf '%s\n' "${PICKLE_LATEST}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.pickle"
fi

PIE_PHAR_FILE="${PHPBREW_BIN}/pie"
PIE_LATEST=${GLOBAL_STACK_PIE_VERSION}
_pie_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.pie" "${PIE_LATEST}" "phpbrew.pie")"
if [ "${_pie_gate}" = "skip" ] && [ -f "${PIE_PHAR_FILE}" ]; then
    echo -e "\n${PIE_PHAR_FILE} already installed (${PIE_LATEST})."
else
    echo -e "\nInstalling ${PIE_PHAR_FILE}."
    _pt_phar pie "https://github.com/php/pie/releases/download/${PIE_LATEST}/pie.phar"
    if ! _pt_runs "${_pt_dl}/pie.phar" "(PIE) " "${PIE_LATEST#v}"; then
        _pt_fatal "the downloaded pie is not ${PIE_LATEST} - pie left as it was"
    fi
    _pt_place pie "${PIE_PHAR_FILE}"
    printf '%s\n' "${PIE_LATEST}" >"${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/phpbrew.pie"
fi

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

rm -rf "${_pt_dl}"
