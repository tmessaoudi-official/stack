#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh

SECONDS=0

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

PATH="${RUSTUP_HOME}/bin:${RUSTUP_HOME}/toolchains/stable-x86_64-unknown-linux-gnu/bin:${CARGO_HOME}/bin:${PYENV_ROOT}/bin:${PATH}"
export PATH

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${RUSTUP_HOME}/bin:${RUSTUP_HOME}/toolchains/stable-x86_64-unknown-linux-gnu/bin:${CARGO_HOME}/bin:${PYENV_ROOT}/bin:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

sleep 1

if [[ "${PYENV_MODE}" = "install" ]]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/pyenv"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

  if [[ "${GLOBAL_STACK_RELOAD_PYENV}" = "true" ]]; then
    rm -rf "${PYENV_ROOT}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/python"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/pyenv" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/pyenv"
    mkdir -p "${PYENV_ROOT}"
  fi
fi

if [[ "${PYENV_MODE}" = "setup" ]]; then
  rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/python.${PYTHON_VERSION_AS:-${PYTHON_VERSION:-}}"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/pyenv" \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rust"

  if [[ "${GLOBAL_STACK_RELOAD_PYTHON:-false}" = "true" ]]; then
    printf '\nReloading python %s ...\n' "${PYTHON_VERSION_AS:-${PYTHON_VERSION:-}}"
    rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/python.${PYTHON_VERSION_AS:-${PYTHON_VERSION:-}}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python.${PYTHON_VERSION_AS:-${PYTHON_VERSION:-}}"
  fi

  # Version-mismatch gate: compare against the raw $PYTHON_VERSION pin (NOT the
  # empty-at-gate-time $PYENV_VERSION). The marker stores the pyenv-resolved
  # version which == the raw value for fully-qualified pins. On mismatch, warn +
  # clean the old pyenv version dir and package markers, then drop the marker so
  # the setup block reinstalls + repopulates. set -eE safe (helper returns 0).
  _python_label="${PYTHON_VERSION_AS:-${PYTHON_VERSION:-}}"
  _python_marker="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python.${_python_label}"
  _python_gate="$(gs_version_gate "${_python_marker}" "${PYTHON_VERSION:-}" "python.${_python_label}")"
  if [[ "${_python_gate}" == "reinstall" ]]; then
    _python_old="$(cat "${_python_marker}" 2>/dev/null || true)"
    if [[ -n "${_python_old}" && "${_python_old}" != "${PYTHON_VERSION:-}" ]]; then
      printf '\nCleaning old python version dir %s\n' "${_python_old}"
      rm -rf "${PYENV_ROOT}/versions/${_python_old}"
    fi
    rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python.${_python_label}.pkg."* || true
    rm -f "${_python_marker}"
  fi

  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    printf '\nAcquiring pyenv lock ...\n'
    exec 200>"${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/pyenv.flock"
    flock 200
    printf 'Lock acquired\n'
  fi
fi

printf '\n******** Starting pyenv %s %s ********\n' "${PYENV_MODE}" "${PYTHON_VERSION:-}"

mkdir -p "${PYENV_ROOT}"

if [[ "${PYENV_MODE}" = "install" ]]; then
  # ckpt4: version-drift WARN only (single source: gs_version_gate). Reinstall
  # decision stays with the existing content-compare below (behavior unchanged).
  # Expected uses the same `#v` strip the compare uses (marker stores `pyenv
  # --version` == pin without the leading v — loop-proof). One probe for both
  # guarded blocks so the WARN fires exactly once. `|| true` per ERR-trap invariant.
  gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/pyenv" "${GLOBAL_STACK_PYENV_VERSION#v}" "pyenv" >/dev/null || true
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/pyenv" ]] || \
     [[ "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/pyenv" 2>/dev/null)" != "${GLOBAL_STACK_PYENV_VERSION#v}" ]] || \
     [[ "true" = "${GLOBAL_STACK_RELOAD_PYENV}" ]]; then
    global-stack-pyenv-iou.sh
  fi
fi

if [[ "${PYENV_MODE}" = "install" ]]; then
  printf '\nWriting /shellrc/pyenv.shellrc\n'
  # E-4: write to a temp file then atomic-rename onto the shared volume so the
  # host never sources a partially-written pyenv.shellrc (rename is atomic on
  # the same filesystem; both paths live under TOOLS_PATH_SHELLRC).
  pyenv_shellrc="${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/pyenv.shellrc"
  echo "export PYENV_ROOT=${PYENV_ROOT}" > "${pyenv_shellrc}.tmp" && mv "${pyenv_shellrc}.tmp" "${pyenv_shellrc}"
