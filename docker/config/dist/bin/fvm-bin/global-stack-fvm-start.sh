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
  # marker stores — no resolver). On mismatch, warn + clean the old fvm version
  # dir, then drop the marker so the setup block below reinstalls the new SDK.
  # flutter has no package loop → no per-package markers to invalidate. set -eE
  # safe (helper returns 0, WARN on stderr).
  _flutter_label="${FLUTTER_VERSION_AS:-${FLUTTER_VERSION:-}}"
  _flutter_marker="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter.${_flutter_label}"
  _flutter_gate="$(gs_version_gate "${_flutter_marker}" "${FLUTTER_VERSION:-}" "flutter.${_flutter_label}")"
  if [[ "${_flutter_gate}" == "reinstall" ]]; then
    _flutter_old="$(cat "${_flutter_marker}" 2>/dev/null || true)"
    if [[ -n "${_flutter_old}" && "${_flutter_old}" != "${FLUTTER_VERSION:-}" ]]; then
      printf '\nCleaning old flutter version dir %s\n' "${_flutter_old}"
      rm -rf "${FVM_CACHE_PATH}/versions/${_flutter_old}"
    fi
    rm -f "${_flutter_marker}"
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
  # ckpt4: version-drift WARN only (single source: gs_version_gate). Reinstall
  # decision stays with the existing content-compare below (behavior unchanged);
  # `|| true` satisfies the set -eE ERR-trap invariant for a discard-decision call.
  gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/fvm" "${GLOBAL_STACK_FVM_VERSION}" "fvm" >/dev/null || true
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/fvm" ]] || \
     [[ "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/fvm" 2>/dev/null)" != "${GLOBAL_STACK_FVM_VERSION}" ]] || \
     [[ "${GLOBAL_STACK_RELOAD_FVM}" = "true" ]]; then
    curl --connect-timeout 30 --max-time 300 -fsSL -o "fvm-${FVM_VERSION}-linux-x64.tar.gz" "https://github.com/leoafarias/fvm/releases/download/${FVM_VERSION}/fvm-${FVM_VERSION}-linux-x64.tar.gz"
    tar -xvf fvm-${FVM_VERSION}-linux-x64.tar.gz
    sudo mv fvm/fvm ${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/fvm
    sudo chmod +x ${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/fvm
    sudo rm -rf fvm-${FVM_VERSION}-linux-x64.tar.gz fvm/
    echo "${FVM_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/fvm"
  fi
fi

if [[ "${FVM_MODE}" = "setup" ]]; then
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/flutter.${FLUTTER_VERSION_AS:-${FLUTTER_VERSION:-}}" ]]; then
    printf '\nInstalling flutter version %s\n' "${FLUTTER_VERSION_AS:-${FLUTTER_VERSION:-}}"
    fvm install "${FLUTTER_VERSION:-}"
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
