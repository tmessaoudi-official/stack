#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh
_node_version_label="${NODE_VERSION_AS:-${NODE_VERSION:-}}"

SECONDS=0

PATH="${GLOBAL_STACK_DOCKER_TOOLS_PATH}/yarn/bin:${DENO_DIR}/bin:${BUN_INSTALL}/bin:${PNPM_HOME}:${PATH}"
export PATH

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${GLOBAL_STACK_DOCKER_TOOLS_PATH}/yarn/bin:${DENO_DIR}/bin:${BUN_INSTALL}/bin:${PNPM_HOME}:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

if [[ "${NVM_MODE}" = "install" ]]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/nvm"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

  if [[ "${GLOBAL_STACK_RELOAD_NVM}" = "true" ]]; then
    printf '\nReloading node ...\n'
    rm -rf "${NVM_DIR}" "${DENO_INSTALL}/bin" "${BUN_INSTALL}/bin" "${YARN_OFFLINE_MIRROR}" "${YARN_CACHE_FOLDER}" "${YARN_GLOBAL_FOLDER}" "${GLOBAL_STACK_PNPM_GLOBAL_DIR}" "${PNPM_HOME}" "${GLOBAL_STACK_PNPM_STORE_DIR}" "${NPM_CACHE_DIR}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/node"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/nvm" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}/nvm.installer.sh"
    mkdir -p "${NVM_DIR}" "${DENO_INSTALL}/bin" "${BUN_INSTALL}/bin" "${YARN_OFFLINE_MIRROR}" "${YARN_CACHE_FOLDER}" "${YARN_GLOBAL_FOLDER}/bin" "${GLOBAL_STACK_PNPM_GLOBAL_DIR}" "${PNPM_HOME}" "${GLOBAL_STACK_PNPM_STORE_DIR}" "${NPM_CACHE_DIR}"
  fi
fi

if [[ "${NVM_MODE}" = "setup" ]]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/node.${_node_version_label}"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/nvm"

  if [[ "${GLOBAL_STACK_RELOAD_NODE:-false}" = "true" ]]; then
    printf '\nReloading node %s ...\n' "${_node_version_label}"
    rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/node.${_node_version_label}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.${_node_version_label}"
  fi

  # Version-mismatch gate: if the recorded node version differs from the pinned
  # NODE_VERSION, warn + clean the old version dir and this runtime's package
  # markers, then drop the version marker so the install/setup blocks below
  # reinstall and repopulate the new version. Compare against the raw pin: the
  # marker stores $(nvm version "$NODE_VERSION") == the raw value for fully-
  # qualified pins (verified on-disk incl. nightly). set -eE safe: helper returns
  # 0 and emits the decision on stdout (WARN on stderr).
  #
  # CARRIED GAP (hunt F8) — pyenv and rbenv had this same raw-vs-resolved shape
  # and were fixed by resolving before gating; nvm was NOT, because the resolver
  # here is `nvm version`, which needs nvm sourced — that happens ~130 lines
  # below, so it cannot be resolved early here without restructuring the lock
  # acquisition around it. The defect stays LATENT while every node pin in .env
  # is fully qualified (v24.19.0, v26.7.0): a PARTIAL pin such as v24 would
  # mismatch its own v24.19.0 marker and recompile on every boot. Do not copy
  # the pyenv shape here without moving the nvm source first. Pinned by
  # bin/tests/startup-prologue.test.sh §22f.
  _node_marker="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.${_node_version_label}"
  _node_gate="$(gs_version_gate "${_node_marker}" "${NODE_VERSION:-}" "node.${_node_version_label}")"
  if [[ "${_node_gate}" == "reinstall" ]]; then
    _node_old="$(cat "${_node_marker}" 2>/dev/null || true)"
    if [[ -n "${_node_old}" && "${_node_old}" != "${NODE_VERSION:-}" ]]; then
      printf '\nCleaning old node version dir %s\n' "${_node_old}"
      rm -rf "${NVM_DIR}/versions/node/${_node_old}"
    fi
    rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.${_node_version_label}.pkg."* || true
    rm -f "${_node_marker}"
  fi

  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    printf '\nAcquiring nvm lock ...\n'
    exec 200>"${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/nvm.flock"
    flock 200
    printf 'Lock acquired\n'
  fi
