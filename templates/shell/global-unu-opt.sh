#!/usr/bin/env bash
# global-unu-opt.sh — keep the tools under /opt/$USER on their .env pin and own their
# desktop launchers. global-unu.sh runs it last with --apply; run alone it defaults
# to --check. Plan: /stack/docs/plans/opt-developer-updater.plan.md
#
#   global-unu-opt.sh [--check | --apply] [--only=<id>[,<id>...]]
#
# --check  report each tool as current / outdated / missing / unmanaged; writes and
#          fetches nothing (the default).
# --apply  install the pin of every tool whose installed version differs, then write
#          the launchers whose content changed.
#
# An install is: resolve the PIN's download (never "latest") → curl -f into
# <root>/.gs-staging/<id>/ (same filesystem as the install, so the swap is a rename;
# /tmp may be tmpfs) → sha256 check → extract → read the extracted tree's version
# WITHOUT running it and require it to equal the pin → swap. The old tree is deleted
# only after the new one is in place; any failure before that leaves it untouched.
# A tool whose binary is running is skipped, never swapped underneath itself.
#
# Test seams: GS_UNU_OPT_ROOT, GS_UNU_OPT_APPS_DIR, GS_UNU_OPT_ENV_FILE,
# GS_UNU_OPT_PROC_DIR. Tests: bin/tests/global-unu-opt.test.sh
set -euo pipefail

GS_UNU_OPT_ROOT="${GS_UNU_OPT_ROOT:-/opt/${USER:-$(id -un)}}"
GS_UNU_OPT_APPS_DIR="${GS_UNU_OPT_APPS_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/applications}"
GS_UNU_OPT_ENV_FILE="${GS_UNU_OPT_ENV_FILE:-${GLOBAL_STACK_DOCKER_ROOT_PATH:-/stack}/.env.local}"
GS_UNU_OPT_PROC_DIR="${GS_UNU_OPT_PROC_DIR:-/proc}"
_OPT_STAGING="${GS_UNU_OPT_ROOT}/.gs-staging"

# ── Tool table ────────────────────────────────────────────────────────────────
# id → install dir (relative to the root), .env pin var, kind. A kind supplies
# _opt_<kind>_installed / _resolve / _version / _launcher.
_OPT_IDS=(idea)
declare -A _OPT_DIR=([idea]=jetbrains/idea)
declare -A _OPT_PIN=([idea]=GLOBAL_STACK_IDEA_VERSION)
declare -A _OPT_KIND=([idea]=jetbrains)
# JetBrains: product code in data.services.jetbrains.com, launcher binary, name.
declare -A _OPT_JB_CODE=([idea]=IIU)
declare -A _OPT_JB_BIN=([idea]=idea)
declare -A _OPT_JB_NAME=([idea]="IntelliJ IDEA")
declare -A _OPT_JB_COMMENT=([idea]="Java and Kotlin IDE")

_opt_log() { printf '[%-9s] %s\n' "$1" "$2"; }
_opt_err() { printf '[%-9s] %s\n' "$1" "$2" >&2; }

# The pin, read literally from the env file: no eval, last assignment wins.
_opt_pin() {
  [[ -f "${GS_UNU_OPT_ENV_FILE}" ]] || return 0
  sed -n "s/^$1=//p" "${GS_UNU_OPT_ENV_FILE}" | tail -n 1
}

# rm -rf, but only strictly inside the staging dir: the one place this script
# creates. Refuses the staging dir itself, anything outside it, and any path
# with a .. component.
_opt_rm_staging() {
  local p="${1:-}"
  case "${p}" in
    "${_OPT_STAGING}"/?*) ;;
    *)
      _opt_err REFUSED "rm outside ${_OPT_STAGING}/: '${p}'"
      return 1
      ;;
  esac
  case "/${p}/" in
    */../*)
      _opt_err REFUSED "rm of a path with '..': '${p}'"
      return 1
      ;;
  esac
  rm -rf -- "${p}"
}

# 0 when any process's executable lives inside $1 (a dir). Reads <proc>/*/exe
# links, so it matches the process image itself, not a command line that merely
# mentions the path (the pgrep -f self-match trap).
_opt_running() {
  local dir="${1%/}" exe link
  for exe in "${GS_UNU_OPT_PROC_DIR}"/[0-9]*/exe; do
    # Another user's process (or one that just exited) has an unreadable link:
    # EACCES/ENOENT. Neither can be running from our own install dir.
    link="$(readlink "${exe}" 2>/dev/null)" || continue
    [[ "${link}" == "${dir}/"* ]] && return 0
  done
  return 1
}

