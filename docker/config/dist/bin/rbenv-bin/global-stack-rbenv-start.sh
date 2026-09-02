#!/bin/bash

set -xeE -o pipefail
shopt -s extdebug
IFS=$'\n\t'
source global-stack-base-prologue.sh
SECONDS=0

PATH="${RBENV_ROOT}/bin:${PATH}"
export PATH

sed -i '/# global-stack-setup-started/,/# global-stack-setup-finished/d' "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "# global-stack-setup-started" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

echo "PATH=${RBENV_ROOT}/bin:${PATH}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
echo "export PATH" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

sleep 1

if [[ "${RBENV_MODE}" = "install" ]]; then
  sudo rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rbenv"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/base"

  if [[ "${GLOBAL_STACK_RELOAD_RBENV}" = "true" ]]; then
    rm -rf "${RBENV_ROOT}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/ruby"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rbenv" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby"* "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/fastlane"
    mkdir -p "${RBENV_ROOT}"
  fi
fi

if [[ "${RBENV_MODE}" = "setup" ]]; then
  rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/ruby.${RUBY_VERSION_AS:-${RUBY_VERSION:-}}"
  rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_ERRORS}/${GLOBAL_STACK_ERROR_TOKEN:-}"
  sleep 1

  global-stack-base-wait-for.sh \
    "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rbenv"

  if [[ "${GLOBAL_STACK_RELOAD_RUBY:-false}" = "true" ]]; then
    printf '\nReloading ruby %s ...\n' "${RUBY_VERSION_AS:-${RUBY_VERSION:-}}"
    rm -rf "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/ruby.${RUBY_VERSION_AS:-${RUBY_VERSION:-}}" "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.${RUBY_VERSION_AS:-${RUBY_VERSION:-}}"
  fi

  # Version-mismatch gate. The marker stores the rbenv-RESOLVED version
  # (RBENV_VERSION, written at the install site below), so gating on the raw pin
  # made every PARTIAL pin look like a version change on EVERY boot: 3.4 against
  # a marker holding 3.4.10, which is the entire reason find-latest and the _AS
  # label scheme exist. Resolve first and gate on the same value the marker
  # gets; the resolved value is REUSED at the install site, so "gate on what
  # gets written" holds by construction rather than by two calls agreeing.
  # Resolving here is safe: this runs after wait-for successes/rbenv, and
  # find-latest short-circuits to the pin when the version dir already exists.
  # Consequence worth knowing: a partial pin now re-resolves every boot, so an
  # rbenv upgrade shipping newer definitions triggers a real reinstall-with-WARN
  # — which is the point of the gate. set -eE safe (find-latest falls back to
  # the raw pin; the gate returns 0, WARN on stderr).
  _ruby_label="${RUBY_VERSION_AS:-${RUBY_VERSION:-}}"
  _ruby_marker="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.${_ruby_label}"
  _ruby_resolved="$(global-stack-rbenv-find-latest.sh "${RUBY_VERSION:-}")"
  _ruby_gate="$(gs_version_gate "${_ruby_marker}" "${_ruby_resolved}" "ruby.${_ruby_label}")"
  if [[ "${_ruby_gate}" == "reinstall" ]]; then
    _ruby_old="$(cat "${_ruby_marker}" 2>/dev/null || true)"
    if [[ -n "${_ruby_old}" && "${_ruby_old}" != "${_ruby_resolved}" ]]; then
      printf '\nCleaning old ruby version dir %s\n' "${_ruby_old}"
      rm -rf "${RBENV_ROOT}/versions/${_ruby_old}"
    fi
    rm -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.${_ruby_label}.pkg."* || true
    rm -f "${_ruby_marker}"
  fi

  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    printf '\nAcquiring rbenv lock ...\n'
    exec 200>"${GLOBAL_STACK_DOCKER_TOOLS_PATH_LOCKS}/rbenv.flock"
    flock 200
    printf 'Lock acquired\n'
  fi
fi

printf '\n******** Starting rbenv %s %s ********\n' "${RBENV_MODE}" "${RUBY_VERSION:-}"

mkdir -p "${RBENV_ROOT}"

if [[ "${RBENV_MODE}" = "install" ]]; then
  # ckpt4: version-drift WARN only (single source: gs_version_gate). Reinstall
  # decision stays with the existing content-compare below (behavior unchanged).
  # Expected uses the same `#v` strip the compare uses (marker stores `rbenv
  # --version` == pin without the leading v — loop-proof). One probe for both
  # guarded blocks so the WARN fires exactly once. `|| true` per ERR-trap invariant.
  gs_version_gate "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv" "${GLOBAL_STACK_RBENV_VERSION#v}" "rbenv" >/dev/null || true
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv" ]] || \
     [[ "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv" 2>/dev/null)" != "${GLOBAL_STACK_RBENV_VERSION#v}" ]] || \
     [[ "true" = "${GLOBAL_STACK_RELOAD_RBENV}" ]]; then
    global-stack-rbenv-iou.sh
  fi
fi

if [[ "${RBENV_MODE}" = "install" ]]; then
  printf '\nWriting /shellrc/rbenv.shellrc\n'
  # E-4: write to a temp file then atomic-rename onto the shared volume so the
  # host never sources a partially-written rbenv.shellrc (rename is atomic on
  # the same filesystem; both paths live under TOOLS_PATH_SHELLRC).
  rbenv_shellrc="${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc"
  echo "export RBENV_ROOT=${RBENV_ROOT}" > "${rbenv_shellrc}.tmp" && mv "${rbenv_shellrc}.tmp" "${rbenv_shellrc}"