fi

printf '\n******** Starting nvm %s %s ********\n' "${NVM_MODE}" "${_node_version_label}"

global-stack-nvm-eval-yarnrc.sh

mkdir -p "${NVM_DIR}" "${DENO_INSTALL}/bin" "${BUN_INSTALL}/bin" "${YARN_OFFLINE_MIRROR}" "${YARN_CACHE_FOLDER}" "${YARN_GLOBAL_FOLDER}/bin" "${GLOBAL_STACK_PNPM_GLOBAL_DIR}" "${PNPM_HOME}" "${GLOBAL_STACK_PNPM_STORE_DIR}" "${NPM_CACHE_DIR}"

# ----------------------------------
if [[ "${NVM_MODE}" = "install" ]]; then
  # ckpt4: version-drift WARN only (single source: gs_version_gate). Reinstall
  # decision stays with the existing content-compare below (behavior unchanged);
  # `|| true` satisfies the set -eE ERR-trap invariant for a discard-decision call.
  gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm" "${GLOBAL_STACK_NVM_VERSION}" "nvm" >/dev/null || true
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm" ]] || \
     [[ "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm" 2>/dev/null)" != "${GLOBAL_STACK_NVM_VERSION}" ]] || \
     [[ "${GLOBAL_STACK_RELOAD_NVM}" = "true" ]]; then
    global-stack-nvm-iou.sh
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_BIN}"/nvm.installer.sh
    echo "${GLOBAL_STACK_NVM_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/nvm"
  fi
fi

printf '\nLoading nvm bash\n'
[ -s "${NVM_DIR}/nvm.sh" ] && \. "${NVM_DIR}/nvm.sh"         # This loads nvm
[ -s "${NVM_DIR}/bash_completion" ] && \. "${NVM_DIR}/bash_completion"  # This loads nvm bash_completion

printf '\nAdding nvm bash to .shellrc\n'
echo "[ -s \"${NVM_DIR}/nvm.sh\" ] && \. \"${NVM_DIR}/nvm.sh\"" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"  # This loads nvm
echo "[ -s \"${NVM_DIR}/bash_completion\" ] && \. \"${NVM_DIR}/bash_completion\"" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"  # This loads nvm bash_completion

if [[ "${NVM_MODE}" = "setup" ]]; then
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.${_node_version_label}" ]]; then
    printf '\nInstalling node version %s\n' "${_node_version_label}"
    # Self-heal a corrupt/partial cached download: nvm reuses .cache/src/node-<VER> on
    # every retry and cannot recover (empty expected checksum), so a download corrupted
    # under concurrent-rebuild load loops forever. Purge this version's cache + retry once.
    gs_install_retry_purge "${NVM_DIR}/.cache/src/node-${NODE_VERSION:-}" nvm install "${NODE_VERSION:-}"
  fi

  echo "nvm use ${NODE_VERSION:-}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
  printf '\nUsing node %s\n' "${NODE_VERSION:-}"
  nvm use "${NODE_VERSION:-}"

  # Package loop runs EVERY boot (after `nvm use`, so node is on PATH), gated
  # per-package by slot markers (--marker-prefix). A package-only version bump is
  # therefore detected even when the node runtime marker is unchanged; unchanged
  # packages skip cheaply. On a runtime bump the checkpoint-2 gate wiped
  # node.<AS>.pkg.*, so this repopulates globals on the freshly installed runtime.
  source /usr/local/bin/global-stack-base-setup-packages.sh
  global_stack_base_setup_packages \
    --prefix='NODE' \
    --marker-prefix="node.${_node_version_label}" \
    --command='echo -e "**** Installing/Updating ${PACKAGE_NAME} ${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}"' \
    --command='echo "y" | npm add --global --force ${PACKAGE_NAME}@${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}'

  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.${_node_version_label}" ]]; then
    printf '\nSetting up node %s\n' "${NODE_VERSION:-}"

    global-stack-nvm-node${NODE_VERSION_AS}-setup.sh
    if [[ -n "${GLOBAL_STACK_NODE_UPGRADE}" ]] && [[ "${GLOBAL_STACK_NODE_UPGRADE}" = "true" ]]; then
      npm --global upgrade --force
    fi
    global-stack-nvm-node${NODE_VERSION_AS}-setup-overrides.sh
  fi
