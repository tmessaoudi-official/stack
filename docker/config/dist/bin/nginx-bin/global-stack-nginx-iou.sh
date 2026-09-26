#!/bin/bash
# iou = install-or-upgrade

# Enable strict error handling and debugging
set -xeEuo pipefail
shopt -s extdebug
IFS=$'\n\t'

# Row 20: prologue-exempt, so the version gate is sourced alone.
source global-stack-base-version-gate.sh

# Trap errors and handle cleanup or error reporting
trap 'stackCatch $? ${LINENO} "${BASH_COMMAND}"' ERR EXIT

stackCatch() {
  local exit_code=${1}
  local line_num=${2}
  local command=${3}
  # Re-entry guard: ERR fires first, then this handler's own `exit 1` comes back
  # through the EXIT trap and would overwrite the error token with the trap's own
  # line number. The `-ne 1` arm removed below had been doing this by accident, at
  # the cost of silencing exit 1 — the most common real failure in this script's
  # own chain, so a failed INSTALL wrote no error token at all (row 25).
  if [[ -n "${_STACK_CAUGHT:-}" ]]; then
    return 0
  fi
  if [[ "${exit_code}" -ne 0 && "${exit_code}" -ne 141 ]]; then
    _STACK_CAUGHT=1
    echo "Error detected !!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${line_num} ** ** command: ${command} ** nginx global-stack-nginx-iou.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
    [[ -n "${GLOBAL_STACK_ERROR_TOKEN:-}" ]] && printf 'line: %s\ncommand: %s\n' "${2}" "${3}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN}"
    exit 1
  fi
}

# Positional reads live BELOW stackCatch. Under `set -u` an argument-less
# invocation makes `${1}` a fatal shell error, and the EXIT/ERR trap is what
# turns that into an error token — but the trap BODY calls stackCatch, so a read
# placed above the function definition dies with `stackCatch: command not found`
# and writes nothing. Measured argless [row 35]: exit 1 with ZERO files in
# tools/errors/, the unattributable death row 30 fixed in android-start.sh. This
# family was missed by row 25, whose Files cell scoped it to the three
# web-server trees, and by row 35's own filing, which named only the three
# *-setup.sh — startup-prologue.test.sh §49 now enumerates the class instead.
# Define reusable paths
NGINX_PATH="${1}"
HTTP_COMMONS_PATH="${2}"
# shellcheck disable=SC2034 # 3, 4 and 6 are kept for the positional contract of the start.sh call
NGINX_VERSIONS_PATH="${3}"
# shellcheck disable=SC2034
MODSECURITY_SOURCE_LIB_PATH="${4}"
MODSECURITY_LIB_PATH="${5}"
# shellcheck disable=SC2034
CORERULESET_PATH="${6}"
CJOSE_SOURCE_PATH="${7}"
CJOSE_PATH="${8}"
LIBOAUTH2_SOURCE_PATH="${9}"
LIBOAUTH2_PATH="${10}"
NGINX_LIBOAUTH2_VERSION_PATH="${11}"
NGINX_CJOSE_VERSION_PATH="${12}"
MOD_AUTH_OPENIDC_NGINX_SOURCE_PATH="${NGINX_PATH}/mods/mod_auth_openidc-source"
MOD_AUTH_OPENIDC_NGINX_PATH="${NGINX_PATH}/mods/mod_auth_openidc"

# Pin-audit tranche 3 step 24 (rulings 2026-09-26 11:17 and 11:43; startup-prologue.test.sh
# §76). nginx was a `curl` of the nginx.org tarball with no signature check, into a tree
# start.sh had already wiped, and the ModSecurity connector was cloned into
# ${NGINX_PATH}/mods on every run and never removed; the gate held NGINX_VERSION alone.
# nginx is PREFIX-BAKED (policy B): the tarball is verified against its .asc with the
# nginx.org keys committed next to this script, and the connector is cloned, both in a temp
# dir; only then is ${NGINX_PATH} wiped (logs/ kept), nginx built at that prefix and
# checked. A BUILD failure leaves no nginx - the accepted trade: the error token makes its
# consumers fail fast.
# The gpg-agent that the import starts in the temp homedir exits on its own once that
# directory is removed [measured in the 01caddy image, gpg 2.4.8: 1 alive before `rm -rf`,
# 0 one second after], so nothing here stops it.
_ng_fatal() {
  printf 'FATAL: %s\n' "$1" >&2
  rm -rf "${_ng_dl:-}"
  exit 1
}
if [[ -z "${NGINX_PATH}" || "${NGINX_PATH}" == / ]]; then
  _ng_fatal "refusing to build nginx at \"${NGINX_PATH}\""
