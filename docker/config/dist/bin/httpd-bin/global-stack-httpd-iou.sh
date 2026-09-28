#!/bin/bash
# iou = install-or-upgrade

# Enable strict error handling and debugging
set -xeEuo pipefail
shopt -s extdebug
IFS=$'\n\t'

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
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${line_num} ** ** command: ${command} ** httpd global-stack-httpd-iou.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
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
HTTPD_PATH="${1}"
MODSECURITY_LIB_PATH="${2}"

# Pin-audit tranche 3 step 23 (rulings 2026-09-26 11:17 and 11:43; startup-prologue.test.sh
# §75). httpd was `svn checkout http://svn.apache.org` of httpd, apr and apr-util (plain
# http, nothing checked) into a tree start.sh had already wiped, and the two connectors
# were cloned only after the build had replaced the old httpd. httpd is PREFIX-BAKED
# (policy B): every source is fetched and checked in a temp dir first, so a failed fetch
# or checksum leaves the old httpd working; then ${HTTPD_PATH} is wiped (logs/ kept),
# httpd is built at that prefix and checked. A BUILD failure leaves no httpd - the
# accepted trade: the error token makes its consumers fail fast.
_hd_fatal() {
  printf 'FATAL: %s\n' "$1" >&2
  rm -rf "${_hd_dl:-}"
  exit 1
}
if [[ -z "${HTTPD_PATH}" || "${HTTPD_PATH}" == / ]]; then
  _hd_fatal "refusing to build httpd at \"${HTTPD_PATH}\""
fi
_hd_dl="$(mktemp -d)"

# Release tarballs from archive.apache.org ONLY: downloads.apache.org drops a release once
# it is superseded, so a pin moved DOWN would 404 there. The .env pins keep their svn
# `tags/` spelling (env-update lists the svn tags), so the tag prefix is stripped here.
# $1 = httpd|apr path segment, $2 = name, $3 = pin (tags/X or X) -> ${_hd_dl}/<name>-<X>/
_hd_fetch() {
  local v="${3#tags/}" a u
  a="${2}-${v}.tar.gz"
  u="https://archive.apache.org/dist/${1}/${a}"
  if ! curl --connect-timeout 30 --max-time 600 -fsSL -o "${_hd_dl}/${a}" "${u}" \
    || ! curl --connect-timeout 30 --max-time 60 -fsSL -o "${_hd_dl}/${a}.sha256" "${u}.sha256"; then
    _hd_fatal "${2} ${v} could not be downloaded from archive.apache.org - httpd left as it was"
  fi
  # Apache writes `<64 hex> *<name>` (binary-mode `*`) [measured: httpd 2.4.68, apr 1.7.6,
  # apr-util 1.6.5], so the name matches with or without the `*`.
  local want
  want="$(awk -v n="${a}" '($2 == n || $2 == "*" n) && length($1) == 64 { print $1 }' "${_hd_dl}/${a}.sha256")"
  if [[ "$(grep -c . <<<"${want}")" != 1 ]]; then
    _hd_fatal "${2} ${v}: ${a}.sha256 lists no single checksum for ${a} - httpd left as it was"
  fi
  if ! printf '%s  %s\n' "${want}" "${_hd_dl}/${a}" | sha256sum -c --quiet - >/dev/null 2>&1; then
    _hd_fatal "${2} ${v}: ${a} does not match its published SHA-256 - httpd left as it was"
  fi
  # grep reads the whole listing (no -q): an early exit would SIGPIPE tar under pipefail.
  if ! tar -tzf "${_hd_dl}/${a}" | grep -xF "${2}-${v}/configure" >/dev/null; then
    _hd_fatal "${2} ${v}: ${a} holds no ${2}-${v}/configure - httpd left as it was"
  fi
  tar -C "${_hd_dl}" -xzf "${_hd_dl}/${a}"
}
_hd_v="${GLOBAL_STACK_HTTPD_VERSION#tags/}"
_hd_apr="${GLOBAL_STACK_HTTPD_APR_VERSION#tags/}"
_hd_apu="${GLOBAL_STACK_HTTPD_APR_UTIL_VERSION#tags/}"
_hd_fetch httpd httpd "${_hd_v}"
_hd_src="${_hd_dl}/httpd-${_hd_v}"
_hd_fetch apr apr "${_hd_apr}"
mv "${_hd_dl}/apr-${_hd_apr}" "${_hd_src}/srclib/apr"
if [[ -n "${_hd_apu}" ]]; then
  _hd_fetch apr apr-util "${_hd_apu}"
  mv "${_hd_dl}/apr-util-${_hd_apu}" "${_hd_src}/srclib/apr-util"