# ── Kind: jetbrains ──────────────────────────────────────────────────────────
_opt_jetbrains_installed() { # $1 id → installed version or empty
  local f="${GS_UNU_OPT_ROOT}/${_OPT_DIR[$1]}/product-info.json"
  [[ -f "${f}" ]] && jq -r '.version // empty' "${f}"
  return 0
}
_opt_jetbrains_version() { # $1 id $2 extracted tree → version
  jq -r '.version // empty' "$2/product-info.json"
}
_opt_jetbrains_resolve() { # $1 id $2 pin → "url<TAB>sha256"
  local code="${_OPT_JB_CODE[$1]}" json link sum
  json="$(curl -fsSL --retry 2 "https://data.services.jetbrains.com/products/releases?code=${code}&type=release")" || return 1
  link="$(jq -r --arg c "${code}" --arg v "$2" '.[$c][] | select(.version == $v) | .downloads.linux.link' <<<"${json}" | head -n 1)"
  sum="$(jq -r --arg c "${code}" --arg v "$2" '.[$c][] | select(.version == $v) | .downloads.linux.checksumLink' <<<"${json}" | head -n 1)"
  [[ -n "${link}" && -n "${sum}" ]] || {
    _opt_err FAILED "$1: ${2} is not in the JetBrains release list"
    return 1
  }
  sum="$(curl -fsSL --retry 2 "${sum}")" || {
    _opt_err FAILED "$1: checksum file not downloadable"
    return 1
  }
  printf '%s\t%s\n' "${link}" "${sum%% *}"
}
_opt_jetbrains_launcher() { # $1 id $2 install dir → .desktop text
  local bin="${_OPT_JB_BIN[$1]}" wm
  wm="$(jq -r '[.launch[]?.startupWmClass // empty][0] // empty' "$2/product-info.json")"
  printf '[Desktop Entry]\nVersion=1.5\nType=Application\nName=%s\nComment=%s\n' "${_OPT_JB_NAME[$1]}" "${_OPT_JB_COMMENT[$1]}"
  printf 'Exec=%s/bin/%s\nTryExec=%s/bin/%s\nIcon=%s/bin/%s.png\n' "$2" "${bin}" "$2" "${bin}" "$2" "${bin}"
  printf 'Terminal=false\nCategories=Development;IDE;\nStartupNotify=true\n'
  [[ -n "${wm}" ]] && printf 'StartupWMClass=%s\n' "${wm}"
  return 0
}