fi

if [[ "${PYENV_MODE}" = "setup" ]]; then
  printf '%s\n' "source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/pyenv.shellrc" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
fi

printf '%s\n' 'eval "$(pyenv init -)"' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
printf '%s\n' 'eval "$(pyenv init --path)"' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
printf '%s\n' 'eval "$(pyenv init --path)"' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.profile"
source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

if [[ "${PYENV_MODE}" = "install" ]]; then
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/pyenv" ]] || \
     [[ "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/pyenv" 2>/dev/null)" != "${GLOBAL_STACK_PYENV_VERSION#v}" ]] || \
     [[ "true" = "${GLOBAL_STACK_RELOAD_PYENV}" ]]; then
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/pyenv.shellrc" && global-stack-pyenv-install-tools.sh
    echo "$(pyenv --version | sed 's/pyenv //')" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/pyenv"
  fi
fi

if [[ "${PYENV_MODE}" = "setup" ]]; then
  echo "export PYENV_VERSION=${PYENV_VERSION}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
  printf '%s\n' "pyenv local ${PYENV_VERSION}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
fi

global-stack-base-init-mkcert.sh
global-stack-base-prepare-shell.sh

if [[ "${PYENV_MODE}" = "install" ]]; then
  printf '\nWriting success\n'
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/pyenv"
fi

if [[ "${PYENV_MODE}" = "setup" ]]; then
  export PYENV_VERSION=""
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python.${PYTHON_VERSION_AS:-${PYTHON_VERSION:-}}" || "true" = "${GLOBAL_STACK_RELOAD_PYENV}" ]]; then
    export PYENV_VERSION=$(global-stack-pyenv-find-latest.sh "${PYTHON_VERSION}")
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/pyenv.shellrc" && global-stack-pyenv-python${PYTHON_VERSION_AS}-install-version.sh

    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/pyenv.shellrc" && eval "$(pyenv init -)" && eval "$(pyenv init --path)" && pyenv shell && global-stack-pyenv-python${PYTHON_VERSION_AS}-setup-version.sh
  fi
  if [[ "" != "${PYENV_VERSION}" ]]; then
    printf '\nWriting version\n'
    echo "${PYENV_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python.${PYTHON_VERSION_AS:-${PYTHON_VERSION:-}}"
  fi
  if [[ "" = "${PYENV_VERSION}" ]]; then
    export PYENV_VERSION=$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python.${PYTHON_VERSION_AS:-${PYTHON_VERSION:-}}")
  fi

  # Package loop runs EVERY boot — pyenv is activated and PYENV_VERSION is now
  # resolved (from find-latest above OR read back from the marker) — gated
  # per-package by slot markers, so a package-only bump is detected even when the
  # python runtime marker is unchanged; unchanged packages skip cheaply. On a
  # runtime bump the checkpoint-2 gate wiped python.<AS>.pkg.*, so this
  # repopulates globals on the freshly installed interpreter. (setup-version.sh is
  # a no-op, so relocating this past it is safe.)
  source /usr/local/bin/global-stack-base-setup-packages.sh
  source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/pyenv.shellrc"
  eval "$(pyenv init -)"
  eval "$(pyenv init --path)"
  pyenv shell
  global_stack_base_setup_packages \
    --prefix='PYTHON' \
    --marker-prefix="python.${PYTHON_VERSION_AS:-${PYTHON_VERSION:-}}" \
    --command='echo -e "**** Installing/Updating ${PACKAGE_NAME} ${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}"' \
    --command='pip install ${PACKAGE_NAME}==${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}'

  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/python.${PYTHON_VERSION_AS:-${PYTHON_VERSION:-}}" || "true" = "${GLOBAL_STACK_RELOAD_PYENV}" ]]; then
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/pyenv.shellrc" && eval "$(pyenv init -)" && pyenv shell && pyenv local "${PYENV_VERSION}" && global-stack-pyenv-python${PYTHON_VERSION_AS}-setup-version.sh
  fi

  printf '\nWriting success\n'
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/python.${PYTHON_VERSION_AS:-${PYTHON_VERSION:-}}"
  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    printf '\nReleasing pyenv lock\n'
    flock -u 200
    exec 200>&-
  fi
fi

echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION="${SECONDS}"
global-stack-base-print-success.sh "${DURATION}" "pyenv (${PYTHON_VERSION:-})"

if [[ "${GLOBAL_STACK_RELOAD_PYENV:-false}" = "true" ]]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_PYENV is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi

sleep infinity