fi

# The ModSecurity connector has no release; its pin is a commit (SHA-tracked, ruling
# 2026-09-26 11:43), fetched as the GitHub archive of that ref. The archive's single top
# directory is ModSecurity-apache-<ref> [measured: a sha and `master`], which also proves
# GitHub served the ref that was asked for.
_hd_msa=""
if [[ -n "${GLOBAL_STACK_HTTPD_MODSECURITY_MOD_VERSION}" ]]; then
  _hd_msa="ModSecurity-apache-${GLOBAL_STACK_HTTPD_MODSECURITY_MOD_VERSION}"
  if ! curl --connect-timeout 30 --max-time 300 -fsSL -o "${_hd_dl}/msa.tar.gz" \
    "https://github.com/owasp-modsecurity/ModSecurity-apache/archive/${GLOBAL_STACK_HTTPD_MODSECURITY_MOD_VERSION}.tar.gz"; then
    _hd_fatal "ModSecurity-apache ${GLOBAL_STACK_HTTPD_MODSECURITY_MOD_VERSION} could not be downloaded - httpd left as it was"
  fi
  if [[ "$(tar -tzf "${_hd_dl}/msa.tar.gz" | awk -F/ '{ print $1 }' | sort -u)" != "${_hd_msa}" ]] \
    || ! tar -tzf "${_hd_dl}/msa.tar.gz" | grep -xF "${_hd_msa}/autogen.sh" >/dev/null; then
    _hd_fatal "ModSecurity-apache ${GLOBAL_STACK_HTTPD_MODSECURITY_MOD_VERSION}: the archive is not a single ${_hd_msa}/ tree with an autogen.sh - httpd left as it was"
  fi
  tar -C "${_hd_dl}" -xzf "${_hd_dl}/msa.tar.gz"
fi

_hd_oidc=""
if [[ -n "${GLOBAL_STACK_HTTPD_MOD_AUTH_OPENIDC_VERSION}" ]]; then
  _hd_oidc="${_hd_dl}/mod_auth_openidc"
  if ! git clone --progress --branch "${GLOBAL_STACK_HTTPD_MOD_AUTH_OPENIDC_VERSION}" --depth 1 \
    https://github.com/OpenIDC/mod_auth_openidc.git "${_hd_oidc}" \
    || [[ ! -f "${_hd_oidc}/autogen.sh" ]]; then
    _hd_fatal "mod_auth_openidc ${GLOBAL_STACK_HTTPD_MOD_AUTH_OPENIDC_VERSION} could not be cloned - httpd left as it was"
  fi
fi

# Every input is here and checked: from now on the old httpd is replaced. logs/ is kept.
mkdir -p "${HTTPD_PATH}"
find "${HTTPD_PATH}" -mindepth 1 -maxdepth 1 ! -name logs -exec rm -rf {} +

