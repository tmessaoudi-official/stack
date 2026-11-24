#!/usr/bin/env bash
# global-stack-android-cli-sync.sh — keep the REAL Android CLI on its .env pin.
#
#   global-stack-android-cli-sync.sh --installed --dest=FILE
#   global-stack-android-cli-sync.sh --apply --pin=VERSION --dest=FILE --cache=DIR
#
# `android` (cmdline-tools/<ver>/bin/android, pinned through GLOBAL_STACK_ANDROID_SDK_BUILD) is only
# a launcher: when ${ANDROID_USER_HOME:-$HOME/.android}/bin/android-cli is absent it downloads
# https://dl.google.com/android/cli/latest/linux_x86_64/android-cli there and execs it; when it is
# present it execs it with no version check and no network (measured 2026-11-24, launcher
# 1.0.15498356). So whatever sits at that path IS the CLI, and this script puts the pin there:
# GLOBAL_STACK_ANDROID_CLI_VERSION, fetched from the immutable versioned URL and checked against
# the .sha256 Google publishes beside it. docs/plans/android-cli-pin.plan.md
#
# --installed  print the version a verified install recorded for FILE, or nothing when FILE is
#              absent, unrecorded or its bytes changed (an `android update` reads as drift).
#              Offline. Always exit 0.
# --apply      install the pin unless it is already current (then: no network, no write).
#              DIR caches <pin>/{android-cli,android-cli.sha256}, shared by the host and the
#              containers, so a recreated $HOME copies instead of downloading. A cached binary is
#              re-checked against its .sha256 before every copy. FILE is replaced atomically and
#              its record (<dir of FILE>/.<name>.gs-pin = "<pin> <sha256>") is written LAST. Any
#              failure exits 1 and leaves FILE and its record as they were. Older version dirs
#              in DIR are pruned only after a success. An empty pin is `unmanaged` (exit 0: the
#              launcher keeps fetching latest); a machine Google builds no CLI for is
#              `unsupported` (exit 0).
# Exit 2: bad arguments, refused before anything is read or written.
#
# Callers: android-bin/global-stack-android-start.sh (every 04android boot),
# alltogether/global-stack-alltogether-start.sh (05*), templates/shell/global-unu-opt.sh (host).
# Test seam: GS_ANDROID_CLI_MACHINE (default uname -m). Tests: bin/tests/android-cli-sync.test.sh
set -euo pipefail

_ACS_BASE_URL="https://dl.google.com/android/cli"
_ACS_VERSION_RE='^[0-9]+(\.[0-9]+)+$'

_acs_log() { printf '[%-9s] %s\n' "$1" "$2"; }
_acs_err() { printf '[%-9s] %s\n' "$1" "$2" >&2; }
_acs_sha256() { sha256sum <"$1" | cut -d' ' -f1; }
_acs_record_of() { printf '%s/.%s.gs-pin' "$(dirname "$1")" "$(basename "$1")"; }

# $1 dest → the recorded version when dest holds the recorded bytes, else nothing.
_acs_installed() {
  local dest="$1" rec v sum
  rec="$(_acs_record_of "${dest}")"
  [[ -f "${dest}" && -f "${rec}" ]] || return 0
  read -r v sum <"${rec}" || true
  [[ -n "${v:-}" && -n "${sum:-}" ]] || return 0
  [[ "$(_acs_sha256 "${dest}")" == "${sum}" ]] && printf '%s\n' "${v}"
  return 0
}

# $1 file $2 sha256 file → 0 when the file's digest is the one published.
_acs_matches() {
  local want
  [[ -f "$1" && -f "$2" ]] || return 1
  want="$(tr -d '[:space:]' <"$2")"
  [[ "${want}" =~ ^[0-9a-f]{64}$ && "$(_acs_sha256 "$1")" == "${want}" ]]
}

# $1 cache root $2 pin → 0 with <cache>/<pin>/android-cli verified, downloading it if needed.
_acs_fill_cache() {
  local c="$1/$2" url="${_ACS_BASE_URL}/$2/linux_x86_64/android-cli" tbin tsum
  _acs_matches "${c}/android-cli" "${c}/android-cli.sha256" && return 0
  mkdir -p "${c}" || {
    _acs_err FAILED "android-cli: cannot create ${c}"
    return 1
  }
  tsum="$(mktemp "${c}/.android-cli.sha256.gs-tmp.XXXXXX")" || return 1
  tbin="$(mktemp "${c}/.android-cli.gs-tmp.XXXXXX")" || {
    rm -f -- "${tsum}"
    return 1
  }
  _acs_log DOWNLOAD "android-cli $2: ${url}"
  if ! curl -fsSL --retry 2 --connect-timeout 30 --max-time 120 -o "${tsum}" "${url}.sha256" \
    || ! curl -fsSL --retry 2 --connect-timeout 30 --max-time 900 -o "${tbin}" "${url}"; then
    _acs_err FAILED "android-cli: $2 is not downloadable from ${url} — installed copy untouched"
    rm -f -- "${tsum}" "${tbin}"
    return 1
  fi
  if ! _acs_matches "${tbin}" "${tsum}"; then
    _acs_err FAILED "android-cli: $2 does not match its published sha256 — installed copy untouched"
    rm -f -- "${tsum}" "${tbin}"
    return 1
  fi
  # The binary first: a crash between the two moves leaves a pair that fails _acs_matches and is
  # fetched again, never a stale .sha256 vouching for new bytes.
  if ! { mv -fT -- "${tbin}" "${c}/android-cli" && mv -fT -- "${tsum}" "${c}/android-cli.sha256"; }; then
    _acs_err FAILED "android-cli: cannot write ${c}"
    rm -f -- "${tsum}" "${tbin}"
    return 1
  fi
}

