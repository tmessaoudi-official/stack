#!/bin/bash
# NOTE: set -euo pipefail is intentionally NOT added to this file.
# This is a function library sourced by caller scripts (e.g. serverless-framework-start.sh).
# Adding set flags here would bleed them into any sourcing script's execution context,
# potentially altering the caller's error-handling behaviour in hard-to-debug ways.
# Additionally, the compgen|grep|sort|while pipeline at line 36 exits 1 with pipefail
# when no matching variables are found — a valid no-op case that must not abort.

global_stack_base_setup_packages() {
    local PREFIX
    local MARKER_PREFIX=""
    local CLEANUP_COMMAND=""
    local COMMAND_COUNTER=0
    local -A COMMANDS=()

    while [[ $# -gt 0 ]]; do
        local __CURRENT_ARG__="${1}"

        case "${__CURRENT_ARG__}" in
            --prefix=*)
                PREFIX="$(echo "${__CURRENT_ARG__}" | sed 's/^--[a-zA-Z0-9_-]\+=//')"
                ;;
            --marker-prefix=*)
                # Opt-in: enables per-slot version markers at
                # ${VERSIONS}/<marker-prefix>.pkg.<slot>. When empty (default) the
                # loop keeps its legacy behavior — run every command, no markers.
                MARKER_PREFIX="$(echo "${__CURRENT_ARG__}" | sed 's/^--[a-zA-Z0-9_-]\+=//')"
                ;;
            --cleanup-command=*)
                # Optional template eval'd (with PACKAGE_OLD_VERSION in scope) before
                # a slot reinstall — used only by accumulate-type managers (sdkman
                # `sdk uninstall`, ruby `gem uninstall`) to remove the old version.
                CLEANUP_COMMAND="$(echo "${__CURRENT_ARG__}" | sed 's/^--[a-zA-Z0-9_-]\+=//')"
                ;;
            --command=*)
                COMMANDS[${COMMAND_COUNTER}]="$(echo "${__CURRENT_ARG__}" | sed 's/^--[a-zA-Z0-9_-]\+=//')"
                ((COMMAND_COUNTER++)) || true
                ;;
            *)
                echo -e "\n ---- (global-stack-setup-packages): Unknown arg passed to global-stack-setup-packages: '${__CURRENT_ARG__}' \n"
                exit 1
                ;;
        esac
        shift
    done

    if [[ -z "${PREFIX:-}" ]]; then
        echo -e "Prefix was not provided !!"
        exit 1
    fi
    if [[ ${#COMMANDS[@]} -eq 0 ]]; then
        echo -e "Command(s) was not provided !!"
        exit 1
    fi

    compgen -A variable | grep "^${PREFIX}_INSTALL_PACKAGE_" | sort | while read -r VARIABLE_NAME; do
        PACKAGE_CONFIG_TEMPLATE="$(echo "${VARIABLE_NAME}" | sed "s/${PREFIX}_INSTALL_PACKAGE_/${PREFIX}_CONFIG_PACKAGE_/")"
        PACKAGE_CONFIG_NAME="$(echo "${PACKAGE_CONFIG_TEMPLATE}" |  sed 's/_VERSION$/_NAME/')"
        PACKAGE_CONFIG_COMMAND_SUFFIX="$(echo "${PACKAGE_CONFIG_TEMPLATE}" | sed 's/_VERSION$/_COMMAND_SUFFIX/')"

        PACKAGE_NAME="${!PACKAGE_CONFIG_NAME:-}"
        PACKAGE_VERSION="${!VARIABLE_NAME:-}"
        PACKAGE_COMMAND_SUFFIX="${!PACKAGE_CONFIG_COMMAND_SUFFIX:-}"

        if [[ "${PACKAGE_NAME}" = "dummy" ]]; then
            continue
        fi

        if [[ -n "${PACKAGE_NAME}" && -n "${PACKAGE_VERSION}" ]]; then
            # Per-slot marker gate (opt-in via --marker-prefix). Marker is keyed by
            # the INSTALL_PACKAGE SLOT (e.g. maven_vx1), NOT the package name, so
            # multiple slots sharing a name get DISTINCT markers and never
            # flip-flop-reinstall. absent → install; equal → skip; differ → warn +
            # optional cleanup(OLD) + reinstall. set -eE safe: gs_version_gate
            # returns 0 (WARN on stderr); the cleanup eval is || true.
            local _slot="" _pkg_marker="" _pkg_decision="install"
            if [[ -n "${MARKER_PREFIX}" ]]; then
                _slot="${VARIABLE_NAME#"${PREFIX}"_INSTALL_PACKAGE_}"
                _slot="${_slot%_VERSION}"
                _slot="${_slot,,}"
                _pkg_marker="${GLOBAL_STACK_DOCKER_TOOLS_PATH_VERSIONS}/${MARKER_PREFIX}.pkg.${_slot}"
                _pkg_decision="$(gs_version_gate "${_pkg_marker}" "${PACKAGE_VERSION}" "${MARKER_PREFIX}.pkg.${_slot}")"
                if [[ "${_pkg_decision}" = "skip" ]]; then
                    continue
                fi
                if [[ "${_pkg_decision}" = "reinstall" && -n "${CLEANUP_COMMAND}" ]]; then
                    local PACKAGE_OLD_VERSION
                    PACKAGE_OLD_VERSION="$(cat "${_pkg_marker}" 2>/dev/null || true)"
                    if [[ -n "${PACKAGE_OLD_VERSION}" && "${PACKAGE_OLD_VERSION}" != "${PACKAGE_VERSION}" ]]; then
                        # Caller cleanup template (PACKAGE_OLD_VERSION in scope); non-fatal.
                        eval "${CLEANUP_COMMAND}" || true
                    fi
                fi
            fi
            for (( INDEX=0; INDEX<${#COMMANDS[@]}; INDEX++ )); do
                # Commands are caller-provided templates evaluated in the current env context (see --command= arg).
                eval "${COMMANDS[${INDEX}]}"
            done
            # Record the installed version only after the commands ran, so a failed
            # install (set -e abort) does NOT leave a satisfied marker behind.
            if [[ -n "${_pkg_marker}" ]]; then
                echo "${PACKAGE_VERSION}" > "${_pkg_marker}"
            fi
        fi
    done
}