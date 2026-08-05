#!/bin/bash
#
# Builds the FPM SAPI as a second configure pass, reusing the configure line
# phpbrew already generated, then replicates phpbrew's FPM post-install config.
#
# Why this exists: phpbrew replays the FULL variant list into every SAPI pass.
# Its FPM pass adds --disable-cli while still carrying --enable-embed. Since
# php-src 4fc487f6d9c6 (2026-07-28, PR #21385) the embed SAPI links
# PHP_CLI_SHARED_OBJS into libphp for do_php_cli(), and sapi/cli/config.m4 now
# hard-errors on that combination. PHP-8.5 and PHP-8.4 lack that guard, which is
# why they still build. So phpbrew gets -fpm (CLI + embed only) and FPM is
# built here, in a pass that keeps CLI enabled at configure time.
#
# Usage: global-stack-phpbrew-php-install-fpm.sh <phpbrew-build-name>
#
# Env:
#   PHPBREW_INI_TIMEZONE     default UTC   (fallback ini path only)
#   PHPBREW_PRODUCTION       1 to seed from php.ini-production
#   PHPBREW_FPM_INI_FROM_CLI default 1     0 = derive from php.ini-*
#
set -eux

PREFIX="${PHPBREW_ROOT}/php/${PHP_VERSION_NAME}"
BUILD="${PHPBREW_ROOT}/build/${PHP_VERSION_NAME}"
ETC="$PREFIX/etc"

INI_TIMEZONE="${PHPBREW_INI_TIMEZONE:-UTC}"
INI_FROM_CLI="${PHPBREW_FPM_INI_FROM_CLI:-1}"
INI_SEED="$BUILD/php.ini-development"

# ---------------------------------------------------------------- build stage
if [[ -x "$PREFIX/sbin/php-fpm" ]]; then
    echo "php-fpm binary already present for ${PHP_VERSION_NAME}, skipping build"
elif [[ ! -f "$BUILD/config.nice" ]]; then
    echo "no config.nice in $BUILD, nothing to build"
    exit 0
else
    cd "$BUILD"
    mkdir -p "$ETC/fpm" "$PREFIX/var/db/fpm"

    # config.nice is the verbatim pass-1 configure line, written by php-src's
    # configure (configure.ac: PHP_CONFIG_NICE). Derive the FPM line from it:
    #   - drop the shared config cache (poisonous across differing SAPI configs)
    #   - drop --enable-cli   (this pass disables CLI)
    #   - drop --enable-embed (would trip the guard; libphp came from pass 1)
    #   - drop --disable-fpm / --without-fpm-systemd (emitted by the -fpm variant)
    #   - repoint the ini paths from etc/cli to etc/fpm
    sed -e "/--cache-file=/d" \
        -e "/'--enable-cli'/d" \
        -e "/'--enable-embed/d" \
        -e "/'--disable-fpm'/d" \
        -e "/'--without-fpm-systemd'/d" \
        -e "s#/etc/cli#/etc/fpm#" \
        -e "s#/var/db/cli#/var/db/fpm#" \
        config.nice > config.fpm
    chmod +x config.fpm

    if grep -q -- "--enable-cli\|--enable-embed" config.fpm; then
        echo "ERROR: config.fpm still enables cli or embed" >&2
        exit 1
    fi

    # config.nice ends in "$@", so these land last and win.
    # No --with-fpm-systemd: pointless in a container, and it would add a
    # libsystemd.so runtime dependency. PHP defaults it to 'no'.
    ./config.fpm --disable-cli --enable-fpm

    make clean
    make -j"$(nproc)"
    make install
fi

# --------------------------------------------------------------- config stage
# Idempotent: only creates what is missing. Mirrors phpbrew's InstallCommand
# post-install block, which make install alone does not do.
mkdir -p "$ETC/fpm" "$ETC/php-fpm.d" "$PREFIX/var/db/fpm" "$PREFIX/var/run"

# make install writes only *.default, into the PREFIX (sapi/fpm/Makefile.frag):
#   $(sysconfdir)/php-fpm.conf.default
#   $(sysconfdir)/php-fpm.d/www.conf.default
# php-fpm.conf defines NO pool by itself -- it ends with
#   include=<sysconfdir>/php-fpm.d/*.conf
# Without www.conf, fpm_conf.c:843 logs "No pool defined" and exits
# FPM_EXIT_CONFIG (78).
[[ -f "$ETC/php-fpm.conf" ]]       || cp "$ETC/php-fpm.conf.default"       "$ETC/php-fpm.conf"
[[ -f "$ETC/php-fpm.d/www.conf" ]] || cp "$ETC/php-fpm.d/www.conf.default" "$ETC/php-fpm.d/www.conf"

# www.conf.in ships "listen = 127.0.0.1:9000"; phpbrew rewrites it to a socket.
# sed -i -E "s#^listen = .*#listen = $PREFIX/var/run/php-fpm.sock#" "$ETC/php-fpm.d/www.conf"

# php.ini for the FPM SAPI. phpbrew's makeIniFile() varies only the directory
# per SAPI, never the content -- so the CLI ini from pass 1 is byte-identical
# to what phpbrew would have written here.
if [[ ! -f "$ETC/fpm/php.ini" ]]; then
    if [[ "$INI_FROM_CLI" == "1" && -f "$ETC/cli/php.ini" ]]; then
        cp "$ETC/cli/php.ini" "$ETC/fpm/php.ini"
    elif [[ -f "$INI_SEED" ]]; then
        cp "$INI_SEED" "$ETC/fpm/php.ini"
        # sed -i -E "s#^;?[[:space:]]*date\.timezone[[:space:]]*=.*#date.timezone = $INI_TIMEZONE#I" \
        #     "$ETC/fpm/php.ini"
    else
        echo "ERROR: no ini source found ($ETC/cli/php.ini or $INI_SEED)" >&2
        exit 1
    fi
fi

# ---------------------------------------------------------------- verification
# test -f "$ETC/fpm/php.ini"
# test -f "$ETC/php-fpm.conf"
# grep -q '^\[www\]' "$ETC/php-fpm.d/www.conf"

# "$PREFIX/bin/php" -v
# find "$PREFIX" -name 'libphp*' -print