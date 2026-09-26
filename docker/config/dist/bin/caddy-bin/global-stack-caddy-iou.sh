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
    echo -e "$(date '+%d-%m-%Y %H:%M:%S'): Error - ** line: ${line_num} ** ** command: ${command} ** caddy global-stack-caddy-iou.sh" >> "${GLOBAL_STACK_DOCKER_TOOLS_PATH}/elapsed"
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
CADDY_PATH="${1}"

# Pin-audit tranche 3 step 22 (rulings 2026-09-26 11:17 and 11:43; startup-prologue.test.sh
# §74). caddy was `go build` of the core, then `caddy add-package` four times, which
# DOWNLOADS a binary built by caddyserver.com's build service ("Downloads an updated Caddy
# binary", `caddy help add-package`), so the shipped binary was neither built here nor
# checked, and start.sh had already wiped the old one. Now xcaddy (pinned, its release
# checked against the published SHA-512) builds caddy with the four pinned plugins in a
# temp dir; the result must report the caddy pin and list every plugin AT its pin before
# `install` replaces bin/caddy. Every failure is a named FATAL that leaves the old binary
# as it was. Go verifies each module it downloads against sum.golang.org.
_cd_fatal() {
  printf 'FATAL: %s\n' "$1" >&2
  rm -rf "${_cd_dl:-}"
  exit 1
}

# Compose passes an EMPTY value, not an unset one, until env-scan has copied the pin into
# .env.local, so name that case instead of failing on a download URL with no version in it.
if [[ -z "${GLOBAL_STACK_XCADDY_VERSION:-}" ]]; then
  _cd_fatal "GLOBAL_STACK_XCADDY_VERSION is empty - run bin/env-scan.sh so .env.local carries it; caddy left as it was"
fi
_xc_v="${GLOBAL_STACK_XCADDY_VERSION#v}"
_xc_base="https://github.com/caddyserver/xcaddy/releases/download/v${_xc_v}"
_xc_asset="xcaddy_${_xc_v}_linux_amd64.tar.gz"
_cd_dl="$(mktemp -d)"
if ! curl --connect-timeout 30 --max-time 300 -fsSL -o "${_cd_dl}/${_xc_asset}" "${_xc_base}/${_xc_asset}" \
  || ! curl --connect-timeout 30 --max-time 60 -fsSL -o "${_cd_dl}/checksums.txt" "${_xc_base}/xcaddy_${_xc_v}_checksums.txt"; then
  _cd_fatal "xcaddy ${GLOBAL_STACK_XCADDY_VERSION} could not be downloaded - caddy left as it was"
fi
# xcaddy publishes SHA-512 sums [measured 0.4.7: 128 hex digits].
if ! _xc_want="$(awk -v n="${_xc_asset}" '$2 == n && length($1) == 128 { print $1 }' "${_cd_dl}/checksums.txt")" \
  || [[ "$(grep -c . <<<"${_xc_want}")" != 1 ]]; then
  _cd_fatal "xcaddy ${GLOBAL_STACK_XCADDY_VERSION}: checksums.txt lists no single checksum for ${_xc_asset} - caddy left as it was"
fi
if ! printf '%s  %s\n' "${_xc_want}" "${_cd_dl}/${_xc_asset}" | sha512sum -c --quiet - >/dev/null 2>&1; then
  _cd_fatal "xcaddy ${GLOBAL_STACK_XCADDY_VERSION}: ${_xc_asset} does not match its published SHA-512 - caddy left as it was"
fi
# grep reads the whole listing (no -q): an early exit would SIGPIPE tar under pipefail.
if ! tar -tzf "${_cd_dl}/${_xc_asset}" 2>/dev/null | grep -xF xcaddy >/dev/null; then
  _cd_fatal "xcaddy ${GLOBAL_STACK_XCADDY_VERSION}: ${_xc_asset} holds no xcaddy - caddy left as it was"
fi
tar -C "${_cd_dl}" -xzf "${_cd_dl}/${_xc_asset}" xcaddy
# `v0.4.7 h1:...` [measured].
if ! _xc_says="$("${_cd_dl}/xcaddy" version 2>&1)" || [[ "${_xc_says%% *}" != "v${_xc_v}" ]]; then
  _cd_fatal "xcaddy ${GLOBAL_STACK_XCADDY_VERSION}: the downloaded binary reports \"${_xc_says%%$'\n'*}\" - caddy left as it was"