# $1 cache root $2 pin → remove every OTHER version-named dir strictly inside the cache root.
_acs_prune() {
  local d name
  for d in "$1"/*/; do
    [[ -d "${d}" ]] || continue
    name="$(basename "${d}")"
    [[ "${name}" =~ ${_ACS_VERSION_RE} && "${name}" != "$2" ]] || continue
    rm -rf -- "${1:?}/${name}" || _acs_err WARN "android-cli: could not prune $1/${name}"
  done
}

# $1 pin $2 dest $3 cache
_acs_apply() {
  local pin="$1" dest="$2" cache="$3" dir rec tmp sum
  if [[ -z "${pin}" ]]; then
    _acs_log unmanaged "android-cli: GLOBAL_STACK_ANDROID_CLI_VERSION is empty — the launcher keeps fetching latest"
    return 0
  fi
  if [[ "${GS_ANDROID_CLI_MACHINE:-$(uname -m)}" != x86_64 ]]; then
    _acs_log unsupported "android-cli: Google publishes no linux build for ${GS_ANDROID_CLI_MACHINE:-$(uname -m)} — skipped"
    return 0
  fi
  if [[ "$(_acs_installed "${dest}")" == "${pin}" ]]; then
    _acs_log current "android-cli ${pin}"
    return 0
  fi
  _acs_fill_cache "${cache}" "${pin}" || return 1

  dir="$(dirname "${dest}")"
  rec="$(_acs_record_of "${dest}")"
  mkdir -p "${dir}" || {
    _acs_err FAILED "android-cli: cannot create ${dir}"
    return 1
  }
  tmp="$(mktemp "${dir}/.android-cli.gs-tmp.XXXXXX" 2>/dev/null)" || {
    _acs_err FAILED "android-cli: cannot write in ${dir} — installed copy untouched"
    return 1
  }
  sum="$(tr -d '[:space:]' <"${cache}/${pin}/android-cli.sha256")"
  # Re-hashed at the destination: the cache is shared, so it is checked again on the copy itself.
  # `mv -T` everywhere: a plain `mv` onto a path that is a DIRECTORY moves the file into it and
  # succeeds, and the record would then vouch for a pin that is not at dest (tests 6e-6g; the
  # .sha256 sidecar site is untested: a non-file sidecar fails _acs_matches and is fetched again).
  if ! cp -- "${cache}/${pin}/android-cli" "${tmp}" || [[ "$(_acs_sha256 "${tmp}")" != "${sum}" ]] \
    || ! chmod 755 "${tmp}" || ! mv -fT -- "${tmp}" "${dest}"; then
    _acs_err FAILED "android-cli: could not put ${pin} in place at ${dest} — installed copy untouched"
    rm -f -- "${tmp}"
    return 1
  fi
  if ! { printf '%s %s\n' "${pin}" "${sum}" >"${rec}.gs-tmp" && mv -fT -- "${rec}.gs-tmp" "${rec}"; }; then
    rm -f -- "${rec}.gs-tmp"
    _acs_err FAILED "android-cli: ${pin} installed at ${dest} but its record ${rec} could not be written — the next run reinstalls it"
    return 1
  fi
  _acs_prune "${cache}" "${pin}"
  _acs_log INSTALLED "android-cli ${pin} → ${dest}"
}

main() {
  local mode="" pin="" dest="" cache="" have_pin=0 arg
  for arg in "$@"; do
    case "${arg}" in
      --installed) mode=installed ;;
      --apply) mode=apply ;;
      --pin=*)
        pin="${arg#--pin=}"
        have_pin=1
        ;;
      --dest=*) dest="${arg#--dest=}" ;;
      --cache=*) cache="${arg#--cache=}" ;;
      *)
        _acs_err USAGE "unknown argument: ${arg}"
        return 2
        ;;
    esac
  done
  [[ -n "${mode}" ]] || {
    _acs_err USAGE "one of --installed or --apply is required"
    return 2
  }
  [[ "${dest}" == /?* ]] || {
    _acs_err REFUSED "--dest must be an absolute path (got '${dest}')"
    return 2
  }
  if [[ "${mode}" == installed ]]; then
    _acs_installed "${dest}"
    return 0
  fi
  [[ "${cache}" == /?* ]] || {
    _acs_err REFUSED "--cache must be an absolute path (got '${cache}')"
    return 2
  }
  ((have_pin)) || {
    _acs_err USAGE "--apply needs --pin= (empty means unmanaged)"
    return 2
  }
  if [[ -n "${pin}" && ! "${pin}" =~ ${_ACS_VERSION_RE} ]]; then
    _acs_err REFUSED "--pin '${pin}' is not a version"
    return 2
  fi
  _acs_apply "${pin}" "${dest}" "${cache}"
}

main "$@"