# --with-included-apr: without it configure is free to take the SYSTEM apr-1-config
# (libapr1-dev and libaprutil1-dev are installed, apr-util 1.6.3), and the two apr pins
# would be decoration. The check below proves which apr was compiled in.
if ! (cd "${_hd_src}" \
  && CFLAGS="-Og" ./configure \
    --prefix="${HTTPD_PATH}" \
    --with-included-apr \
    --enable-load-all-modules \
    --with-ssl=/usr/lib/ssl \
    --enable-ssl \
    --enable-mods-shared=all \
    --enable-mods-static=all \
    --enable-modules=all \
    --enable-debugger-mode \
    --enable-rewrite \
    --enable-log-debug \
    --with-libxml2=/usr/lib \
    --with-ldap=ldap \
    --with-openssl \
  && make prefix="${HTTPD_PATH}" \
  && make prefix="${HTTPD_PATH}" install); then
  _hd_fatal "httpd ${_hd_v}: the build failed - the old httpd is already removed (prefix-baked), fix the cause and restart"
fi
if [[ -n "${_hd_msa}" ]] && ! (cd "${_hd_dl}/${_hd_msa}" \
  && ./autogen.sh \
  && CFLAGS="-Og" ./configure \
    --with-apxs="${HTTPD_PATH}/bin/apxs" \
    --with-apache="${HTTPD_PATH}/bin/httpd" \
    --with-libmodsecurity="${MODSECURITY_LIB_PATH}" \
  && make \
  && make install); then
  _hd_fatal "ModSecurity-apache ${GLOBAL_STACK_HTTPD_MODSECURITY_MOD_VERSION}: the build failed - httpd ${_hd_v} is built but has no ModSecurity module"
fi
if [[ -n "${_hd_oidc}" ]] && ! (cd "${_hd_oidc}" \
  && ./autogen.sh \
  && CFLAGS="-Og" ./configure --with-apxs="${HTTPD_PATH}/bin/apxs" \
  && make \
  && make install); then
  _hd_fatal "mod_auth_openidc ${GLOBAL_STACK_HTTPD_MOD_AUTH_OPENIDC_VERSION}: the build failed - httpd ${_hd_v} is built but has no mod_auth_openidc"
fi

# Check the build [measured: `Server version: Apache/2.4.68 (Unix)` and
# `Compiled using: APR 1.7.6, APR-UTIL 1.6.5, PCRE ...`; `apachectl -t` -> Syntax OK on the
# freshly installed conf, which httpd-setup replaces right after].
find "${HTTPD_PATH}/bin" -type f -exec sudo chmod a+x {} \;
if ! _hd_says="$("${HTTPD_PATH}/bin/httpd" -v 2>&1)" || [[ "${_hd_says}" != "Server version: Apache/${_hd_v} "* ]]; then
  _hd_fatal "httpd ${_hd_v}: the built binary reports \"${_hd_says%%$'\n'*}\""
fi
_hd_apr_want="APR ${_hd_apr},"
[[ -z "${_hd_apu}" ]] || _hd_apr_want="APR ${_hd_apr}, APR-UTIL ${_hd_apu},"
if ! _hd_cfg="$("${HTTPD_PATH}/bin/httpd" -V 2>&1)" || ! grep -qF "Compiled using: ${_hd_apr_want}" <<<"${_hd_cfg}"; then
  _hd_fatal "httpd ${_hd_v}: not compiled with the pinned ${_hd_apr_want%,} (httpd -V: \"$(grep -F 'Compiled using:' <<<"${_hd_cfg}" || true)\")"
fi
if ! "${HTTPD_PATH}/bin/apachectl" -t; then
  _hd_fatal "httpd ${_hd_v}: apachectl -t rejects the freshly installed configuration"
fi
for _hd_m in ${_hd_msa:+mod_security3.so} ${_hd_oidc:+mod_auth_openidc.so}; do
  [[ -f "${HTTPD_PATH}/modules/${_hd_m}" ]] || _hd_fatal "httpd ${_hd_v}: modules/${_hd_m} was not installed"
done

rm -rf "${_hd_dl}"
cd "${GLOBAL_STACK_DOCKER_TOOLS_PATH}"
