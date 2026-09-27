#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh
SECONDS=0
PATH="${PUB_CACHE}/bin:${FVM_CACHE_PATH}/versions/${FLUTTER_VERSION:-}/bin:${PATH}"
export PATH

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${PUB_CACHE}/bin:${FVM_CACHE_PATH}/versions/${FLUTTER_VERSION:-}/bin:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

if [[ "${FVM_MODE}" = "install" ]]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/fvm"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

  if [[ "${GLOBAL_STACK_RELOAD_FVM}" = "true" ]]; then
    printf '\nReloading flutter ...\n'
    rm -rf "${PUB_CACHE}" "${FVM_CACHE_PATH}" "${FVM_GIT_CACHE_PATH}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/flutter"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/fvm" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/fvm"
    mkdir -p "${PUB_CACHE}" "${FVM_CACHE_PATH}" "${FVM_GIT_CACHE_PATH}"
  fi
fi

if [[ "${FVM_MODE}" = "setup" ]]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/flutter.${FLUTTER_VERSION_AS:-${FLUTTER_VERSION:-}}"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/fvm"

  if [[ "${GLOBAL_STACK_RELOAD_FLUTTER:-false}" = "true" ]]; then
    printf '\nReloading flutter %s ...\n' "${FLUTTER_VERSION:-}"
    rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/flutter.${FLUTTER_VERSION_AS:-${FLUTTER_VERSION:-}}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter.${FLUTTER_VERSION_AS:-${FLUTTER_VERSION:-}}"
  fi

  # Version-mismatch gate: compare against $FLUTTER_VERSION (the raw value the
  # marker stores — no resolver). On mismatch, warn and DECIDE — nothing is deleted
  # here. The install trigger below also fires on "reinstall", and the old fvm
  # version dir is dropped only after the new SDK is on disk (the cleanup block after
  # `fvm install`; pin-audit tranche 2, startup-prologue.test.sh §60). flutter has no
  # package loop → no per-package markers to invalidate. set -eE safe (helper returns
  # 0, WARN on stderr).
  _flutter_label="${FLUTTER_VERSION_AS:-${FLUTTER_VERSION:-}}"
  _flutter_marker="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter.${_flutter_label}"
  _flutter_gate="$(gs_version_gate "${_flutter_marker}" "${FLUTTER_VERSION:-}" "flutter.${_flutter_label}")"
  _flutter_old=""
  if [[ "${_flutter_gate}" == "reinstall" ]]; then
    _flutter_old="$(cat "${_flutter_marker}" 2>/dev/null || true)"
  fi

  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    printf '\nAcquiring fvm lock ...\n'
    exec 200>"${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/fvm.flock"
    flock 200
    printf 'Lock acquired\n'
  fi
fi

printf '\n******** Starting fvm %s %s ********\n' "${FVM_MODE}" "${FLUTTER_VERSION_AS:-${FLUTTER_VERSION:-}}"

mkdir -p "${PUB_CACHE}" "${FVM_CACHE_PATH}" "${FVM_GIT_CACHE_PATH}"