fi
_ng_dl="$(mktemp -d)"
_ng_v="${GLOBAL_STACK_NGINX_VERSION}"
_ng_a="nginx-${_ng_v}.tar.gz"

# The PRIMARY key fingerprints of the nginx.org signing keys (nginx-release-keys.asc, whose
# header says where they come from). A signature by any other key - including the two older
# keys that file also carries - fails closed; a new nginx.org key is added here by hand.
_ng_fprs=(
  43387825DDB1BB97EC36BA5D007C8D7C15D87369
  D6786CE303D9A9022998DC6CC8464D549AF75C0A
  7338973069ED3F443F4D37DFA64FD5B17ADB39A8
  13C82A63B603576156E30A4EA0EA981B66B0D967
  8540A6F18833A80E9C1653A42FD21310B49F6B46
)
_ng_keys="${BASH_SOURCE[0]%/*}/nginx-release-keys.asc"
if [[ ! -f "${_ng_keys}" ]]; then
  _ng_fatal "nginx ${_ng_v}: ${_ng_keys} is missing - nginx left as it was"
fi
if ! curl --connect-timeout 30 --max-time 300 -fsSL -o "${_ng_dl}/${_ng_a}" "https://nginx.org/download/${_ng_a}" \
  || ! curl --connect-timeout 30 --max-time 60 -fsSL -o "${_ng_dl}/${_ng_a}.asc" "https://nginx.org/download/${_ng_a}.asc"; then
  _ng_fatal "nginx ${_ng_v} could not be downloaded from nginx.org - nginx left as it was"
fi
# gpg's exit status alone is not the check: the status lines are [measured, 1.31.6:
# `GOODSIG C8464D549AF75C0A …` and `VALIDSIG <signing fpr> … <primary fpr>`; a tampered
# tarball gives BADSIG]. GOODSIG is not emitted for an expired or revoked key, and the
# VALIDSIG primary fingerprint (its last field) must be a pinned one.
mkdir -m 0700 "${_ng_dl}/gnupg"
if ! gpg --batch --homedir "${_ng_dl}/gnupg" --no-default-keyring --keyring "${_ng_dl}/gnupg/release.gpg" \
  --import "${_ng_keys}" >"${_ng_dl}/gpg-import.log" 2>&1; then
  _ng_fatal "nginx ${_ng_v}: gpg cannot import ${_ng_keys} - nginx left as it was"
fi
gpg --batch --homedir "${_ng_dl}/gnupg" --no-default-keyring --keyring "${_ng_dl}/gnupg/release.gpg" \
  --status-fd 1 --verify "${_ng_dl}/${_ng_a}.asc" "${_ng_dl}/${_ng_a}" >"${_ng_dl}/gpg-status" 2>"${_ng_dl}/gpg-verify.log" || true
_ng_signer="$(awk '$1 == "[GNUPG:]" && $2 == "VALIDSIG" { print $NF }' "${_ng_dl}/gpg-status")"
# Membership by loop, never by joining the list: this script runs with IFS=$'\n\t', so
# "${_ng_fprs[*]}" joins with NEWLINES and a space-delimited match can never succeed
# [measured: a good pluknet signature was rejected that way].
_ng_pinned=""
for _ng_f in "${_ng_fprs[@]}"; do
  if [[ "${_ng_f}" == "${_ng_signer}" ]]; then
    _ng_pinned=1
  fi
