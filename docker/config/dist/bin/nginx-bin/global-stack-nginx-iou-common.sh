#!/bin/bash

# Enable strict error handling and debugging
set -xeEuo pipefail
shopt -s extdebug
IFS=$'\n\t'

# Row 20: prologue-exempt, so the version gate is sourced alone.
source global-stack-base-version-gate.sh

# Function to handle errors and trap cleanup
stackCatch() {
  local exit_code=$1
  local line_num=$2
  local command=$3
  # Re-entry guard: ERR fires first, then this handler's own `exit 1` comes back
  # through the EXIT trap and would overwrite the error token with the trap's own
  # line number. The `-ne 1` arm removed below had been doing this by accident,
  # at the cost of silencing exit 1 — the most common real failure here.
  if [[ -n "${_STACK_CAUGHT:-}" ]]; then
    return 0
  fi
  if [[ $exit_code -ne 0 && $exit_code -ne 141 ]]; then
    _STACK_CAUGHT=1
    echo "Error detected!"
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - line: $line_num, command: $command, nginx global-stack-nginx-iou-common.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
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

# Trap errors for cleanup or error reporting
trap 'stackCatch $? ${LINENO} "${BASH_COMMAND}"' ERR EXIT

# Define reusable paths passed as arguments
# shellcheck disable=SC2034 # kept for the positional contract both start.sh call sites use
HTTP_COMMONS_PATH="${1}"
HTTP_COMMON_MOD_SECURITY_VERSION_PATH="${2}"
HTTP_COMMON_CORERULESET_VERSION_PATH="${3}"
MODSECURITY_SOURCE_LIB_PATH="${4}"
MODSECURITY_LIB_PATH="${5}"
CORERULESET_PATH="${6}"

# Tranche 3 step 23a (startup-prologue.test.sh §75). This body is byte-identical in
# httpd- and nginx-iou-common.sh (§75 guards it): the two web servers are alternatives
# sharing one tree and one pair of markers.
# The ModSecurity library is PREFIX-BAKED (policy B, ruling 2026-09-26 11:43): its source is
# cloned and checked in a temp dir BEFORE anything is removed, so a failed fetch leaves the
# old library working; then the old library is removed, the new one is built at its prefix
# and checked. A BUILD failure therefore leaves no library - the accepted trade: the web
# server writes its error token and its consumers fail fast on it. The CoreRuleSet is plain
# files, so it is cloned and checked in the temp dir and only then swapped in. mod_security's
# tmp/, logs/ and conf/ are kept (they were wiped before): the setup scripts recreate them
# and re-sync conf/ on every boot.
_hc_fatal() {
  printf 'FATAL: %s\n' "$1" >&2
  rm -rf "${_hc_dl:-}"
  exit 1
}
_hc_dl="$(mktemp -d)"

if [[ -n "${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}" ]] \
  && [[ "$(gs_version_gate "${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}" "${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}" "http.mod_security")" != "skip" ]]; then
  _hc_ms="${_hc_dl}/modsecurity"
  # --recursive: Mbed TLS (others/mbedtls) carries its own submodule, and without it
  # v3.0.16's configure stops at "Mbed TLS was not found" [measured, 01caddy image] - the
  # plain --init used before could not build this library at all.
  if ! git clone --progress --branch "${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}" --depth 1 \
    https://github.com/SpiderLabs/ModSecurity.git "${_hc_ms}" \
    || ! git -C "${_hc_ms}" config core.fileMode false \
    || ! git -C "${_hc_ms}" submodule update --init --recursive; then
    _hc_fatal "ModSecurity ${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION} could not be cloned - the old library left as it was"
  fi
  if [[ ! -f "${_hc_ms}/build.sh" ]]; then
    _hc_fatal "ModSecurity ${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}: the clone holds no build.sh - the old library left as it was"
  fi
  # Checked: from here on the old library is replaced.
  rm -rf "${MODSECURITY_SOURCE_LIB_PATH}" "${MODSECURITY_LIB_PATH}" "${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}"
  mkdir -p "${MODSECURITY_LIB_PATH}"
  # No --with-lua (ruling 2026-09-26 15:52): it made configure stop at "LUA was explicitly
  # requested but not found" - no image installs a Lua dev package and no rule here uses
  # Lua - so configure now auto-detects it and builds without.
  if ! (cd "${_hc_ms}" \
    && ./build.sh \
    && CFLAGS="-Og" ./configure --prefix="${MODSECURITY_LIB_PATH}" --enable-shared \
    && make \
    && make install); then
    _hc_fatal "ModSecurity ${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}: the build failed - the old library is already removed (prefix-baked), fix the cause and restart"
  fi
  if [[ ! -e "${MODSECURITY_LIB_PATH}/lib/libmodsecurity.so.3" ]] || ! compgen -G "${MODSECURITY_LIB_PATH}/bin/*" >/dev/null; then
    _hc_fatal "ModSecurity ${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}: the build installed no lib/libmodsecurity.so.3 or nothing in bin/"
  fi
  find "${MODSECURITY_LIB_PATH}/bin" -type f -exec sudo chmod a+x {} \;
  printf '%s\n' "${GLOBAL_STACK_HTTP_MODSECURITY_LIB_VERSION}" >"${HTTP_COMMON_MOD_SECURITY_VERSION_PATH}"
fi

if [[ -n "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" ]] \
  && [[ "$(gs_version_gate "${HTTP_COMMON_CORERULESET_VERSION_PATH}" "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" "http.coreruleset")" != "skip" ]]; then
  _hc_crs="${_hc_dl}/coreruleset"
  if ! git clone --progress --branch "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" --depth 1 \
    https://github.com/coreruleset/coreruleset.git "${_hc_crs}" \
    || ! git -C "${_hc_crs}" config core.fileMode false; then
    _hc_fatal "CoreRuleSet ${GLOBAL_STACK_HTTP_CORERULESET_VERSION} could not be cloned - the old rules left as they were"
  fi
  if [[ ! -f "${_hc_crs}/crs-setup.conf.example" || ! -d "${_hc_crs}/rules" ]]; then
    _hc_fatal "CoreRuleSet ${GLOBAL_STACK_HTTP_CORERULESET_VERSION}: the clone holds no crs-setup.conf.example or rules/ - the old rules left as they were"
  fi
  cp "${_hc_crs}/crs-setup.conf.example" "${_hc_crs}/crs-setup.conf"
  # Checked: from here on the old rules are replaced.
  rm -rf "${CORERULESET_PATH}"
  mkdir -p "${CORERULESET_PATH%/*}"
  mv "${_hc_crs}" "${CORERULESET_PATH}"
  printf '%s\n' "${GLOBAL_STACK_HTTP_CORERULESET_VERSION}" >"${HTTP_COMMON_CORERULESET_VERSION_PATH}"
fi

rm -rf "${_hc_dl}"