fi

if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/nvm" ]]; then
  if [[ "${NVM_MODE}" = "install" ]]; then
    global-stack-nvm-install-tools.sh
  fi
fi

if [[ "${NVM_MODE}" = "setup" ]]; then
  printf '\nSetting project for node %s\n' "${NODE_VERSION:-}"
  global-stack-nvm-node${NODE_VERSION_AS}-setup-project.sh
fi

if [[ "${NVM_MODE}" = "install" ]]; then
  printf '\nWriting /.shellrc/.nvm.shellrc\n'
  # E-4: write to a temp file then atomic-rename onto the shared volume so the
  # host never sources a partially-written nvm.shellrc (rename is atomic on the
  # same filesystem; both paths live under TOOLS_PATH_SHELLRC).
  nvm_shellrc="${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/nvm.shellrc"
  {
    echo "export NVM_DIR=${NVM_DIR}"
    echo "export DENO_INSTALL=${DENO_INSTALL}"
    echo "export DENO_INSTALL_ROOT=${DENO_INSTALL_ROOT}"
    echo "export DENO_DIR=${DENO_DIR}"
    echo "export YARN_OFFLINE_MIRROR=${YARN_OFFLINE_MIRROR}"
    echo "export YARN_CACHE_FOLDER=${YARN_CACHE_FOLDER}"
    echo "export YARN_GLOBAL_FOLDER=${YARN_GLOBAL_FOLDER}"
    echo "export GLOBAL_STACK_PNPM_GLOBAL_DIR=${GLOBAL_STACK_PNPM_GLOBAL_DIR}"
    echo "export PNPM_HOME=${PNPM_HOME}"
    echo "export GLOBAL_STACK_PNPM_STORE_DIR=${GLOBAL_STACK_PNPM_STORE_DIR}"
    echo "export CYPRESS_CACHE_FOLDER=${CYPRESS_CACHE_FOLDER}"
    echo "export NPM_CACHE_DIR=${NPM_CACHE_DIR}"
  } > "${nvm_shellrc}.tmp" && mv "${nvm_shellrc}.tmp" "${nvm_shellrc}"
fi
# ----------------------------------

global-stack-base-init-mkcert.sh
global-stack-base-prepare-shell.sh
echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION="${SECONDS}"
global-stack-base-print-success.sh "${DURATION}" "nvm (${NODE_VERSION:-})"

if [[ "${NVM_MODE}" = "install" ]]; then
  printf '\nWriting success\n'
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/nvm"
fi

if [[ "${NVM_MODE}" = "setup" ]]; then
  printf '\nWriting version\n'
  echo "$(nvm version "${NODE_VERSION:-}")" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/node.${_node_version_label}"
  printf '\nWriting success\n'
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/node.${_node_version_label}"
  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    printf '\nReleasing nvm lock\n'
    flock -u 200
    exec 200>&-
  fi
fi

if [[ "${NVM_MODE:-}" = "install" ]] && [[ "${GLOBAL_STACK_RELOAD_NVM:-false}" = "true" ]]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_NVM is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi
if [[ "${NVM_MODE:-}" = "setup" ]] && [[ "${GLOBAL_STACK_RELOAD_NODE:-false}" = "true" ]]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_NODE is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi

sleep infinity