done
if ! grep -q '^\[GNUPG:\] GOODSIG ' "${_ng_dl}/gpg-status" \
  || grep -qE '^\[GNUPG:\] (BADSIG|ERRSIG|EXPSIG|EXPKEYSIG|REVKEYSIG) ' "${_ng_dl}/gpg-status" \
  || [[ "$(grep -c . <<<"${_ng_signer}")" != 1 ]] \
  || [[ -z "${_ng_pinned}" ]]; then
  _ng_fatal "nginx ${_ng_v}: ${_ng_a}.asc is not a good signature by a pinned nginx.org key (signer: \"${_ng_signer//$'\n'/ }\") - nginx left as it was"
fi
# grep reads the whole listing (no -q): an early exit would SIGPIPE tar under pipefail.
if ! tar -tzf "${_ng_dl}/${_ng_a}" | grep -xF "nginx-${_ng_v}/configure" >/dev/null; then
  _ng_fatal "nginx ${_ng_v}: ${_ng_a} holds no nginx-${_ng_v}/configure - nginx left as it was"
fi
tar -C "${_ng_dl}" -xzf "${_ng_dl}/${_ng_a}"

_ng_add=()
_ng_msn=""
if [[ -n "${GLOBAL_STACK_NGINX_MODSECURITY_MOD_VERSION}" ]]; then
  _ng_msn="${_ng_dl}/ModSecurity-nginx"
  if ! git clone --progress --branch "${GLOBAL_STACK_NGINX_MODSECURITY_MOD_VERSION}" --depth 1 \
    https://github.com/SpiderLabs/ModSecurity-nginx.git "${_ng_msn}" \
    || ! git -C "${_ng_msn}" config core.fileMode false \
    || ! git -C "${_ng_msn}" submodule update --init \
    || [[ ! -f "${_ng_msn}/config" ]]; then
    _ng_fatal "ModSecurity-nginx ${GLOBAL_STACK_NGINX_MODSECURITY_MOD_VERSION} could not be cloned (or holds no nginx module config) - nginx left as it was"
  fi
  _ng_add=(--add-module="${_ng_msn}")
fi

# Every input is here and checked: from now on the old nginx is replaced. logs/ is kept.
# The OpenIDC chain's libs live under ${NGINX_PATH}/libs, so their markers go with them
# (start.sh used to delete both with the tree). nginx builds in ${NGINX_PATH}/nginx-build,
# not in the temp dir, because the chain below is configured against that path.
mkdir -p "${NGINX_PATH}"
find "${NGINX_PATH}" -mindepth 1 -maxdepth 1 ! -name logs -exec rm -rf {} +
rm -f "${NGINX_CJOSE_VERSION_PATH}" "${NGINX_LIBOAUTH2_VERSION_PATH}"
mv "${_ng_dl}/nginx-${_ng_v}" "${NGINX_PATH}/nginx-build"

if ! (cd "${NGINX_PATH}/nginx-build" \
  && ./configure \
    --prefix="${NGINX_PATH}" \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_realip_module \
    --with-http_gzip_static_module \
    --with-http_stub_status_module \
    --with-http_auth_request_module \
    --with-http_addition_module \
    --with-http_sub_module \
    --with-http_flv_module \
    --with-http_mp4_module \
    --with-pcre \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-mail \
    --with-mail_ssl_module \
    --with-http_geoip_module \
    --with-http_xslt_module \
    --with-http_image_filter_module \
    --with-http_slice_module \
    --with-http_random_index_module \
    --with-http_secure_link_module \
    --with-http_degradation_module \
    --with-http_dav_module \
    --with-compat \
    "${_ng_add[@]}" \
    --with-cc-opt="-I${MODSECURITY_LIB_PATH}/include \
                   -I${CJOSE_PATH}/include" \
    --with-ld-opt="-Wl,-rpath=${MODSECURITY_LIB_PATH}/lib \
                   -Wl,-rpath=${CJOSE_PATH}/lib \
                   -L${MODSECURITY_LIB_PATH}/lib \
                   -L${CJOSE_PATH}/lib" \
  && make prefix="${NGINX_PATH}" \
  && make prefix="${NGINX_PATH}" install); then
  _ng_fatal "nginx ${_ng_v}: the build failed - the old nginx is already removed (prefix-baked), fix the cause and restart"