fi

if [[ "${RBENV_MODE}" = "setup" ]]; then
  printf '%s\n' "source ${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
fi

printf '%s\n' 'eval "$(rbenv init - ${GLOBAL_STACK_SHELL})"' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
printf '%s\n' 'eval "$(rbenv init - ${GLOBAL_STACK_SHELL})"' >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/.profile"
source "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

if [[ "${RBENV_MODE}" = "install" ]]; then
  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv" ]] || \
     [[ "$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv" 2>/dev/null)" != "${GLOBAL_STACK_RBENV_VERSION#v}" ]] || \
     [[ "true" = "${GLOBAL_STACK_RELOAD_RBENV}" ]]; then
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" && global-stack-rbenv-install-tools.sh
    echo "$(rbenv --version | sed 's/rbenv //')" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/rbenv"
  fi
fi

global-stack-base-init-mkcert.sh
global-stack-base-prepare-shell.sh

if [[ "${RBENV_MODE}" = "install" ]]; then
  printf '\nWriting success\n'
  touch "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/rbenv"
fi

if [[ "${RBENV_MODE}" = "setup" ]]; then
  # Reuse the value the gate above resolved — a second call could disagree and
  # would silently reinstate the raw-vs-resolved mismatch this fix removed.
  export RBENV_VERSION="${_ruby_resolved}"

  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.${RUBY_VERSION_AS:-${RUBY_VERSION:-}}" || "true" = "${GLOBAL_STACK_RELOAD_RUBY}" ]]; then
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" && rbenv install --verbose --skip-existing --keep "${RBENV_VERSION}"
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" && eval "$(rbenv init - --no-rehash ${GLOBAL_STACK_SHELL})" && global-stack-rbenv-ruby${RUBY_VERSION_AS}-setup-version.sh
  fi

  # Package loop runs EVERY boot (ruby installed above / already present, rbenv
  # activated here, RBENV_VERSION resolved at :121), gated per-package by slot
  # markers, so a package-only bump is detected even when the ruby runtime marker
  # is unchanged; unchanged gems skip cheaply. On a runtime bump the checkpoint-2
  # gate wiped ruby.<AS>.pkg.*, repopulating gems on the fresh interpreter. gems
  # accumulate, so --cleanup-command uninstalls the OLD version on a bump.
  # (setup-version.sh is a no-op, so relocating this past it is safe.)
  source /usr/local/bin/global-stack-base-setup-packages.sh
  source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc"
  eval "$(rbenv init - --no-rehash ${GLOBAL_STACK_SHELL})"
  global_stack_base_setup_packages \
    --prefix='RUBY' \
    --marker-prefix="ruby.${RUBY_VERSION_AS:-${RUBY_VERSION:-}}" \
    --cleanup-command='gem uninstall ${PACKAGE_NAME} -v "${PACKAGE_OLD_VERSION}" -x -I || true' \
    --command='echo -e "**** Installing/Updating ${PACKAGE_NAME} ${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}"' \
    --command='gem --backtrace --debug install ${PACKAGE_NAME}:${PACKAGE_VERSION} ${PACKAGE_COMMAND_SUFFIX}'

  if [[ ! -f "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.${RUBY_VERSION_AS:-${RUBY_VERSION:-}}" || "true" = "${GLOBAL_STACK_RELOAD_RUBY}" ]]; then
    source "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SHELLRC}/rbenv.shellrc" && eval "$(rbenv init - --no-rehash ${GLOBAL_STACK_SHELL})" && rbenv shell && rbenv local "${RBENV_VERSION}" && global-stack-rbenv-ruby${RUBY_VERSION_AS}-setup-version.sh
  fi

  if [[ "" != "${RBENV_VERSION}" ]]; then
    printf '\nWriting version\n'
    echo "${RBENV_VERSION}" > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.${RUBY_VERSION_AS:-${RUBY_VERSION:-}}"
    export RBENV_VERSION=$(cat "${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/ruby.${RUBY_VERSION_AS:-${RUBY_VERSION:-}}")
  fi

  echo "export RBENV_VERSION=${RBENV_VERSION}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"
  printf '%s\n' "rbenv local ${RBENV_VERSION}" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

  printf '\nWriting success\n'
  : > "${GLOBAL_STACK_DOCKER_TOOLS_PATH_SUCCESSES}/ruby.${RUBY_VERSION_AS:-${RUBY_VERSION:-}}"
  if [[ "true" = "${GLOBAL_STACK_USE_LOCKS}" ]]; then
    printf '\nReleasing rbenv lock\n'
    flock -u 200
    exec 200>&-
  fi
fi

echo "# global-stack-setup-finished" >> "/home/${GLOBAL_STACK_DOCKER_USER_ID}/${GLOBAL_STACK_SHELL_RC_TARGET}"

DURATION="${SECONDS}"
global-stack-base-print-success.sh "${DURATION}" "rbenv (${RUBY_VERSION:-})"

if [[ "${RBENV_MODE:-}" = "install" ]] && [[ "${GLOBAL_STACK_RELOAD_RBENV:-false}" = "true" ]]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_RBENV is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi
if [[ "${RBENV_MODE:-}" = "setup" ]] && [[ "${GLOBAL_STACK_RELOAD_RUBY:-false}" = "true" ]]; then
  printf '\nWARN: GLOBAL_STACK_RELOAD_RUBY is still true — set it back to false in .env.local to avoid full reinstall on next restart\n' >&2
fi

sleep infinity