if [[ "${FVM_MODE}" = "install" ]]; then
  # Pin-audit tranche 3 step 18 (ruling 2026-09-26 11:17; pinned by startup-prologue.test.sh
  # §70). The tarball used to be downloaded and unpacked in the cwd, which is compose's
  # working_dir, the developer's /stack/projects, and then `sudo rm -rf fvm/` ran there. So a
  # project named fvm was deleted on every fvm bump, and nothing was checked. Now the tarball
  # lands in a temp dir and is checked (it holds fvm/fvm, and that binary's own --version
  # prints the pin) before it replaces the old binary. The marker is written last.
  # fvm publishes no checksum FILE [Verified 2026-09-26: the 4.3.1 release assets], but GitHub
  # serves each release asset's SHA-256 as its `digest` [measured 4.3.1: sha256:ad59c861… =
  # sha256sum of the tarball]; since row 28 that counts as a published checksum (as for
  # elasticmq), so the tarball is checked against it first (row 29). The API call is
  # unauthenticated (60 an hour per IP, shared with elasticmq and env-update's github:
  # fetcher) and made only on a change; a refusal FATALs and keeps the old fvm.
  # The gate compares FVM_VERSION, the variable 02fvm's compose passes and the install below
  # uses: it compared GLOBAL_STACK_FVM_VERSION, which never reaches the container, so the
  # marker never matched "" and fvm was re-downloaded on every boot (step 27 panel; §70m).
  # Every FATAL also removes the temp dir (row 29; step 27 fixed the same leak elsewhere).
  # Defined inside this block, which §70 extracts by anchor.
  _fvm_fatal() {
    printf 'FATAL: fvm %s%s - fvm left as it was\n' "${FVM_VERSION}" "$1" >&2
    [[ -z "${_fvm_dl:-}" ]] || rm -rf "${_fvm_dl}"
    exit 1
  }
  _fvm_gate="$(gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/fvm" "${FVM_VERSION}" "fvm")"
  if [[ "${_fvm_gate}" != "skip" ]] || [[ "${GLOBAL_STACK_RELOAD_FVM}" = "true" ]]; then
    _fvm_dl="$(mktemp -d)"
    _fvm_asset="fvm-${FVM_VERSION}-linux-x64.tar.gz"
    _fvm_tgz="${_fvm_dl}/${_fvm_asset}"
    if ! curl --connect-timeout 30 --max-time 60 -fsSL -o "${_fvm_dl}/release.json" \
      "https://api.github.com/repos/leoafarias/fvm/releases/tags/${FVM_VERSION}"; then
      _fvm_fatal ": cannot fetch its release from api.github.com (unreachable or rate-limited)"
    fi
    # `// empty`: a release older than GitHub's digests has none, and "null" must not become the sum.
    if ! _fvm_sum="$(jq -r --arg n "${_fvm_asset}" '.assets[] | select(.name == $n) | .digest // empty' "${_fvm_dl}/release.json" \
      | sed -n 's/^sha256:\([0-9a-f]\{64\}\)$/\1/p')" \
      || [[ "$(grep -c . <<<"${_fvm_sum}")" != 1 ]]; then
      _fvm_fatal ": its release lists no single sha256 digest for ${_fvm_asset}"
    fi
    if ! curl --connect-timeout 30 --max-time 300 -fsSL -o "${_fvm_tgz}" "https://github.com/leoafarias/fvm/releases/download/${FVM_VERSION}/${_fvm_asset}"; then
      _fvm_fatal " could not be downloaded"
    fi
    if ! printf '%s  %s\n' "${_fvm_sum}" "${_fvm_tgz}" | sha256sum -c --quiet - >/dev/null 2>&1; then
      _fvm_fatal ": ${_fvm_asset} does not match its published SHA-256"
    fi
    # grep reads the whole listing (no -q): an early exit would SIGPIPE tar under pipefail.
    if ! tar -tzf "${_fvm_tgz}" 2>/dev/null | grep -xF 'fvm/fvm' >/dev/null; then
      _fvm_fatal ": the download is not a tarball holding fvm/fvm"
    fi
    tar -C "${_fvm_dl}" -xzf "${_fvm_tgz}" fvm/fvm
    if ! _fvm_says="$("${_fvm_dl}/fvm/fvm" --version 2>&1)" || [[ "${_fvm_says}" != "${FVM_VERSION}" ]]; then
      _fvm_fatal ": the downloaded binary reports \"${_fvm_says:-}\""
    fi
    # Checked: from here on the old binary is replaced.
    sudo install -m 0755 "${_fvm_dl}/fvm/fvm" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/fvm"
    rm -rf "${_fvm_dl}"
    echo "${FVM_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/fvm"
  fi
fi