fi
# @todo install quic http3 support
# --with-http_v3_module \
# --add-module="${MOD_AUTH_OPENIDC_NGINX_PATH}" \
# -I${LIBOAUTH2_PATH}/include" \
# -Wl,-rpath=${LIBOAUTH2_PATH}/lib \
# -L${LIBOAUTH2_PATH}/lib"

cd "${NGINX_PATH}"

# Install cJOSE if needed
if [[ -n "${GLOBAL_STACK_NGINX_CJOSE_VERSION}" ]] && \
   { [[ ! -e "${NGINX_CJOSE_VERSION_PATH}" ]] || \
     [[ "$(gs_version_gate "${NGINX_CJOSE_VERSION_PATH}" "${GLOBAL_STACK_NGINX_CJOSE_VERSION}" "nginx.cjose")" != "skip" ]]; }; then
  
  # Create directory for cJOSE source & lib
  mkdir -p \
    "${CJOSE_SOURCE_PATH}" \
    "${CJOSE_PATH}"
  
  # Clone the cJOSE repository
  git clone --progress \
    --branch "${GLOBAL_STACK_NGINX_CJOSE_VERSION}" \
    https://github.com/OpenIDC/cjose.git \
    --depth 1 \
    "${CJOSE_SOURCE_PATH}"
  
  # Configure Git and update submodules
  git -C "${CJOSE_SOURCE_PATH}" config core.fileMode false
  git -C "${CJOSE_SOURCE_PATH}" submodule update --init
  
  # Build and install cJOSE
  cd "${CJOSE_SOURCE_PATH}"

  CFLAGS="-Og" ./configure \
    --prefix="${CJOSE_PATH}"

  make
  make install

  cd "${HTTP_COMMONS_PATH}"

  # rm -rf \
  #   "${CJOSE_SOURCE_PATH}"
  
  # Save the installed version
  echo "${GLOBAL_STACK_NGINX_CJOSE_VERSION}" > "${NGINX_CJOSE_VERSION_PATH}"

  cd "${NGINX_PATH}"
fi

# Install liboauth2 if needed
if [[ -n "${GLOBAL_STACK_NGINX_LIBOAUTH2_VERSION}" ]] && \
   { [[ ! -e "${NGINX_LIBOAUTH2_VERSION_PATH}" ]] || \
     [[ "$(cat "${NGINX_LIBOAUTH2_VERSION_PATH}")" != "${GLOBAL_STACK_NGINX_LIBOAUTH2_VERSION}" ]]; }; then
  rm -rf \
    "${LIBOAUTH2_SOURCE_PATH}" \
    "${LIBOAUTH2_PATH}"

  # Create directory for liboauth2 source & lib
  mkdir -p \
    "${LIBOAUTH2_SOURCE_PATH}" \
    "${LIBOAUTH2_PATH}"
  
  # Clone the cJOSE repository
  git clone --progress \
    --branch "${GLOBAL_STACK_NGINX_LIBOAUTH2_VERSION}" \
    https://github.com/OpenIDC/liboauth2.git \
    --depth 1 \
    "${LIBOAUTH2_SOURCE_PATH}"
  
  # Configure Git and update submodules
  git -C "${LIBOAUTH2_SOURCE_PATH}" config core.fileMode false
  git -C "${LIBOAUTH2_SOURCE_PATH}" submodule update --init
  
  # Build and install cJOSE
  cd "${LIBOAUTH2_SOURCE_PATH}"

  ./autogen.sh

  CFLAGS="-Og" ./configure \
    --prefix="${LIBOAUTH2_PATH}" \
    --with-nginx=${NGINX_PATH}/nginx-build \
    --without-apache \
    CFLAGS="-I${CJOSE_PATH}/include" \
    LDFLAGS="-L${CJOSE_PATH}/lib -Wl,-rpath=${CJOSE_PATH}/lib"

  make
  make install

  # rm -rf \
  #   "${LIBOAUTH2_SOURCE_PATH}"
  
  # Save the installed version
  echo "${GLOBAL_STACK_NGINX_LIBOAUTH2_VERSION}" > "${NGINX_LIBOAUTH2_VERSION_PATH}"

  cd "${NGINX_PATH}"