fi

# Plugin pins: package|pin. A 40-hex pin is a commit, which caddy lists as a Go
# pseudo-version ending in its first 12 hex digits [measured: transform-encoder
# v0.0.0-20260423033309-ba4124974830]; any other pin must be listed exactly.
_cd_plugins=(
  "github.com/caddyserver/transform-encoder|${GLOBAL_STACK_CADDY_TRANSFORM_ENCODER_VERSION}"
  "github.com/ueffel/caddy-brotli|${GLOBAL_STACK_CADDY_BROTLI_VERSION}"
  "github.com/greenpau/caddy-security|${GLOBAL_STACK_CADDY_SECURITY_VERSION}"
  "github.com/caddyserver/cache-handler|${GLOBAL_STACK_CADDY_CACHE_HANDLER_VERSION}"
)
_cd_with=()
for _cd_p in "${_cd_plugins[@]}"; do
  _cd_with+=(--with "${_cd_p%%|*}@${_cd_p#*|}")
done
# GOTOOLCHAIN=local: the default is `auto` [measured in 01caddy: go 1.27.1], under which a
# module whose go.mod needs a newer go makes go DOWNLOAD an unpinned toolchain. With
# `local` that module fails the build here instead; the remedy is a GLOBAL_STACK_GO_VERSION
# bump. Modules are verified against GOSUMDB=sum.golang.org [measured: GOFLAGS empty].
# shellcheck disable=SC2153 # GLOBAL_STACK_CADDY_VERSION comes from the container env, not a typo of XCADDY
if ! (cd "${_cd_dl}" && GOTOOLCHAIN=local "${_cd_dl}/xcaddy" build "${GLOBAL_STACK_CADDY_VERSION}" --output "${_cd_dl}/caddy" "${_cd_with[@]}"); then
  _cd_fatal "caddy ${GLOBAL_STACK_CADDY_VERSION}: xcaddy build failed (GOTOOLCHAIN=local: a module needing a newer go than tools/go fails here - bump GLOBAL_STACK_GO_VERSION) - caddy left as it was"
fi
# `v2.11.4 h1:...` [measured].
if ! _cd_says="$("${_cd_dl}/caddy" version 2>&1)" || [[ "${_cd_says%% *}" != "${GLOBAL_STACK_CADDY_VERSION}" ]]; then
  _cd_fatal "caddy ${GLOBAL_STACK_CADDY_VERSION}: the built binary reports \"${_cd_says%%$'\n'*}\" - caddy left as it was"
fi
if ! "${_cd_dl}/caddy" list-modules --packages --versions >"${_cd_dl}/modules" 2>&1; then
  _cd_fatal "caddy ${GLOBAL_STACK_CADDY_VERSION}: the built binary cannot list its modules - caddy left as it was"
fi
for _cd_p in "${_cd_plugins[@]}"; do
  _cd_pkg="${_cd_p%%|*}"
  _cd_pin="${_cd_p#*|}"
  _cd_got="$(awk -v p="${_cd_pkg}" '$3 == p { print $2 }' "${_cd_dl}/modules" | sort -u)"
  if [[ "${_cd_pin}" =~ ^[0-9a-f]{40}$ ]]; then
    [[ "$(grep -c . <<<"${_cd_got}")" == 1 && "${_cd_got}" == *"-${_cd_pin:0:12}" ]] && continue
  else
    [[ "${_cd_got}" == "${_cd_pin}" ]] && continue
  fi
  _cd_fatal "caddy ${GLOBAL_STACK_CADDY_VERSION}: the built binary lists ${_cd_pkg} at \"${_cd_got//$'\n'/ }\", pin is ${_cd_pin} - caddy left as it was"
done

# Checked: from here on the old binary is replaced.
mkdir -p "${CADDY_PATH}/bin"
install -m 0755 "${_cd_dl}/caddy" "${CADDY_PATH}/bin/caddy"
# The git clone the pre-xcaddy build left behind; nothing reads it any more.
rm -rf "${_cd_dl}" "${CADDY_PATH}/caddy-build"
cd "${GLOBAL_STACK_DOCKER_TOOLS_PATH}"