# ── Engine ───────────────────────────────────────────────────────────────────
# $1 extract dir → the single top-level entry (the app tree), or fail.
_opt_single_root() {
  local entries=("$1"/*)
  [[ ${#entries[@]} -eq 1 && -d "${entries[0]}" ]] || {
    _opt_err FAILED "archive does not hold exactly one top-level dir"
    return 1
  }
  printf '%s' "${entries[0]}"
}

_opt_extract() { # $1 archive $2 url (for the format) $3 dest
  case "$2" in
    *.tar.gz | *.tgz) tar -xzf "$1" -C "$3" ;;
    *.tar.xz) tar -xJf "$1" -C "$3" ;;
    *.zip) unzip -q "$1" -d "$3" ;;
    *)
      _opt_err FAILED "unknown archive format: $2"
      return 1
      ;;
  esac
}

# $1 id $2 pin → 0 installed, 1 failed, 3 skipped (running)
_opt_install() {
  local id="$1" pin="$2" kind="${_OPT_KIND[$1]}"
  local final="${GS_UNU_OPT_ROOT}/${_OPT_DIR[$1]}" stage="${_OPT_STAGING}/$1"
  local res url sum tree got

  if [[ -d "${final}" ]] && _opt_running "${final}"; then
    _opt_log SKIPPED "${id}: running from ${final} — close it and re-run to install ${pin}"
    return 3
  fi
  [[ -e "${stage}" ]] && { _opt_rm_staging "${stage}" || return 1; }
  mkdir -p "${stage}/x"

  if ! res="$("_opt_${kind}_resolve" "${id}" "${pin}")"; then
    _opt_rm_staging "${stage}"
    return 1
  fi
  url="${res%%$'\t'*}" sum="${res#*$'\t'}"
  _opt_log DOWNLOAD "${id} ${pin}: ${url}"
  if ! curl -fsSL --retry 2 -o "${stage}/archive" "${url}"; then
    _opt_err FAILED "${id}: download failed — installed copy untouched"
    _opt_rm_staging "${stage}"
    return 1
  fi
  if [[ "${sum}" == none ]]; then
    _opt_log NOCHECKSUM "${id}: the vendor publishes no checksum — verified by version only"
  elif ! printf '%s  %s\n' "${sum}" "${stage}/archive" | sha256sum -c --status; then
    _opt_err FAILED "${id}: sha256 mismatch — installed copy untouched"
    _opt_rm_staging "${stage}"
    return 1
  fi
  if ! _opt_extract "${stage}/archive" "${url}" "${stage}/x" || ! tree="$(_opt_single_root "${stage}/x")"; then
    _opt_rm_staging "${stage}"
    return 1
  fi
  got="$("_opt_${kind}_version" "${id}" "${tree}" 2>/dev/null || true)"
  if [[ "${got}" != "${pin}" ]]; then
    _opt_err FAILED "${id}: the archive holds '${got}', not the pin ${pin} — installed copy untouched"
    _opt_rm_staging "${stage}"
    return 1
  fi

  mkdir -p "$(dirname "${final}")"
  [[ -e "${final}" ]] && mv "${final}" "${stage}/old"
  if ! mv "${tree}" "${final}"; then
    [[ -e "${stage}/old" ]] && mv "${stage}/old" "${final}"
    _opt_err FAILED "${id}: could not move the new tree into place — old copy restored"
    return 1
  fi
  _opt_rm_staging "${stage}"
  _opt_log INSTALLED "${id} ${pin}"
}

# $1 id → 0 unchanged/written, 1 invalid. Sets _OPT_LAUNCHERS_CHANGED.
_opt_launcher() {
  local id="$1" final="${GS_UNU_OPT_ROOT}/${_OPT_DIR[$1]}" dest="${GS_UNU_OPT_APPS_DIR}/$1.desktop"
  local tmp rc=0
  tmp="$(mktemp -d)"
  "_opt_${_OPT_KIND[$1]}_launcher" "${id}" "${final}" >"${tmp}/$1.desktop"
  if [[ -f "${dest}" ]] && cmp -s "${tmp}/$1.desktop" "${dest}"; then
    :
  elif ! desktop-file-validate "${tmp}/$1.desktop" >&2; then
    _opt_err FAILED "${id}: generated launcher is invalid — ${dest} left as it was"
    rc=1
  else
    mkdir -p "${GS_UNU_OPT_APPS_DIR}"
    cp "${tmp}/$1.desktop" "${dest}.gs-tmp" && mv "${dest}.gs-tmp" "${dest}"
    _opt_log LAUNCHER "${id}: wrote ${dest}"
    _OPT_LAUNCHERS_CHANGED=1
  fi
  rm -rf "${tmp}"
  return "${rc}"
}

_opt_usage() {
  sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

main() {
  local mode=check only="" arg id
  for arg in "$@"; do
    case "${arg}" in
      --check) mode=check ;;
      --apply) mode=apply ;;
      --only=*) only="${arg#--only=}" ;;
      -h | --help)
        _opt_usage
        return 0
        ;;
      *)
        _opt_err USAGE "unknown argument: ${arg}"
        return 2
        ;;
    esac
  done
  local ids=("${_OPT_IDS[@]}")
  if [[ -n "${only}" ]]; then
    IFS=',' read -r -a ids <<<"${only}"
    for id in "${ids[@]}"; do
      [[ -n "${_OPT_KIND[${id}]:-}" ]] || {
        _opt_err USAGE "unknown tool '${id}' (known: ${_OPT_IDS[*]})"
        return 2
      }
    done
  fi

  local failed=0 pin cur rc
  _OPT_LAUNCHERS_CHANGED=0
  for id in "${ids[@]}"; do
    pin="$(_opt_pin "${_OPT_PIN[${id}]}")"
    cur="$("_opt_${_OPT_KIND[${id}]}_installed" "${id}")"
    if [[ -z "${pin}" ]]; then
      _opt_log unmanaged "${id}: ${_OPT_PIN[${id}]} is empty or absent${cur:+ (installed ${cur})}"
    elif [[ "${cur}" == "${pin}" ]]; then
      _opt_log current "${id} ${cur}"
    elif [[ "${mode}" == check ]]; then
      _opt_log "$([[ -n "${cur}" ]] && echo outdated || echo missing)" "${id} ${cur:-—} → ${pin}"
    else
      rc=0
      _opt_install "${id}" "${pin}" || rc=$?
      ((rc == 1)) && failed=1
    fi
    if [[ "${mode}" == apply && -d "${GS_UNU_OPT_ROOT}/${_OPT_DIR[${id}]}" ]]; then
      _opt_launcher "${id}" || failed=1
    fi
  done
  # The menu cache is an optimisation over the files just written; a failed refresh
  # is reported, not fatal — the launchers themselves are already in place.
  if ((_OPT_LAUNCHERS_CHANGED)) && command -v update-desktop-database >/dev/null; then
    update-desktop-database "${GS_UNU_OPT_APPS_DIR}" || _opt_err WARN "update-desktop-database failed on ${GS_UNU_OPT_APPS_DIR}"
  fi
  return "${failed}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