if [[ "${FVM_MODE}" = "setup" ]]; then
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter.${FLUTTER_VERSION_AS:-${FLUTTER_VERSION:-}}" ]] || [[ "${_flutter_gate}" == "reinstall" ]]; then
    printf '\nInstalling flutter version %s\n' "${FLUTTER_VERSION_AS:-${FLUTTER_VERSION:-}}"
    fvm install "${FLUTTER_VERSION:-}"
    _flutter_new="${FLUTTER_VERSION:-}"
    # Delete-after-install: only now, with the new SDK proven on disk, drop the old
    # version dir — unless another label still records it (flutter.3 and
    # flutter.3.41.9 share this versions/ dir).
    if [[ "${_flutter_gate}" == "reinstall" ]]; then
      if [[ ! -x "${FVM_CACHE_PATH}/versions/${_flutter_new}/bin/flutter" ]]; then
        printf 'FATAL: flutter %s is not installed after the install step; keeping %s\n' "${_flutter_new}" "${_flutter_old}" >&2
        exit 1
      fi
      if [[ -n "${_flutter_old}" && "${_flutter_old}" != "${_flutter_new}" ]] \
        && [[ "$(gs_version_in_use "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}" flutter "${_flutter_label}" "${_flutter_old}")" == "free" ]]; then
        printf '\nCleaning old flutter version dir %s\n' "${_flutter_old}"
        rm -rf "${FVM_CACHE_PATH}/versions/${_flutter_old}"
      fi
    fi
  fi

  # echo "fvm use ${FLUTTER_VERSION:-}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
  printf '\nUsing flutter %s\n' "${FLUTTER_VERSION:-}"
  # fvm use "${FLUTTER_VERSION:-}"
fi

if [[ "${FVM_MODE}" = "install" ]]; then
  printf '\nWriting /.shellrc/.fvm.shellrc\n'
  # E-4: write to a temp file then atomic-rename onto the shared volume so the
  # host never sources a partially-written fvm.shellrc (rename is atomic on the
  # same filesystem; both paths live under TOOLS_PATH_SHELLRC).
  fvm_shellrc="${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/fvm.shellrc"
  {
    echo "export FVM_CACHE_PATH=${FVM_CACHE_PATH}"
    echo "export FVM_GIT_CACHE_PATH=${FVM_GIT_CACHE_PATH}"
    echo "export FVM_USE_GIT_CACHE=${FVM_USE_GIT_CACHE}"
    echo "export FVM_FLUTTER_URL=${FVM_FLUTTER_URL}"
    echo "export PUB_CACHE=${PUB_CACHE}"
  } > "${fvm_shellrc}.tmp" && mv "${fvm_shellrc}.tmp" "${fvm_shellrc}"
fi
# ----------------------------------

global-stack-base-init-mkcert.sh
global-stack-base-prepare-shell.sh
echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION="${SECONDS}"
global-stack-base-print-success.sh "${DURATION}" "fvm (${FLUTTER_VERSION:-})"

if [[ "${FVM_MODE}" = "install" ]]; then
  printf '\nWriting success\n'
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/fvm"
fi

if [[ "${FVM_MODE}" = "setup" ]]; then
  flutter precache
  flutter doctor -v
  printf '\nWriting version\n'
  echo "${FLUTTER_VERSION:-}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter.${FLUTTER_VERSION_AS:-${FLUTTER_VERSION:-}}"
  printf '\nWriting success\n'
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/flutter.${FLUTTER_VERSION_AS:-${FLUTTER_VERSION:-}}"
  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    printf '\nReleasing fvm lock\n'
    flock -u 200
    exec 200>&-
  fi
fi

if [[ "${FVM_MODE:-}" = "install" ]] && [[ "${GLOBAL_STACK_RELOAD_FVM:-false}" = "true" ]]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_FVM is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi
if [[ "${FVM_MODE:-}" = "setup" ]] && [[ "${GLOBAL_STACK_RELOAD_FLUTTER:-false}" = "true" ]]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_FLUTTER is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi

sleep infinity