fi

# Install the Nginx mod_auth_openidc connector if needed
if [[ -n "${GLOBAL_STACK_NGINX_MOD_AUTH_OPENIDC_VERSION}" && "" != "${GLOBAL_STACK_NGINX_MOD_AUTH_OPENIDC_VERSION}" ]]; then
  mkdir -p \
    "${MOD_AUTH_OPENIDC_NGINX_SOURCE_PATH}" \
    "${MOD_AUTH_OPENIDC_NGINX_PATH}"

  git clone --progress --branch "${GLOBAL_STACK_NGINX_MOD_AUTH_OPENIDC_VERSION}" \
    https://github.com/OpenIDC/ngx_openidc_module.git \
    --depth 1 "${MOD_AUTH_OPENIDC_NGINX_SOURCE_PATH}"

  git -C "${MOD_AUTH_OPENIDC_NGINX_SOURCE_PATH}" config core.fileMode false
  git -C "${MOD_AUTH_OPENIDC_NGINX_SOURCE_PATH}" submodule update --init

  cd "${MOD_AUTH_OPENIDC_NGINX_SOURCE_PATH}"

  ./autogen.sh

  OAUTH2_NGINX_CFLAGS="-I${LIBOAUTH2_PATH}/include -I${CJOSE_PATH}/include" OAUTH2_NGINX_LIBS="-L${LIBOAUTH2_PATH}/lib -L${CJOSE_PATH}/lib -loauth2_nginx -loauth2 -lcjose" OAUTH2_CFLAGS="-I${LIBOAUTH2_PATH}/include -I${CJOSE_PATH}/include" OAUTH2_LIBS="-L${LIBOAUTH2_PATH}/lib -L${CJOSE_PATH}/lib -loauth2 -lcjose" CFLAGS="-Og" CFLAGS="-Og" ./configure \
     --prefix="${MOD_AUTH_OPENIDC_NGINX_PATH}" \
     --with-nginx=${NGINX_PATH}/nginx-build

  make
  make install

  # rm -rf \
  #   "${MOD_AUTH_OPENIDC_NGINX_SOURCE_PATH}"

  cd "${NGINX_PATH}"
fi

rm -rf "${NGINX_PATH}/nginx-build"

# Check the build [measured, 1.31.6: `nginx -V` writes to stderr only, first line
# `nginx version: nginx/1.31.6`, and `configure arguments:` names the --add-module path;
# `nginx -t` passes on the freshly installed conf, which nginx-setup replaces right after].
find "${NGINX_PATH}/sbin" -type f -exec sudo chmod a+x {} \;
if ! _ng_cfg="$("${NGINX_PATH}/sbin/nginx" -V 2>&1)" || [[ "${_ng_cfg%%$'\n'*}" != "nginx version: nginx/${_ng_v}" ]]; then
  _ng_fatal "nginx ${_ng_v}: the built binary reports \"${_ng_cfg%%$'\n'*}\""
fi
if [[ -n "${_ng_msn}" ]] && ! grep -qF -- "--add-module=${_ng_msn}" <<<"${_ng_cfg}"; then
  _ng_fatal "nginx ${_ng_v}: the built binary was not configured with the ModSecurity-nginx module"
fi
if ! "${NGINX_PATH}/sbin/nginx" -t; then
  _ng_fatal "nginx ${_ng_v}: nginx -t rejects the freshly installed configuration"
fi

rm -rf "${_ng_dl}"
cd "${GLOBAL_STACK_DOCKER_TOOLS_PATH}"
